// TODOS:
// Add the different types of Vectors and implement the 'Component Comparison' set of GLSL functions
// Translation for more advanced jai features
// Add the differet types of Samplers
// Add support for out parameters
// Add support for structs and arrays

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

IR_Pipeline :: #import,dir "ir_pipeline";
using IR_Pipeline;

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    
    // options
    output_shaders: bool;
    shader_entry_ids_filter: string;
    use_slang_backend: bool = false;
    slang_emit_line_directives: bool;
    timings_enabled: bool;
    
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      generated_module_import: *Message_Import;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      manifest_entries: [..] Shader_Reload_Manifest_Entry;
      did_emit_lookup_overloads: bool;
      did_log_ir_pipeline: bool;
      did_log_ir_limitations: bool;
      timings: Build_Timing_Totals;
    }
}

Build_Timing_Totals :: struct {
  typechecked_message_s: float64;
  phase_message_s: float64;

  known_proc_collect_s: float64;
  declaration_collect_s: float64;
  pending_resolution_s: float64;

  pair_emit_s: float64;
  single_emit_s: float64;
  add_build_string_s: float64;
  lookup_emit_s: float64;

  typechecked_message_count: s64;
  phase_message_count: s64;
  emitted_pair_count: s64;
  emitted_single_count: s64;

  spv_single_total_s: float64;
  spv_pair_total_s: float64;
  spv_lower_s: float64;
  spv_normalize_s: float64;
  spv_emit_slang_s: float64;
  spv_emit_text_s: float64;
  spv_write_files_s: float64;
  spv_read_files_s: float64;
  spv_assemble_s: float64;
  spv_optimize_s: float64;
  spv_validate_s: float64;
  spv_cross_s: float64;
}

Transpiled_Lookup_Entry :: struct {
  target_name: string;
  primary_name: string;
  secondary_name: string;
  symbol_name: string;
}

Shader_Reload_Manifest_Entry :: struct {
  entry_id: string;
  request_name: string;
  shader_kind: string;
  stage: string;
  target: string;
  primary_name: string;
  secondary_name: string;
  signature: string;
  signature_hash: u64;
  dependencies: [..] string;
}

manifest_target_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == .METAL return "METAL";
  if language == .HLSL return "HLSL";
  if language == .GLSL {
    if glsl_target == .VULKAN return "VULKAN_GLSL";
    return "OPENGL_GLSL";
  }
  return "UNKNOWN";
}

manifest_stage_from_shader_type :: (type: Shader_Type) -> string {
  if type == .Vertex return "vertex";
  if type == .Fragment return "fragment";
  if type == .Compute return "compute";
  return "unknown";
}

manifest_target_from_context :: (ctx: *Shader_Write_Context) -> string {
  if !ctx return "UNKNOWN";
  return manifest_target_from_language(ctx.language, ctx.glsl_target);
}

manifest_target_from_pair_context :: (ctx: *Shader_Write_Pair_Context) -> string {
  if !ctx return "UNKNOWN";
  return manifest_target_from_language(ctx.language, ctx.glsl_target);
}

manifest_hash_u64 :: (s: string) -> u64 {
  h: u64 = 1469598103934665603;
  for s {
    h = h ^ cast(u64) it;
    h *= 1099511628211;
  }
  return h;
}

manifest_path_to_workspace_relative :: (full_path: string, workspace_root: string) -> (string, bool) {
  if full_path.count == 0 || workspace_root.count == 0 return "", false;
  root := workspace_root;
  if ends_with(root, "/") root.count -= 1;
  prefix := tprint("%/", root);
  if !begins_with(full_path, prefix) return "", false;
  out: string;
  out.data = full_path.data + prefix.count;
  out.count = full_path.count - prefix.count;
  return manifest_normalize_relative_path(out), true;
}

manifest_array_add_unique_string :: (dst: *[..] string, value: string) {
  for dst.* if it == value return;
  array_add(dst, value);
}

manifest_normalize_relative_path :: (path: string) -> string {
  if path.count == 0 return "";
  parts: [..] string;
  i: s64 = 0;
  while i < path.count {
    while i < path.count && path[i] == #char "/" i += 1;
    if i >= path.count break;
    start := i;
    while i < path.count && path[i] != #char "/" i += 1;
    part: string;
    part.data = path.data + start;
    part.count = i - start;
    if part == "." continue;
    if part == ".." {
      if parts.count > 0 && parts[parts.count-1] != ".." {
        parts.count -= 1;
        continue;
      }
      array_add(*parts, part);
      continue;
    }
    array_add(*parts, part);
  }

  if parts.count == 0 return ".";
  sb: String_Builder;
  for parts {
    if it_index != 0 append(*sb, "/");
    append(*sb, it);
  }
  return builder_to_string(*sb);
}

manifest_make_entry_id_single :: (ctx: *Shader_Write_Context) -> string {
  if !ctx || !ctx.main_fn || !ctx.main_fn.header return "";
  return tprint("single|%|%|%", manifest_target_from_context(ctx), manifest_stage_from_shader_type(ctx.type), ctx.main_fn.header.name);
}

manifest_make_entry_id_pair :: (ctx: *Shader_Write_Pair_Context) -> string {
  if !ctx || !ctx.vertex_fn || !ctx.fragment_fn || !ctx.vertex_fn.header || !ctx.fragment_fn.header return "";
  return tprint("pair|%|%|%", manifest_target_from_pair_context(ctx), ctx.vertex_fn.header.name, ctx.fragment_fn.header.name);
}

manifest_make_entry_id_single_from_parts :: (language: Shader_Language, glsl_target: GLSL_Target, type: Shader_Type, name: string) -> string {
  if name.count == 0 return "";
  return tprint("single|%|%|%", manifest_target_from_language(language, glsl_target), manifest_stage_from_shader_type(type), name);
}

manifest_make_entry_id_pair_from_parts :: (language: Shader_Language, glsl_target: GLSL_Target, vertex_name: string, fragment_name: string) -> string {
  if vertex_name.count == 0 || fragment_name.count == 0 return "";
  return tprint("pair|%|%|%", manifest_target_from_language(language, glsl_target), vertex_name, fragment_name);
}

manifest_collect_header_file_dependency :: (header: *Code_Procedure_Header,
                                            workspace_root: string,
                                            out_deps: *[..] string) {
  if !header return;
  loc := make_location(header);
  if loc.fully_pathed_filename.count == 0 return;
  rel, ok := manifest_path_to_workspace_relative(loc.fully_pathed_filename, workspace_root);
  if !ok return;
  manifest_array_add_unique_string(out_deps, copy_string(rel));
}

manifest_header_seen :: (seen: [] *Code_Procedure_Header, header: *Code_Procedure_Header) -> bool {
  for seen if it == header return true;
  return false;
}

