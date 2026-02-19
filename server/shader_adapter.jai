Shader_HTTP_Result :: struct {
  status: s32;
  body: string;
}

shader_request_serial: s64 = 0;

compile_jai_to_metal :: (shader_source: string) -> Shader_HTTP_Result {
  only_whitespace := true;
  for shader_source {
    if it != #char " " && it != #char "\n" && it != #char "\r" && it != #char "\t" {
      only_whitespace = false;
      break;
    }
  }
  if only_whitespace {
    return .{ status = 400, body = "Shader source is empty." };
  }

  shader_request_serial += 1;

  request_dir := tprint(".build/server_shader_requests/request_%", shader_request_serial);
  if !F.make_directory_if_it_does_not_exist(request_dir, recursive=true) {
    return .{ status = 500, body = "Failed to create request workspace directory." };
  }

  generated_module_dir := tprint("%/modules/generated", request_dir);
  if !F.make_directory_if_it_does_not_exist(generated_module_dir, recursive=true) {
    return .{ status = 500, body = "Failed to create generated module directory." };
  }
  if !F.write_entire_file(tprint("%/module.jai", generated_module_dir), "// generated module placeholder\n") {
    return .{ status = 500, body = "Failed to create generated module placeholder." };
  }

  source_path := tprint("%/input_shader.jai", request_dir);
  jst_root_abs, jst_root_ok := F.get_absolute_path("..");
  if !jst_root_ok {
    return .{ status = 500, body = "Failed to resolve transpiler module root path." };
  }

  wrapped_source := tprint("#import \"Basic\";\n#import \"Math\";\n#import,dir \"%\";\nG :: #import \"generated\";\n\n%\n", jst_root_abs, shader_source);
  if !F.write_entire_file(source_path, wrapped_source) {
    return .{ status = 500, body = "Failed to write shader source file." };
  }

  plugin_module_abs, plugin_ok := F.get_absolute_path("../module.jai");
  source_abs, source_ok := F.get_absolute_path(source_path);
  request_abs, request_ok := F.get_absolute_path(request_dir);
  if !plugin_ok || !source_ok || !request_ok {
    return .{ status = 500, body = "Failed to resolve compile request paths." };
  }

  script_path := tprint("%/compile_request.jai", request_dir);
  script_source := tprint(#string END
#import "Basic";
#import "Compiler";
JST :: #import,file "%";

#run,stallable {
  set_build_options_dc(.{do_output=false, write_added_strings=false});
  set_working_directory("%");

  w := compiler_create_workspace("server_shader_request");
  defer compiler_destroy_workspace(w);

  options := get_build_options(w);
  options.output_type = .NO_OUTPUT;
  options.output_executable_name = "server_shader_request";
  set_build_options(options, w);

  plugin := JST.get_plugin();
  plugin.workspace = w;
  plugin.output_shaders = true;

  p := cast(*Metaprogram_Plugin) plugin;

  compiler_begin_intercept(w);
  defer compiler_end_intercept(w);

  add_build_file("%", w);

  ok := false;
  while true {
    message := compiler_wait_for_message();
    if p.message p.message(p, message);
    if message.kind == .COMPLETE {
      complete := cast(*Message_Complete) message;
      ok = complete.error_code == .NONE;
      break;
    }
  }

  if !ok exit(1);
}
END,
    plugin_module_abs, request_abs, source_abs);

  if !F.write_entire_file(script_path, script_source) {
    return .{ status = 500, body = "Failed to write compile script." };
  }

  script_abs, script_ok := F.get_absolute_path(script_path);
  if !script_ok {
    return .{ status = 500, body = "Failed to resolve compile script path." };
  }

  result, output, error, timeout_reached := run_command("jai", "-quiet", script_abs, capture_and_return_output=true, working_directory=request_abs, timeout_ms=60000);
  if timeout_reached {
    return .{ status = 504, body = "Shader compile timed out." };
  }
  if result.type == .FAILED_TO_LAUNCH {
    return .{ status = 500, body = "Failed to launch 'jai' compiler process." };
  }
  if result.type != .EXITED || result.exit_code != 0 {
    if error.count > 0 return .{ status = 422, body = error };
    if output.count > 0 return .{ status = 422, body = output };
    return .{ status = 422, body = "Shader compilation failed." };
  }

  generated_dir := tprint("%/.generated_shaders", request_dir);
  metal_files := collect_files_with_extension_in_dir(generated_dir, ".metal");
  if metal_files.count == 0 {
    return .{ status = 422, body = "No Metal shaders were generated. Check your @shader_to_metal / @shader_pair_to_metal annotations." };
  }

  sb: String_Builder;
  for metal_files {
    source, ok := F.read_entire_file(it);
    if !ok continue;
    append(*sb, tprint("// ---- % ----\n", it));
    append(*sb, source);
    append(*sb, "\n\n");
  }

  out := builder_to_string(*sb);
  if out.count == 0 {
    return .{ status = 500, body = "Generated shader files were unreadable." };
  }

  return .{ status = 200, body = out };
}

collect_files_with_extension_in_dir :: (directory: string, extension: string) -> [..] string {
  Args :: struct {
    directory: string;
    extension: string;
    files: *[..] string;
  }

  files: [..] string;
  args: Args;
  args.directory = directory;
  args.extension = extension;
  args.files = *files;

  visitor :: (info: *FU.File_Visit_Info, args: *Args) {
    if !Str.ends_with(info.short_name, args.extension) return;
    array_add(args.files, copy_string(tprint("%/%", args.directory, info.short_name)));
  }

  ok := FU.visit_files(directory, recursive=false, *args, visitor, visit_files=true, visit_directories=false);
  if !ok return files;

  return files;
}

#scope_file
#import "Basic";
F :: #import "File";
FU :: #import "File_Utilities";
Str :: #import "String";
#import "Process";
