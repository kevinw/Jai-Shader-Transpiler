#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";
#import "Metaprogram_Plugins";
#import,file "./module.jai"; // #import "Jai-Shader-Transpiler" in your code.

#run,stallable {
  command_line_opts := get_build_options();
  run_tests := false;
  use_ir_pipeline := false;
  verbose_build_progress := false;
  ir_case := "";
  for command_line_opts.compile_time_command_line {
    if it == "-run_tests" run_tests = true;
    if it == "-use_ir_pipeline" use_ir_pipeline = true;
    if it == "-verbose_build_progress" verbose_build_progress = true;
    if begins_with(it, "-ir_case=") {
      ir_case = slice(it, 9, it.count);
    }
  }

  {
    start_time := current_time_monotonic();
    defer {
      elapsed_time := to_float64_seconds(current_time_monotonic() - start_time);
      log("All examples built in %s", elapsed_time);
    }
    
    if !use_ir_pipeline {
      build("example/cpu_example.jai", "cpu_example", verbose_build_progress);
      build("example/vulkan_example.jai", "vulkan_example", verbose_build_progress);
      build("example/glsl_example.jai", "glsl_example", verbose_build_progress);
      build("example/hlsl_example.jai", "hlsl_example", verbose_build_progress);
    } else {
      if ir_case.count == 0 {
        build("example/ir_smoke_metal_pair.jai", "ir_smoke_metal_pair", verbose_build_progress);
        build("example/ir_smoke_vk_compute.jai", "ir_smoke_vk_compute", verbose_build_progress);
        build("example/ir_smoke_vk_bindless.jai", "ir_smoke_vk_bindless", verbose_build_progress);
      } else if ir_case == "metal_pair" {
        build("example/ir_smoke_metal_pair.jai", "ir_smoke_metal_pair", verbose_build_progress);
      } else if ir_case == "vk_compute" {
        build("example/ir_smoke_vk_compute.jai", "ir_smoke_vk_compute", verbose_build_progress);
      } else if ir_case == "vk_bindless" {
        build("example/ir_smoke_vk_bindless.jai", "ir_smoke_vk_bindless", verbose_build_progress);
      } else {
        compiler_report(tprint("Unknown -ir_case value '%'. Expected one of: metal_pair, vk_compute, vk_bindless.", ir_case));
      }
      log("Skipping OpenGL/HLSL examples in IR mode (-use_ir_pipeline): only METAL and VULKAN_GLSL are currently targeted.");
    }
    #if OS == .MACOS {
      if !use_ir_pipeline {
        build("example/metal_example.jai", "metal_example", verbose_build_progress);
      }
    }
  }

  if run_tests {
    TEST_RUNNER :: "test_runner.jai";
    log("Running %...", TEST_RUNNER);
    result, output, error, timeout_reached := run_command("jai", TEST_RUNNER, "+Autorun", capture_and_return_output=true);
    if output.count != 0 log("%", output);
    if error.count != 0 log_error("%", error);

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

build :: (build_file: string, output_exe_name: string, verbose_build_progress: bool=false) {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();
  text_output_flags := command_line_opts.text_output_flags;

  w := compiler_create_workspace(output_exe_name);

  options := get_build_options(w);
  options.output_executable_name = output_exe_name;
  options.text_output_flags = text_output_flags;
  set_optimization(*options, .VERY_DEBUG);
  if text_output_flags == 0 log("Building '%'...", output_exe_name);
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
        case "-output_shaders"; jai_to_shader_plugin.output_shaders = true;
        case "-use_ir_pipeline"; jai_to_shader_plugin.use_ir_pipeline = true;
      }
  }

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);
  add_build_file(build_file, w);
  compile_ok := message_loop(w, jai_to_shader_plugin, verbose_build_progress);
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
