// TODOS:
// Add the different types of Vectors and implement the 'Component Comparison' set of GLSL functions
// Translation for more advanced jai features
// Add the differet types of Samplers
// Add support for out parameters
// Add support for structs and arrays
// Add support for Geometry and Compute Shaders

// Think about:
// Changing GLSL version without changing module code.
// Adding #line directive for shader debuggers to point back at the original Jai file

VERBOSE      :: false;
DEBUG_OUTDIR :: ".generated_shaders";

Transpiled_Target :: enum {
  METAL;
  HLSL;
  OPENGL_GLSL;
  VULKAN_GLSL;
}

#load "backend_shared.jai";
#load "ir_pipeline/slang_toolchain.jai";
#load "ir_pipeline/ir_shared.jai";
#load "ir_pipeline/ir_lowering.jai";
#load "ir_pipeline/spirv_text_backend.jai";

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    
    // options
    output_shaders: bool;
    use_spirv_backend: bool;
    use_direct_spirv_text: bool;
    slang_emit_line_directives: bool;
    
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      generated_module_import: *Message_Import;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      did_emit_lookup_overloads: bool;
      did_log_ir_pipeline: bool;
      did_log_ir_limitations: bool;
    }
}

Transpiled_Lookup_Entry :: struct {
  target_name: string;
  primary_name: string;
  secondary_name: string;
  symbol_name: string;
}

get_plugin :: () -> *Jai_To_Shader_Plugin {
  p := New(Jai_To_Shader_Plugin);
  p.use_spirv_backend = false; // Experimental: IR -> SPIR-V -> spirv-cross path.
  p.use_direct_spirv_text = false; // Experimental: direct IR -> SPIR-V text emission.
  p.slang_emit_line_directives = false; // Default: emit cleaner Slang outputs without #line noise.
  opts := get_build_options();
  for opts.compile_time_command_line {
    if it == "-slang_emit_line_directives" {
      p.slang_emit_line_directives = true;
    }
    if it == "-use_spirv_backend" {
      p.use_spirv_backend = true;
      p.use_direct_spirv_text = true;
    }
    if it == "-use_direct_spirv_text" {
      p.use_direct_spirv_text = true;
    }
  }

  p.message = convert_procs;

  return p;
}

get_transpiled_requests_seen: Table(string, bool);

expression_to_source_string :: (node: *Code_Node) -> string {
  sb: String_Builder;
  PP.print_expression(*sb, node);
  return builder_to_string(*sb);
}

transpiled_target_from_expr_string :: (expr: string) -> (single_note: string, pair_note: string, supports_pair: bool, is_metal: bool, ok: bool) {
  if expr == {
    case ".METAL";       return "shader_to_metal",  "shader_pair_to_metal",  true,  true,  true;
    case ".HLSL";        return "shader_to_hlsl",   "",                      false, false, true;
    case ".OPENGL_GLSL"; return "shader_to_glsl",   "shader_pair_to_glsl",   true,  false, true;
    case ".VULKAN_GLSL"; return "shader_to_vulkan", "shader_pair_to_vulkan", true,  false, true;
  }
  return "", "", false, false, false;
}

shader_name_from_call_arg :: (arg: *Code_Node) -> (string, bool) {
  if !arg return "", false;
  if arg.kind == {
    case .IDENT;
      ident := cast(*Code_Ident) arg;
      return ident.name, true;
    case .PROCEDURE_BODY;
      proc := cast(*Code_Procedure_Body) arg;
      return proc.header.name, true;
    case .PROCEDURE_HEADER;
      header := cast(*Code_Procedure_Header) arg;
      return header.name, true;
  }

  expr := trim_ascii_whitespace(expression_to_source_string(arg));
  if expr.count == 0 return "", false;

  end := expr.count - 1;
  while end >= 0 {
    ch := expr[end];
    if (ch >= #char "a" && ch <= #char "z") || (ch >= #char "A" && ch <= #char "Z") || (ch >= #char "0" && ch <= #char "9") || ch == #char "_" {
      break;
    }
    end -= 1;
  }
  if end < 0 return "", false;

  start := end;
  while start >= 0 {
    ch := expr[start];
    if !((ch >= #char "a" && ch <= #char "z") || (ch >= #char "A" && ch <= #char "Z") || (ch >= #char "0" && ch <= #char "9") || ch == #char "_") {
      break;
    }
    start -= 1;
  }
  start += 1;

  name: string;
  name.data = expr.data + start;
  name.count = end - start + 1;
  if name.count == 0 return "", false;
  return name, true;
}

sanitize_identifier_component :: (in: string) -> string {
  out := copy_string(in);
  out = replace(out, ".", "_");
  out = replace(out, " ", "_");
  out = replace(out, "(", "_");
  out = replace(out, ")", "_");
  out = replace(out, ",", "_");
  return out;
}

ensure_get_transpiled_request_registered :: (key: string, source: string) #compile_time {
  found, _ := table_find(*get_transpiled_requests_seen, key);
  if found return;
  table_add(*get_transpiled_requests_seen, key, true);
  add_build_string(source, get_current_workspace());
}

