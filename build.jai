#import "Basic";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Process";

#import "Metaprogram_Plugins";

#import,file "Jai_To_Shader.jai";


#run,stallable {
  build("src/glsl_example.jai", "Shaders");
  build("src/hlsl_example.jai", "hlsl_example");
}

build :: (build_file: string, output_exe_name: string) {
  set_build_options_dc(.{do_output=false, write_added_strings=false});

  command_line_opts := get_build_options();
  text_output_flags := command_line_opts.text_output_flags;

  w := compiler_create_workspace("Shaders");

  options := get_build_options(w);
  options.output_executable_name = output_exe_name;
  options.text_output_flags = text_output_flags;
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
