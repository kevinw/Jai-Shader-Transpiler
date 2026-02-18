#run,stallable {
  start_time := current_time_monotonic();
  set_build_options_dc(.{do_output=false, write_added_strings=false});
  command_line_opts := get_build_options();
  opts: Opts;
  run_tests := false;
  single_build := "";
  for command_line_opts.compile_time_command_line {
    if it == "-single" {
      single_build = command_line_opts.compile_time_command_line[it_index + 1];
      it_index += 1;
    } else if it == "-run_tests" {
      run_tests = true;
      opts.emit_shader_outputs = true;
    }
    else if it == "-verbose_build_progress" opts.verbose_build_progress = true;
    else if it == "-timings" opts.timings = true;
    else fail("Unrecognized argument '%'", it);
  }

  {
    defer {
      if !single_build && opts.timings {
        elapsed_time := to_float64_seconds(current_time_monotonic() - start_time);
        log("All examples built in %s", elapsed_time);
      }
    }
    
    to_build: [..]string;
    if single_build {
      array_add(*to_build, single_build);
    } else {
      #if OS == .MACOS {
        array_add(*to_build, "example/metal_example.jai");
      }
      array_add(*to_build, 
        "example/cpu_example.jai",
        "example/vulkan_example.jai",
        "example/ir_smoke_metal_pair.jai",
        "example/ir_smoke_vk_compute.jai",
        "example/ir_smoke_vk_bindless.jai");
      if run_tests {
        array_add(*to_build, "test_runner.jai");
      }
    }
    
    assert(to_build.count > 0, "Expected something to build");
    if single_build != "" {
      assert(to_build.count == 1);
      build(to_build[0], opts);
    } else {
      // parallelize builds
      to_args :: (opts: Opts) -> [..]string {
        res: [..]string;
        if opts.verbose_build_progress array_add(*res, "-verbose_build_progress");
        if opts.timings array_add(*res, "-timings");
        return res;
      }
      extra_args := to_args(opts);
      parallel_build(to_build, extra_args);
    }
  }

  if run_tests {
    TEST_RUNNER :: "test_runner.jai";
    run_args: [..] string;
    array_add(*run_args, "./test_runner");
    result: Process_Result;
    output, error: string;
    timeout_reached: bool;
    if opts.timings array_add(*run_args, "-timings");
    {
      time_scope(opts.timings, "Run test_runner.jai");
      result, output, error, timeout_reached = run_command(..run_args);
    }
    if timeout_reached fail("% timed out.", TEST_RUNNER);
    if result.type == .FAILED_TO_LAUNCH fail("Failed to launch %.", TEST_RUNNER);
    if result.type != .EXITED || result.exit_code != 0 fail("% failed with exit code %.", TEST_RUNNER, result.exit_code);
    
    log("Total time %s", FormatFloat.{value=to_float64_seconds(current_time_monotonic() - start_time), trailing_width=2});
  }
}

Opts :: struct {
  verbose_build_progress: bool;
  timings: bool;
  emit_shader_outputs: bool;
}

build :: (build_file: string, using opts: Opts) {
  output_exe_name := path_strip_extension(path_filename(build_file));
  command_line_opts := get_build_options();
  w := compiler_create_workspace(output_exe_name);
  options := get_build_options(w);
  {
    using options;
    intermediate_path = sprint(".build/%", output_exe_name);
    output_executable_name = output_exe_name;
    text_output_flags = 0; // command_line_opts.text_output_flags;
    set_optimization(*options, .VERY_DEBUG);
    if emit_shader_outputs {
      compile_time_args: [..] string;
      for compile_time_command_line array_add(*compile_time_args, it);
      array_add(*compile_time_args, "-output_shaders");
      compile_time_command_line = compile_time_args;
    }
    if text_output_flags == 0 log("Building '%'...", output_exe_name);
  }
  step_start_time := current_time_monotonic();
  if verbose_build_progress log("[build] start % (%).", output_exe_name, build_file);
  defer {
    step_elapsed := to_float64_seconds(current_time_monotonic() - step_start_time);
    if verbose_build_progress log("[build] end % (%.3fs).", output_exe_name, step_elapsed);
  }
  set_build_options(options, w);

  jai_to_shader_plugin := get_plugin();
  jai_to_shader_plugin.workspace = w;

  autorun := false;
  for command_line_opts.compile_time_command_line {
      if it == {
        case "-run"; autorun = true;
      }
  }

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);
  add_build_file(build_file, w);
  compile_ok: bool;
  {
    time_scope(timings, tprint("Compile %", output_exe_name));
    compile_ok = message_loop(w, jai_to_shader_plugin, verbose_build_progress);
  }
  if !compile_ok {
    exit(1);
  }
  if autorun {
    run_command(output_exe_name);
  }
}