get_transpiled_result_expr_from_call :: (call: Code, loc: Source_Code_Location) -> string #compile_time {
  root := compiler_get_nodes(call);
  if root.kind != .PROCEDURE_CALL {
    compiler_report("Jai Shader Transpiler: get_transpiled must be called directly (e.g. get_transpiled(.METAL, vertex_fn, fragment_fn)).", loc=loc);
    return "";
  }

  pc := cast(*Code_Procedure_Call) root;
  if pc.arguments_unsorted.count != 2 && pc.arguments_unsorted.count != 3 {
    compiler_report("Jai Shader Transpiler: get_transpiled expects 2 args (target, stage_fn) or 3 args (target, vertex_fn, fragment_fn).", loc=loc);
    return "";
  }

  target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
  target_ident := sanitize_identifier_component(target_expr);
  single_note, pair_note, supports_pair, _, target_ok := transpiled_target_from_expr_string(target_expr);
  if !target_ok {
    compiler_report("Jai Shader Transpiler: First argument to get_transpiled must be .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.", loc=loc);
    return "";
  }

  shader_name, shader_ok := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
  if !shader_ok {
    compiler_report("Jai Shader Transpiler: get_transpiled shader arguments must be procedure identifiers.", loc=loc);
    return "";
  }

  if pc.arguments_unsorted.count == 2 {
    request_name := tprint("__get_transpiled_single_%_%", target_ident, shader_name);
    to_lower_in_place(request_name);
    key := tprint("single|%|%", single_note, shader_name);
    request_source := tprint("% :: %; @%\n", request_name, shader_name, single_note);
    ensure_get_transpiled_request_registered(key, request_source);
    return tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", target_expr, shader_name);
  }

  if !supports_pair {
    compiler_report("Jai Shader Transpiler: get_transpiled target does not support paired graphics shaders for this backend.", loc=loc);
    return "";
  }

  fragment_name, fragment_ok := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
  if !fragment_ok {
    compiler_report("Jai Shader Transpiler: get_transpiled fragment argument must be a procedure identifier.", loc=loc);
    return "";
  }

  request_name := tprint("__get_transpiled_pair_%_%_%", target_ident, shader_name, fragment_name);
  to_lower_in_place(request_name);
  key := tprint("pair|%|%|%", pair_note, shader_name, fragment_name);
  request_source := tprint("% :: %; @%(%)\n", request_name, shader_name, pair_note, fragment_name);
  ensure_get_transpiled_request_registered(key, request_source);
  return tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", target_expr, shader_name, fragment_name);
}

get_transpiled :: (target: Transpiled_Target, args: ..Any, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> string #expand {
  #insert #run tprint("G :: #import \"generated\";\nreturn %;",
                      get_transpiled_result_expr_from_call(call, loc));
}

convert_procs :: (p: *Metaprogram_Plugin, message: *Message) {
  plugin := cast(*Jai_To_Shader_Plugin) p;

  if message.kind == {
    case .IMPORT; {
      import_message := cast(*Message_Import) message;
      if import_message.module_name == "generated" || import_message.module_name == "Jai-Shader-Transpiler/generated" {
        plugin.generated_module_import = import_message;
      }
    }

    case .TYPECHECKED; {
      tc := cast(*Message_Typechecked) message;
      for tc.procedure_bodies {
        proc := it.expression;
        already := false;
        for plugin.known_procedure_bodies if it == proc { already = true; break; }
        if !already array_add(*plugin.known_procedure_bodies, proc);
      }

      for tc.declarations {
        resolved := collect_shader_requests_from_declaration(plugin, it.expression, plugin.known_procedure_bodies);
        if !resolved add_pending_request_declaration(plugin, it.expression);
      }

      for plugin.pending_request_declarations {
        if collect_shader_requests_from_declaration(plugin, it, plugin.known_procedure_bodies) {
          remove it;
        }
      }
    }
    
    case .PHASE; {
      phase := cast(*Message_Phase) message;
      if phase.phase == .TYPECHECKED_ALL_WE_CAN {
        if !plugin.did_log_ir_pipeline {
          plugin.did_log_ir_pipeline = true;
        }

        for * pair_ctx: plugin.currently_waiting_pair_contexts {
          s: string;
          used_ir_pipeline := false;
          if plugin.use_spirv_backend {
            s2, ok2, diag := write_shader_pair_ir_spirv(pair_ctx, plugin.slang_emit_line_directives);
            if ok2 {
              s = s2;
              used_ir_pipeline = true;
            } else {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader pair '%'.", pair_ctx.name);
              if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
              if diag.has_location compiler_report(report_message, diag.location);
              else compiler_report(report_message, make_location(pair_ctx.vertex_fn.header));
              remove pair_ctx;
              continue;
            }
          } else {
            s2, ok2, diag := write_shader_pair_ir_slang(pair_ctx, plugin.slang_emit_line_directives);
            if ok2 {
              s = s2;
              used_ir_pipeline = true;
            } else {
              report_message := tprint("Jai Shader Transpiler: IR-only mode failed for shader pair '%'.", pair_ctx.name);
              if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
              if diag.has_location compiler_report(report_message, diag.location);
              else compiler_report(report_message, make_location(pair_ctx.vertex_fn.header));
              remove pair_ctx;
              continue;
            }
          }

          assert(s != "");
          if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
          else add_build_string(s, p.workspace);

          if plugin.output_shaders && !(used_ir_pipeline && is_internal_transpiled_request_name(pair_ctx.name)) {
            ext := tprint("%", pair_ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, pair_ctx.name, ext);
            ok := false;
            ir_source_path := ir_output_path_from_pair_context(pair_ctx);
            file_source, read_ok := read_entire_file(ir_source_path);
            if !read_ok {
              log_error("Error reading IR output file '%'", ir_source_path);
              assert(false);
            }
            ok = write_entire_file(filename, file_source);
            if !ok {
              log_error("Error writing file to '%'", filename);
            } else {
              #if VERBOSE log("Transpiled Jai pair shader to %", filename);
            }
          }

          remove pair_ctx;
        }

        for * ctx: plugin.currently_waiting_contexts {
          
          s: string;
          if plugin.use_spirv_backend {
            s2, ok2, diag := write_shader_single_ir_spirv(ctx, plugin.use_direct_spirv_text);
            if ok2 {
              s = s2;
            } else {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
              if diag.has_location compiler_report(report_message, diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              remove ctx;
              continue;
            }
          } else {
            s2, ok2, diag := write_shader_single_ir_slang(ctx, plugin.slang_emit_line_directives);
            if ok2 {
              s = s2;
            } else {
              report_message := tprint("Jai Shader Transpiler: IR-only mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
              if diag.has_location compiler_report(report_message, diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              remove ctx;
              continue;
            }
          }

          if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
          else add_build_string(s, p.workspace);
          if plugin.output_shaders && !is_internal_transpiled_request_name(ctx.name) {
            ext := tprint("%", ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, ctx.name, ext);
            ok := false;
            ir_source_path := ir_output_path_from_context(ctx);
            file_source, read_ok := read_entire_file(ir_source_path);
            if !read_ok {
              log_error("Error reading IR output file '%'", ir_source_path);
              assert(false);
            }
            ok = write_entire_file(filename, file_source);
            if !ok {
              log_error("Error writing file to '%'", filename);
            } else {
              #if VERBOSE log("Transpiled Jai to %", filename);
            }
          }
          remove ctx;
        }

        emit_lookup_overloads(plugin, p.workspace);
      }
    }
    
    case .COMPLETE; {
      if plugin.currently_waiting_contexts.count != 0 || plugin.currently_waiting_pair_contexts.count != 0 {
        compiler_report("Jai Shader Transpiler: Something went wrong while converting Jai Shaders to shader code.\nThere's some functions that have not yet been transpiled, that a shader is waiting on. This is not good.");
      }
      array_reset(*plugin.currently_waiting_contexts);
      array_reset(*plugin.currently_waiting_pair_contexts);
      array_reset(*plugin.pending_request_declarations);
      array_reset(*plugin.known_procedure_bodies);
      plugin.generated_module_import = null;
      array_reset(*plugin.lookup_entries);
      plugin.did_emit_lookup_overloads = false;
      plugin.did_log_ir_pipeline = false;
      plugin.did_log_ir_limitations = false;
      table_reset(*get_transpiled_requests_seen);
    }
  }
}

ir_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.language != .METAL && !(ctx.language == .GLSL && ctx.glsl_target == .VULKAN) return false;
  return ctx.type == .Vertex || ctx.type == .Fragment || ctx.type == .Compute;
}

ir_symbol_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.language == .METAL return tprint("%_metal_string", ctx.name);
  return tprint("%_string", ctx.name);
}

ir_entry_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.type == .Vertex return "VertexMain";
  if ctx.type == .Fragment return "FragmentMain";
  if ctx.type == .Compute return "ComputeMain";
  return "";
}

