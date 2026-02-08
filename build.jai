#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";
#import "Metaprogram_Plugins";
#import,dir "."; // #import "Jai-Shader-Transpiler" in your code.

#run,stallable {
  command_line_opts := get_build_options();
  run_tests := false;
  for command_line_opts.compile_time_command_line {
    if it == "-run_tests" run_tests = true;
  }

  build("example/glsl_example.jai", "glsl_example");
  build("example/hlsl_example.jai", "hlsl_example");
  #if OS == .MACOS {
    build("example/metal_example.jai", "metal_example");
  }

  if run_tests {
    log("Running tests.jai...");
    result, output, error, timeout_reached := run_command("jai", "tests.jai", "+Autorun", capture_and_return_output=true);
    if output.count != 0 log("%", output);
    if error.count != 0 log_error("%", error);

    if timeout_reached {
      compiler_report("tests.jai timed out.");
    }
    if result.type == .FAILED_TO_LAUNCH {
      compiler_report("Failed to launch tests.jai.");
    }
    if result.type != .EXITED || result.exit_code != 0 {
      compiler_report(tprint("tests.jai failed with exit code %.", result.exit_code));
    }
  }
}

build :: (build_file: string, output_exe_name: string) {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();
  text_output_flags := command_line_opts.text_output_flags;

  w := compiler_create_workspace(output_exe_name);

  options := get_build_options(w);
  options.output_executable_name = output_exe_name;
  options.text_output_flags = text_output_flags;
  if text_output_flags == 0 {
    log("Building '%'...", output_exe_name);
  }
  set_build_options(options, w);

  jai_to_shader_plugin := get_plugin();
  jai_to_shader_plugin.workspace = w;

  autorun := false;
  for command_line_opts.compile_time_command_line {
      if it == {
        case "-run"; autorun = true;
        case "-output_shaders"; jai_to_shader_plugin.output_shaders = true;
      }
  }

  compiler_begin_intercept(w);
  add_build_file(build_file, w);
  message_loop(w, jai_to_shader_plugin);
  compiler_end_intercept(w);
  if autorun {
    run_command(output_exe_name);
  }
}

message_loop :: (w: Workspace, plugin: *Metaprogram_Plugin) {
  while true {
    message := compiler_wait_for_message();
    plugin.message(plugin, message);
    if message.kind == .COMPLETE break;
  }
}