manifest_collect_node_dependencies :: (node: *Code_Node,
                                       workspace_root: string,
                                       out_deps: *[..] string,
                                       seen_headers: *[..] *Code_Procedure_Header) {
  if !node return;

  if node.kind == {
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if pc.resolved_procedure_expression && pc.resolved_procedure_expression.kind == .PROCEDURE_HEADER {
        header := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
        manifest_collect_header_dependencies(header, workspace_root, out_deps, seen_headers);
      }
      if pc.procedure_expression manifest_collect_node_dependencies(pc.procedure_expression, workspace_root, out_deps, seen_headers);
      for pc.arguments_sorted manifest_collect_node_dependencies(it, workspace_root, out_deps, seen_headers);
      for pc.arguments_unsorted if it.expression manifest_collect_node_dependencies(it.expression, workspace_root, out_deps, seen_headers);
      return;
    }

    case .DECLARATION; {
      decl := cast(*Code_Declaration) node;
      if decl.expression manifest_collect_node_dependencies(decl.expression, workspace_root, out_deps, seen_headers);
      return;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      if bn.left manifest_collect_node_dependencies(bn.left, workspace_root, out_deps, seen_headers);
      if bn.right manifest_collect_node_dependencies(bn.right, workspace_root, out_deps, seen_headers);
      return;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      if un.subexpression manifest_collect_node_dependencies(un.subexpression, workspace_root, out_deps, seen_headers);
      return;
    }

    case .CAST; {
      cn := cast(*Code_Cast) node;
      if cn.expression manifest_collect_node_dependencies(cn.expression, workspace_root, out_deps, seen_headers);
      return;
    }

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        for lit.struct_literal_info.arguments manifest_collect_node_dependencies(it, workspace_root, out_deps, seen_headers);
      } else if lit.value_type == .ARRAY {
        for lit.array_literal_info.array_members manifest_collect_node_dependencies(it, workspace_root, out_deps, seen_headers);
      }
      return;
    }

    case .IF; {
      ifn := cast(*Code_If) node;
      if ifn.condition manifest_collect_node_dependencies(ifn.condition, workspace_root, out_deps, seen_headers);
      if ifn.then_block manifest_collect_node_dependencies(cast(*Code_Node) ifn.then_block, workspace_root, out_deps, seen_headers);
      if ifn.else_block manifest_collect_node_dependencies(cast(*Code_Node) ifn.else_block, workspace_root, out_deps, seen_headers);
      return;
    }

    case .BLOCK; {
      block := cast(*Code_Block) node;
      for block.statements manifest_collect_node_dependencies(it, workspace_root, out_deps, seen_headers);
      return;
    }

    case .RETURN; {
      rn := cast(*Code_Return) node;
      for rn.arguments_sorted manifest_collect_node_dependencies(it, workspace_root, out_deps, seen_headers);
      return;
    }

    case .FOR; {
      fn := cast(*Code_For) node;
      if fn.iteration_expression manifest_collect_node_dependencies(fn.iteration_expression, workspace_root, out_deps, seen_headers);
      if fn.iteration_expression_right manifest_collect_node_dependencies(fn.iteration_expression_right, workspace_root, out_deps, seen_headers);
      if fn.ident_decl manifest_collect_node_dependencies(cast(*Code_Node) fn.ident_decl, workspace_root, out_deps, seen_headers);
      if fn.block manifest_collect_node_dependencies(cast(*Code_Node) fn.block, workspace_root, out_deps, seen_headers);
      return;
    }

    case .WHILE; {
      wn := cast(*Code_While) node;
      if wn.condition manifest_collect_node_dependencies(wn.condition, workspace_root, out_deps, seen_headers);
      if wn.block manifest_collect_node_dependencies(cast(*Code_Node) wn.block, workspace_root, out_deps, seen_headers);
      return;
    }

    case .USING; {
      un := cast(*Code_Using) node;
      if un.expression manifest_collect_node_dependencies(un.expression, workspace_root, out_deps, seen_headers);
      return;
    }

    case .DEFER; {
      dn := cast(*Code_Defer) node;
      if dn.block manifest_collect_node_dependencies(cast(*Code_Node) dn.block, workspace_root, out_deps, seen_headers);
      return;
    }
  }
}

manifest_collect_header_dependencies :: (header: *Code_Procedure_Header,
                                         workspace_root: string,
                                         out_deps: *[..] string,
                                         seen_headers: *[..] *Code_Procedure_Header) {
  if !header return;
  if manifest_header_seen(seen_headers.*, header) return;
  array_add(seen_headers, header);

  manifest_collect_header_file_dependency(header, workspace_root, out_deps);
  if header.body_or_null manifest_collect_node_dependencies(cast(*Code_Node) header.body_or_null, workspace_root, out_deps, seen_headers);
}

manifest_decl_type_signature :: (decl: *Code_Declaration) -> string {
  if !decl return "unknown";
  decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
  if decl_type return type_to_string(decl_type);
  return "unknown";
}

manifest_header_signature :: (header: *Code_Procedure_Header) -> string {
  if !header return "header=null";
  sb: String_Builder;
  append(*sb, "name=");
  append(*sb, header.name);
  append(*sb, ";ret=");
  if header.returns.count == 0 {
    append(*sb, "void");
  } else if header.returns.count == 1 {
    append(*sb, manifest_decl_type_signature(header.returns[0]));
  } else {
    append(*sb, "multi(");
    for header.returns {
      if it_index != 0 append(*sb, ",");
      append(*sb, manifest_decl_type_signature(it));
    }
    append(*sb, ")");
  }
  append(*sb, ";args=");
  for header.arguments {
    if it_index != 0 append(*sb, ",");
    append(*sb, it.name);
    append(*sb, ":");
    append(*sb, manifest_decl_type_signature(it));
  }
  return builder_to_string(*sb);
}

manifest_make_single_entry :: (ctx: *Shader_Write_Context, workspace_root: string) -> Shader_Reload_Manifest_Entry {
  out: Shader_Reload_Manifest_Entry;
  if !ctx || !ctx.main_fn || !ctx.main_fn.header return out;

  out.request_name = copy_string(ctx.name);
  out.entry_id = manifest_make_entry_id_single(ctx);
  out.shader_kind = "single";
  out.stage = manifest_stage_from_shader_type(ctx.type);
  out.target = manifest_target_from_context(ctx);
  out.primary_name = copy_string(ctx.main_fn.header.name);
  out.secondary_name = "";
  proc_sig := manifest_header_signature(ctx.main_fn.header);
  out.signature = tprint("kind=single;stage=%;target=%;%", out.stage, out.target, proc_sig);
  out.signature_hash = manifest_hash_u64(out.signature);

  seen_headers: [..] *Code_Procedure_Header;
  manifest_collect_header_dependencies(ctx.main_fn.header, workspace_root, *out.dependencies, *seen_headers);
  for ctx.functions if it.prototype manifest_collect_header_dependencies(it.prototype, workspace_root, *out.dependencies, *seen_headers);
  return out;
}

manifest_make_pair_entry :: (ctx: *Shader_Write_Pair_Context, workspace_root: string) -> Shader_Reload_Manifest_Entry {
  out: Shader_Reload_Manifest_Entry;
  if !ctx || !ctx.vertex_fn || !ctx.fragment_fn || !ctx.vertex_fn.header || !ctx.fragment_fn.header return out;

  out.request_name = copy_string(ctx.name);
  out.entry_id = manifest_make_entry_id_pair(ctx);
  out.shader_kind = "pair";
  out.stage = "pair";
  out.target = manifest_target_from_pair_context(ctx);
  out.primary_name = copy_string(ctx.vertex_fn.header.name);
  out.secondary_name = copy_string(ctx.fragment_fn.header.name);
  v_sig := manifest_header_signature(ctx.vertex_fn.header);
  f_sig := manifest_header_signature(ctx.fragment_fn.header);
  out.signature = tprint("kind=pair;target=%;vertex={%};fragment={%}", out.target, v_sig, f_sig);
  out.signature_hash = manifest_hash_u64(out.signature);

  seen_headers: [..] *Code_Procedure_Header;
  manifest_collect_header_dependencies(ctx.vertex_fn.header, workspace_root, *out.dependencies, *seen_headers);
  manifest_collect_header_dependencies(ctx.fragment_fn.header, workspace_root, *out.dependencies, *seen_headers);
  return out;
}

