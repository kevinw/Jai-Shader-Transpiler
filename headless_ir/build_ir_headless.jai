#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";
#import,file "../module.jai";

#run,stallable {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();

  w := compiler_create_workspace("ir_headless_runner");
  options := get_build_options(w);
  options.output_executable_name = "ir_headless_runner";
  set_optimization(*options, .VERY_DEBUG);
  options.text_output_flags = command_line_opts.text_output_flags;
  set_build_options(options, w);

  plugin := get_plugin();
  plugin.workspace = w;

  for command_line_opts.compile_time_command_line {
    if it == "-output_shaders" {
      plugin.output_shaders = true;
    }
    if it == "-use_ir_pipeline" {
      plugin.use_ir_pipeline = true;
    }
  }

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);
  add_build_file("ir_headless_runner.jai", w);

  ok := false;
  while true {
    message := compiler_wait_for_message();
    plugin.message(plugin, message);
    if message.kind == .COMPLETE {
      ok = message.(*Message_Complete).error_code == 0;
      break;
    }
  }

  if !ok {
    exit(1);
  }
}