ir_stage_from_context :: (ctx: *Shader_Write_Context) -> (Slang_Stage, bool) {
  if ctx.type == .Vertex return .VERTEX, true;
  if ctx.type == .Fragment return .FRAGMENT, true;
  if ctx.type == .Compute return .COMPUTE, true;
  return .VERTEX, false;
}

ir_target_from_context :: (ctx: *Shader_Write_Context) -> (Slang_Target, bool) {
  if ctx.language == .METAL return .METAL, true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return .VULKAN_GLSL, true;
  return .METAL, false;
}

ir_stage_short_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.type == .Vertex return "vert";
  if ctx.type == .Compute return "comp";
  return "frag";
}

ir_output_ext_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.language == .METAL return "metal";
  return "glsl";
}

ir_output_path_from_context :: (ctx: *Shader_Write_Context) -> string {
  build_dir := ".build/ir_slang";
  return tprint("%/%_%.%", build_dir, ctx.name, ir_stage_short_from_context(ctx), ir_output_ext_from_context(ctx));
}

ir_output_path_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  build_dir := ".build/ir_slang";
  return tprint("%/%_pair.metal", build_dir, pair_ctx.name);
}

is_internal_transpiled_request_name :: (name: string) -> bool {
  return begins_with(name, "__get_transpiled_");
}

ir_mark_metal_device_pointers_const :: (source: string) -> string {
  // Slang currently emits graphics buffer params as `T device*` in Metal wrappers, which triggers
  // writable-resource warnings on non-void vertex functions. Rewriting to `T const device*` keeps
  // the generated code semantically read-only for graphics stages and removes that warning.
  return replace(source, " device*", " const device*");
}

ir_source_file_from_proc :: (proc: *Code_Procedure_Body) -> string {
  if !proc || !proc.header return "";
  loc := make_location(proc.header);
  return loc.fully_pathed_filename;
}

ir_source_file_from_context :: (ctx: *Shader_Write_Context) -> string {
  if !ctx return "";
  return ir_source_file_from_proc(ctx.main_fn);
}

ir_source_file_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  if !pair_ctx return "";
  vertex_file := ir_source_file_from_proc(pair_ctx.vertex_fn);
  fragment_file := ir_source_file_from_proc(pair_ctx.fragment_fn);
  if vertex_file.count == 0 return fragment_file;
  if fragment_file.count == 0 return vertex_file;
  if vertex_file == fragment_file return vertex_file;
  return tprint("% | %", vertex_file, fragment_file);
}

ir_pipeline_label_slang :: (target: Slang_Target) -> string {
  if target == .METAL return "Jai -> IR -> Slang -> Metal";
  return "Jai -> IR -> Slang -> GLSL";
}

ir_pipeline_label_spirv :: (target: Slang_Target) -> string {
  if target == .METAL return "Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal";
  return "Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL";
}

ir_prepend_generated_comment :: (target_source: string, source_jai_file: string, pipeline_label: string) -> string {
  jai_file := source_jai_file;
  if jai_file.count == 0 jai_file = "<unknown>";
  return tprint("// Generated from % with (<<%>>)\n%", jai_file, pipeline_label, target_source);
}