emit_shader_reload_manifest :: (plugin: *Jai_To_Shader_Plugin) {
  assert(plugin != null);

  global_dependencies: [..] string;
  for plugin.manifest_entries {
    for it.dependencies manifest_array_add_unique_string(*global_dependencies, it);
  }

  sb: String_Builder;
  append(*sb, "version 1\n");
  append(*sb, tprint("entry_count %\n", plugin.manifest_entries.count));
  append(*sb, tprint("global_dependency_count %\n", global_dependencies.count));
  for global_dependencies append(*sb, tprint("global_dependency %\n", it));

  for plugin.manifest_entries {
    append(*sb, "entry_begin\n");
    append(*sb, tprint("entry_id %\n", it.entry_id));
    append(*sb, tprint("request_name %\n", it.request_name));
    append(*sb, tprint("shader_kind %\n", it.shader_kind));
    append(*sb, tprint("stage %\n", it.stage));
    append(*sb, tprint("target %\n", it.target));
    append(*sb, tprint("primary_name %\n", it.primary_name));
    append(*sb, tprint("secondary_name %\n", it.secondary_name));
    append(*sb, tprint("signature_hash 0x%\n", formatInt(it.signature_hash, base=16)));
    append(*sb, tprint("signature %\n", it.signature));
    append(*sb, tprint("dependency_count %\n", it.dependencies.count));
    for it.dependencies append(*sb, tprint("dependency %\n", it));
    append(*sb, "entry_end\n");
  }

  make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive=true);
  workspace_name := get_name(plugin.workspace);
  if workspace_name.count == 0 workspace_name = "workspace";
  workspace_name = replace(workspace_name, " ", "_");
  workspace_name = replace(workspace_name, "/", "_");
  workspace_name = replace(workspace_name, "\\", "_");
  workspace_name = replace(workspace_name, ":", "_");

  manifest_set_hash: u64 = 0;
  for plugin.manifest_entries manifest_set_hash = manifest_set_hash ^ manifest_hash_u64(it.entry_id);
  if manifest_set_hash == 0 manifest_set_hash = manifest_hash_u64(workspace_name);

  path := tprint("%/shader_reload_manifest_%_%.txt", DEBUG_OUTDIR, workspace_name, formatInt(manifest_set_hash, base=16));
  manifest_text := builder_to_string(*sb);
  ok := write_entire_file(path, manifest_text);
  if !ok {
    log_error("Jai Shader Transpiler: failed to write shader reload manifest to '%'.", path);
    return;
  }

  latest_path := tprint("%/shader_reload_manifest_latest.txt", DEBUG_OUTDIR);
  _ = write_entire_file(latest_path, manifest_text);
}