message_loop :: (w: Workspace, plugin: *Metaprogram_Plugin, verbose_build_progress: bool=false) -> bool {
  ok := false;
  message_count: s64 = 0;
  last_progress_log_time := current_time_monotonic();
  while true {
    message := compiler_wait_for_message();
    message_count += 1;
    plugin.message(plugin, message);
    if verbose_build_progress {
      now := current_time_monotonic();
      elapsed_since_log := to_float64_seconds(now - last_progress_log_time);
      if elapsed_since_log >= 0.5 {
        log("[build] workspace % progress: % messages, last kind=%", w, message_count, message.kind);
        last_progress_log_time = now;
      }
    }
    if message.kind == .COMPLETE {
      ok = message.(*Message_Complete).error_code == 0;
      break;
    }
  }
  return ok;
}

time_scope :: (enabled: bool, label: string) #expand {
  __jsl_timing_enabled := enabled;
  __jsl_timing_start := current_time_monotonic();
  `defer {
    if __jsl_timing_enabled {
      __jsl_timing_elapsed := to_float64_seconds(current_time_monotonic() - __jsl_timing_start);
      log("[timing] %: %s", label, __jsl_timing_elapsed);
    }
  }
}

parallel_build :: (to_build: []string, extra_args: []string) {
  parallel_fail :: (fmt: string, args: ..Any) #expand {
    for * children if !it.done {
      kill_process(*it.proc);
    }
    fail(fmt, ..args);
  }
  
  children: [..]struct { proc: Process; done: bool; };
  defer for children deinit(*it.proc);
  
  // spawn processes
  for to_build {
    child := array_add(*children);
    args: [..]string;
    array_add(*args, jai_exe, "build.jai", "-", "-single", it);
    array_add(*args, ..extra_args);
    create_success := create_process(*child.proc, ..args, capture_and_return_output=true);
    if !create_success {
      parallel_fail("Failed to create subprocess for build: %", it);
    }
  }
  
  // interleave output
  done_count := 0;
  while done_count < children.count {
    made_progress := false;
    for to_build {
      if children[it_index].done continue;
      child := *children[it_index].proc;

      out_buf: [4096]u8;
      err_buf: [4096]u8;
      read_ok, output_bytes, error_bytes := read_from_process(child, out_buf, err_buf, timeout_ms = 0);
      if !read_ok parallel_fail("Failed while reading output from build '%'.", to_build[it_index]);

      if output_bytes > 0 {
        write_string(to_string(out_buf.data, output_bytes), to_standard_error = false);
        made_progress = true;
      }
      if error_bytes > 0 {
        write_string(to_string(err_buf.data, error_bytes), to_standard_error = true);
        made_progress = true;
      }

      if child.output.eof && child.error.eof {
        result_ok, process_result := get_process_result(child, timeout_ms = -1);
        if !result_ok parallel_fail("Failed to fetch subprocess result for build '%'.", to_build[it_index]);

        children[it_index].done = true;
        done_count += 1;

        if process_result.type != .EXITED || process_result.exit_code != 0 {
          parallel_fail("Subprocess build '%' failed with exit code %.", to_build[it_index], process_result.exit_code);
        }
      }
    }
    if !made_progress {
      sleep_milliseconds(1);
    }
  }
}

#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";
#import "Metaprogram_Plugins";
#import,file "./module.jai"; // #import "Jai-Shader-Transpiler" in your code.

#if OS == .MACOS jai_exe :: "jai-macos";
else #if OS == .LINUX jai_exe :: "jai-linux";
else jai_exe :: "jai";

fail :: (fmt: string, args: ..Any) {
  compiler_report(sprint(fmt, ..args));
  exit(1);
}
