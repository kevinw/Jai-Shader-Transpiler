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
#load "glsl_backend.jai";
#load "hlsl_backend.jai";
#load "metal_backend.jai";

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    
    // options
    output_shaders: bool;
    
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      generated_module_import: *Message_Import;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      did_emit_lookup_overloads: bool;
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

  p.message = convert_procs;

  return p;
}

Generated_Shader_Strings_Module :: #import "generated";

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
        for * pair_ctx: plugin.currently_waiting_pair_contexts {
          s := write_shader_pair(pair_ctx);
          if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
          else add_build_string(s, p.workspace);

          if plugin.output_shaders {
            ext := tprint("%", pair_ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, pair_ctx.name, ext);
            file_source := write_shader_pair_code(pair_ctx, as_jai_string=false);
            ok := write_entire_file(filename, file_source);
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
          if ctx.type == {
            case .Vertex;   #through;
            case .Fragment; #through;
            case .Compute;
              s = write_shader(ctx, ctx.main_fn);
              
            case; compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader",
                            make_location(ctx.main_fn.header));
          }

          if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
          else add_build_string(s, p.workspace);
          if plugin.output_shaders {
            ext := tprint("%", ctx.language);
            to_lower_in_place(ext);
            make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive = true);
            filename := tprint("%/%.%", DEBUG_OUTDIR, ctx.name, ext);
            file_source := write_shader_code(ctx, ctx.main_fn, as_jai_string=false);
            ok := write_entire_file(filename, file_source);
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
      table_reset(*get_transpiled_requests_seen);
    }
  }
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

write_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  reset_unnamed_struct_cache();
  // log("Converting % Shader: %", ctx.type, node.header.name);
  
  if ctx.language == {
    case .GLSL;  return write_glsl_shader (ctx, node, ctx.type);
    case .HLSL;  return write_hlsl_shader (ctx, node, ctx.type);
    case .METAL; return write_metal_shader(ctx, node, ctx.type);
  }
  
  return "";
}

write_procedure_call :: (ctx: *Shader_Write_Context, node: *String_Builder, pc: *Code_Procedure_Call) {
  if ctx.language == {
    case .GLSL;  print_glsl_procedure_call (ctx, node, pc);
    case .HLSL;  print_hlsl_procedure_call (ctx, node, pc);
    case .METAL; print_metal_procedure_call(ctx, node, pc);
  }
}

write_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, called_fn: *Code_Procedure_Header) {
  if ctx.language == {
    case .GLSL;  print_glsl_function (ctx, sb, called_fn);
    case .HLSL;  print_hlsl_function (ctx, sb, called_fn);
    case .METAL; print_metal_function(ctx, sb, called_fn);
  }
}

write_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  if ctx.language == {
    case .GLSL;  return write_glsl_shader_code (ctx, node, as_jai_string=as_jai_string);
    case .HLSL;  return write_hlsl_shader_code (ctx, node, as_jai_string=as_jai_string);
    case .METAL; return write_metal_shader_code(ctx, node, as_jai_string=as_jai_string);
  }

  return "";
}

write_shader_pair :: (ctx: *Shader_Write_Pair_Context) -> string {
  reset_unnamed_struct_cache();
  return write_shader_pair_code(ctx, as_jai_string=true);
}

write_shader_pair_code :: (ctx: *Shader_Write_Pair_Context, as_jai_string := true) -> string {
  vertex_ctx := create_shader_write_context(ctx.language, ctx.vertex_fn, ctx.glsl_target);
  fragment_ctx := create_shader_write_context(ctx.language, ctx.fragment_fn, ctx.glsl_target);

  if ctx.language == {
    case .GLSL;
      return write_glsl_shader_pair(ctx.name, *vertex_ctx, *fragment_ctx, as_jai_string=as_jai_string);
    case .METAL;
      return write_metal_shader_pair(ctx.name, *vertex_ctx, *fragment_ctx, as_jai_string=as_jai_string);
    case;
      compiler_report("Jai Shader Transpiler: Pair shader emission currently supports GLSL and METAL only.", make_location(ctx.vertex_fn.header));
  }

  return "";
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
  for member.notes {
    found, _ := contains(it, note_fragment);
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