get_plugin :: () -> *Jai_To_Shader_Plugin {
  p := New(Jai_To_Shader_Plugin);
  opts := get_build_options();
  if getenv("JSL_SLANG_BACKEND") p.use_slang_backend = true;
  for opts.compile_time_command_line {
    if it == "-slang_emit_line_directives" {
      p.slang_emit_line_directives = true;
    } else if it == "-timings" {
      p.timings_enabled = true;
    } else if begins_with(it, "-shader_entry_ids=") {
      filter: string;
      filter.data = it.data + 18;
      filter.count = it.count - 18;
      p.shader_entry_ids_filter = trim_ascii_whitespace(filter);
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
    request_name := tprint("transpiled_single_%_%", target_ident, shader_name);
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

  request_name := tprint("transpiled_pair_%_%_%", target_ident, shader_name, fragment_name);
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
      tc_message_start := current_time_monotonic();
      tc := cast(*Message_Typechecked) message;
      t0 := current_time_monotonic();
      for tc.procedure_bodies {
        proc := it.expression;
        already := false;
        for plugin.known_procedure_bodies if it == proc { already = true; break; }
        if !already array_add(*plugin.known_procedure_bodies, proc);
      }
      plugin.timings.known_proc_collect_s += to_float64_seconds(current_time_monotonic() - t0);

      t0 = current_time_monotonic();
      for tc.declarations {
        resolved := collect_shader_requests_from_declaration(plugin, it.expression, plugin.known_procedure_bodies);
        if !resolved add_pending_request_declaration(plugin, it.expression);
      }
      plugin.timings.declaration_collect_s += to_float64_seconds(current_time_monotonic() - t0);

      t0 = current_time_monotonic();
      for plugin.pending_request_declarations {
        if collect_shader_requests_from_declaration(plugin, it, plugin.known_procedure_bodies) {
          remove it;
        }
      }
      plugin.timings.pending_resolution_s += to_float64_seconds(current_time_monotonic() - t0);
      plugin.timings.typechecked_message_s += to_float64_seconds(current_time_monotonic() - tc_message_start);
      plugin.timings.typechecked_message_count += 1;
    }
    
    case .PHASE; {
      phase_message_start := current_time_monotonic();
      phase := cast(*Message_Phase) message;
      if phase.phase == .TYPECHECKED_ALL_WE_CAN {
        array_reset(*plugin.manifest_entries);
        workspace_root := get_working_directory();
        if !plugin.did_log_ir_pipeline {
          plugin.did_log_ir_pipeline = true;
        }

        t_pairs := current_time_monotonic();
        for * pair_ctx: plugin.currently_waiting_pair_contexts {
          s: string;
          used_ir_pipeline := false;
          if !plugin.use_slang_backend {
            s2, ok2, diag := write_shader_pair_ir_spirv(pair_ctx, plugin.slang_emit_line_directives, *plugin.timings);
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
          t_add := current_time_monotonic();
          if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
          else add_build_string(s, p.workspace);
          plugin.timings.add_build_string_s += to_float64_seconds(current_time_monotonic() - t_add);

          if plugin.output_shaders {
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

          manifest_entry := manifest_make_pair_entry(pair_ctx, workspace_root);
          if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);

          remove pair_ctx;
          plugin.timings.emitted_pair_count += 1;
        }
        plugin.timings.pair_emit_s += to_float64_seconds(current_time_monotonic() - t_pairs);

        t_single := current_time_monotonic();
        if !plugin.use_slang_backend {
          t_single_spv := current_time_monotonic();
          jobs: [..] SPV_External_Single_Job;
          for *ctx: plugin.currently_waiting_contexts {
            job: SPV_External_Single_Job;
            prep_ok, prep_diag := prepare_single_spirv_external_job(ctx, *job, *plugin.timings);
            if !prep_ok {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if prep_diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, prep_diag.message);
              if prep_diag.has_location compiler_report(report_message, prep_diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              continue;
            }
            array_add(*jobs, job);
          }

          run_spirv_external_jobs_parallel(jobs);

          for *jobs {
            ctx := it.ctx;
            source, finalize_ok, finalize_diag := finalize_single_spirv_external_job(it, add_generated_comment=true, timings_totals=*plugin.timings);
            if !finalize_ok {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if finalize_diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, finalize_diag.message);
              if finalize_diag.has_location compiler_report(report_message, finalize_diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              continue;
            }

            s := tprint("% :: #string END\n%\nEND", ir_symbol_name_from_context(ctx), source);
            t_add := current_time_monotonic();
            if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
            else add_build_string(s, p.workspace);
            plugin.timings.add_build_string_s += to_float64_seconds(current_time_monotonic() - t_add);
            if plugin.output_shaders {
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
            manifest_entry := manifest_make_single_entry(ctx, workspace_root);
            if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);
            plugin.timings.emitted_single_count += 1;
          }
          plugin.timings.spv_single_total_s += to_float64_seconds(current_time_monotonic() - t_single_spv);
          array_reset(*plugin.currently_waiting_contexts);
        } else {
          for * ctx: plugin.currently_waiting_contexts {
            s: string;
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

            t_add := current_time_monotonic();
            if plugin.generated_module_import add_build_string(s, p.workspace, plugin.generated_module_import);
            else add_build_string(s, p.workspace);
            plugin.timings.add_build_string_s += to_float64_seconds(current_time_monotonic() - t_add);
            if plugin.output_shaders {
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
            manifest_entry := manifest_make_single_entry(ctx, workspace_root);
            if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);
            remove ctx;
            plugin.timings.emitted_single_count += 1;
          }
        }
        plugin.timings.single_emit_s += to_float64_seconds(current_time_monotonic() - t_single);

        if plugin.manifest_entries.count > 0 emit_shader_reload_manifest(plugin);

        t_lookup := current_time_monotonic();
        emit_lookup_overloads(plugin, p.workspace);
        plugin.timings.lookup_emit_s += to_float64_seconds(current_time_monotonic() - t_lookup);
      }
      plugin.timings.phase_message_s += to_float64_seconds(current_time_monotonic() - phase_message_start);
      plugin.timings.phase_message_count += 1;
    }
    
    case .COMPLETE; {
      if plugin.currently_waiting_contexts.count != 0 || plugin.currently_waiting_pair_contexts.count != 0 {
        complete_message := cast(*Message_Complete)message;
        if complete_message.error_code == 0 {
          compiler_report("Jai Shader Transpiler: Compiler is finished, but some functions have not yet been transpiled.");
        }
      }
      if plugin.timings_enabled {
        log("[timing][build][plugin] typechecked msgs=% total=%s collect_known=%s collect_decl=%s resolve_pending=%s",
          plugin.timings.typechecked_message_count,
          plugin.timings.typechecked_message_s,
          plugin.timings.known_proc_collect_s,
          plugin.timings.declaration_collect_s,
          plugin.timings.pending_resolution_s);
        log("[timing][build][plugin] phase msgs=% total=%s pair_emit=%s single_emit=%s add_build_string=%s emit_lookup=%s emitted_pairs=% emitted_singles=%",
          plugin.timings.phase_message_count,
          plugin.timings.phase_message_s,
          plugin.timings.pair_emit_s,
          plugin.timings.single_emit_s,
          plugin.timings.add_build_string_s,
          plugin.timings.lookup_emit_s,
          plugin.timings.emitted_pair_count,
          plugin.timings.emitted_single_count);
        log("[timing][build][plugin][spv] wall_single=%s wall_pair=%s worker_sum_lower=%s worker_sum_normalize=%s worker_sum_emit_slang=%s worker_sum_emit_spvasm=%s worker_sum_write_files=%s worker_sum_read_files=%s worker_sum_assemble=%s worker_sum_optimize=%s worker_sum_validate=%s worker_sum_cross=%s",
          plugin.timings.spv_single_total_s,
          plugin.timings.spv_pair_total_s,
          plugin.timings.spv_lower_s,
          plugin.timings.spv_normalize_s,
          plugin.timings.spv_emit_slang_s,
          plugin.timings.spv_emit_text_s,
          plugin.timings.spv_write_files_s,
          plugin.timings.spv_read_files_s,
          plugin.timings.spv_assemble_s,
          plugin.timings.spv_optimize_s,
          plugin.timings.spv_validate_s,
          plugin.timings.spv_cross_s);
      }
      array_reset(*plugin.currently_waiting_contexts);
      array_reset(*plugin.currently_waiting_pair_contexts);
      array_reset(*plugin.pending_request_declarations);
      array_reset(*plugin.known_procedure_bodies);
      array_reset(*plugin.lookup_entries);
      array_reset(*plugin.manifest_entries);
      plugin.generated_module_import = null;
      plugin.did_emit_lookup_overloads = false;
      plugin.did_log_ir_pipeline = false;
      plugin.did_log_ir_limitations = false;
      plugin.timings = .{};
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
  return begins_with(name, "transpiled_single_") || begins_with(name, "transpiled_pair_");
}

ir_mark_metal_device_pointers_const :: (source: string) -> string {
  // Slang currently emits graphics buffer params as `T device*` in Metal wrappers, which triggers
  // writable-resource warnings on non-void vertex functions. Rewriting to `T const device*` keeps
  // the generated code semantically read-only for graphics stages and removes that warning.
  return replace(source, " device*", " const device*");
}

ir_metal_enable_unsafe_runtime_array_indexing :: (source: string) -> string {
  return source;
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

normalize_vertex_ir :: (shader: *IR_Vertex_Shader) -> (ok: bool, diag: IR_Diagnostic) {
  assert(shader != null);
  base := cast(*IR_Shader) shader;
  ok, diag := normalize_shader(base);
  return ok, diag;
}

normalize_fragment_ir :: (shader: *IR_Fragment_Shader) -> (ok: bool, diag: IR_Diagnostic) {
  assert(shader != null);
  base := cast(*IR_Shader) shader;
  ok, diag := normalize_shader(base);
  return ok, diag;
}

normalize_compute_ir :: (shader: *IR_Compute_Shader) -> (ok: bool, diag: IR_Diagnostic) {
  assert(shader != null);
  base := cast(*IR_Shader) shader;
  ok, diag := normalize_shader(base);
  return ok, diag;
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
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    normalized, normalize_diag := normalize_vertex_ir(*ir_vertex);
    if !normalized return "", false, normalize_diag;
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
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    normalized, normalize_diag := normalize_fragment_ir(*ir_fragment);
    if !normalized return "", false, normalize_diag;
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
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if !lowered {
      #if VERBOSE log("IR lowering failed for %", ctx.name);
      return "", false, lowered_diag;
    }
    normalized, normalize_diag := normalize_compute_ir(*ir_compute);
    if !normalized return "", false, normalize_diag;
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
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
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

ir_is_resource_buffer_type_name :: (type_name: string) -> bool {
  if begins_with(type_name, "StructuredBuffer<") return true;
  if begins_with(type_name, "RWStructuredBuffer<") return true;
  return false;
}

ir_parse_parameter_block_struct_name_for_args :: (type_name: string) -> (string, bool) {
  prefix :: "ParameterBlock<";
  if !begins_with(type_name, prefix) return "", false;
  if type_name.count < prefix.count + 1 return "", false;
  if type_name[type_name.count-1] != #char ">" return "", false;
  out: string;
  out.data = type_name.data + prefix.count;
  out.count = type_name.count - prefix.count - 1;
  if out.count == 0 return "", false;
  return out, true;
}

ir_lowered_struct_has_resource_fields :: (structs: [] IR_Struct, struct_name: string, depth := 0) -> bool {
  if struct_name.count == 0 return false;
  if depth > 16 return false;
  for structs {
    if it.name != struct_name continue;
    for it.fields {
      if ir_is_resource_buffer_type_name(it.type_name) return true;
      nested_name := it.type_name;
      param_block_name, is_param_block := ir_parse_parameter_block_struct_name_for_args(it.type_name);
      if is_param_block nested_name = param_block_name;
      if ir_lowered_struct_has_resource_fields(structs, nested_name, depth + 1) return true;
    }
    return false;
  }
  return false;
}

ir_graphics_requires_metal_argument_buffer :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool {
  for args {
    struct_name := it.type_name;
    param_block_name, is_param_block := ir_parse_parameter_block_struct_name_for_args(it.type_name);
    if is_param_block struct_name = param_block_name;
    if ir_is_resource_buffer_type_name(struct_name) return true;
    if ir_lowered_struct_has_resource_fields(extra_structs, struct_name) return true;
  }
  return false;
}

SPV_External_Single_Job :: struct {
  ctx: *Shader_Write_Context;
  started: Apollo_Time;
  validate_before_opt: bool;
  stage: Slang_Stage;
  target: Slang_Target;
  entry_name: string;
  use_metal_argument_buffers: bool;

  source_path: string;
  spvasm_path: string;
  spv_path: string;
  spv_opt_path: string;
  output_path: string;

  ok: bool;
  error_message: string;

  assemble_s: float64;
  optimize_s: float64;
  validate_s: float64;
  cross_s: float64;
}

prepare_single_spirv_external_job :: (ctx: *Shader_Write_Context,
                                      job: *SPV_External_Single_Job,
                                      timings_totals: *Build_Timing_Totals = null) -> (ok: bool, diag: IR_Diagnostic) {
  assert(ctx != null);
  assert(job != null);

  diag: IR_Diagnostic;
  if !ir_spirv_supports_single_context(ctx) {
    diag.message = "SPIR-V backend currently supports vertex/fragment/compute shaders targeting Metal or Vulkan GLSL only.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return false, diag;
  }

  stage, stage_ok := ir_stage_from_context(ctx);
  if !stage_ok {
    diag.message = "SPIR-V backend: unsupported shader stage.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return false, diag;
  }

  target, target_ok := ir_target_from_context(ctx);
  if !target_ok {
    diag.message = "SPIR-V backend: unsupported target for context.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return false, diag;
  }

  slang_source: string;
  spvasm_source: string;
  spvasm_ok := false;
  spvasm_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;

  if ctx.type == .Vertex {
    t0 := current_time_monotonic();
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_vertex_ir(*ir_vertex);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_vertex_to_slang(ir_vertex);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for vertex shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_vertex.entry_name;
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_vertex_to_spirv_text_branch(ir_vertex);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    t0 := current_time_monotonic();
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_fragment_ir(*ir_fragment);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_fragment_to_slang(ir_fragment);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for fragment shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_fragment.entry_name;
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_fragment_to_spirv_text_branch(ir_fragment);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    t0 := current_time_monotonic();
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_compute_ir(*ir_compute);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_compute_to_slang(ir_compute);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
    if !emitted {
      diag.message = tprint("IR->Slang emission failed for compute shader '%'.", ctx.name);
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      return false, diag;
    }
    slang_source = emitted_source;
    entry_name = ir_compute.entry_name;
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_compute_to_spirv_text_branch(ir_compute);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
  }

  if entry_name.count == 0 {
    diag.message = "SPIR-V backend: empty entry name.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return false, diag;
  }

  if !spvasm_ok {
    if spvasm_diag.message.count == 0 spvasm_diag.message = tprint("SPIR-V text backend: failed to emit SPIR-V assembly for '%'.", ctx.name);
    if !spvasm_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spvasm_diag.location = make_location(ctx.main_fn.header);
      spvasm_diag.has_location = true;
    }
    return false, spvasm_diag;
  }

  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  stage_short := ir_stage_short_from_context(ctx);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";

  job.ctx = ctx;
  job.started = current_time_monotonic();
  job.validate_before_opt = false;
  job.stage = stage;
  job.target = target;
  job.entry_name = copy_string(entry_name);
  job.use_metal_argument_buffers = use_metal_argument_buffers;
  job.source_path = copy_string(tprint("%/%_%.slang", build_dir, ctx.name, stage_short));
  job.spvasm_path = copy_string(tprint("%/%_%.spvasm", build_dir, ctx.name, stage_short));
  job.spv_path = copy_string(tprint("%/%_%.spv", build_dir, ctx.name, stage_short));
  job.spv_opt_path = copy_string(tprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short));
  job.output_path = copy_string(tprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext));
  job.ok = false;
  job.error_message = "";

  t0 := current_time_monotonic();
  if !write_entire_file(job.source_path, slang_source) {
    diag.message = tprint("SPIR-V backend: failed writing Slang source file '%'.", job.source_path);
    return false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !write_entire_file(job.spvasm_path, spvasm_source) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V text file '%'.", job.spvasm_path);
    return false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);

  return true, diag;
}

run_spirv_external_single_job :: (job: *SPV_External_Single_Job) -> bool {
  assert(job != null);
  t0 := current_time_monotonic();
  if !assemble_spirv_text(job.spvasm_path, job.spv_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: failed assembling SPIR-V text for '%'. Source: %", job.ctx.name, job.spvasm_path));
    return false;
  }
  job.assemble_s = to_float64_seconds(current_time_monotonic() - t0);

  if job.validate_before_opt {
    t0 = current_time_monotonic();
    if !validate_spirv_binary(job.spv_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
    job.validate_s += to_float64_seconds(current_time_monotonic() - t0);
  }

  t0 = current_time_monotonic();
  if !optimize_spirv_binary(job.spv_path, job.spv_opt_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
    return false;
  }
  job.optimize_s = to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  if !validate_spirv_binary(job.spv_opt_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }
  job.validate_s = to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  if !emit_spirv_cross_target_source(job.spv_opt_path, job.entry_name, job.stage, job.target, job.output_path, job.use_metal_argument_buffers, source_entry_name=job.entry_name) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }
  job.cross_s = to_float64_seconds(current_time_monotonic() - t0);

  return true;
}

spv_external_single_worker_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
  _ = group;
  _ = thread;
  job := cast(*SPV_External_Single_Job) work;
  job.ok = run_spirv_external_single_job(job);
  return .CONTINUE;
}

run_spirv_external_jobs_parallel :: (jobs: [] SPV_External_Single_Job) {
  if jobs.count == 0 return;
  cpus := get_number_of_processors();
  if cpus < 1 cpus = 1;
  job_count := cast(s32) jobs.count;
  worker_count := min(max(cpus - 1, 1), job_count);
  tg: Thread_Group;
  init(*tg, worker_count, spv_external_single_worker_proc);
  tg.logging = false;
  tg.name = "JTS-SPV-External";
  start(*tg);
  defer {
    shutdown(*tg);
  }

  for *jobs add_work(*tg, it);

  completed := 0;
  while completed < jobs.count {
    done := get_completed_work(*tg);
    completed += done.count;
    if completed < jobs.count sleep_milliseconds(1);
  }
}

finalize_single_spirv_external_job :: (job: *SPV_External_Single_Job,
                                       add_generated_comment := true,
                                       timings_totals: *Build_Timing_Totals = null) -> (target_source: string, ok: bool, diag: IR_Diagnostic) {
  assert(job != null);
  diag: IR_Diagnostic;
  if !job.ok {
    diag.message = ifx job.error_message.count != 0 then job.error_message else "SPIR-V backend: external toolchain step failed.";
    if job.ctx && job.ctx.main_fn && job.ctx.main_fn.header {
      diag.location = make_location(job.ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  t0 := current_time_monotonic();
  target_source, read_ok := read_entire_file(job.output_path);
  if timings_totals timings_totals.spv_read_files_s += to_float64_seconds(current_time_monotonic() - t0);
  if !read_ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", job.output_path);
    return "", false, diag;
  }

  if job.ctx.language == .METAL && job.ctx.type != .Compute {
    target_source = ir_mark_metal_device_pointers_const(target_source);
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    t0 = current_time_monotonic();
    write_entire_file(job.output_path, target_source);
    if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);
  }
  if job.ctx.type == .Compute && job.ctx.language == .METAL {
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(job.ctx), ir_pipeline_label_spirv(job.target));
  }
  t0 = current_time_monotonic();
  write_entire_file(job.output_path, target_source);
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);

  if timings_totals {
    timings_totals.spv_assemble_s += job.assemble_s;
    timings_totals.spv_optimize_s += job.optimize_s;
    timings_totals.spv_validate_s += job.validate_s;
    timings_totals.spv_cross_s += job.cross_s;
  }

  return target_source, true, diag;
}