write_shader_single_ir_slang :: (ctx: *Shader_Write_Context, emit_line_directives := false) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !ir_supports_single_context(ctx) {
    diag.message = "IR lowering: unsupported shader context/target combination.";
    if ctx && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  stage, stage_ok := ir_stage_from_context(ctx);
  target, target_ok := ir_target_from_context(ctx);
  if !stage_ok || !target_ok {
    diag.message = "IR lowering: unsupported shader stage/target combination.";
    if ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  slang_source: string;
  entry_name: string;
  if ctx.type == .Vertex {
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(ctx);
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    emitted_source, emitted := emit_ir_vertex_to_slang(ir_vertex);
    if !emitted {
      #if VERBOSE log("IR->Slang emission failed for %", ctx.name);
      diag.message = tprint("IR->Slang emission failed for vertex shader '%'.", ctx.name);
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
      return "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_vertex.entry_name;
  } else if ctx.type == .Fragment {
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(ctx);
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    emitted_source, emitted := emit_ir_fragment_to_slang(ir_fragment);
    if !emitted {
      #if VERBOSE log("IR->Slang emission failed for %", ctx.name);
      diag.message = tprint("IR->Slang emission failed for fragment shader '%'.", ctx.name);
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
      return "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_fragment.entry_name;
  } else if ctx.type == .Compute {
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(ctx);
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    emitted_source, emitted := emit_ir_compute_to_slang(ir_compute);
    if !emitted {
      #if VERBOSE log("IR->Slang emission failed for %", ctx.name);
      diag.message = tprint("IR->Slang emission failed for compute shader '%'.", ctx.name);
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
      return "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_compute.entry_name;
  } else {
    diag.message = "IR lowering: unsupported shader type.";
    if ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);

  stage_short := "frag";
  if ctx.type == .Vertex stage_short = "vert";
  if ctx.type == .Compute stage_short = "comp";
  source_path := tprint("%/%_%.slang", build_dir, ctx.name, stage_short);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";
  output_path := tprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);

  if !write_entire_file(source_path, slang_source) {
    #if VERBOSE log("Failed writing IR Slang source %", source_path);
    diag.message = tprint("IR pipeline: failed writing Slang source file '%'.", source_path);
    return "", false, diag;
  }

  if entry_name.count == 0 {
    diag.message = "IR pipeline: entry name is empty.";
    if ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }
  if !emit_slang_target_source(source_path, entry_name, stage, target, output_path, emit_line_directives) {
    #if VERBOSE log("Slang target emission failed for %", ctx.name);
    diag.message = tprint("IR pipeline: Slang target emission failed for shader '%'. Source: %", ctx.name, source_path);
    if ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  target_source, ok := read_entire_file(output_path);
  if !ok {
    diag.message = tprint("IR pipeline: failed reading emitted target source '%'.", output_path);
    return "", false, diag;
  }
  if ctx.language == .METAL && ctx.type != .Compute {
    target_source = ir_mark_metal_device_pointers_const(target_source);
    // Keep .build/ir_slang output aligned with the embedded string for debugging and test checks.
    write_entire_file(output_path, target_source);
  }
  if ctx.type == .Compute && ctx.language == .METAL {
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(ctx), ir_pipeline_label_slang(target));
  // Keep .build/ir_slang output aligned with the embedded string for debugging and test checks.
  write_entire_file(output_path, target_source);

  symbol_name := ir_symbol_name_from_context(ctx);
  decl := tprint("% :: #string END\n%\nEND", symbol_name, target_source);
  return decl, true, diag;
}

ir_spirv_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.type != .Vertex && ctx.type != .Fragment && ctx.type != .Compute return false;
  if ctx.language == .METAL return true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return true;
  return false;
}

ir_emit_single_spirv_target_source :: (ctx: *Shader_Write_Context, use_direct_spirv_text := false, add_generated_comment := true) -> (string, string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !ir_spirv_supports_single_context(ctx) {
    diag.message = "SPIR-V backend currently supports vertex/fragment/compute shaders targeting Metal or Vulkan GLSL only.";
    if ctx && ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  stage, stage_ok := ir_stage_from_context(ctx);
  if !stage_ok {
    diag.message = "SPIR-V backend: unsupported shader stage.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  slang_source: string;
  entry_name: string;
  if ctx.type == .Vertex {
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(ctx);
    if !lowered return "", "", false, lowered_diag;
    emitted_source, emitted := emit_ir_vertex_to_slang(ir_vertex);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for vertex shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_vertex.entry_name;
  } else if ctx.type == .Fragment {
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(ctx);
    if !lowered return "", "", false, lowered_diag;
    emitted_source, emitted := emit_ir_fragment_to_slang(ir_fragment);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for fragment shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_fragment.entry_name;
  } else {
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(ctx);
    if !lowered return "", "", false, lowered_diag;
    emitted_source, emitted := emit_ir_compute_to_slang(ir_compute);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for compute shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_compute.entry_name;
  }

  target, target_ok := ir_target_from_context(ctx);
  if !target_ok {
    diag.message = "SPIR-V backend: unsupported target for context.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);

  stage_short := ir_stage_short_from_context(ctx);
  source_path := tprint("%/%_%.slang", build_dir, ctx.name, stage_short);
  spv_path := tprint("%/%_%.spv", build_dir, ctx.name, stage_short);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";
  output_path := tprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);

  if !write_entire_file(source_path, slang_source) {
    diag.message = tprint("SPIR-V backend: failed writing Slang source file '%'.", source_path);
    return "", "", false, diag;
  }

  if entry_name.count == 0 {
    diag.message = "SPIR-V backend: empty entry name.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  if use_direct_spirv_text && ctx.type == .Compute {
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(ctx);
    if !lowered return "", "", false, lowered_diag;
    spvasm_source, spvasm_ok, spvasm_diag := emit_ir_compute_to_spirv_text_branch(ir_compute);
    if !spvasm_ok {
      if spvasm_diag.message.count == 0 spvasm_diag.message = tprint("SPIR-V text backend: failed to emit SPIR-V assembly for '%'.", ctx.name);
      if !spvasm_diag.has_location && ctx.main_fn && ctx.main_fn.header {
        spvasm_diag.location = make_location(ctx.main_fn.header);
        spvasm_diag.has_location = true;
      }
      return "", "", false, spvasm_diag;
    }
    spvasm_path := tprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
    if !write_entire_file(spvasm_path, spvasm_source) {
      diag.message = tprint("SPIR-V backend: failed writing SPIR-V text file '%'.", spvasm_path);
      return "", "", false, diag;
    }
    if !assemble_spirv_text(spvasm_path, spv_path) {
      diag.message = tprint("SPIR-V backend: failed assembling SPIR-V text for '%'. Source: %", ctx.name, spvasm_path);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
  } else {
    if !compile_slang_to_spirv(source_path, entry_name, stage, spv_path) {
      diag.message = tprint("SPIR-V backend: failed compiling SPIR-V for '%'. Source: %", ctx.name, source_path);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return "", "", false, diag;
    }
  }

  if !validate_spirv_binary(spv_path) {
    diag.message = tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", ctx.name, spv_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  if !emit_spirv_cross_target_source(spv_path, entry_name, stage, target, output_path) {
    diag.message = tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", ctx.name, spv_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  target_source, ok := read_entire_file(output_path);
  if !ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", output_path);
    return "", "", false, diag;
  }
  if ctx.language == .METAL && ctx.type != .Compute {
    target_source = ir_mark_metal_device_pointers_const(target_source);
    write_entire_file(output_path, target_source);
  }
  if ctx.type == .Compute && ctx.language == .METAL {
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(ctx), ir_pipeline_label_spirv(target));
  }
  write_entire_file(output_path, target_source);

  return target_source, output_path, true, diag;
}

write_shader_single_ir_spirv :: (ctx: *Shader_Write_Context, use_direct_spirv_text := false) -> (string, bool, IR_Diagnostic) {
  target_source, _, ok, diag := ir_emit_single_spirv_target_source(ctx, use_direct_spirv_text, add_generated_comment=true);
  if !ok return "", false, diag;

  symbol_name := ir_symbol_name_from_context(ctx);
  decl := tprint("% :: #string END\n%\nEND", symbol_name, target_source);
  return decl, true, diag;
}

ir_strip_metal_preamble_for_pair_merge :: (source: string) -> string {
  marker := "using namespace metal;";
  index := find_index_from_left(source, marker);
  if index == -1 return source;

  start := index + marker.count;
  while start < source.count && (source[start] == #char "\n" || source[start] == #char "\r")
    start += 1;

  stripped: string;
  stripped.data = source.data + start;
  stripped.count = source.count - start;
  return stripped;
}

write_shader_pair_ir_spirv :: (pair_ctx: *Shader_Write_Pair_Context, emit_line_directives := false) -> (string, bool, IR_Diagnostic) {
  _ = emit_line_directives;

  diag: IR_Diagnostic;
  if !ir_supports_pair_context(pair_ctx) {
    diag.message = "SPIR-V backend: unsupported shader pair context/target combination.";
    if pair_ctx && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  vertex_ctx := create_shader_write_context(.METAL, pair_ctx.vertex_fn, pair_ctx.glsl_target);
  fragment_ctx := create_shader_write_context(.METAL, pair_ctx.fragment_fn, pair_ctx.glsl_target);

  vertex_source, _, vertex_emitted, vertex_diag := ir_emit_single_spirv_target_source(*vertex_ctx, use_direct_spirv_text=false, add_generated_comment=false);
  if !vertex_emitted {
    if !vertex_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      vertex_diag.location = make_location(pair_ctx.vertex_fn.header);
      vertex_diag.has_location = true;
    }
    return "", false, vertex_diag;
  }

  fragment_source, _, fragment_emitted, fragment_diag := ir_emit_single_spirv_target_source(*fragment_ctx, use_direct_spirv_text=false, add_generated_comment=false);
  if !fragment_emitted {
    if !fragment_diag.has_location && pair_ctx.fragment_fn && pair_ctx.fragment_fn.header {
      fragment_diag.location = make_location(pair_ctx.fragment_fn.header);
      fragment_diag.has_location = true;
    }
    return "", false, fragment_diag;
  }

  merged_source := tprint("%\n\n%", vertex_source, ir_strip_metal_preamble_for_pair_merge(fragment_source));
  merged_source = ir_prepend_generated_comment(merged_source, ir_source_file_from_pair_context(pair_ctx), ir_pipeline_label_spirv(.METAL));

  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  output_path := ir_output_path_from_pair_context(pair_ctx);
  if !write_entire_file(output_path, merged_source) {
    diag.message = tprint("SPIR-V backend: failed writing merged pair source '%'.", output_path);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  decl := tprint("%_metal_string :: #string END\n%\nEND", pair_ctx.name, merged_source);
  return decl, true, diag;
}

ir_supports_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> bool {
  if !pair_ctx return false;
  if pair_ctx.language != .METAL return false;
  return pair_ctx.vertex_fn != null && pair_ctx.fragment_fn != null;
}

write_shader_pair_ir_slang :: (pair_ctx: *Shader_Write_Pair_Context, emit_line_directives := false) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !ir_supports_pair_context(pair_ctx) {
    diag.message = "IR lowering: unsupported shader pair context/target combination.";
    if pair_ctx && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  vertex_ctx := create_shader_write_context(.METAL, pair_ctx.vertex_fn, pair_ctx.glsl_target);
  fragment_ctx := create_shader_write_context(.METAL, pair_ctx.fragment_fn, pair_ctx.glsl_target);
  ir_vertex, vertex_ok, vertex_diag := ir_lower_vertex_from_shader_context(*vertex_ctx);
  if !vertex_ok return "", false, vertex_diag;
  ir_fragment, fragment_ok, fragment_diag := ir_lower_fragment_from_shader_context(*fragment_ctx);
  if !fragment_ok return "", false, fragment_diag;

  slang_source, emitted := emit_ir_graphics_pair_to_slang(ir_vertex, ir_fragment);
  if !emitted {
    diag.message = tprint("IR->Slang emission failed for shader pair '%'.", pair_ctx.name);
    diag.location = make_location(pair_ctx.vertex_fn.header);
    diag.has_location = true;
    return "", false, diag;
  }

  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);

  source_path := tprint("%/%_pair.slang", build_dir, pair_ctx.name);
  output_path := tprint("%/%_pair.metal", build_dir, pair_ctx.name);
  if !write_entire_file(source_path, slang_source) {
    diag.message = tprint("IR pipeline: failed writing Slang source file '%'.", source_path);
    return "", false, diag;
  }
  if !emit_slang_module_target_source(source_path, .METAL, output_path, emit_line_directives) {
    diag.message = tprint("IR pipeline: Slang module emission failed for pair '%'. Source: %", pair_ctx.name, source_path);
    diag.location = make_location(pair_ctx.vertex_fn.header);
    diag.has_location = true;
    return "", false, diag;
  }

  target_source, ok := read_entire_file(output_path);
  if !ok {
    diag.message = tprint("IR pipeline: failed reading emitted target source '%'.", output_path);
    return "", false, diag;
  }
  target_source = ir_mark_metal_device_pointers_const(target_source);
  target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_pair_context(pair_ctx), ir_pipeline_label_slang(.METAL));
  // Keep .build/ir_slang output aligned with the embedded string for debugging and test checks.
  write_entire_file(output_path, target_source);
  decl := tprint("%_metal_string :: #string END\n%\nEND", pair_ctx.name, target_source);
  return decl, true, diag;
}

shader_request_name_to_language :: (name: string) -> (Shader_Language, GLSL_Target, bool) {
  if name == {
    case "shader_to_glsl";   return .GLSL, .OPENGL, true;
    case "shader_to_vulkan"; return .GLSL, .VULKAN, true;
    case "shader_to_hlsl";   return .HLSL, .OPENGL, true;
    case "shader_to_metal";  return .METAL, .OPENGL, true;
    case; return .NONE, .OPENGL, false;
  }
}

target_name_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == {
    case .METAL; return ".METAL";
    case .HLSL;  return ".HLSL";
    case .GLSL;  return ifx glsl_target == .VULKAN then ".VULKAN_GLSL" else ".OPENGL_GLSL";
  }
  return "";
}

trim_ascii_whitespace :: (in: string) -> string {
  if in.count == 0 return in;

  start := cast(s64) 0;
  end := in.count - 1;
  while start <= end && (in[start] == #char " " || in[start] == #char "\t" || in[start] == #char "\n" || in[start] == #char "\r")
    start += 1;
  while end >= start && (in[end] == #char " " || in[end] == #char "\t" || in[end] == #char "\n" || in[end] == #char "\r")
    end -= 1;

  ret: string;
  ret.data = in.data + start;
  ret.count = end - start + 1;
  return ret;
}

lookup_entry_already_queued :: (plugin: *Jai_To_Shader_Plugin, target_name: string, primary_name: string, secondary_name: string, symbol_name: string) -> bool {
  for plugin.lookup_entries {
    if it.target_name != target_name continue;
    if it.primary_name != primary_name continue;
    if it.secondary_name != secondary_name continue;
    if it.symbol_name != symbol_name continue;
    return true;
  }
  return false;
}

queue_lookup_entry :: (plugin: *Jai_To_Shader_Plugin, target_name: string, primary_name: string, secondary_name: string, symbol_name: string) {
  if lookup_entry_already_queued(plugin, target_name, primary_name, secondary_name, symbol_name) return;
  array_add(*plugin.lookup_entries, .{
    target_name = target_name,
    primary_name = primary_name,
    secondary_name = secondary_name,
    symbol_name = symbol_name,
  });
}

emit_lookup_overloads :: (plugin: *Jai_To_Shader_Plugin, workspace: Workspace) {
  if plugin.did_emit_lookup_overloads return;
  if plugin.lookup_entries.count == 0 return;

  sb: String_Builder;
  append(*sb, "G :: #import \"generated\";\n");
  append(*sb, "#poke_name G lookup_transpiled_impl;\n");
  append(*sb, "lookup_transpiled_impl :: (target_name: string, primary_name: string, secondary_name: string) -> string {\n");
  for plugin.lookup_entries {
    append(*sb, tprint("  if target_name == \"%\" && primary_name == \"%\" && secondary_name == \"%\" return %;\n",
                       it.target_name, it.primary_name, it.secondary_name, it.symbol_name));
  }
  append(*sb, "  return \"\";\n}\n");

  if plugin.generated_module_import add_build_string(builder_to_string(*sb), workspace, plugin.generated_module_import);
  else add_build_string(builder_to_string(*sb), workspace);
  plugin.did_emit_lookup_overloads = true;
}

parse_shader_pair_note :: (note_text: string) -> (Shader_Language, GLSL_Target, string, bool, bool) {
  prefixes := string.[
    "shader_pair_to_glsl(",
    "shader_pair_to_vulkan(",
    "shader_pair_to_metal(",
  ];

  languages := Shader_Language.[.GLSL, .GLSL, .METAL];
  targets   := GLSL_Target.[.OPENGL, .VULKAN, .OPENGL];

  for prefixes {
    prefix := it;
    if !begins_with(note_text, prefix) continue;

    rest: string;
    rest.data = note_text.data + prefix.count;
    rest.count = note_text.count - prefix.count;
    if rest.count == 0 return .NONE, .OPENGL, "", true, false;

    close_paren_index: s64 = -1;
    for i: 0..rest.count-1 {
      if rest[i] == #char ")" {
        close_paren_index = i;
        break;
      }
    }
    if close_paren_index == -1 return .NONE, .OPENGL, "", true, false;

    arg: string;
    arg.data = rest.data;
    arg.count = close_paren_index;
    arg = trim_ascii_whitespace(arg);
    if arg.count == 0 return .NONE, .OPENGL, "", true, false;

    trailing: string;
    trailing.data = rest.data + close_paren_index + 1;
    trailing.count = rest.count - (close_paren_index + 1);
    trailing = trim_ascii_whitespace(trailing);
    if trailing.count != 0 return .NONE, .OPENGL, "", true, false;

    return languages[it_index], targets[it_index], arg, true, true;
  }

  return .NONE, .OPENGL, "", false, false;
}

context_already_queued :: (plugin: *Jai_To_Shader_Plugin, language: Shader_Language, proc: *Code_Procedure_Body, glsl_target: GLSL_Target) -> bool {
  for *plugin.currently_waiting_contexts {
    if it.main_fn != proc continue;
    if it.language != language continue;
    if it.glsl_target != glsl_target continue;
    return true;
  }
  return false;
}

pair_context_already_queued :: (plugin: *Jai_To_Shader_Plugin, language: Shader_Language, vertex: *Code_Procedure_Body, fragment: *Code_Procedure_Body, glsl_target: GLSL_Target) -> bool {
  for *plugin.currently_waiting_pair_contexts {
    if it.vertex_fn != vertex continue;
    if it.fragment_fn != fragment continue;
    if it.language != language continue;
    if it.glsl_target != glsl_target continue;
    return true;
  }
  return false;
}

add_pending_request_declaration :: (plugin: *Jai_To_Shader_Plugin, decl: *Code_Declaration) {
  if !decl return;
  for plugin.pending_request_declarations if it == decl return;
  array_add(*plugin.pending_request_declarations, decl);
}

resolve_shader_request_target :: (arg: *Code_Node, procedure_bodies: [] *Code_Procedure_Body) -> *Code_Procedure_Body {
  if !arg return null;
  if arg.kind == {
    case .PROCEDURE_BODY;
      return cast(*Code_Procedure_Body) arg;
    case .PROCEDURE_HEADER; {
      header := cast(*Code_Procedure_Header) arg;
      return header.body_or_null;
    }
    case .IDENT; {
      ident := cast(*Code_Ident) arg;
      if ident.resolved_declaration {
        if ident.resolved_declaration.expression && ident.resolved_declaration.expression.kind == .PROCEDURE_HEADER {
          header := cast(*Code_Procedure_Header) ident.resolved_declaration.expression;
          if header.body_or_null return header.body_or_null;
        }

        if ident.resolved_declaration.expression && ident.resolved_declaration.expression.kind == .PROCEDURE_BODY
          return cast(*Code_Procedure_Body) ident.resolved_declaration.expression;
      }

      // Some top-level declarations can be visited before ident.resolved_declaration is available.
      for procedure_bodies {
        if it.header.name == ident.name return it;
      }
    }
    case;
      return null;
  }
  return null;
}

resolve_shader_request_target_by_name :: (name: string, procedure_bodies: [] *Code_Procedure_Body) -> *Code_Procedure_Body {
  for procedure_bodies {
    if it.header.name == name return it;
  }
  return null;
}

collect_shader_requests_from_declaration :: (plugin: *Jai_To_Shader_Plugin, decl: *Code_Declaration, procedure_bodies: [] *Code_Procedure_Body) -> bool {
  if !decl return true;

  requested_languages: [..] Shader_Language;
  requested_glsl_targets: [..] GLSL_Target;
  pair_requested_languages: [..] Shader_Language;
  pair_requested_glsl_targets: [..] GLSL_Target;
  pair_fragment_names: [..] string;
  for decl.notes {
    language, glsl_target, is_shader_request := shader_request_name_to_language(it.text);
    if is_shader_request {
      array_add(*requested_languages, language);
      array_add(*requested_glsl_targets, glsl_target);
      continue;
    }

    pair_language, pair_glsl_target, fragment_name, pair_matched, pair_valid := parse_shader_pair_note(it.text);
    if !pair_matched continue;
    if !pair_valid {
      compiler_report("Jai Shader Transpiler: Invalid shader pair request note format. Use @shader_pair_to_metal(fragment_fn), @shader_pair_to_glsl(fragment_fn), or @shader_pair_to_vulkan(fragment_fn).", make_location(decl));
      continue;
    }
    array_add(*pair_requested_languages, pair_language);
    array_add(*pair_requested_glsl_targets, pair_glsl_target);
    array_add(*pair_fragment_names, fragment_name);
  }
  if requested_languages.count == 0 && pair_requested_languages.count == 0 return true;

  vertex_proc := resolve_shader_request_target(decl.expression, procedure_bodies);
  if !vertex_proc {
    // Declarations can typecheck before the target procedure body is available in early passes.
    return false;
  }

  for requested_languages {
    language := it;
    glsl_target := requested_glsl_targets[it_index];
    if context_already_queued(plugin, language, vertex_proc, glsl_target) continue;
    array_add(*plugin.currently_waiting_contexts, create_shader_write_context(language, vertex_proc, glsl_target));
    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := ifx language == .METAL then tprint("%_metal_string", vertex_proc.header.name) else tprint("%_string", vertex_proc.header.name);
      queue_lookup_entry(plugin, target_name, vertex_proc.header.name, "", symbol_name);
    }
  }

  for pair_requested_languages {
    language := it;
    glsl_target := pair_requested_glsl_targets[it_index];
    fragment_name := pair_fragment_names[it_index];
    fragment_proc := resolve_shader_request_target_by_name(fragment_name, procedure_bodies);
    if !fragment_proc {
      // The fragment function can still appear later in typecheck order.
      return false;
    }

    vertex_is_valid := proc_has_note(vertex_proc.header, "vertex_shader");
    fragment_is_valid := proc_has_note(fragment_proc.header, "fragment_shader");
    if !vertex_is_valid || !fragment_is_valid {
      compiler_report("Jai Shader Transpiler: shader_pair_to_* requires the declaration expression to resolve to a @vertex_shader and the note argument to resolve to a @fragment_shader.", make_location(decl));
      continue;
    }

    if pair_context_already_queued(plugin, language, vertex_proc, fragment_proc, glsl_target) continue;
    pair_name := ifx decl.name.count != 0 then decl.name else tprint("%_%", vertex_proc.header.name, fragment_proc.header.name);
    array_add(*plugin.currently_waiting_pair_contexts, .{
      name = pair_name,
      language = language,
      glsl_target = glsl_target,
      vertex_fn = vertex_proc,
      fragment_fn = fragment_proc,
    });
    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := ifx language == .METAL then tprint("%_metal_string", pair_name) else tprint("%_string", pair_name);
      queue_lookup_entry(plugin, target_name, vertex_proc.header.name, fragment_proc.header.name, symbol_name);
    }
  }
  return true;
}




// Only function that has to be called from a backend

handle_custom_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  name := cast(*Code_Ident) pc.procedure_expression;
  
  // Make sure we're not writing the function again
  found := false;
  for ctx.functions if it.name == name.name found = true;
  if !found {
    called_function := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
    
    function_code: String_Builder;
    write_function(ctx, *function_code, called_function);
      
    array_add(*ctx.functions, .{
      prototype=called_function,
      name=name.name,
      code=builder_to_string(*function_code),
    });
  }
}

// @whatthefuckisthis im 99% sure there's a simpler way of converting an int to a string directly.
// or atleast printing it as a character, because the first switch is.... yikes
operator_string :: (op: Operator_Type) -> string {
  if op == {
    case cast(Operator_Type) #char "="; return "=";
    case cast(Operator_Type) #char "<"; return "<";
    case cast(Operator_Type) #char "?"; return "?";
    case cast(Operator_Type) #char ">"; return ">";
    case cast(Operator_Type) #char "!"; return "!";
    case cast(Operator_Type) #char "+"; return "+";
    case cast(Operator_Type) #char "-"; return "-";
    case cast(Operator_Type) #char "*"; return "*";
    case cast(Operator_Type) #char "/"; return "/";
    case cast(Operator_Type) #char "%"; return "%";
    case cast(Operator_Type) #char "&"; return "&";
    case cast(Operator_Type) #char "|"; return "|";
    case cast(Operator_Type) #char "^"; return "^";
    case cast(Operator_Type) #char "~"; return "~";
    case cast(Operator_Type) #char "."; return ".";
  }

  if op == {
    case .PLUS_ASSIGN; return "+=";
    case .MINUS_ASSIGN; return "-=";
    case .TIMES_ASSIGN; return "*=";
    case .DIV_ASSIGN; return "/=";
    case .MOD_ASSIGN; return "%=";
    case .IS_EQUAL; return "==";
    case .IS_NOT_EQUAL; return "!=";
    case .LOGICAL_AND; return "&&";
    case .LOGICAL_OR; return "||";
    case .LESS_OR_EQUAL; return "<=";
    case .GREATER_OR_EQUAL; return ">=";
    
    case .SHIFT_LEFT; return "<<";
    case .SHIFT_RIGHT; return ">>";
    case .ARRAY_SUBSCRIPT; return "[]";
    
    // I don't think operators below this are supported in glsl
    // But this can stay just incase...
    // case .ROTATE_LEFT; return "<<<";
    // case .ROTATE_RIGHT; return ">>>";
    // case .SHIFT_LEFT_ASSIGN; return "<<=";
    // case .SHIFT_RIGHT_ASSIGN; return ">>=";
    // case .ROTATE_LEFT_ASSIGN; return "<<<=";
    // case .ROTATE_RIGHT_ASSIGN; return ">>>=";
    // case .BITWISE_AND_ASSIGN; return "&=";
    // case .BITWISE_OR_ASSIGN; return "|=";
    // case .BITWISE_XOR_ASSIGN; return "^=";
    // case .LOGICAL_AND_ASSIGN; return "&&=";
    // case .LOGICAL_OR_ASSIGN; return "||=";
    
    case; return "<operator_not_supported>";
  }
}

//~



Shader_Type :: enum {
  Vertex;
  Fragment;
  Compute;
}

Shader_Language :: enum {
  NONE;
  GLSL;
  HLSL;
  METAL;
}

GLSL_Target :: enum {
  OPENGL;
  VULKAN;
}

Shader_Function :: struct {
  prototype: *Code_Procedure_Header;
  name: string; // @Cleanup This doesn't have to be here
  code: string;
}

Shader_Write_Context :: struct {
  name: string;
  type: Shader_Type;
  language: Shader_Language;
  main_fn: *Code_Procedure_Body;
  functions: [..] Shader_Function;
  glsl_target: GLSL_Target;
  metal_use_jai_radians: bool;
  metal_use_jai_degrees: bool;
  metal_allow_fragcoord_from_position: bool;
}

Shader_Write_Pair_Context :: struct {
  name: string;
  language: Shader_Language;
  glsl_target: GLSL_Target;
  vertex_fn: *Code_Procedure_Body;
  fragment_fn: *Code_Procedure_Body;
}

node_is_fragment_shader :: (node: *Code_Procedure_Header) -> bool {
  for node.notes if it.text == "fragment_shader" return true;
  return false;
}

member_has_note :: (member: *Type_Info_Struct_Member, note: string) -> bool {
  for member.notes if it == note return true;
  return false;
}

member_has_note_contains :: (member: *Type_Info_Struct_Member, note_fragment: string) -> bool {
  normalized_fragment := copy_string(note_fragment);
  to_lower_in_place(normalized_fragment);
  normalized_fragment = replace(normalized_fragment, "_", "");

  for member.notes {
    normalized_note := copy_string(it);
    to_lower_in_place(normalized_note);
    normalized_note = replace(normalized_note, "_", "");
    found, _ := contains(normalized_note, normalized_fragment);
    if found return true;
  }
  return false;
}

member_is_stage_builtin :: (member: *Type_Info_Struct_Member) -> bool {
  if member_has_note_contains(member, "position") return true;
  if member_has_note_contains(member, "frag_coord") return true;
  if member_has_note_contains(member, "frag_depth") return true;
  if member_has_note_contains(member, "vertex_id") return true;
  if member_has_note_contains(member, "instance_id") return true;
  if member_has_note_contains(member, "front_facing") return true;
  if member_has_note_contains(member, "point_size") return true;
  if member_has_note_contains(member, "sample_id") return true;
  if member_has_note_contains(member, "sample_mask") return true;
  return false;
}

member_get_compute_builtin_note :: (member: *Type_Info_Struct_Member) -> (string, bool) {
  for member.notes {
    found, _ := contains(it, "thread_position_in_grid");
    if found return "thread_position_in_grid", true;
    found, _ = contains(it, "thread_position_in_threadgroup");
    if found return "thread_position_in_threadgroup", true;
    found, _ = contains(it, "threadgroup_position_in_grid");
    if found return "threadgroup_position_in_grid", true;
    found, _ = contains(it, "thread_index_in_threadgroup");
    if found return "thread_index_in_threadgroup", true;
  }
  return "", false;
}

member_get_note_suffix :: (member: *Type_Info_Struct_Member, prefix_check: string) -> (string, bool) {
  for member.notes if begins_with(it, prefix_check) {
    ret: string;
    ret.data = it.data + prefix_check.count;
    ret.count = it.count - prefix_check.count;
    return ret, true;
  }
  return "", false;
}

declaration_get_note_suffix :: (decl: *Code_Declaration, prefix_check: string) -> (string, bool) {
  for decl.notes if begins_with(it.text, prefix_check) {
    ret: string;
    ret.data = it.text.data + prefix_check.count;
    ret.count = it.text.count - prefix_check.count;
    return ret, true;
  }
  return "", false;
}

declaration_is_parameter_using :: (header: *Code_Procedure_Header, decl: *Code_Declaration) -> bool {
  for header.parameter_usings {
    if !it.expression || it.expression.kind != .IDENT continue;
    ident := cast(*Code_Ident) it.expression;
    if ident.resolved_declaration == decl return true;
    if ident.name == decl.name return true;
  }
  return false;
}


#import "Basic";
#import "Compiler";
PP :: #import "Program_Print";
#import "String";
#import "Math";
#import "Hash_Table";

append :: inline (builder: *String_Builder, strings: ..string) {
  for strings {
    append(builder, it.data, it.count);
  }
}

#scope_file

#import "File";

proc_has_note :: (node: *Code_Procedure_Header, note: string) -> bool {
  for node.notes if it.text == note return true;
  return false;
}

create_shader_write_context :: (language: Shader_Language, proc: *Code_Procedure_Body, glsl_target: GLSL_Target = .OPENGL) -> Shader_Write_Context {
    shader_type: Shader_Type;
    if      proc_has_note(proc.header, "vertex_shader")    shader_type = .Vertex;
    else if proc_has_note(proc.header, "fragment_shader")  shader_type = .Fragment;
    else if proc_has_note(proc.header, "compute_shader")   shader_type = .Compute;
    else
      compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader", make_location(proc.header));
    
    return {
        name = proc.header.name,
        type = shader_type,
        language = language,
        main_fn = proc,
        glsl_target = glsl_target,
        metal_use_jai_radians = false,
        metal_use_jai_degrees = false,
        metal_allow_fragcoord_from_position = false,
    };
}
