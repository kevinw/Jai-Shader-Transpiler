#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";
#import "Metaprogram_Plugins";
#import,file "./module.jai"; // #import "Jai-Shader-Transpiler" in your code.

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

#run,stallable {
  command_line_opts := get_build_options();
  run_tests := false;
  verbose_build_progress := false;
  timings := false;
  ir_case := "";
  for command_line_opts.compile_time_command_line {
    if it == "-run_tests" run_tests = true;
    else if it == "-verbose_build_progress" verbose_build_progress = true;
    else if it == "-timings" timings = true;
    else if begins_with(it, "-ir_case=") {
      ir_case = slice(it, 9, it.count);
    } else {
      compiler_report(tprint("Unrecognized argument '%'", it));
    }
  }

  {
    start_time := current_time_monotonic();
    defer {
      if timings {
        elapsed_time := to_float64_seconds(current_time_monotonic() - start_time);
        log("All examples built in %s", elapsed_time);
      }
    }
    
    emit_shader_outputs := run_tests;
    build("example/cpu_example.jai", "cpu_example", verbose_build_progress, timings, emit_shader_outputs);
    build("example/vulkan_example.jai", "vulkan_example", verbose_build_progress, timings, emit_shader_outputs);
    //build("example/glsl_example.jai", "glsl_example", verbose_build_progress);
    //build("example/hlsl_example.jai", "hlsl_example", verbose_build_progress);
    #if OS == .MACOS {
      build("example/metal_example.jai", "metal_example", verbose_build_progress, timings, emit_shader_outputs);
    }
    if ir_case.count == 0 {
      build("example/ir_smoke_metal_pair.jai", "ir_smoke_metal_pair", verbose_build_progress, timings, emit_shader_outputs);
      build("example/ir_smoke_vk_compute.jai", "ir_smoke_vk_compute", verbose_build_progress, timings, emit_shader_outputs);
      build("example/ir_smoke_vk_bindless.jai", "ir_smoke_vk_bindless", verbose_build_progress, timings, emit_shader_outputs);
    } else if ir_case == "metal_pair" {
      build("example/ir_smoke_metal_pair.jai", "ir_smoke_metal_pair", verbose_build_progress, timings, emit_shader_outputs);
    } else if ir_case == "vk_compute" {
      build("example/ir_smoke_vk_compute.jai", "ir_smoke_vk_compute", verbose_build_progress, timings, emit_shader_outputs);
    } else if ir_case == "vk_bindless" {
      build("example/ir_smoke_vk_bindless.jai", "ir_smoke_vk_bindless", verbose_build_progress, timings, emit_shader_outputs);
    } else {
      compiler_report(tprint("Unknown -ir_case value '%'. Expected one of: metal_pair, vk_compute, vk_bindless.", ir_case));
    }
  }

  if run_tests {
    TEST_RUNNER :: "test_runner.jai";
    log("Running %...", TEST_RUNNER);
    {
      time_scope(timings, "Compile test_runner.jai");
      build(TEST_RUNNER, "test_runner", verbose_build_progress, timings=false, emit_shader_outputs=true);
    }

    run_args: [..] string;
    array_add(*run_args, "./test_runner");
    result: Process_Result;
    output, error: string;
    timeout_reached: bool;
    if timings array_add(*run_args, "-timings");
    {
      time_scope(timings, "Run test_runner.jai");
      result, output, error, timeout_reached = run_command(..run_args);
    }
    if timeout_reached {
      compiler_report(tprint("% timed out.", TEST_RUNNER));
    }
    if result.type == .FAILED_TO_LAUNCH {
      compiler_report(tprint("Failed to launch %.", TEST_RUNNER));
    }
    if result.type != .EXITED || result.exit_code != 0 {
      compiler_report(tprint("% failed with exit code %.", TEST_RUNNER, result.exit_code));
    }
  }
}

build :: (build_file: string, output_exe_name: string, verbose_build_progress: bool=false, timings: bool=false, emit_shader_outputs: bool=false) {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();

  w := compiler_create_workspace(output_exe_name);

  options := get_build_options(w);
  options.output_executable_name = output_exe_name;
  options.text_output_flags = 0; // command_line_opts.text_output_flags;
  set_optimization(*options, .VERY_DEBUG);
  if emit_shader_outputs {
    compile_time_args: [..] string;
    for options.compile_time_command_line array_add(*compile_time_args, it);
    array_add(*compile_time_args, "-output_shaders");
    options.compile_time_command_line = compile_time_args;
  }
  if options.text_output_flags == 0 log("Building '%'...", output_exe_name);
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