ir_emit_single_spirv_target_source :: (ctx: *Shader_Write_Context, add_generated_comment := true, timings_totals: *Build_Timing_Totals = null) -> (string, string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  single_start := current_time_monotonic();
  defer if timings_totals {
    timings_totals.spv_single_total_s += to_float64_seconds(current_time_monotonic() - single_start);
  }
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
  spvasm_source: string;
  spvasm_ok := false;
  spvasm_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;
  if ctx.type == .Vertex {
    t0 := current_time_monotonic();
    ir_vertex, lowered, lowered_diag := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return "", "", false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_vertex_ir(*ir_vertex);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return "", "", false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_vertex_to_slang(ir_vertex);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
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
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_vertex_to_spirv_text_branch(ir_vertex);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    t0 := current_time_monotonic();
    ir_fragment, lowered, lowered_diag := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return "", "", false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_fragment_ir(*ir_fragment);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return "", "", false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_fragment_to_slang(ir_fragment);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
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
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_fragment_to_spirv_text_branch(ir_fragment);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    t0 := current_time_monotonic();
    ir_compute, lowered, lowered_diag := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
    if !lowered return "", "", false, lowered_diag;
    t0 = current_time_monotonic();
    normalized, normalize_diag := normalize_compute_ir(*ir_compute);
    if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
    if !normalized return "", "", false, normalize_diag;
    t0 = current_time_monotonic();
    emitted_source, emitted := emit_ir_compute_to_slang(ir_compute);
    if timings_totals timings_totals.spv_emit_slang_s += to_float64_seconds(current_time_monotonic() - t0);
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
    t0 = current_time_monotonic();
    spvasm_source, spvasm_ok, spvasm_diag = emit_ir_compute_to_spirv_text_branch(ir_compute);
    if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
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
  spv_opt_path := tprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";
  output_path := tprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);

  t0 := current_time_monotonic();
  if !write_entire_file(source_path, slang_source) {
    diag.message = tprint("SPIR-V backend: failed writing Slang source file '%'.", source_path);
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);

  if entry_name.count == 0 {
    diag.message = "SPIR-V backend: empty entry name.";
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }

  if !spvasm_ok {
    if spvasm_diag.message.count == 0 spvasm_diag.message = tprint("SPIR-V text backend: failed to emit SPIR-V assembly for '%'.", ctx.name);
    if !spvasm_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spvasm_diag.location = make_location(ctx.main_fn.header);
      spvasm_diag.has_location = true;
    }
    return "", "", false, spvasm_diag;
  }
  spvasm_path := tprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  t0 = current_time_monotonic();
  if !write_entire_file(spvasm_path, spvasm_source) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V text file '%'.", spvasm_path);
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !assemble_spirv_text(spvasm_path, spv_path) {
    diag.message = tprint("SPIR-V backend: failed assembling SPIR-V text for '%'. Source: %", ctx.name, spvasm_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_assemble_s += to_float64_seconds(current_time_monotonic() - t0);

  spv_for_target := spv_path;
  t0 = current_time_monotonic();
  if !optimize_spirv_binary(spv_path, spv_opt_path) {
    diag.message = tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", ctx.name, spv_path);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_optimize_s += to_float64_seconds(current_time_monotonic() - t0);
  spv_for_target = spv_opt_path;

  t0 = current_time_monotonic();
  if !validate_spirv_binary(spv_for_target) {
    diag.message = tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_validate_s += to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  if !emit_spirv_cross_target_source(spv_for_target, entry_name, stage, target, output_path, use_metal_argument_buffers, source_entry_name=entry_name) {
    diag.message = tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", ctx.name, spv_for_target);
    if ctx.main_fn && ctx.main_fn.header {
      diag.location = make_location(ctx.main_fn.header);
      diag.has_location = true;
    }
    return "", "", false, diag;
  }
  if timings_totals timings_totals.spv_cross_s += to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  target_source, ok := read_entire_file(output_path);
  if timings_totals timings_totals.spv_read_files_s += to_float64_seconds(current_time_monotonic() - t0);
  if !ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", output_path);
    return "", "", false, diag;
  }
  if ctx.language == .METAL && ctx.type != .Compute {
    target_source = ir_mark_metal_device_pointers_const(target_source);
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    t0 = current_time_monotonic();
    write_entire_file(output_path, target_source);
    if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);
  }
  if ctx.type == .Compute && ctx.language == .METAL {
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(ctx), ir_pipeline_label_spirv(target));
  }
  t0 = current_time_monotonic();
  write_entire_file(output_path, target_source);
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);

  return target_source, output_path, true, diag;
}

