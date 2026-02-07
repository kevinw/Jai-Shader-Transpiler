#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";

#import "Metaprogram_Plugins";

#load "Jai_To_Shader.jai";

jai_to_shader_plugin: *Metaprogram_Plugin;
OUTPUT_EXE_NAME :: "Shaders";

#run build();
build :: () {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();
  text_output_flags := command_line_opts.text_output_flags;

  w := compiler_create_workspace("Shaders");

  options := get_build_options(w);
  options.output_executable_name = OUTPUT_EXE_NAME;
  options.text_output_flags = text_output_flags;
  set_build_options(options, w);

  jai_to_shader_plugin = get_plugin();
  jai_to_shader_plugin.workspace = w;

  compiler_begin_intercept(w);
  add_build_file("./src/glsl_example.jai", w);
  message_loop(w);
  compiler_end_intercept(w);

  for command_line_opts.compile_time_command_line {
      if it == "-run" {
          run_command(OUTPUT_EXE_NAME);
      }
  }
}

message_loop :: (w: Workspace) {
  while true {
    message := compiler_wait_for_message();

    convert_procs(jai_to_shader_plugin, message);

    if message.kind == .COMPLETE break;
  }
}
