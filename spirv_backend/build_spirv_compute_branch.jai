#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";
Proc :: #import "Process";
#import,file "../module.jai";

#run,stallable {
  set_build_options_dc(.{do_output=false, write_added_strings=false});
  command_line_opts := get_build_options();

  w := compiler_create_workspace("spirv_compute_branch_runner");
  options := get_build_options(w);
  options.output_executable_name = "spirv_compute_branch_runner";
  set_optimization(*options, .VERY_DEBUG);
  options.text_output_flags = command_line_opts.text_output_flags;
  explicit_import_paths: [..] string;
  array_add(*explicit_import_paths, "/Users/kev/src/peel/modules"); // Resolve `#import "generated"` to /src/peel/modules/generated.
  array_add(*explicit_import_paths, ..options.import_path);
  options.import_path = explicit_import_paths;
  set_build_options(options, w);

  plugin := get_plugin();
  plugin.workspace = w;
  plugin.use_spirv_backend = true;
  plugin.use_direct_spirv_text = true;

  for command_line_opts.compile_time_command_line {
    if it == "-slang_emit_line_directives" {
      plugin.slang_emit_line_directives = true;
    }

    if it == "-use_direct_spirv_text" {
      plugin.use_direct_spirv_text = true;
    }
  }

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);
  add_build_file("spirv_compute_branch_runner.jai", w);

  ok := false;
  while true {
    message := compiler_wait_for_message();
    plugin.message(plugin, message);
    if message.kind == .COMPLETE {
      ok = message.(*Message_Complete).error_code == 0;
      break;
    }
  }

  if !ok exit(1);

  result, output, error, timeout_reached := Proc.run_command("./spirv_compute_branch_runner", capture_and_return_output=true);
  if output.count != 0 log("%", output);
  if error.count != 0 log_error("%", error);
  if timeout_reached {
    compiler_report("spirv compute branch runner timed out");
  }
  if result.type == .FAILED_TO_LAUNCH {
    compiler_report("failed to launch spirv compute branch runner");
  }
  if result.type != .EXITED || result.exit_code != 0 {
    compiler_report(tprint("spirv compute branch runner failed with exit code %", result.exit_code));
  }
}