write_shader_single_ir_spirv :: (ctx: *Shader_Write_Context, timings_totals: *Build_Timing_Totals = null) -> (string, bool, IR_Diagnostic) {
  target_source, _, ok, diag := ir_emit_single_spirv_target_source(ctx, add_generated_comment=true, timings_totals=timings_totals);
  if !ok return "", false, diag;

  symbol_name := ir_symbol_name_from_context(ctx);
  decl := tprint("% :: #string END\n%\nEND", symbol_name, target_source);
  return decl, true, diag;
}

ir_metal_find_preamble_end :: (source: string) -> s64 {
  marker := "using namespace metal;";
  index := find_index_from_left(source, marker);
  if index == -1 return 0;

  end := index + marker.count;
  while end < source.count && (source[end] == #char "\n" || source[end] == #char "\r") end += 1;
  return end;
}

ir_metal_compact_decl_key :: (decl: string) -> string {
  out: [..] u8;
  for decl {
    ch := it;
    if ch == #char " " || ch == #char "\t" || ch == #char "\r" || ch == #char "\n" continue;
    array_add(*out, ch);
  }
  return string.{data = out.data, count = out.count};
}

ir_metal_split_top_level_decls :: (source: string, out_preamble: *string, out_decls: *[..] string) {
  assert(out_preamble != null);
  assert(out_decls != null);

  preamble_end := ir_metal_find_preamble_end(source);
  preamble: string;
  preamble.data = source.data;
  preamble.count = preamble_end;
  out_preamble.* = preamble;

  i := preamble_end;
  while i < source.count {
    while i < source.count {
      ch := source[i];
      if ch != #char " " && ch != #char "\t" && ch != #char "\r" && ch != #char "\n" break;
      i += 1;
    }
    if i >= source.count break;

    start := i;
    brace_depth: s64 = 0;
    paren_depth: s64 = 0;
    saw_block := false;
    ended := false;

    while i < source.count {
      ch := source[i];
      if ch == #char "(" paren_depth += 1;
      if ch == #char ")" && paren_depth > 0 paren_depth -= 1;
      if ch == #char "{" {
        brace_depth += 1;
        saw_block = true;
      }
      if ch == #char "}" && brace_depth > 0 {
        brace_depth -= 1;
        if brace_depth == 0 && saw_block {
          cursor := i + 1;
          while cursor < source.count && (source[cursor] == #char " " || source[cursor] == #char "\t" || source[cursor] == #char "\r" || source[cursor] == #char "\n") {
            cursor += 1;
          }
          // Struct/enum declarations terminate with `};`, function definitions at `}`.
          if cursor >= source.count || source[cursor] != #char ";" {
            i += 1;
            ended = true;
            break;
          }
        }
      }
      if ch == #char ";" && brace_depth == 0 && paren_depth == 0 {
        i += 1;
        ended = true;
        break;
      }
      i += 1;
    }

    if !ended && i >= source.count {
      // Accept trailing declaration-like chunk at EOF.
    }

    decl: string;
    decl.data = source.data + start;
    decl.count = i - start;
    if decl.count > 0 array_add(out_decls, copy_string(decl));
  }
}

ir_merge_metal_pair_sources :: (vertex_source: string, fragment_source: string) -> string {
  preamble_v: string;
  preamble_f: string;
  decls_v: [..] string;
  decls_f: [..] string;
  ir_metal_split_top_level_decls(vertex_source, *preamble_v, *decls_v);
  ir_metal_split_top_level_decls(fragment_source, *preamble_f, *decls_f);

  sb: String_Builder;
  if preamble_v.count != 0 append(*sb, preamble_v);
  else if preamble_f.count != 0 append(*sb, preamble_f);
  append(*sb, "\n");

  seen: Table(string, bool);
  for decls_v {
    decl := it;
    key := ir_metal_compact_decl_key(decl);
    if key.count == 0 continue;
    found, _ := table_find(*seen, key);
    if found continue;
    table_add(*seen, copy_string(key), true);
    append(*sb, decl);
    append(*sb, "\n");
  }

  for decls_f {
    decl := it;
    key := ir_metal_compact_decl_key(decl);
    if key.count == 0 continue;
    found, _ := table_find(*seen, key);
    if found continue;
    table_add(*seen, copy_string(key), true);
    append(*sb, decl);
    append(*sb, "\n");
  }

  return builder_to_string(*sb);
}

