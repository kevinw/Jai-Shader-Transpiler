#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";
Proc :: #import "Process";
#import,file "../module.jai";

simple_jst_build :: (name: string, source_filename: string) {

  command_line_opts := get_build_options();

  w := compiler_create_workspace("ir_compute_semantics_runner");
  options := get_build_options(w);
  options.output_executable_name = "ir_compute_semantics_runner";
  set_optimization(*options, .VERY_DEBUG);
  options.text_output_flags = command_line_opts.text_output_flags;
  explicit_import_paths: [..] string;
  array_add(*explicit_import_paths, "/Users/kev/src/peel/modules"); // TODO
  array_add(*explicit_import_paths, ..options.import_path);
  options.import_path = explicit_import_paths;
  set_build_options(options, w);

  plugin := get_plugin();
  plugin.workspace = w;
  timings := false;

  for command_line_opts.compile_time_command_line {
    if it == "-timings" timings = true;
  }

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);
  plugin.add_source(plugin);
  add_build_file(source_filename, w);

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

  run_args: [..] string;
  array_add(*run_args, "./ir_compute_semantics_runner");
  if timings array_add(*run_args, "-timings");
  result, output, error, timeout_reached := Proc.run_command(..run_args, capture_and_return_output=true);
  if output.count != 0 log("%", output);
  if error.count != 0 log_error("%", error);
  if timeout_reached {
    compiler_report("compute semantics runner timed out");
  }
  if result.type == .FAILED_TO_LAUNCH {
    compiler_report("failed to launch compute semantics runner");
  }
  if result.type != .EXITED || result.exit_code != 0 {
    compiler_report(tprint("compute semantics runner failed with exit code %", result.exit_code));
  }
}