spv_memory_model_from_text :: (spvasm: string) -> string {
  marker := "OpMemoryModel ";
  idx := find_index_from_left(spvasm, marker);
  if idx == -1 return "";
  start := idx + marker.count;
  if start >= spvasm.count return "";

  end := start;
  while end < spvasm.count && spvasm[end] != #char "\n" && spvasm[end] != #char "\r" end += 1;
  line: string;
  line.data = spvasm.data + start;
  line.count = end - start;
  return trim(line);
}

ir_find_struct_by_name_local :: (extra_structs: [] IR_Struct, name: string) -> *IR_Struct {
  for *extra_structs if it.name == name return it;
  return null;
}

ir_struct_has_pointer_fields_recursive_local :: (extra_structs: [] IR_Struct, name: string) -> bool {
  st := ir_find_struct_by_name_local(extra_structs, name);
  if !st return false;
  for st.fields {
    if it.is_pointer return true;
    if it.type_name.count != 0 && ir_struct_has_pointer_fields_recursive_local(extra_structs, it.type_name) return true;
  }
  return false;
}

ir_uses_pointer_abi_local :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool {
  for args {
    arg := it;
    if !arg.is_pointer || !arg.pointer_pointee_is_struct || arg.pointer_pointee_type_name.count == 0 continue;
    if ir_struct_has_pointer_fields_recursive_local(extra_structs, arg.pointer_pointee_type_name) return true;
  }
  return false;
}

ir_semantic_upper_local :: (semantic: string) -> string {
  if semantic.count == 0 return "";
  return to_upper_copy(trim(semantic));
}

ir_vertex_output_field_is_builtin_local :: (field: *IR_Field) -> bool {
  if !field return false;
  sem := ir_semantic_upper_local(field.semantic);
  if sem == "SV_POSITION" || sem == "GL_POSITION" || sem == "POSITION" return true;
  if sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return true;
  return false;
}

ir_fragment_input_field_is_builtin_local :: (field: *IR_Field) -> bool {
  if !field return false;
  if field.name == "gl_FragCoord" return true;
  sem := ir_semantic_upper_local(field.semantic);
  if sem == "SV_POSITION" || sem == "POSITION" || sem == "GL_POSITION" || sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return true;
  return false;
}

ir_pair_varying_field_label_local :: (field: *IR_Field) -> string {
  if !field return "<null>";
  if field.semantic.count != 0 return tprint("% (semantic %)", field.name, field.semantic);
  return field.name;
}

ir_pair_varyings_match_local :: (vertex_field: *IR_Field, fragment_field: *IR_Field) -> bool {
  assert(vertex_field != null);
  assert(fragment_field != null);

  vertex_sem := ir_semantic_upper_local(vertex_field.semantic);
  fragment_sem := ir_semantic_upper_local(fragment_field.semantic);
  if vertex_sem.count != 0 && fragment_sem.count != 0 return vertex_sem == fragment_sem;
  return vertex_field.name == fragment_field.name;
}

ir_validate_pair_stage_interface_local :: (pair_name: string, vertex: *IR_Vertex_Shader, fragment: *IR_Fragment_Shader) -> (bool, string) {
  assert(vertex != null);
  assert(fragment != null);

  vertex_varyings: [..] IR_Field;
  fragment_varyings: [..] IR_Field;
  for vertex.output.fields {
    if ir_vertex_output_field_is_builtin_local(*it) continue;
    array_add(*vertex_varyings, it);
  }
  for fragment.input.fields {
    if ir_fragment_input_field_is_builtin_local(*it) continue;
    array_add(*fragment_varyings, it);
  }

  if vertex_varyings.count != fragment_varyings.count {
    return false, tprint("SPIR-V backend: pair '%': stage interface mismatch: vertex exports % user varyings but fragment consumes %.", pair_name, vertex_varyings.count, fragment_varyings.count);
  }

  for i: 0..fragment_varyings.count-1 {
    v := vertex_varyings[i];
    f := fragment_varyings[i];
    if v.type_name != f.type_name {
      return false, tprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' has type '%', fragment '%' has type '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), v.type_name, ir_pair_varying_field_label_local(*f), f.type_name);
    }
    if !ir_pair_varyings_match_local(*v, *f) {
      return false, tprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' does not match fragment '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), ir_pair_varying_field_label_local(*f));
    }
  }

  return true, "";
}

write_shader_pair_ir_spirv :: (pair_ctx: *Shader_Write_Pair_Context, emit_line_directives := false, timings_totals: *Build_Timing_Totals = null) -> (string, bool, IR_Diagnostic) {
  _ = emit_line_directives;

  diag: IR_Diagnostic;
  pair_start := current_time_monotonic();
  defer if timings_totals {
    timings_totals.spv_pair_total_s += to_float64_seconds(current_time_monotonic() - pair_start);
  }
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

  t0 := current_time_monotonic();
  ir_vertex, vertex_ok, vertex_diag := ir_lower_vertex_from_shader_context(.{name=vertex_ctx.name, header=vertex_ctx.main_fn.header});
  if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
  if !vertex_ok {
    if !vertex_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      vertex_diag.location = make_location(pair_ctx.vertex_fn.header);
      vertex_diag.has_location = true;
    }
    return "", false, vertex_diag;
  }
  t0 = current_time_monotonic();
  vertex_normalized, vertex_normalize_diag := normalize_vertex_ir(*ir_vertex);
  if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
  if !vertex_normalized return "", false, vertex_normalize_diag;

  t0 = current_time_monotonic();
  ir_fragment, fragment_ok, fragment_diag := ir_lower_fragment_from_shader_context(.{name=fragment_ctx.name, header=fragment_ctx.main_fn.header});
  if timings_totals timings_totals.spv_lower_s += to_float64_seconds(current_time_monotonic() - t0);
  if !fragment_ok {
    if !fragment_diag.has_location && pair_ctx.fragment_fn && pair_ctx.fragment_fn.header {
      fragment_diag.location = make_location(pair_ctx.fragment_fn.header);
      fragment_diag.has_location = true;
    }
    return "", false, fragment_diag;
  }
  t0 = current_time_monotonic();
  fragment_normalized, fragment_normalize_diag := normalize_fragment_ir(*ir_fragment);
  if timings_totals timings_totals.spv_normalize_s += to_float64_seconds(current_time_monotonic() - t0);
  if !fragment_normalized return "", false, fragment_normalize_diag;

  vertex_uses_pointer_abi := ir_uses_pointer_abi_local(ir_vertex.args, ir_vertex.extra_structs);
  fragment_uses_pointer_abi := ir_uses_pointer_abi_local(ir_fragment.args, ir_fragment.extra_structs);
  if vertex_uses_pointer_abi != fragment_uses_pointer_abi {
    diag.message = tprint("SPIR-V backend: pair '%': vertex and fragment use incompatible resource ABI styles (vertex pointer-ABI=%; fragment pointer-ABI=%). Pair shaders must agree on resource ABI.", pair_ctx.name, vertex_uses_pointer_abi, fragment_uses_pointer_abi);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  interface_ok, interface_err := ir_validate_pair_stage_interface_local(pair_ctx.name, *ir_vertex, *ir_fragment);
  if !interface_ok {
    diag.message = interface_err;
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  // Keep direct bindings by default for pair shaders, but switch to argument buffers when
  // bindless globals are present in SPIR-V text (required for large bindless arrays on Metal).
  use_metal_argument_buffers := false;


  t0 = current_time_monotonic();
  vertex_spvasm, fragment_spvasm, pair_spvasm_ok, pair_spvasm_diag := emit_ir_graphics_pair_to_spirv_text_branch(ir_vertex, ir_fragment);
  if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
  if !pair_spvasm_ok {
    if !pair_spvasm_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      pair_spvasm_diag.location = make_location(pair_ctx.vertex_fn.header);
      pair_spvasm_diag.has_location = true;
    }
    return "", false, pair_spvasm_diag;
  }
  build_dir := ".build/ir_slang";
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  vertex_spvasm_path := tprint("%/%_vert.spvasm", build_dir, pair_ctx.name);
  fragment_spvasm_path := tprint("%/%_frag.spvasm", build_dir, pair_ctx.name);
  vertex_spv_path := tprint("%/%_vert.spv", build_dir, pair_ctx.name);
  fragment_spv_path := tprint("%/%_frag.spv", build_dir, pair_ctx.name);
  pair_spv_path := tprint("%/%_pair.spv", build_dir, pair_ctx.name);
  pair_opt_spv_path := tprint("%/%_pair.opt.spv", build_dir, pair_ctx.name);
  pair_spvasm_path := tprint("%/%_pair.spvasm", build_dir, pair_ctx.name);
  vertex_output_path := tprint("%/%_vert.metal", build_dir, pair_ctx.name);
  fragment_output_path := tprint("%/%_frag.metal", build_dir, pair_ctx.name);
  t0 = current_time_monotonic();
  if !write_entire_file(vertex_spvasm_path, vertex_spvasm) || !write_entire_file(fragment_spvasm_path, fragment_spvasm) {
    diag.message = "SPIR-V backend: failed writing pair SPIR-V text files.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !assemble_spirv_text(vertex_spvasm_path, vertex_spv_path) || !assemble_spirv_text(fragment_spvasm_path, fragment_spv_path) {
    diag.message = "SPIR-V backend: failed assembling pair SPIR-V text.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_assemble_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !link_spirv_binaries(.[vertex_spv_path, fragment_spv_path], pair_spv_path) {
    vertex_model := spv_memory_model_from_text(vertex_spvasm);
    fragment_model := spv_memory_model_from_text(fragment_spvasm);
    if vertex_model.count != 0 || fragment_model.count != 0 {
      diag.message = tprint("SPIR-V backend: spirv-link failed for pair module (vertex model='%'; fragment model='%').", vertex_model, fragment_model);
    } else {
      diag.message = "SPIR-V backend: spirv-link failed for pair module.";
    }
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_assemble_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !optimize_spirv_binary(pair_spv_path, pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for pair module.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_optimize_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !validate_spirv_binary(pair_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for pair module.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_validate_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !disassemble_spirv_binary(pair_opt_spv_path, pair_spvasm_path) {
    diag.message = "SPIR-V backend: spirv-dis failed for optimized pair module.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_emit_text_s += to_float64_seconds(current_time_monotonic() - t0);
  t0 = current_time_monotonic();
  if !emit_spirv_cross_target_source(pair_opt_spv_path, "VertexMain", .VERTEX, .METAL, vertex_output_path, use_metal_argument_buffers, source_entry_name="VertexMain") {
    diag.message = "SPIR-V backend: pair vertex spirv-cross failed.";
    return "", false, diag;
  }
  if !emit_spirv_cross_target_source(pair_opt_spv_path, "FragmentMain", .FRAGMENT, .METAL, fragment_output_path, use_metal_argument_buffers, source_entry_name="FragmentMain") {
    diag.message = "SPIR-V backend: pair fragment spirv-cross failed.";
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_cross_s += to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  vertex_source, v_ok := read_entire_file(vertex_output_path);
  fragment_source, f_ok := read_entire_file(fragment_output_path);
  if timings_totals timings_totals.spv_read_files_s += to_float64_seconds(current_time_monotonic() - t0);
  if !v_ok || !f_ok {
    diag.message = "SPIR-V backend: failed reading pair spirv-cross outputs.";
    return "", false, diag;
  }

  merged_source := ir_merge_metal_pair_sources(vertex_source, fragment_source);
  merged_source = ir_mark_metal_device_pointers_const(merged_source);
  merged_source = ir_metal_enable_unsafe_runtime_array_indexing(merged_source);
  merged_source = ir_prepend_generated_comment(merged_source, ir_source_file_from_pair_context(pair_ctx), ir_pipeline_label_spirv(.METAL));
  output_path := ir_output_path_from_pair_context(pair_ctx);
  t0 = current_time_monotonic();
  if !write_entire_file(output_path, merged_source) {
    diag.message = tprint("SPIR-V backend: failed writing merged pair source '%'.", output_path);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }
  if timings_totals timings_totals.spv_write_files_s += to_float64_seconds(current_time_monotonic() - t0);

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
  ir_vertex, vertex_ok, vertex_diag := ir_lower_vertex_from_shader_context(.{name=vertex_ctx.name, header=vertex_ctx.main_fn.header});
  if !vertex_ok return "", false, vertex_diag;
  vertex_normalized, vertex_normalize_diag := normalize_vertex_ir(*ir_vertex);
  if !vertex_normalized return "", false, vertex_normalize_diag;
  ir_fragment, fragment_ok, fragment_diag := ir_lower_fragment_from_shader_context(.{name=fragment_ctx.name, header=fragment_ctx.main_fn.header});
  if !fragment_ok return "", false, fragment_diag;
  fragment_normalized, fragment_normalize_diag := normalize_fragment_ir(*ir_fragment);
  if !fragment_normalized return "", false, fragment_normalize_diag;

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
  target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
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
    ctx := create_shader_write_context(language, vertex_proc, glsl_target);
    entry_id := manifest_make_entry_id_single_from_parts(language, glsl_target, ctx.type, vertex_proc.header.name);
    if !shader_entry_id_is_selected(plugin.shader_entry_ids_filter, entry_id) continue;
    array_add(*plugin.currently_waiting_contexts, ctx);
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
    pair_ctx := Shader_Write_Pair_Context.{
      name = pair_name,
      language = language,
      glsl_target = glsl_target,
      vertex_fn = vertex_proc,
      fragment_fn = fragment_proc,
    };
    entry_id := manifest_make_entry_id_pair_from_parts(language, glsl_target, vertex_proc.header.name, fragment_proc.header.name);
    if !shader_entry_id_is_selected(plugin.shader_entry_ids_filter, entry_id) continue;
    array_add(*plugin.currently_waiting_pair_contexts, pair_ctx);
    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := ifx language == .METAL then tprint("%_metal_string", pair_name) else tprint("%_string", pair_name);
      queue_lookup_entry(plugin, target_name, vertex_proc.header.name, fragment_proc.header.name, symbol_name);
    }
  }
  return true;
}

shader_entry_id_is_selected :: (csv_filter: string, entry_id: string) -> bool {
  if csv_filter.count == 0 return true;
  if entry_id.count == 0 return false;

  i: s64 = 0;
  while i < csv_filter.count {
    while i < csv_filter.count && (csv_filter[i] == #char "," || csv_filter[i] == #char " " || csv_filter[i] == #char "\t" || csv_filter[i] == #char "\n" || csv_filter[i] == #char "\r") i += 1;
    if i >= csv_filter.count break;

    start := i;
    while i < csv_filter.count && csv_filter[i] != #char "," i += 1;
    token: string;
    token.data = csv_filter.data + start;
    token.count = i - start;
    token = trim_ascii_whitespace(token);
    if token.count != 0 && token == entry_id return true;

    if i < csv_filter.count && csv_filter[i] == #char "," i += 1;
  }

  return false;
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
#import "Thread";
#import "System";

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

using,only(getenv) POSIX :: #import "POSIX";
