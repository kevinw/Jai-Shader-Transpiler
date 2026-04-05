//
// Metaprogram plugin for converting Jai funcs marked with @vertex_shader @fragment_shader or @compute_shader to shaders.
// 
// Usage:
// 
// metal_bytes := get_transpiled(.METAL, pbr_vertex_main, pbr_fragment_main);
// 

VERBOSE            :: false;
USE_SPIRV_OPT      :: true;
WRITE_SPVASM_DEBUG :: false;

DEBUG_OUTDIR                   :: ".generated_shaders"; // TODO: use get_build_options to determine a build-specific directory for this
IR_INTERMEDIATE_DIR            :: ".build/ir_intermediate"; // TODO: use get_build_options to determine a build-specific directory for this
JST_TOOL_VERSION_CACHE_DIR     :: ".build/ir_tool_cache/tool_versions";
JST_TOOL_ARTIFACT_CACHE_DIR    :: ".build/ir_tool_cache/artifacts";
JST_FINGERPRINT_FILE_CACHE_DIR :: ".build/ir_tool_cache/fingerprint_files";

Transpiled_Target :: enum {
  METAL;
  HLSL;
  OPENGL_GLSL;
  VULKAN_GLSL;
}

Jai_To_Shader_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = convert_procs; // the Compiler message handler
    before_intercept = _before_intercept;
    add_source = _add_source;
    
    // options
    output_shaders: bool;
    shader_entry_ids_filter: string;
    manifest_app_name: string;
    
    // internal
    using impl: struct {
      currently_waiting_contexts: [..] Shader_Write_Context;
      currently_waiting_pair_contexts: [..] Shader_Write_Pair_Context;
      currently_waiting_mesh_contexts: [..] Shader_Write_Mesh_Context;
      pending_request_declarations: [..] *Code_Declaration;
      known_procedure_bodies: [..] *Code_Procedure_Body;
      lookup_entries: [..] Transpiled_Lookup_Entry;
      emitted_symbol_names: [..] string;
      manifest_entries: [..] Shader_Reload_Manifest_Entry;
      did_emit_lookup_overloads: bool;
      did_log_ir_pipeline: bool;
      did_log_ir_limitations: bool;
      did_add_setup_source: bool;
    }
}

Transpiled_Lookup_Entry :: struct {
  target_name: string;
  primary_name: string;
  secondary_name: string;
  tertiary_name: string;
  symbol_name: string;
}

offset_of :: ($T: Type, $member: string) -> int { // nocommit
    for type_info(T).members {
        if it.name == member return it.offset_in_bytes;
    }

    assert(false, "Type '%' does not have member '%'", T, member);
    return -1;
}

get_plugin :: () -> *Jai_To_Shader_Plugin {
  using p := New(Jai_To_Shader_Plugin);
  
  for get_build_options().compile_time_command_line {
    if it == "-output_shaders" {
      output_shaders = true;
    } else if begins_with(it, "-shader_entry_ids=") {
      shader_entry_ids_filter = trim_ascii_whitespace(string.{ it.count - 18, it.data + 18});
    }
  }

  return p;
}

get_transpiled_requests_seen: Table(string, bool);

expression_to_source_string :: (node: *Code_Node) -> string {
  sb: String_Builder;
  PP.print_expression(*sb, node);
  return builder_to_string(*sb);
}

normalize_target_expr :: (expr: string) -> string {
  prefix :: "Transpiled_Target";
  if begins_with(expr, prefix) && expr.count > prefix.count && expr[prefix.count] == #char "."
    return string.{expr.count - prefix.count, expr.data + prefix.count};
  return expr;
}

transpiled_target_from_expr_string :: (expr: string) -> (single_note: string, pair_note: string, supports_pair: bool, is_metal: bool, ok: bool) {
  if normalize_target_expr(expr) == {
    case ".METAL";       return "shader_to_metal",  "shader_pair_to_metal",  true,  true,  true;
    case ".HLSL";        return "shader_to_hlsl",   "",                      false, false, true;
    case ".OPENGL_GLSL"; return "shader_to_glsl",   "shader_pair_to_glsl",   true,  false, true;
    case ".VULKAN_GLSL"; return "shader_to_vulkan", "shader_pair_to_vulkan", true,  false, true;
  }
  return "", "", false, false, false;
}

canonical_transpiled_target_expr_string :: (expr: string) -> (string, bool) {
  normalized := normalize_target_expr(expr);
  if normalized == {
    case ".METAL";       return ".METAL", true;
    case ".HLSL";        return ".HLSL", true;
    case ".OPENGL_GLSL"; return ".OPENGL_GLSL", true;
    case ".VULKAN_GLSL"; return ".VULKAN_GLSL", true;
  }
  return "", false;
}

entry_id_target_name_from_canonical_target_expr :: (expr: string) -> string #compile_time {
  canonical, ok := canonical_transpiled_target_expr_string(expr);
  if !ok || canonical.count == 0 return "";
  if canonical[0] != #char "." return canonical;
  return .{ canonical.count - 1, canonical.data + 1 };
}

resolve_transpiled_target_expr_string :: (node: *Code_Node, depth: s64 = 0) -> (string, bool) #compile_time {
  if !node return "", false;
  if depth > 4 {
      log_error("hit depth max in resolve_transpiled_target_expr_string");
      return "", false;
  }

  expr := trim_ascii_whitespace(expression_to_source_string(node));
  if expr.count > 0 {
    _, _, _, _, ok := transpiled_target_from_expr_string(expr);
    if ok return expr, true;
  }

  if node.kind == .IDENT {
    ident := cast(*Code_Ident) node;
    if ident.resolved_declaration && ident.resolved_declaration.expression {
      nested_expr, nested_ok := resolve_transpiled_target_expr_string(ident.resolved_declaration.expression, depth + 1);
      return nested_expr, nested_ok;
    }
  }

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    if decl.expression {
      nested_expr, nested_ok := resolve_transpiled_target_expr_string(decl.expression, depth + 1);
      return nested_expr, nested_ok;
    }
  }

  return "", false;
}

sanitize_identifier_component :: (in: string) -> string {
  out := copy_string(in);
  for out {
    if it == {
      case #char "."; #through;
      case #char " "; #through;
      case #char "("; #through;
      case #char ")"; #through;
      case #char ",";
        out[it_index] = "_";
    }
  }
  return out;
}

ensure_get_transpiled_request_registered :: (key: string, source: string) #compile_time {
  found, _ := table_find(*get_transpiled_requests_seen, key);
  if found return;
  table_add(*get_transpiled_requests_seen, key, true);
  add_build_string(source, get_current_workspace());
}

Transpiled_Request_Info :: struct {
  request_name: string;
  entry_id: string;
  source_symbol_name: string;
  function_constants_type_name: string;
  function_constant_info_name: string;
}

source_symbol_name_for_request :: (request_name: string) -> string {
  return tprint("%_source", request_name);
}

function_constants_type_name_for_request :: (request_name: string) -> string {
  return tprint("%_function_constants", generated_function_constant_base_name(request_name, ""));
}

function_constant_info_name_for_request :: (request_name: string) -> string {
  return tprint("%_function_constant_info", generated_function_constant_base_name(request_name, ""));
}

get_transpiled_request_info_from_call :: (call: Code, loc: Source_Code_Location) -> Transpiled_Request_Info #compile_time {
  return_fail :: (msg: string) #expand {
      compiler_report(tprint("Jai Shader Transpiler: %", msg), loc=loc);
      `return .{};
  }
  
  root := compiler_get_nodes(call);
  if root.kind != .PROCEDURE_CALL {
      return_fail("get_transpiled must be called directly (e.g. get_transpiled(.METAL, vertex_fn, fragment_fn)).");
  }

  pc := cast(*Code_Procedure_Call) root;
  if pc.arguments_unsorted.count != 2 && pc.arguments_unsorted.count != 3 {
      return_fail("get_transpiled expects 2 args (target, stage_fn) or 3 args (target, vertex_fn, fragment_fn).");
  }

  target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
  resolved_target_expr, resolved_target_ok := resolve_transpiled_target_expr_string(pc.arguments_unsorted[0].expression);
  target_parse_expr := ifx resolved_target_ok then resolved_target_expr else target_expr;
  canonical_target_expr, canonical_target_ok := canonical_transpiled_target_expr_string(target_parse_expr);
  single_note, pair_note, supports_pair, _, target_ok := transpiled_target_from_expr_string(canonical_target_expr);
  if !target_ok || !canonical_target_ok {
    return_fail("First argument to get_transpiled must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.");
  }
  target_ident := "";
  if canonical_target_expr == {
  case ".METAL";       target_ident = "metal";
  case ".HLSL";        target_ident = "hlsl";
  case ".OPENGL_GLSL"; target_ident = "opengl_glsl";
  case ".VULKAN_GLSL"; target_ident = "vulkan_glsl";
  case; return_fail("Failed to derive canonical target identifier for get_transpiled.");
  }

  shader_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
  if !shader_name {
    return_fail("get_transpiled shader arguments must be procedure identifiers.");
  }

  if pc.arguments_unsorted.count == 2 {
    request_name := tprint("transpiled_single_%_%", target_ident, shader_name);
    to_lower_in_place(request_name);
    key := tprint("single|%|%", single_note, shader_name);
    request_source := tprint("% :: %; @%\n", request_name, shader_name, single_note);
    ensure_get_transpiled_request_registered(key, request_source);
    return .{
      request_name = request_name,
      entry_id = "",
      source_symbol_name = tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", canonical_target_expr, shader_name),
      function_constants_type_name = function_constants_type_name_for_request(request_name),
      function_constant_info_name = function_constant_info_name_for_request(request_name),
    };
  }

  if !supports_pair return_fail("get_transpiled target does not support paired graphics shaders for this backend.");

  fragment_name := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
  if !fragment_name return_fail("get_transpiled fragment argument must be a procedure identifier.");

  request_name := tprint("transpiled_pair_%_%_%", target_ident, shader_name, fragment_name);
  to_lower_in_place(request_name);
  entry_id := tprint("pair|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), shader_name, fragment_name);
  key := tprint("pair|%|%|%", pair_note, shader_name, fragment_name);
  request_source := tprint("% :: %; @%(%)\n", request_name, shader_name, pair_note, fragment_name);
  
  #if 0 {
    log("----- (original api)");
    log("request_name:  %", request_name);
    log("pair_note:     %", pair_note);
    log("shader_name:   %", shader_name);
    log("fragment_name: %", fragment_name);
    log("-----");
  }
  
  ensure_get_transpiled_request_registered(key, request_source);

  return .{
    request_name = request_name,
    entry_id = entry_id,
    source_symbol_name = tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", canonical_target_expr, shader_name, fragment_name),
    function_constants_type_name = function_constants_type_name_for_request(request_name),
    function_constant_info_name = function_constant_info_name_for_request(request_name),
  };
}


Shader_Meta :: struct {
    request_name: string;
    entry_id: string;
    function_constants_type_name: string;
}

Transpiled_Shader :: struct {
    source: string;
    meta: Shader_Meta;
}

Transpiled_Mesh_Source_Bundle :: struct {
    task_source: string;
    mesh_source: string;
    pixel_source: string;
    payload_size_bytes: s64;
    payload_memory_length: s64;
}

Transpiled_Mesh_Pipeline :: struct {
    task_source: string;
    mesh_source: string;
    pixel_source: string;
    payload_size_bytes: s64;
    payload_memory_length: s64;
    meta: Shader_Meta;
}

make_constants_code_string :: (using shader_meta: Shader_Meta) -> string {
    return tprint("%.{};", function_constants_type_name);
}

transpiled_shader_exprs_from_call :: (call: Code, loc: Source_Code_Location) -> (string, string, string) #compile_time {
    info := get_transpiled_request_info_from_call(call, loc);
    if info.request_name.count == 0 return "", "", "";

    source_expr := info.source_symbol_name;
    meta_expr := tprint("Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", info.request_name, info.entry_id, info.function_constants_type_name);
    constants_expr := tprint("%.{}", info.function_constants_type_name);
    return source_expr, meta_expr, constants_expr;
}

Code_Procedure_Discovery :: struct {
    decl_name: string;
    proc_header: *Code_Procedure_Header;
    ident_name: string;
}

discover_procedure_info :: (code: Code, required_note: string, loc: Source_Code_Location = #caller_location) -> Code_Procedure_Discovery {
    return_fail :: (msg: string) #expand {
        compiler_report(tprint("Jai Shader Transpiler: %", msg), loc=loc);
        `return .{};
    }

    code_node := compiler_get_nodes(code);
    if code_node.kind != .IDENT {
        return_fail(tprint("Expected a procedure identifier, got %.", code_node.kind));
    }
    
    code_ident := cast(*Code_Ident)code_node;
    resolved_decl := code_ident.resolved_declaration;
    if resolved_decl == null {
        return_fail("Expected a resolved declaration for function passed to get_transpiled2, but got null.");
    }
    if (resolved_decl.flags & .IS_CONSTANT) == 0 {
        return_fail("Expected a constant declaration for get_transpiled2 procedure argument.");
    }
    
    if resolved_decl.kind != .DECLARATION {
        return_fail(tprint("Expected ident passed to get_transpiled2 to resolve to a .DECLARATION, got %.", resolved_decl.kind));
    }
    code_declaration := cast(*Code_Declaration)resolved_decl;
    if (code_declaration.flags & .IS_CONSTANT) == 0 {
        return_fail("Expected a constant declaration for get_transpiled2 procedure argument.");
    }
    
    if code_declaration.expression == null {
        return_fail(tprint("Procedure declaration '%' had null expression.", code_declaration.name));
    }
    if code_declaration.expression.kind != .PROCEDURE_HEADER {
        return_fail(tprint("Expected a .PROCEDURE_HEADER expression for '%', got %.", code_declaration.name, code_declaration.expression.kind));
    }
    proc_header := cast(*Code_Procedure_Header)code_declaration.expression;

    found_required_note := false;
    for proc_header.notes if it.text == required_note {
        found_required_note = true;
    }
    
    if !found_required_note {
        return_fail(tprint("Expected note '%' on procedure '%'.", required_note, code_declaration.name));
    }

    return .{
        decl_name = code_declaration.name,
        proc_header = proc_header,
        ident_name = code_ident.name,
    };
}

get_transpiled2_expand_pair :: (
    vert_name: string,
    frag_name: string,
    canonical_target_expr: string,
    target_ident: string,
    pair_note: string,
    supports_pair: bool,
    loc: Source_Code_Location = #caller_location,
) -> string #compile_time {
    if canonical_target_expr.count == 0 {
        compiler_report("Jai Shader Transpiler: get_transpiled2 target must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.", loc=loc);
        return "return \"\", .{};";
    }

    if !supports_pair {
        compiler_report("Jai Shader Transpiler: get_transpiled2 currently only supports paired graphics shaders for this target.", loc=loc);
        return "return \"\", .{};";
    }

    if vert_name.count == 0 || frag_name.count == 0 {
        return "return \"\", .{};";
    }

    request_name := tprint("transpiled_pair_%_%_%", target_ident, vert_name, frag_name);
    to_lower_in_place(request_name);
    key := tprint("pair|%|%|%", pair_note, vert_name, frag_name);
    request_source := tprint("% :: %; @%(%)\n", request_name, vert_name, pair_note, frag_name);
    ensure_get_transpiled_request_registered(key, request_source);

    source_expr := tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", canonical_target_expr, vert_name, frag_name);
    entry_id := tprint("pair|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), vert_name, frag_name);
    meta_expr := tprint("Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, entry_id, function_constants_type_name_for_request(request_name));
    path_to_shader_module := compute_path_to_shader_bucket_module(get_current_workspace());
    return tprint(#string END
G :: #import,file "%";
return %, %;
END, path_to_shader_module, source_expr, meta_expr);
}

get_transpiled2_exprs_from_call :: (call: Code, loc: Source_Code_Location) -> (string, string) #compile_time {
    return_fail :: (msg: string) #expand {
        compiler_report(tprint("Jai Shader Transpiler: %", msg), loc=loc);
        `return "", "";
    }

    root := compiler_get_nodes(call);
    if root.kind != .PROCEDURE_CALL {
        return_fail("get_transpiled2 must be called directly.");
    }

    pc := cast(*Code_Procedure_Call) root;
    if pc.arguments_unsorted.count != 2 && pc.arguments_unsorted.count != 3 {
        return_fail("get_transpiled2 expects (vert, frag) or (vert, frag, target).");
    }

    vert_name := shader_name_from_call_arg(pc.arguments_unsorted[0].expression);
    frag_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
    if !vert_name || !frag_name {
        return_fail("get_transpiled2 shader arguments must be procedure identifiers.");
    }

    packed_names := tprint("%|%", vert_name, frag_name);

    if pc.arguments_unsorted.count == 2 {
        #if OS == .MACOS return packed_names, ".METAL";
        else             return packed_names, ".VULKAN_GLSL";
    }

    target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[2].expression));
    resolved_target_expr, resolved_target_ok := resolve_transpiled_target_expr_string(pc.arguments_unsorted[2].expression);
    target_parse_expr := ifx resolved_target_ok then resolved_target_expr else target_expr;
    canonical_target_expr, canonical_target_ok := canonical_transpiled_target_expr_string(target_parse_expr);
    if !canonical_target_ok {
        return_fail("get_transpiled2 target must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.");
    }
    return packed_names, canonical_target_expr;
}

split_packed_shader_names :: (packed_names: string) -> (string, string, bool) #compile_time {
    sep_index: s64 = -1;
    for packed_names {
        if it == #char "|" {
            sep_index = it_index;
            break;
        }
    }
    if sep_index < 0 return "", "", false;
    left := string.{sep_index, packed_names.data};
    right := string.{packed_names.count - sep_index - 1, packed_names.data + sep_index + 1};
    return left, right, true;
}

get_transpiled2_named_exprs :: (vert_name: string, frag_name: string, loc: Source_Code_Location = #caller_location) -> (source_expr: string, meta_expr: string, ok: bool) #compile_time {
    if vert_name.count == 0 || frag_name.count == 0 return "", "", false;

    #if OS == .MACOS {
        canonical_target_expr := ".METAL";
        request_name := tprint("transpiled_pair_metal_%_%", vert_name, frag_name);
        to_lower_in_place(request_name);
        ensure_get_transpiled_request_registered(
            tprint("pair|%|%|%", "shader_pair_to_metal", vert_name, frag_name),
            tprint("% :: %; @%(%)\n", request_name, vert_name, "shader_pair_to_metal", frag_name),
        );
        source_expr := tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", canonical_target_expr, vert_name, frag_name);
        meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("pair|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), vert_name, frag_name), function_constants_type_name_for_request(request_name));
        return source_expr, meta_expr, true;
    }
    else {
        canonical_target_expr := ".VULKAN_GLSL";
        request_name := tprint("transpiled_pair_vulkan_glsl_%_%", vert_name, frag_name);
        to_lower_in_place(request_name);
        ensure_get_transpiled_request_registered(
            tprint("pair|%|%|%", "shader_pair_to_vulkan", vert_name, frag_name),
            tprint("% :: %; @%(%)\n", request_name, vert_name, "shader_pair_to_vulkan", frag_name),
        );
        source_expr := tprint("G.lookup_transpiled(\"%\", \"%\", \"%\")", canonical_target_expr, vert_name, frag_name);
        meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("pair|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), vert_name, frag_name), function_constants_type_name_for_request(request_name));
        return source_expr, meta_expr, true;
    }
}

get_transpiled_compute_named_exprs :: (compute_name: string, loc: Source_Code_Location = #caller_location) -> (source_expr: string, meta_expr: string, ok: bool) #compile_time {
    if compute_name.count == 0 return "", "", false;

    #if OS == .MACOS {
        canonical_target_expr := ".METAL";
        request_name := tprint("transpiled_single_metal_%", compute_name);
        to_lower_in_place(request_name);
        ensure_get_transpiled_request_registered(
            tprint("single|%|%", "shader_to_metal", compute_name),
            tprint("% :: %; @%\n", request_name, compute_name, "shader_to_metal"),
        );
        source_expr := tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", canonical_target_expr, compute_name);
        meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("single|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), "compute", compute_name), function_constants_type_name_for_request(request_name));
        return source_expr, meta_expr, true;
    }
    else {
        canonical_target_expr := ".VULKAN_GLSL";
        request_name := tprint("transpiled_single_vulkan_glsl_%", compute_name);
        to_lower_in_place(request_name);
        ensure_get_transpiled_request_registered(
            tprint("single|%|%", "shader_to_vulkan", compute_name),
            tprint("% :: %; @%\n", request_name, compute_name, "shader_to_vulkan"),
        );
        source_expr := tprint("G.lookup_transpiled(\"%\", \"%\", \"\")", canonical_target_expr, compute_name);
        meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("single|%|%|%", entry_id_target_name_from_canonical_target_expr(canonical_target_expr), "compute", compute_name), function_constants_type_name_for_request(request_name));
        return source_expr, meta_expr, true;
    }
}

get_transpiled_mesh_pipeline_named_exprs :: (mesh_name: string, fragment_name: string, loc: Source_Code_Location = #caller_location) -> (bundle_expr: string, meta_expr: string, ok: bool) #compile_time {
    if mesh_name.count == 0 || fragment_name.count == 0 return "", "", false;

    request_name := tprint("transpiled_mesh_metal_%_%", mesh_name, fragment_name);
    to_lower_in_place(request_name);
    ensure_get_transpiled_request_registered(
        tprint("mesh|%||%|%", "METAL", mesh_name, fragment_name),
        tprint("% :: %; @shader_mesh_to_metal(%)\n", request_name, mesh_name, fragment_name),
    );

    bundle_expr := tprint("G.lookup_transpiled_mesh(\".METAL\", \"\", \"%\", \"%\")", mesh_name, fragment_name);
    meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("mesh|METAL||%|%", mesh_name, fragment_name), function_constants_type_name_for_request(request_name));
    return bundle_expr, meta_expr, true;
}

get_transpiled_task_mesh_pipeline_named_exprs :: (task_name: string, mesh_name: string, fragment_name: string, loc: Source_Code_Location = #caller_location) -> (bundle_expr: string, meta_expr: string, ok: bool) #compile_time {
    if task_name.count == 0 || mesh_name.count == 0 || fragment_name.count == 0 return "", "", false;

    request_name := tprint("transpiled_mesh_metal_%_%_%", task_name, mesh_name, fragment_name);
    to_lower_in_place(request_name);
    ensure_get_transpiled_request_registered(
        tprint("mesh|%|%|%|%", "METAL", task_name, mesh_name, fragment_name),
        tprint("% :: %; @shader_task_mesh_to_metal(\"%,%\")\n", request_name, task_name, mesh_name, fragment_name),
    );

    bundle_expr := tprint("G.lookup_transpiled_mesh(\".METAL\", \"%\", \"%\", \"%\")", task_name, mesh_name, fragment_name);
    meta_expr := tprint("JTS.Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("mesh|METAL|%|%|%", task_name, mesh_name, fragment_name), function_constants_type_name_for_request(request_name));
    return bundle_expr, meta_expr, true;
}

get_transpiled2 :: (vert: $V, frag: $F, target: Transpiled_Target, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> (shader_bytes: string, shader_meta: Shader_Meta) #expand {
    #insert #run,stallable -> string {
        packed_names, canonical_target_expr := get_transpiled2_exprs_from_call(call, loc);
        if packed_names.count == 0 || canonical_target_expr.count == 0 return "return \"\", .{};";
        vert_name, frag_name, split_ok := split_packed_shader_names(packed_names);
        assert(split_ok, "get_transpiled2 internal name packing failed.");

        if canonical_target_expr == {
        case ".METAL";       return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "metal", "shader_pair_to_metal", true, loc);
        case ".HLSL";        return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "hlsl", "", false, loc);
        case ".OPENGL_GLSL"; return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "opengl_glsl", "shader_pair_to_glsl", true, loc);
        case ".VULKAN_GLSL"; return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "vulkan_glsl", "shader_pair_to_vulkan", true, loc);
        }
        compiler_report("Jai Shader Transpiler: get_transpiled2 target must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.", loc=loc);
        return "return \"\", .{};";
    };
}

// target is implied by the OS
get_transpiled2 :: (vert: $V, frag: $F, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> (shader_bytes: string, shader_meta: Shader_Meta) #expand {
    #insert #run,stallable -> string {
        packed_names, canonical_target_expr := get_transpiled2_exprs_from_call(call, loc);
        if packed_names.count == 0 || canonical_target_expr.count == 0 return "return \"\", .{};";
        vert_name, frag_name, split_ok := split_packed_shader_names(packed_names);
        assert(split_ok, "get_transpiled2 internal name packing failed.");

        if canonical_target_expr == {
        case ".METAL";       return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "metal", "shader_pair_to_metal", true, loc);
        case ".HLSL";        return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "hlsl", "", false, loc);
        case ".OPENGL_GLSL"; return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "opengl_glsl", "shader_pair_to_glsl", true, loc);
        case ".VULKAN_GLSL"; return get_transpiled2_expand_pair(vert_name, frag_name, canonical_target_expr, "vulkan_glsl", "shader_pair_to_vulkan", true, loc);
        }
        compiler_report("Jai Shader Transpiler: get_transpiled2 target must resolve to .METAL, .HLSL, .OPENGL_GLSL, or .VULKAN_GLSL.", loc=loc);
        return "return \"\", .{};";
    };
}

get_transpiled :: (
    target: Transpiled_Target, 
    args: ..Any, 
    call: Code = #caller_code, 
    loc: Source_Code_Location = #caller_location
) -> (shader_bytes: string, shader_meta: Shader_Meta) #expand {
    #insert #run,stallable -> string {
        source_expr, meta_expr, _ := transpiled_shader_exprs_from_call(call, loc);
        path_to_shader_module := compute_path_to_shader_bucket_module(get_current_workspace());
        return tprint(#string END
G :: #import,file "%";
return %, %;
END, path_to_shader_module, source_expr, meta_expr);
    };
}

get_transpiled_shader :: (
    target: Transpiled_Target,
    args: ..Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) -> Transpiled_Shader #expand {
    #insert #run,stallable -> string {
        source_expr, meta_expr, _ := transpiled_shader_exprs_from_call(call, loc);
        return tprint(#string END
G :: #import,file "%";
return Transpiled_Shader.{source = %, meta = %};
END, compute_path_to_shader_bucket_module(get_current_workspace()), source_expr, meta_expr);
    };
}

get_default_function_constants :: (
    target: Transpiled_Target,
    args: ..Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) #expand {
    #insert #run,stallable -> string {
        _, _, constants_expr := transpiled_shader_exprs_from_call(call, loc);
        return tprint("%;", constants_expr);
    };
}

get_transpiled_mesh_pipeline :: (
    target: Transpiled_Target,
    mesh_shader: Any,
    fragment_shader: Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) -> Transpiled_Mesh_Pipeline #expand {
    #insert #run,stallable -> string {
        root := compiler_get_nodes(call);
        if root.kind != .PROCEDURE_CALL {
            compiler_report("Jai Shader Transpiler: get_transpiled_mesh_pipeline must be called directly.", loc=loc);
            return "return .{};";
        }

        pc := cast(*Code_Procedure_Call) root;
        if pc.arguments_unsorted.count != 3 {
            compiler_report("Jai Shader Transpiler: get_transpiled_mesh_pipeline expects 3 args (target, mesh_fn, fragment_fn).", loc=loc);
            return "return .{};";
        }

        target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
        resolved_target_expr, resolved_target_ok := resolve_transpiled_target_expr_string(pc.arguments_unsorted[0].expression);
        target_parse_expr := ifx resolved_target_ok then resolved_target_expr else target_expr;
        canonical_target_expr, canonical_target_ok := canonical_transpiled_target_expr_string(target_parse_expr);
        if !canonical_target_ok || canonical_target_expr != ".METAL" {
            compiler_report("Jai Shader Transpiler: get_transpiled_mesh_pipeline currently only supports .METAL.", loc=loc);
            return "return .{};";
        }

        mesh_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
        fragment_name := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
        if !mesh_name || !fragment_name {
            compiler_report("Jai Shader Transpiler: mesh pipeline shader arguments must be procedure identifiers.", loc=loc);
            return "return .{};";
        }

        request_name := tprint("transpiled_mesh_metal_%_%", mesh_name, fragment_name);
        to_lower_in_place(request_name);
        key := tprint("mesh|METAL||%|%", mesh_name, fragment_name);
        request_source := tprint("% :: %; @shader_mesh_to_metal(%)\n", request_name, mesh_name, fragment_name);
        ensure_get_transpiled_request_registered(key, request_source);

        source_expr := tprint("G.lookup_transpiled_mesh(\".METAL\", \"\", \"%\", \"%\")", mesh_name, fragment_name);
        meta_expr := tprint("Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("mesh|METAL||%|%", mesh_name, fragment_name), function_constants_type_name_for_request(request_name));
        return tprint(#string END
G :: #import,file "%";
bundle := %;
return Transpiled_Mesh_Pipeline.{
  task_source = bundle.task_source,
  mesh_source = bundle.mesh_source,
  pixel_source = bundle.pixel_source,
  payload_size_bytes = bundle.payload_size_bytes,
  payload_memory_length = bundle.payload_memory_length,
  meta = %,
};
END, compute_path_to_shader_bucket_module(get_current_workspace()), source_expr, meta_expr);
    };
}

get_transpiled_task_mesh_pipeline :: (
    target: Transpiled_Target,
    task_shader: Any,
    mesh_shader: Any,
    fragment_shader: Any,
    call: Code = #caller_code,
    loc: Source_Code_Location = #caller_location
) -> Transpiled_Mesh_Pipeline #expand {
    #insert #run,stallable -> string {
        root := compiler_get_nodes(call);
        if root.kind != .PROCEDURE_CALL {
            compiler_report("Jai Shader Transpiler: get_transpiled_task_mesh_pipeline must be called directly.", loc=loc);
            return "return .{};";
        }

        pc := cast(*Code_Procedure_Call) root;
        if pc.arguments_unsorted.count != 4 {
            compiler_report("Jai Shader Transpiler: get_transpiled_task_mesh_pipeline expects 4 args (target, task_fn, mesh_fn, fragment_fn).", loc=loc);
            return "return .{};";
        }

        target_expr := trim_ascii_whitespace(expression_to_source_string(pc.arguments_unsorted[0].expression));
        resolved_target_expr, resolved_target_ok := resolve_transpiled_target_expr_string(pc.arguments_unsorted[0].expression);
        target_parse_expr := ifx resolved_target_ok then resolved_target_expr else target_expr;
        canonical_target_expr, canonical_target_ok := canonical_transpiled_target_expr_string(target_parse_expr);
        if !canonical_target_ok || canonical_target_expr != ".METAL" {
            compiler_report("Jai Shader Transpiler: get_transpiled_task_mesh_pipeline currently only supports .METAL.", loc=loc);
            return "return .{};";
        }

        task_name := shader_name_from_call_arg(pc.arguments_unsorted[1].expression);
        mesh_name := shader_name_from_call_arg(pc.arguments_unsorted[2].expression);
        fragment_name := shader_name_from_call_arg(pc.arguments_unsorted[3].expression);
        if !task_name || !mesh_name || !fragment_name {
            compiler_report("Jai Shader Transpiler: task+mesh pipeline shader arguments must be procedure identifiers.", loc=loc);
            return "return .{};";
        }

        request_name := tprint("transpiled_mesh_metal_%_%_%", task_name, mesh_name, fragment_name);
        to_lower_in_place(request_name);
        key := tprint("mesh|METAL|%|%|%", task_name, mesh_name, fragment_name);
        request_source := tprint("% :: %; @shader_task_mesh_to_metal(\"%,%\")\n", request_name, task_name, mesh_name, fragment_name);
        ensure_get_transpiled_request_registered(key, request_source);

        source_expr := tprint("G.lookup_transpiled_mesh(\".METAL\", \"%\", \"%\", \"%\")", task_name, mesh_name, fragment_name);
        meta_expr := tprint("Shader_Meta.{request_name = \"%\", entry_id = \"%\", function_constants_type_name = \"%\"}", request_name, tprint("mesh|METAL|%|%|%", task_name, mesh_name, fragment_name), function_constants_type_name_for_request(request_name));
        return tprint(#string END
G :: #import,file "%";
bundle := %;
return Transpiled_Mesh_Pipeline.{
  task_source = bundle.task_source,
  mesh_source = bundle.mesh_source,
  pixel_source = bundle.pixel_source,
  payload_size_bytes = bundle.payload_size_bytes,
  payload_memory_length = bundle.payload_memory_length,
  meta = %,
};
END, compute_path_to_shader_bucket_module(get_current_workspace()), source_expr, meta_expr);
    };
}


convert_procs :: (p: *Metaprogram_Plugin, message: *Message) {
  plugin := cast(*Jai_To_Shader_Plugin) p;
  
  assert(plugin.did_add_setup_source, "Your compiler message loop needs to call plugin.add_source first");

  if message.kind == {
    case .TYPECHECKED; {
      tc := cast(*Message_Typechecked) message;
      for tc.procedure_bodies {
        proc := it.expression;
        already := false;
        for note: proc.header.notes {
            if note.text == {
            case "compute_shader"; #through;
            case "vertex_shader"; #through;
            case "fragment_shader"; #through;
            case "task_shader"; #through;
            case "mesh_shader";
              array_add_if_unique(*plugin.known_procedure_bodies, proc);
              break;
            }
        }
      }
      for tc.declarations {
        resolved := collect_shader_requests_from_declaration(plugin, it.expression, plugin.known_procedure_bodies);
        if !resolved {
          add_pending_request_declaration(plugin, it.expression);
        }
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
        array_reset(*plugin.manifest_entries);
        workspace_root := get_working_directory();
        if !plugin.did_log_ir_pipeline {
          plugin.did_log_ir_pipeline = true;
        }

        for * pair_ctx: plugin.currently_waiting_pair_contexts {
          s: string;
          used_ir_pipeline := false;
          {
            s2, ok2, diag := write_shader_pair_ir_spirv(pair_ctx);
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
          }

          assert(s != "");
          pair_source_symbol := source_symbol_name_from_pair_context(pair_ctx);
          if !generated_symbol_already_emitted(plugin, pair_source_symbol) {
            add_code(plugin, s, "waiting_pairs");
            mark_generated_symbol_emitted(plugin, pair_source_symbol);
          }
          emit_generated_function_constant_decl(plugin,
                                               generated_function_constant_base_name(pair_ctx.name, ""),
                                               pair_ctx.vertex_fn.header.name,
                                               pair_ctx.fragment_fn.header.name,
                                               pair_ctx.function_constants);

          if plugin.output_shaders {
            ext := tprint("%", pair_ctx.language);
            to_lower_in_place(ext);
            generated_dir := jst_generated_dir();
            make_directory_if_it_does_not_exist(generated_dir, recursive = true);
            filename := tprint("%/%.%", generated_dir, pair_ctx.name, ext);
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
        }

        for *mesh_ctx: plugin.currently_waiting_mesh_contexts {
          s2, ok2, diag := write_shader_mesh_ir_spirv(mesh_ctx);
          if !ok2 {
            report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for mesh pipeline '%'.", mesh_ctx.name);
            if diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, diag.message);
            if diag.has_location compiler_report(report_message, diag.location);
            else compiler_report(report_message, make_location(mesh_ctx.mesh_fn.header));
            remove mesh_ctx;
            continue;
          }

          source_symbol := source_symbol_name_for_request(mesh_ctx.name);
          if !generated_symbol_already_emitted(plugin, source_symbol) {
            add_code(plugin, s2, "waiting_meshes");
            mark_generated_symbol_emitted(plugin, source_symbol);
          }

          manifest_entry := manifest_make_mesh_entry(mesh_ctx, workspace_root);
          if manifest_entry.request_name.count != 0 array_add(*plugin.manifest_entries, manifest_entry);
          remove mesh_ctx;
        }

        {
          jobs: [..] SPV_External_Single_Job;
          for *ctx: plugin.currently_waiting_contexts {
            job: SPV_External_Single_Job;
            prep_ok, prep_diag := prepare_single_spirv_external_job(ctx, *job);
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
            source, finalize_ok, finalize_diag := finalize_single_spirv_external_job(it, add_generated_comment=true);
            if !finalize_ok {
              report_message := tprint("Jai Shader Transpiler: SPIR-V backend mode failed for shader '%' (%).",
                                       ctx.name, ctx.type);
              if finalize_diag.message.count != 0 report_message = tprint("%\nReason: %", report_message, finalize_diag.message);
              if finalize_diag.has_location compiler_report(report_message, finalize_diag.location);
              else compiler_report(report_message, make_location(ctx.main_fn.header));
              continue;
            }
            if ctx.language == .METAL {
              ctx.metal_output_source_path = copy_string(manifest_output_source_path(ctx.name, "METAL"));
              if ctx.metal_output_source_path.count != 0 {
                make_directory_if_it_does_not_exist(path_strip_filename(ctx.metal_output_source_path), recursive=true);
                if !write_entire_file(ctx.metal_output_source_path, source) {
                  compiler_report(tprint("Jai Shader Transpiler: failed to write Metal source '%'.", ctx.metal_output_source_path), make_location(ctx.main_fn.header));
                  continue;
                }
              }
              if ctx.type == .Vertex ctx.metal_vertex_entry_name = copy_string(it.entry_name);
              if ctx.type == .Fragment ctx.metal_fragment_entry_name = copy_string(it.entry_name);
              if ctx.type == .Compute {
                ctx.metal_compute_entry_name = copy_string(it.entry_name);
                if contains(source, "constant*") && contains(source, "[[buffer(0)]]") ctx.metal_compute_binding_mode = "ROOT_POINTER_STRUCT";
                else ctx.metal_compute_binding_mode = "DIRECT_ADDRESSES";
              }
            }

            source_symbol := source_symbol_name_from_context(ctx);
            if !generated_symbol_already_emitted(plugin, source_symbol) {
              s := tprint("% :: #string END\n%\nEND", source_symbol, source);
              add_code(plugin, s, "jobs");
              mark_generated_symbol_emitted(plugin, source_symbol);
            }
            emit_generated_function_constant_decl(plugin,
                                                 generated_function_constant_base_name(request_name_from_context(ctx), ""),
                                                 ctx.name,
                                                 "",
                                                 ctx.function_constants);
            if plugin.output_shaders {
              ext := tprint("%", ctx.language);
              to_lower_in_place(ext);
              generated_dir := jst_generated_dir();
              make_directory_if_it_does_not_exist(generated_dir, recursive = true);
              filename := tprint("%/%.%", generated_dir, ctx.name, ext);
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
          }
          array_reset(*plugin.currently_waiting_contexts);
        }

        if !build_metal_artifacts_for_manifest_entries(plugin, workspace_root) {
          compiler_report("Jai Shader Transpiler: failed building Metal AIR/metallib artifacts.");
        }

        if plugin.manifest_entries.count > 0 emit_shader_reload_manifest(plugin);
        #if VERBOSE jst_log_cache_summary();

        emit_lookup_overloads(plugin, p.workspace);
      }
    }
    
    /*
    case .FILE;
        message_file := cast(*Message_File)message;
        log("FILE: % vs %", message_file.fully_pathed_filename, #file);
    */
    
    case .COMPLETE; {
      using,except(message, plugin) plugin;
      if currently_waiting_contexts.count != 0 || currently_waiting_pair_contexts.count != 0 || currently_waiting_mesh_contexts.count != 0 {
        complete_message := cast(*Message_Complete)message;
        if complete_message.error_code == 0 {
          compiler_report("Jai Shader Transpiler: Compiler is finished, but some functions have not yet been transpiled.");
        }
      }
      array_reset(*currently_waiting_contexts);
      array_reset(*currently_waiting_pair_contexts);
      array_reset(*currently_waiting_mesh_contexts);
      array_reset(*pending_request_declarations);
      array_reset(*known_procedure_bodies);
      array_reset(*lookup_entries);
      array_reset(*emitted_symbol_names);
      array_reset(*manifest_entries);
      did_emit_lookup_overloads = false;
      did_log_ir_pipeline = false;
      did_log_ir_limitations = false;
      jst_cache_stats = .{};
      table_reset(*get_transpiled_requests_seen);
    }
  }
}

_before_intercept :: (p: *Metaprogram_Plugin, intercept_flags: *Intercept_Flags) {
}

_add_source :: (p: *Metaprogram_Plugin) {
    // Here at the beginning of the compiler loop, we generate a .jai file in the intermediate directory.
    // We can use that generated module as a known-good place in this workspace to #poke_name our generated
    // shader strings into later, and also to look them up via get_transpiled.
    assert(p.workspace > 0);
    path_to_generated_source := compute_path_to_shader_bucket_module(p.workspace);
    make_directory_if_it_does_not_exist(path_strip_filename(path_to_generated_source), recursive=true);
    ok := write_entire_file(path_to_generated_source, #string END
// Auto-generated from Jai_To_Shader's _add_source
#scope_export

shader_function_constant_type :: enum {
    BOOL;
    U8;
    S8;
    U16;
    S16;
    U32;
    S32;
    U64;
    S64;
    FLOAT;
    FLOAT2;
    FLOAT3;
    FLOAT4;
}

shader_function_constant_info :: struct {
    name: string;
    index: u32;
    type: shader_function_constant_type;
    offset: s64;
}

JST_Mesh_Source_Bundle_Lookup :: struct {
    task_source: string;
    mesh_source: string;
    pixel_source: string;
    payload_size_bytes: s64;
    payload_memory_length: s64;
}

#placeholder lookup_transpiled_impl;
#placeholder lookup_transpiled_mesh_impl;

lookup_transpiled :: (target_name: string, primary_name: string, secondary_name: string) -> string {
    return lookup_transpiled_impl(target_name, primary_name, secondary_name);
}

lookup_transpiled_mesh :: (target_name: string, primary_name: string, secondary_name: string, tertiary_name: string) -> JST_Mesh_Source_Bundle_Lookup {
    value := lookup_transpiled_mesh_impl(target_name, primary_name, secondary_name, tertiary_name);
    return .{
        task_source = value.task_source,
        mesh_source = value.mesh_source,
        pixel_source = value.pixel_source,
        payload_size_bytes = value.payload_size_bytes,
        payload_memory_length = value.payload_memory_length,
    };
}
END);
    assert(ok);
    
    plugin := cast(*Jai_To_Shader_Plugin)p;
    add_build_file(path_to_generated_source, p.workspace);
    plugin.did_add_setup_source = true;
}

compute_path_to_shader_bucket_module :: (workspace: Workspace) -> string {
    assert(workspace > 0);
    opts := get_build_options(workspace);
    path := sprint("%/jst_generated.jai", opts.intermediate_path);
    return path;
}

ir_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.language != .METAL && !(ctx.language == .GLSL && ctx.glsl_target == .VULKAN) return false;
  return ctx.type == .Vertex || ctx.type == .Fragment || ctx.type == .Compute || ctx.type == .Task || ctx.type == .Mesh;
}

request_target_ident_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == {
    case .METAL; return "_metal";
    case .HLSL; return "_hlsl";
    case .GLSL;
      if glsl_target == .VULKAN return "_vulkan_glsl";
      return "_opengl_glsl";
  }
  return "";
}

request_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  if !ctx return "";
  target_ident := request_target_ident_from_language(ctx.language, ctx.glsl_target);
  return tprint("transpiled_single_%_%", target_ident, ctx.name);
}

source_symbol_name_from_context :: (ctx: *Shader_Write_Context) -> string {
  return source_symbol_name_for_request(request_name_from_context(ctx));
}

source_symbol_name_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  if !pair_ctx return "";
  return source_symbol_name_for_request(pair_ctx.name);
}

ir_target_from_context :: (ctx: *Shader_Write_Context) -> (Toolchain_Target, bool) {
  if ctx.language == .METAL return .METAL, true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return .VULKAN_GLSL, true;
  return .METAL, false;
}

ir_stage_short_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.type == .Vertex return "vert";
  if ctx.type == .Compute return "comp";
  if ctx.type == .Task return "task";
  if ctx.type == .Mesh return "mesh";
  return "frag";
}

ir_output_ext_from_context :: (ctx: *Shader_Write_Context) -> string {
  if ctx.language == .METAL return "metal";
  return "glsl";
}

function_constant_decl_already_present :: (constants: [] IR_Function_Constant, decl: *Code_Declaration) -> bool {
  if !decl return false;
  for constants if it.declaration == decl return true;
  return false;
}

function_constant_spec_slot_count :: (type: IR_Function_Constant_Type) -> u32 {
  if type == {
    case .FLOAT2; return 2;
    case .FLOAT3; return 3;
    case .FLOAT4; return 4;
  }
  return 1;
}

assign_single_function_constant_spec_ids :: (shader: *IR_Shader) {
  if !shader return;
  next_spec_id: u32 = 0;
  for *shader.function_constants {
    it.spec_id = next_spec_id;
    next_spec_id += function_constant_spec_slot_count(it.type);
  }
}

assign_pair_function_constant_spec_ids :: (vertex: *IR_Vertex_Shader, fragment: *IR_Fragment_Shader, out_pair_constants: *[..] IR_Function_Constant) {
  array_reset(out_pair_constants);
  if vertex for vertex.function_constants if !function_constant_decl_already_present(out_pair_constants.*, it.declaration) array_add(out_pair_constants, it);
  if fragment for fragment.function_constants if !function_constant_decl_already_present(out_pair_constants.*, it.declaration) array_add(out_pair_constants, it);

  next_spec_id: u32 = 0;
  for i: 0..out_pair_constants.count-1 {
    out_pair_constants.*[i].spec_id = next_spec_id;
    next_spec_id += function_constant_spec_slot_count(out_pair_constants.*[i].type);
  }

  if vertex {
    for i: 0..vertex.function_constants.count-1 {
      fc := *vertex.function_constants[i];
      for pair_fc: out_pair_constants.* {
        if fc.declaration != pair_fc.declaration continue;
        fc.spec_id = pair_fc.spec_id;
        break;
      }
    }
  }
  if fragment {
    for i: 0..fragment.function_constants.count-1 {
      fc := *fragment.function_constants[i];
      for pair_fc: out_pair_constants.* {
        if fc.declaration != pair_fc.declaration continue;
        fc.spec_id = pair_fc.spec_id;
        break;
      }
    }
  }
}

generated_function_constant_base_name :: (request_name: string, kind_suffix: string) -> string {
  base := sanitize_identifier_component(request_name);
  to_lower_in_place(base);
  //while contains(base, "__") base = replace(base, "__", "_");
  if ends_with(base, "_main") {
    base.count -= 5;
  }
  if kind_suffix.count != 0 {
    suffix_text := tprint("_%", kind_suffix);
    if ends_with(base, suffix_text) return base;
    return tprint("%_%", base, kind_suffix);
  }
  return base;
}

emit_generated_function_constant_decl :: (plugin: *Jai_To_Shader_Plugin,
                                          base_name: string,
                                          primary_name: string,
                                          secondary_name: string,
                                          constants: [] IR_Function_Constant) {
  _ = primary_name;
  _ = secondary_name;

  struct_name := tprint("%_function_constants", base_name);
  info_name := tprint("%_function_constant_info", base_name);
  if generated_symbol_already_emitted(plugin, struct_name) return;

  sb: String_Builder;
  for constants {
    alias_name := tprint("__%_%_type", base_name, it.name);
    append(*sb, tprint("% :: type_of(%);\n", alias_name, it.name));
  }
  if constants.count > 0 append(*sb, "\n");
  append(*sb, tprint("% :: struct {\n", struct_name));
  for constants {
    type_name := tprint("__%_%_type", base_name, it.name);
    append(*sb, tprint("  %: % = %;\n", it.name, type_name, it.default_value_text));
  }
  append(*sb, "}\n\n");
  append(*sb, tprint("% :: shader_function_constant_info.[\n", info_name));
  for constants {
    type_enum_str := tprint(".%", it.type);
    append(*sb, tprint("  .{name = \"%\", index = %, type = %, offset = #run offset_of(%, \"%\")},\n",
                       it.name, it.spec_id, type_enum_str, struct_name, it.name));
  }
  append(*sb, "];\n");

  code := builder_to_string(*sb);
  #if VERBOSE log("----\n%\n----", code);

  add_code(plugin, code, tprint("function_constants_%", base_name));
  mark_generated_symbol_emitted(plugin, struct_name);
  mark_generated_symbol_emitted(plugin, info_name);
}

ir_output_path_from_context :: (ctx: *Shader_Write_Context) -> string {
  return tprint("%/%.%", jst_generated_dir(), ctx.name, ir_output_ext_from_context(ctx));
}

ir_output_path_from_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> string {
  return tprint("%/%.metal", jst_generated_dir(), pair_ctx.name);
}

is_internal_transpiled_request_name :: (name: string) -> bool {
  return begins_with(name, "transpiled_single_") || begins_with(name, "transpiled_pair_");
}

ir_metal_enable_unsafe_runtime_array_indexing :: (source: string) -> string {
  out := source;
  // SPIRV-Cross can emit a generic signed-mod helper that uses `select(...)`
  // in a way Metal may treat as ambiguous for 64-bit integer template params.
  out = replace(out,
                "return select(Tx(remainder + y), remainder, remainder == 0 || (x >= 0) == (y >= 0));",
                "return (remainder == 0 || (x >= 0) == (y >= 0)) ? remainder : Tx(remainder + y);");
  return out;
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

ir_pipeline_label_spirv :: (target: Toolchain_Target) -> string {
  if target == .METAL return "Jai -> IR -> SPIRV -> SPIRV-Cross -> Metal";
  return "Jai -> IR -> SPIRV -> SPIRV-Cross -> GLSL";
}

ir_prepend_generated_comment :: (target_source: string, source_jai_file: string, pipeline_label: string) -> string {
  jai_file := source_jai_file;
  if jai_file.count == 0 jai_file = "<unknown>";
  return tprint("// Generated from % with (<<%>>)\n%", jai_file, pipeline_label, target_source);
}

ir_spirv_supports_single_context :: (ctx: *Shader_Write_Context) -> bool {
  if !ctx return false;
  if ctx.type != .Vertex && ctx.type != .Fragment && ctx.type != .Compute return false;
  if ctx.language == .METAL return true;
  if ctx.language == .GLSL && ctx.glsl_target == .VULKAN return true;
  return false;
}

ir_lowered_struct_has_resource_fields :: (structs: [] IR_Struct, struct_name: string, depth := 0) -> bool {
  if struct_name.count == 0 return false;
  if depth > 16 return false;
  for structs {
    if it.name != struct_name continue;
    for it.fields {
      if it.type.kind == .POINTER return true;
      nested_name := it.type.struct_name;
      if ir_lowered_struct_has_resource_fields(structs, nested_name, depth + 1) return true;
    }
    return false;
  }
  return false;
}

ir_graphics_requires_metal_argument_buffer :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> bool {
  for args {
    if it.type.kind == .POINTER return true;
    struct_name := it.type.struct_name;
    if ir_lowered_struct_has_resource_fields(extra_structs, struct_name) return true;
  }
  return false;
}

SPV_External_Single_Job :: struct {
  ctx: *Shader_Write_Context;
  validate_before_opt: bool;
  stage: IR_Shader_Kind;
  target: Toolchain_Target;
  entry_name: string;
  source_entry_name: string;
  use_metal_argument_buffers: bool;
  spvasm_path: string;
  spv_path: string;
  spv_opt_path: string;
  output_path: string;

  ok: bool;
  error_message: string;
}

prepare_single_spirv_external_job :: (ctx: *Shader_Write_Context, job: *SPV_External_Single_Job) -> (ok: bool, diag: IR_Diagnostic) {
  assert(ctx != null && job != null);
  
  return_err :: (msg: string) #expand {
      diag: IR_Diagnostic = { message = msg };
      if ctx.main_fn && ctx.main_fn.header {
        diag.location = make_location(ctx.main_fn.header);
        diag.has_location = true;
      }
      `return false, diag;
  }

  diag: IR_Diagnostic;
  if !ir_spirv_supports_single_context(ctx)
      return_err("SPIR-V backend currently supports vertex/fragment/compute shaders targeting Metal or Vulkan GLSL only. Task/mesh lowering is not wired yet.");

  target, target_ok := ir_target_from_context(ctx);
  if !target_ok
      return_err("SPIR-V backend: unsupported target for context.");

  spv_binary: [] u8;
  spv_ok := false;
  spv_diag: IR_Diagnostic;
  entry_name: string;
  use_metal_argument_buffers := false;

  if ctx.type == .Vertex {
    vert_result := ir_lower_vertex_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_vertex, lowered, lowered_diag := unpack_result(vert_result);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_vertex);
    entry_name = ir_vertex.entry_name;
    vert_spv_res := to_spv_binary(*ir_vertex);
    spv_binary, spv_ok, spv_diag = unpack_result(vert_spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_vertex.args, ir_vertex.extra_structs);
  } else if ctx.type == .Fragment {
    frag_lower_res := ir_lower_fragment_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_fragment, lowered, lowered_diag := unpack_result(frag_lower_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_fragment);
    entry_name = ir_fragment.entry_name;
    frag_spv_res := to_spv_binary(*ir_fragment);
    spv_binary, spv_ok, spv_diag = unpack_result(frag_spv_res);
    use_metal_argument_buffers = ir_graphics_requires_metal_argument_buffer(ir_fragment.args, ir_fragment.extra_structs);
  } else {
    lower_compute_res := ir_lower_compute_from_shader_context(.{name=ctx.name, header=ctx.main_fn.header});
    ir_compute, lowered, lowered_diag := unpack_result(lower_compute_res);
    if !lowered return false, lowered_diag;
    normalize_shader(*ir_compute);
    entry_name = ir_compute.entry_name;
    compute_spv_res := to_spv_binary(*ir_compute);
    spv_binary, spv_ok, spv_diag = unpack_result(compute_spv_res);
  }

  if entry_name.count == 0
      return_err("SPIR-V backend: empty entry name.");
  source_entry_name := entry_name;
  if ctx.language == .METAL {
    if ctx.type == .Compute entry_name = tprint("%_ComputeMain", ctx.name);
  }

  build_dir := jst_ir_intermediate_dir();
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  stage_short := ir_stage_short_from_context(ctx);
  output_ext := ifx ctx.language == .METAL then "metal" else "glsl";

  job.ctx = ctx;
  job.validate_before_opt = false;
  job.stage = ctx.type;
  job.target = target;
  job.entry_name = copy_string(entry_name);
  job.source_entry_name = copy_string(source_entry_name);
  job.use_metal_argument_buffers = use_metal_argument_buffers;
  job.spvasm_path = sprint("%/%_%.spvasm", build_dir, ctx.name, stage_short);
  job.spv_path = sprint("%/%_%.spv", build_dir, ctx.name, stage_short);
  job.spv_opt_path = sprint("%/%_%.opt.spv", build_dir, ctx.name, stage_short);
  job.output_path = sprint("%/%_%.%", build_dir, ctx.name, stage_short, output_ext);
  job.ok = false;
  job.error_message = "";

  if !spv_ok {
    if spv_diag.message.count == 0 spv_diag.message = tprint("SPIR-V binary backend: failed to emit SPIR-V for '%'.", ctx.name);
    if !spv_diag.has_location && ctx.main_fn && ctx.main_fn.header {
      spv_diag.location = make_location(ctx.main_fn.header);
      spv_diag.has_location = true;
    }
    return false, spv_diag;
  }

  if !write_entire_file(job.spv_path, spv_binary.data, spv_binary.count) {
    diag.message = tprint("SPIR-V backend: failed writing SPIR-V binary '%'.", job.spv_path);
    if spv_binary.data free(spv_binary.data);
    return false, diag;
  }
  if spv_binary.data free(spv_binary.data);
  jst_mirror_to_legacy_intermediate_if_needed(job.spv_path);

  return true, diag;
}

run_spirv_external_single_job :: (job: *SPV_External_Single_Job) -> bool {
  assert(job != null);
  if job.validate_before_opt {
    if !validate_spirv_binary(job.spv_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
  }

  if USE_SPIRV_OPT {
    if !jst_optimize_spirv_binary_cached(job.spv_path, job.spv_opt_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-opt failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
    jst_mirror_to_legacy_intermediate_if_needed(job.spv_opt_path);
  } else {
    job.spv_opt_path = job.spv_path;
  }

  if !validate_spirv_binary(job.spv_opt_path) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-val failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }

  if jst_should_emit_spvasm_debug() {
    if !jst_disassemble_spirv_binary_cached(job.spv_path, job.spvasm_path) {
      job.error_message = copy_string(tprint("SPIR-V backend: spirv-dis failed for '%'. SPIR-V: %", job.ctx.name, job.spv_path));
      return false;
    }
    jst_mirror_to_legacy_intermediate_if_needed(job.spvasm_path);
  }

  if !jst_emit_spirv_cross_target_source_cached(job.spv_opt_path, job.entry_name, job.stage, job.target, job.output_path, job.use_metal_argument_buffers, source_entry_name=job.source_entry_name) {
    job.error_message = copy_string(tprint("SPIR-V backend: spirv-cross failed for '%'. SPIR-V: %", job.ctx.name, job.spv_opt_path));
    return false;
  }
  jst_mirror_to_legacy_intermediate_if_needed(job.output_path);

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
  defer shutdown(*tg);

  for *jobs add_work(*tg, it);

  completed := 0;
  while completed < jobs.count {
    done := get_completed_work(*tg);
    completed += done.count;
    if completed < jobs.count sleep_milliseconds(1);
  }
}

finalize_single_spirv_external_job :: (job: *SPV_External_Single_Job, add_generated_comment := true) -> (target_source: string, ok: bool, diag: IR_Diagnostic) {
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

  target_source, read_ok := read_entire_file(job.output_path);
  if !read_ok {
    diag.message = tprint("SPIR-V backend: failed reading emitted target source '%'.", job.output_path);
    return "", false, diag;
  }

  if job.ctx.language == .METAL && job.ctx.type != .Compute {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    write_entire_file(job.output_path, target_source);
  }
  if job.ctx.type == .Compute && job.ctx.language == .METAL {
    target_source = ir_metal_enable_unsafe_runtime_array_indexing(target_source);
    target_source = replace(target_source, "[[kernel]] void", "kernel void");
  }
  if add_generated_comment {
    target_source = ir_prepend_generated_comment(target_source, ir_source_file_from_context(job.ctx), ir_pipeline_label_spirv(job.target));
  }
  write_entire_file(job.output_path, target_source);

  return target_source, true, diag;
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

ir_type_text_local :: (type: IR_Type) -> string {
  if type.display_name.count != 0 return type.display_name;
  if type.struct_name.count != 0 return type.struct_name;
  return "<unknown>";
}

ir_types_equal_local :: (a: IR_Type, b: IR_Type) -> bool {
  if a.kind != b.kind return false;
  if a.flags != b.flags return false;
  if a.struct_name != b.struct_name return false;
  if a.array_count != b.array_count return false;
  if a.element_kind != b.element_kind return false;
  if a.element_struct_name != b.element_struct_name return false;
  if a.pointee_kind != b.pointee_kind return false;
  if a.pointee_struct_name != b.pointee_struct_name return false;
  if a.pointee_array_count != b.pointee_array_count return false;
  if a.pointee_element_kind != b.pointee_element_kind return false;
  if a.pointee_element_struct_name != b.pointee_element_struct_name return false;
  return true;
}

ir_validate_pair_stage_interface_local :: (pair_name: string, vertex: *IR_Vertex_Shader, fragment: *IR_Fragment_Shader) -> (bool, string) {
    auto_release_temp();
  assert(vertex != null && fragment != null);

  vertex_varyings:   [..] IR_Field;
  vertex_varyings.allocator = temp;
  
  fragment_varyings: [..] IR_Field;
  fragment_varyings.allocator = temp;
  
  for vertex.output.fields {
    if ir_vertex_output_field_is_builtin_local(*it) continue;
    array_add(*vertex_varyings, it);
  }
  for fragment.input.fields {
    if ir_fragment_input_field_is_builtin_local(*it) continue;
    array_add(*fragment_varyings, it);
  }

  if vertex_varyings.count != fragment_varyings.count {
    return false, sprint("SPIR-V backend: pair '%': stage interface mismatch: vertex exports % user varyings but fragment consumes %.", pair_name, vertex_varyings.count, fragment_varyings.count);
  }

  for i: 0..fragment_varyings.count-1 {
    v := vertex_varyings[i];
    f := fragment_varyings[i];
    if !ir_types_equal_local(v.type, f.type) {
      return false, sprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' has type '%', fragment '%' has type '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), ir_type_text_local(v.type), ir_pair_varying_field_label_local(*f), ir_type_text_local(f.type));
    }
    if !ir_pair_varyings_match_local(*v, *f) {
      return false, sprint("SPIR-V backend: pair '%': stage interface mismatch at varying %: vertex '%' does not match fragment '%'.", pair_name, i, ir_pair_varying_field_label_local(*v), ir_pair_varying_field_label_local(*f));
    }
  }

  return true, "";
}

write_shader_pair_ir_spirv :: (pair_ctx: *Shader_Write_Pair_Context) -> (string, bool, IR_Diagnostic) {
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

  vert_result := ir_lower_vertex_from_shader_context(.{name=vertex_ctx.name, header=vertex_ctx.main_fn.header});
  ir_vertex, vertex_ok, vertex_diag := unpack_result(vert_result);
  if !vertex_ok {
    if !vertex_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      vertex_diag.location = make_location(pair_ctx.vertex_fn.header);
      vertex_diag.has_location = true;
    }
    return "", false, vertex_diag;
  }
  assign_single_function_constant_spec_ids(*ir_vertex);
  normalize_shader(*ir_vertex);

  frag_result := ir_lower_fragment_from_shader_context(.{name=fragment_ctx.name, header=fragment_ctx.main_fn.header});
  ir_fragment, fragment_ok, fragment_diag := unpack_result(frag_result);
  
  if !fragment_ok {
    if !fragment_diag.has_location && pair_ctx.fragment_fn && pair_ctx.fragment_fn.header {
      fragment_diag.location = make_location(pair_ctx.fragment_fn.header);
      fragment_diag.has_location = true;
    }
    return "", false, fragment_diag;
  }
  assign_single_function_constant_spec_ids(*ir_fragment);
  normalize_shader(*ir_fragment);
  assign_pair_function_constant_spec_ids(*ir_vertex, *ir_fragment, *pair_ctx.function_constants);

  vertex_uses_pointer_abi   := ir_uses_pointer_abi_local(ir_vertex.args, ir_vertex.extra_structs);
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

  assert(ir_vertex.entry_name.count != 0);
  assert(ir_fragment.entry_name.count != 0);
  vert_spv_res := to_spv_binary(*ir_vertex);
  vertex_spv_binary, vertex_spv_ok, vertex_spv_diag := unpack_result(vert_spv_res);
  if !vertex_spv_ok {
    if !vertex_spv_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      vertex_spv_diag.location = make_location(pair_ctx.vertex_fn.header);
      vertex_spv_diag.has_location = true;
    }
    return "", false, vertex_spv_diag;
  }
  frag_spv_res := to_spv_binary(*ir_fragment);
  fragment_spv_binary, fragment_spv_ok, fragment_spv_diag := unpack_result(frag_spv_res);
  if !fragment_spv_ok {
    if !fragment_spv_diag.has_location && pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      fragment_spv_diag.location = make_location(pair_ctx.vertex_fn.header);
      fragment_spv_diag.has_location = true;
    }
    return "", false, fragment_spv_diag;
  }

  build_dir := jst_ir_intermediate_dir();
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  vertex_spvasm_path := tprint("%/%_vert.spvasm", build_dir, pair_ctx.name);
  fragment_spvasm_path := tprint("%/%_frag.spvasm", build_dir, pair_ctx.name);
  vertex_spv_path := tprint("%/%_vert.spv", build_dir, pair_ctx.name);
  fragment_spv_path := tprint("%/%_frag.spv", build_dir, pair_ctx.name);
  vertex_opt_spv_path := tprint("%/%_vert.opt.spv", build_dir, pair_ctx.name);
  fragment_opt_spv_path := tprint("%/%_frag.opt.spv", build_dir, pair_ctx.name);
  pair_spv_path := tprint("%/%_pair.spv", build_dir, pair_ctx.name);
  pair_spvasm_path := tprint("%/%_pair.spvasm", build_dir, pair_ctx.name);
  vertex_output_path := tprint("%/%_vert.metal", build_dir, pair_ctx.name);
  fragment_output_path := tprint("%/%_frag.metal", build_dir, pair_ctx.name);
  metal_vertex_entry_name := tprint("%_VertexMain", pair_ctx.name);
  metal_fragment_entry_name := tprint("%_FragmentMain", pair_ctx.name);
  if !write_entire_file(vertex_spv_path, vertex_spv_binary.data, vertex_spv_binary.count) || !write_entire_file(fragment_spv_path, fragment_spv_binary.data, fragment_spv_binary.count) {
    diag.message = "SPIR-V backend: failed writing pair SPIR-V binaries.";
    if vertex_spv_binary.data free(vertex_spv_binary.data);
    if fragment_spv_binary.data free(fragment_spv_binary.data);
    return "", false, diag;
  }
  if vertex_spv_binary.data free(vertex_spv_binary.data);
  if fragment_spv_binary.data free(fragment_spv_binary.data);
  jst_mirror_to_legacy_intermediate_if_needed(vertex_spv_path);
  jst_mirror_to_legacy_intermediate_if_needed(fragment_spv_path);

  if !jst_optimize_spirv_binary_cached(vertex_spv_path, vertex_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for pair vertex module.";
    return "", false, diag;
  }
  if !jst_optimize_spirv_binary_cached(fragment_spv_path, fragment_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for pair fragment module.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(vertex_opt_spv_path);
  jst_mirror_to_legacy_intermediate_if_needed(fragment_opt_spv_path);

  if !validate_spirv_binary(vertex_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for pair vertex module.";
    return "", false, diag;
  }
  if !validate_spirv_binary(fragment_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for pair fragment module.";
    return "", false, diag;
  }

  if !link_spirv_binaries(.[vertex_spv_path, fragment_spv_path], pair_spv_path) {
    diag.message = "SPIR-V backend: spirv-link failed for pair module.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(pair_spv_path);

  if jst_should_emit_spvasm_debug() {
    if !jst_disassemble_spirv_binary_cached(vertex_opt_spv_path, vertex_spvasm_path) {
      diag.message = "SPIR-V backend: spirv-dis failed for pair vertex module.";
      return "", false, diag;
    }
    if !jst_disassemble_spirv_binary_cached(fragment_opt_spv_path, fragment_spvasm_path) {
      diag.message = "SPIR-V backend: spirv-dis failed for pair fragment module.";
      return "", false, diag;
    }
    if !jst_disassemble_spirv_binary_cached(pair_spv_path, pair_spvasm_path) {
      diag.message = "SPIR-V backend: spirv-dis failed for pair module.";
      return "", false, diag;
    }
    jst_mirror_to_legacy_intermediate_if_needed(vertex_spvasm_path);
    jst_mirror_to_legacy_intermediate_if_needed(fragment_spvasm_path);
    jst_mirror_to_legacy_intermediate_if_needed(pair_spvasm_path);
  }
  if !jst_emit_spirv_cross_target_source_cached(vertex_opt_spv_path, metal_vertex_entry_name, .Vertex, .METAL, vertex_output_path, use_metal_argument_buffers, source_entry_name=ir_vertex.entry_name) {
    diag.message = "SPIR-V backend: pair vertex spirv-cross failed.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(vertex_output_path);
  if !jst_emit_spirv_cross_target_source_cached(fragment_opt_spv_path, metal_fragment_entry_name, .Fragment, .METAL, fragment_output_path, use_metal_argument_buffers, source_entry_name=ir_fragment.entry_name) {
    diag.message = "SPIR-V backend: pair fragment spirv-cross failed.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(fragment_output_path);

  vertex_source, v_ok   := read_entire_file(vertex_output_path);
  fragment_source, f_ok := read_entire_file(fragment_output_path);
  if !v_ok || !f_ok {
    diag.message = "SPIR-V backend: failed reading pair spirv-cross outputs.";
    return "", false, diag;
  }

  vertex_source = ir_metal_enable_unsafe_runtime_array_indexing(vertex_source);
  fragment_source = ir_metal_enable_unsafe_runtime_array_indexing(fragment_source);
  _ = write_entire_file(vertex_output_path, vertex_source);
  _ = write_entire_file(fragment_output_path, fragment_source);

  merged_source := ir_merge_metal_pair_sources(vertex_source, fragment_source);
  merged_source = ir_metal_enable_unsafe_runtime_array_indexing(merged_source);
  merged_source = ir_prepend_generated_comment(merged_source, ir_source_file_from_pair_context(pair_ctx), ir_pipeline_label_spirv(.METAL));
  output_path := ir_output_path_from_pair_context(pair_ctx);
  make_directory_if_it_does_not_exist(path_strip_filename(output_path), recursive=true);
  if !write_entire_file(output_path, merged_source) {
    diag.message = tprint("SPIR-V backend: failed writing merged pair source '%'.", output_path);
    if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
      diag.location = make_location(pair_ctx.vertex_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  pair_ctx.metal_vertex_entry_name = copy_string(metal_vertex_entry_name);
  pair_ctx.metal_fragment_entry_name = copy_string(metal_fragment_entry_name);
  pair_ctx.metal_output_source_path = copy_string(manifest_output_source_path(pair_ctx.name, "METAL"));
  if pair_ctx.metal_output_source_path.count != 0 {
    make_directory_if_it_does_not_exist(path_strip_filename(pair_ctx.metal_output_source_path), recursive=true);
    if !write_entire_file(pair_ctx.metal_output_source_path, merged_source) {
      diag.message = tprint("SPIR-V backend: failed writing pair source '%'.", pair_ctx.metal_output_source_path);
      if pair_ctx.vertex_fn && pair_ctx.vertex_fn.header {
        diag.location = make_location(pair_ctx.vertex_fn.header);
        diag.has_location = true;
      }
      return "", false, diag;
    }
  }

  decl := tprint("% :: #string END\n%\nEND", source_symbol_name_from_pair_context(pair_ctx), merged_source);
  return decl, true, diag;
}

ir_source_file_from_mesh_context :: (mesh_ctx: *Shader_Write_Mesh_Context) -> string {
  if !mesh_ctx return "";
  mesh_file := ir_source_file_from_proc(mesh_ctx.mesh_fn);
  fragment_file := ir_source_file_from_proc(mesh_ctx.fragment_fn);
  if mesh_file.count == 0 return fragment_file;
  if fragment_file.count == 0 return mesh_file;
  if mesh_file == fragment_file return mesh_file;
  return tprint("% | %", mesh_file, fragment_file);
}

mesh_payload_builtin_from_expr :: (using expr: *IR_Expr) -> IR_Call_Builtin_Kind {
  if !expr || kind != .CALL return .NONE;
  if call_builtin_kind == .TASK_PAYLOAD_PTR return .TASK_PAYLOAD_PTR;
  if call_builtin_kind == .MESH_PAYLOAD_PTR return .MESH_PAYLOAD_PTR;
  callee_name := call_resolved_name;
  if callee_name.count == 0 && left && (left.kind == .IDENT || left.kind == .MEMBER) callee_name = left.text;
  if callee_name.count == 0 {
    call_text := ir_canonical_callee_name(expr_text(expr));
    if contains(call_text, "task_payload_ptr()") return .TASK_PAYLOAD_PTR;
    if contains(call_text, "mesh_payload_ptr()") return .MESH_PAYLOAD_PTR;
  }
  if ir_canonical_callee_name(callee_name) == "task_payload_ptr" return .TASK_PAYLOAD_PTR;
  if ir_canonical_callee_name(callee_name) == "mesh_payload_ptr" return .MESH_PAYLOAD_PTR;
  return .NONE;
}

mesh_payload_struct_name_in_expr :: (expr: *IR_Expr, out_name: *string) -> bool {
  if !expr return true;

  if expr.kind == .CALL {
    builtin_kind := mesh_payload_builtin_from_expr(expr);
    if builtin_kind == .TASK_PAYLOAD_PTR || builtin_kind == .MESH_PAYLOAD_PTR {
      struct_name := expr.result_type.pointee_struct_name;
      if struct_name.count == 0 return false;
      if out_name.*.count == 0 out_name.* = struct_name;
      else assert(out_name.* == struct_name, "Mesh payload type mismatch: '%' vs '%'.", out_name.*, struct_name);
    }
  }

  if expr.left && !mesh_payload_struct_name_in_expr(expr.left, out_name) return false;
  if expr.right && !mesh_payload_struct_name_in_expr(expr.right, out_name) return false;
  for expr.args if !mesh_payload_struct_name_in_expr(it, out_name) return false;
  return true;
}

mesh_payload_struct_name_in_block :: (block: *IR_Block, out_name: *string) -> bool {
  if !block return true;
  for block.statements {
    stmt := *it;
    if stmt.decl_init && !mesh_payload_struct_name_in_expr(stmt.decl_init, out_name) return false;
    if stmt.binary_left && !mesh_payload_struct_name_in_expr(stmt.binary_left, out_name) return false;
    if stmt.binary_right && !mesh_payload_struct_name_in_expr(stmt.binary_right, out_name) return false;
    if stmt.if_condition && !mesh_payload_struct_name_in_expr(stmt.if_condition, out_name) return false;
    if stmt.if_then && !mesh_payload_struct_name_in_block(stmt.if_then, out_name) return false;
    if stmt.if_else && !mesh_payload_struct_name_in_block(stmt.if_else, out_name) return false;
    if stmt.for_start && !mesh_payload_struct_name_in_expr(stmt.for_start, out_name) return false;
    if stmt.for_end && !mesh_payload_struct_name_in_expr(stmt.for_end, out_name) return false;
    if stmt.for_body && !mesh_payload_struct_name_in_block(stmt.for_body, out_name) return false;
    if stmt.while_condition && !mesh_payload_struct_name_in_expr(stmt.while_condition, out_name) return false;
    if stmt.while_body && !mesh_payload_struct_name_in_block(stmt.while_body, out_name) return false;
    if stmt.call_expr && !mesh_payload_struct_name_in_expr(stmt.call_expr, out_name) return false;
    if stmt.return_expr && !mesh_payload_struct_name_in_expr(stmt.return_expr, out_name) return false;
    for stmt.switch_cases if it.body && !mesh_payload_struct_name_in_block(it.body, out_name) return false;
  }
  return true;
}

mesh_payload_struct_name_in_shader :: (shader: *IR_Shader) -> string {
  if !shader return "";
  name := "";
  _ = mesh_payload_struct_name_in_block(*shader.body, *name);
  for shader.functions {
    _ = mesh_payload_struct_name_in_block(*it.body, *name);
  }
  if name.count == 0 {
    payload_candidate := "";
    for shader.extra_structs {
      has_upper, _ := contains(it.name, "Payload");
      has_lower, _ := contains(it.name, "payload");
      if !has_upper && !has_lower continue;
      if payload_candidate.count == 0 payload_candidate = it.name;
      else return "";
    }
    if payload_candidate.count != 0 return payload_candidate;
  }
  if name.count == 0 && shader.extra_structs.count == 1 {
    name = shader.extra_structs[0].name;
  }
  return name;
}

payload_layout_for_type :: (structs: [] IR_Struct, ir_type: IR_Type) -> (size: s64, align: s64, ok: bool) {
  if ir_type.kind == .BOOL return 4, 4, true;
  if ir_type.kind == .I32 || ir_type.kind == .U32 || ir_type.kind == .F32 return 4, 4, true;
  if ir_type.kind == .I64 || ir_type.kind == .U64 return 8, 8, true;
  if ir_type.kind == .F16 return 2, 2, true;
  if ir_type.kind == .F32x2 return 8, 8, true;
  if ir_type.kind == .F32x3 return 12, 16, true;
  if ir_type.kind == .F32x4 return 16, 16, true;
  if ir_type.kind == .STRUCT {
    nested: *IR_Struct = null;
    for *structs {
      if it.name == ir_type.struct_name {
        nested = it;
        break;
      }
    }
    if !nested return 0, 0, false;
    nested_size, nested_align, nested_ok := payload_layout_for_struct(structs, nested);
    return nested_size, nested_align, nested_ok;
  }
  if ir_type.kind == .FIXED_ARRAY {
    elem_type := IR_Type.{
      kind = ir_type.element_kind,
      display_name = ir_type.element_display_name,
      struct_name = ir_type.element_struct_name,
    };
    elem_size, elem_align, elem_ok := payload_layout_for_type(structs, elem_type);
    if !elem_ok return 0, 0, false;
    stride := align_up(elem_size, elem_align);
    return stride * ir_type.array_count, elem_align, true;
  }
  return 0, 0, false;
}

payload_layout_for_struct :: (structs: [] IR_Struct, st: *IR_Struct) -> (size: s64, align: s64, ok: bool) {
  if !st return 0, 0, false;
  offset: s64 = 0;
  max_align: s64 = 1;
  for st.fields {
    field_size, field_align, field_ok := payload_layout_for_type(structs, it.type);
    if !field_ok return 0, 0, false;
    offset = align_up(offset, field_align);
    offset += field_size;
    if field_align > max_align max_align = field_align;
  }
  return offset, max_align, true;
}

payload_layout_from_name :: (structs: [] IR_Struct, payload_struct_name: string) -> (size: s64, memory_length: s64, ok: bool) {
  if !payload_struct_name.count return 0, 0, true;
  st: *IR_Struct = null;
  for *structs {
    if it.name == payload_struct_name {
      st = it;
      break;
    }
  }
  if !st return 0, 0, false;
  payload_size, _, payload_ok := payload_layout_for_struct(structs, st);
  if !payload_ok return 0, 0, false;
  return payload_size, align_up(payload_size, 16), true;
}

write_shader_mesh_ir_spirv :: (mesh_ctx: *Shader_Write_Mesh_Context) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !mesh_ctx || mesh_ctx.language != .METAL || mesh_ctx.mesh_fn == null || mesh_ctx.fragment_fn == null {
    diag.message = "SPIR-V backend: unsupported mesh pipeline context/target combination.";
    if mesh_ctx && mesh_ctx.mesh_fn && mesh_ctx.mesh_fn.header {
      diag.location = make_location(mesh_ctx.mesh_fn.header);
      diag.has_location = true;
    }
    return "", false, diag;
  }

  task_source := "";
  metal_task_entry_name := "";
  payload_struct_name := "";
  payload_size_bytes: s64 = 0;
  payload_memory_length: s64 = 0;
  if mesh_ctx.task_fn != null {
    task_ir_res := ir_lower_task_from_shader_context(.{name = mesh_ctx.task_fn.header.name, header = mesh_ctx.task_fn.header});
    ir_task, task_ok, task_diag := unpack_result(task_ir_res);
    if !task_ok return "", false, task_diag;
    ir_task.payload_struct_name = mesh_payload_struct_name_in_shader(*ir_task);
    if ir_task.payload_struct_name.count != 0 {
      computed_payload_size, computed_payload_memory_length, payload_ok := payload_layout_from_name(ir_task.extra_structs, ir_task.payload_struct_name);
      if !payload_ok {
        diag.message = tprint("SPIR-V backend: failed computing payload layout for '%'.", ir_task.payload_struct_name);
        return "", false, diag;
      }
      ir_task.payload_size_bytes = computed_payload_size;
      payload_memory_length = computed_payload_memory_length;
      payload_struct_name = ir_task.payload_struct_name;
      payload_size_bytes = ir_task.payload_size_bytes;
    }
    assign_single_function_constant_spec_ids(*ir_task);
    normalize_shader(*ir_task);

    task_spv_res := to_spv_binary(*ir_task);
    task_spv, task_spv_ok, task_spv_diag := unpack_result(task_spv_res);
    if !task_spv_ok return "", false, task_spv_diag;

    build_dir := jst_ir_intermediate_dir();
    make_directory_if_it_does_not_exist(build_dir, recursive=true);
    task_spv_path := tprint("%/%_task.spv", build_dir, mesh_ctx.name);
    task_opt_spv_path := tprint("%/%_task.opt.spv", build_dir, mesh_ctx.name);
    task_output_path := tprint("%/%_task.metal", build_dir, mesh_ctx.name);
    metal_task_entry_name = tprint("%_ObjectMain", mesh_ctx.name);

    if !write_entire_file(task_spv_path, task_spv.data, task_spv.count) {
      if task_spv.data free(task_spv.data);
      diag.message = "SPIR-V backend: failed writing mesh task SPIR-V binary.";
      return "", false, diag;
    }
    if task_spv.data free(task_spv.data);
    jst_mirror_to_legacy_intermediate_if_needed(task_spv_path);

    if !jst_optimize_spirv_binary_cached(task_spv_path, task_opt_spv_path) {
      diag.message = "SPIR-V backend: spirv-opt failed for task stage.";
      return "", false, diag;
    }
    jst_mirror_to_legacy_intermediate_if_needed(task_opt_spv_path);

    if !validate_spirv_binary(task_opt_spv_path) {
      diag.message = "SPIR-V backend: spirv-val failed for task stage.";
      return "", false, diag;
    }

    if !jst_emit_spirv_cross_target_source_cached(task_opt_spv_path, metal_task_entry_name, .Task, .METAL, task_output_path, false, source_entry_name=ir_task.entry_name) {
      diag.message = "SPIR-V backend: task spirv-cross failed.";
      return "", false, diag;
    }
    jst_mirror_to_legacy_intermediate_if_needed(task_output_path);

    task_source_read, task_read_ok := read_entire_file(task_output_path);
    if !task_read_ok {
      diag.message = "SPIR-V backend: failed reading task spirv-cross output.";
      return "", false, diag;
    }
    task_source_read = replace(task_source_read, "[[object]]", "[[object, max_total_threads_per_threadgroup(1)]]");
    task_source_read = ir_metal_enable_unsafe_runtime_array_indexing(task_source_read);
    task_source_read = ir_prepend_generated_comment(task_source_read, ir_source_file_from_mesh_context(mesh_ctx), ir_pipeline_label_spirv(.METAL));
    _ = write_entire_file(task_output_path, task_source_read);
    task_source = task_source_read;
  }

  mesh_ir_res := ir_lower_mesh_from_shader_context(.{name = mesh_ctx.mesh_fn.header.name, header = mesh_ctx.mesh_fn.header});
  ir_mesh, mesh_ok, mesh_diag := unpack_result(mesh_ir_res);
  if !mesh_ok return "", false, mesh_diag;
  ir_mesh.payload_struct_name = mesh_payload_struct_name_in_shader(*ir_mesh);
  if ir_mesh.payload_struct_name.count != 0 {
    computed_payload_size, mesh_payload_memory_length, payload_ok := payload_layout_from_name(ir_mesh.extra_structs, ir_mesh.payload_struct_name);
    if !payload_ok {
      diag.message = tprint("SPIR-V backend: failed computing mesh payload layout for '%'.", ir_mesh.payload_struct_name);
      return "", false, diag;
    }
    ir_mesh.payload_size_bytes = computed_payload_size;
    if payload_struct_name.count == 0 {
      payload_struct_name = ir_mesh.payload_struct_name;
      payload_size_bytes = ir_mesh.payload_size_bytes;
      payload_memory_length = mesh_payload_memory_length;
    } else {
      assert(payload_struct_name == ir_mesh.payload_struct_name, "Mesh payload type mismatch: '%' vs '%'.", payload_struct_name, ir_mesh.payload_struct_name);
      assert(payload_size_bytes == ir_mesh.payload_size_bytes, "Mesh payload size mismatch for '%'.", payload_struct_name);
      payload_memory_length = max(payload_memory_length, mesh_payload_memory_length);
    }
  }
  assign_single_function_constant_spec_ids(*ir_mesh);
  normalize_shader(*ir_mesh);

  frag_ir_res := ir_lower_fragment_from_shader_context(.{name = mesh_ctx.fragment_fn.header.name, header = mesh_ctx.fragment_fn.header});
  ir_fragment, frag_ok, frag_diag := unpack_result(frag_ir_res);
  if !frag_ok return "", false, frag_diag;
  ir_mesh.output = ir_fragment.input;
  assign_single_function_constant_spec_ids(*ir_fragment);
  normalize_shader(*ir_fragment);

  mesh_spv_res := to_spv_binary(*ir_mesh);
  mesh_spv, mesh_spv_ok, mesh_spv_diag := unpack_result(mesh_spv_res);
  if !mesh_spv_ok return "", false, mesh_spv_diag;

  frag_spv_res := to_spv_binary(*ir_fragment);
  frag_spv, frag_spv_ok, frag_spv_diag := unpack_result(frag_spv_res);
  if !frag_spv_ok return "", false, frag_spv_diag;

  build_dir := jst_ir_intermediate_dir();
  make_directory_if_it_does_not_exist(build_dir, recursive=true);
  mesh_spv_path := tprint("%/%_mesh.spv", build_dir, mesh_ctx.name);
  frag_spv_path := tprint("%/%_frag.spv", build_dir, mesh_ctx.name);
  mesh_opt_spv_path := tprint("%/%_mesh.opt.spv", build_dir, mesh_ctx.name);
  frag_opt_spv_path := tprint("%/%_frag.opt.spv", build_dir, mesh_ctx.name);
  mesh_output_path := tprint("%/%_mesh.metal", build_dir, mesh_ctx.name);
  frag_output_path := tprint("%/%_frag.metal", build_dir, mesh_ctx.name);
  combined_output_path := tprint("%/%_mesh_pipeline.metal", build_dir, mesh_ctx.name);
  metal_mesh_entry_name := tprint("%_MeshMain", mesh_ctx.name);
  metal_fragment_entry_name := tprint("%_FragmentMain", mesh_ctx.name);

  if !write_entire_file(mesh_spv_path, mesh_spv.data, mesh_spv.count) || !write_entire_file(frag_spv_path, frag_spv.data, frag_spv.count) {
    if mesh_spv.data free(mesh_spv.data);
    if frag_spv.data free(frag_spv.data);
    diag.message = "SPIR-V backend: failed writing mesh pipeline SPIR-V binaries.";
    return "", false, diag;
  }
  if mesh_spv.data free(mesh_spv.data);
  if frag_spv.data free(frag_spv.data);
  jst_mirror_to_legacy_intermediate_if_needed(mesh_spv_path);
  jst_mirror_to_legacy_intermediate_if_needed(frag_spv_path);

  if !jst_optimize_spirv_binary_cached(mesh_spv_path, mesh_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for mesh stage.";
    return "", false, diag;
  }
  if !jst_optimize_spirv_binary_cached(frag_spv_path, frag_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-opt failed for mesh fragment stage.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(mesh_opt_spv_path);
  jst_mirror_to_legacy_intermediate_if_needed(frag_opt_spv_path);

  if !validate_spirv_binary(mesh_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for mesh stage.";
    return "", false, diag;
  }
  if !validate_spirv_binary(frag_opt_spv_path) {
    diag.message = "SPIR-V backend: spirv-val failed for mesh fragment stage.";
    return "", false, diag;
  }

  if !jst_emit_spirv_cross_target_source_cached(mesh_opt_spv_path, metal_mesh_entry_name, .Mesh, .METAL, mesh_output_path, false, source_entry_name=ir_mesh.entry_name) {
    diag.message = "SPIR-V backend: mesh spirv-cross failed.";
    return "", false, diag;
  }
  if !jst_emit_spirv_cross_target_source_cached(frag_opt_spv_path, metal_fragment_entry_name, .Fragment, .METAL, frag_output_path, false, source_entry_name=ir_fragment.entry_name) {
    diag.message = "SPIR-V backend: mesh fragment spirv-cross failed.";
    return "", false, diag;
  }
  jst_mirror_to_legacy_intermediate_if_needed(mesh_output_path);
  jst_mirror_to_legacy_intermediate_if_needed(frag_output_path);

  mesh_source, mesh_read_ok := read_entire_file(mesh_output_path);
  frag_source, frag_read_ok := read_entire_file(frag_output_path);
  if !mesh_read_ok || !frag_read_ok {
    diag.message = "SPIR-V backend: failed reading mesh pipeline spirv-cross outputs.";
    return "", false, diag;
  }

  mesh_source = ir_metal_enable_unsafe_runtime_array_indexing(mesh_source);
  frag_source = ir_metal_enable_unsafe_runtime_array_indexing(frag_source);
  mesh_source = ir_prepend_generated_comment(mesh_source, ir_source_file_from_mesh_context(mesh_ctx), ir_pipeline_label_spirv(.METAL));
  frag_source = ir_prepend_generated_comment(frag_source, ir_source_file_from_mesh_context(mesh_ctx), ir_pipeline_label_spirv(.METAL));
  _ = write_entire_file(mesh_output_path, mesh_source);
  _ = write_entire_file(frag_output_path, frag_source);

  combined_source := ifx task_source.count != 0
      then tprint("%\n%\n%", task_source, mesh_source, frag_source)
      else tprint("%\n%", mesh_source, frag_source);
  _ = write_entire_file(combined_output_path, combined_source);

  mesh_ctx.metal_output_source_path = copy_string(combined_output_path);
  mesh_ctx.metal_output_air_path = copy_string(tprint("%.air", combined_output_path));
  mesh_ctx.metal_task_entry_name = ifx task_source.count != 0 then copy_string(metal_task_entry_name) else "";
  mesh_ctx.metal_mesh_entry_name = copy_string(metal_mesh_entry_name);
  mesh_ctx.metal_fragment_entry_name = copy_string(metal_fragment_entry_name);

  bundle_symbol := source_symbol_name_for_request(mesh_ctx.name);
  decl := tprint(#string END
% :: JST_Mesh_Source_Bundle_Lookup.{
  task_source = #string END_TASK
%
END_TASK,
  mesh_source = #string END_MESH
%
END_MESH,
  pixel_source = #string END_PIXEL
%
END_PIXEL,
  payload_size_bytes = %,
  payload_memory_length = %,
};
END, bundle_symbol, task_source, mesh_source, frag_source, payload_size_bytes, payload_memory_length);
  return decl, true, diag;
}

ir_supports_pair_context :: (pair_ctx: *Shader_Write_Pair_Context) -> bool {
  if !pair_ctx return false;
  if pair_ctx.language != .METAL return false;
  return pair_ctx.vertex_fn != null && pair_ctx.fragment_fn != null;
}

shader_request_name_to_language :: (name: string) -> (Shader_Language, GLSL_Target, bool) {
  if name == {
    case "shader_to_glsl";   return .GLSL,  .OPENGL, true;
    case "shader_to_vulkan"; return .GLSL,  .VULKAN, true;
    case "shader_to_hlsl";   return .HLSL,  .OPENGL, true;
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

queue_lookup_entry :: (plugin: *Jai_To_Shader_Plugin, target_name: string, primary_name: string, secondary_name: string, symbol_name: string, tertiary_name := "") {
  for plugin.lookup_entries {
    if it.target_name != target_name continue;
    if it.primary_name != primary_name continue;
    if it.secondary_name != secondary_name continue;
    if it.tertiary_name != tertiary_name continue;
    if it.symbol_name != symbol_name continue;
    return;
  }
  array_add(*plugin.lookup_entries, .{
    target_name = target_name,
    primary_name = primary_name,
    secondary_name = secondary_name,
    tertiary_name = tertiary_name,
    symbol_name = symbol_name,
  });
  if plugin.did_emit_lookup_overloads {
    plugin.did_emit_lookup_overloads = false;
    emit_lookup_overloads(plugin, plugin.workspace);
  }
}

emit_lookup_overloads :: (plugin: *Jai_To_Shader_Plugin, workspace: Workspace) {
  if plugin.did_emit_lookup_overloads return;
  plugin.did_emit_lookup_overloads = true;

  sb: String_Builder;
  append_lines(*sb,
    tprint("G :: #import,file \"%\";", compute_path_to_shader_bucket_module(plugin.workspace)),
    "#poke_name G lookup_transpiled_impl;",
    "lookup_transpiled_impl :: (target_name: string, primary_name: string, secondary_name: string) -> string {",
  );
  for plugin.lookup_entries {
    if it.tertiary_name.count != 0 continue;
    a(*sb, "  if target_name == \"%\" && primary_name == \"%\" && secondary_name == \"%\" return %;",
                 it.target_name, it.primary_name, it.secondary_name, it.symbol_name);
  }
  a(*sb, "  return \"\";\n}");

  append_lines(*sb,
    "#poke_name G lookup_transpiled_mesh_impl;",
    "lookup_transpiled_mesh_impl :: (target_name: string, primary_name: string, secondary_name: string, tertiary_name: string) -> JST_Mesh_Source_Bundle_Lookup {",
  );
  for plugin.lookup_entries {
    if it.tertiary_name.count == 0 continue;
    a(*sb, "  if target_name == \"%\" && primary_name == \"%\" && secondary_name == \"%\" && tertiary_name == \"%\" return %;",
                 it.target_name, it.primary_name, it.secondary_name, it.tertiary_name, it.symbol_name);
  }
  a(*sb, "  return .{};\n}");

  add_code(plugin, builder_to_string(*sb), "lookup_overloads");
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

    rest: string = { note_text.count - prefix.count, note_text.data + prefix.count };
    if rest.count == 0 return .NONE, .OPENGL, "", true, false;

    close_paren_index: s64 = -1;
    for i: 0..rest.count-1 {
      if rest[i] == #char ")" {
        close_paren_index = i;
        break;
      }
    }
    if close_paren_index == -1 return .NONE, .OPENGL, "", true, false;

    arg: string = { close_paren_index, rest.data };
    arg = trim_ascii_whitespace(arg);
    if arg.count == 0 return .NONE, .OPENGL, "", true, false;

    trailing: string = { rest.count - (close_paren_index + 1), rest.data + close_paren_index + 1 };
    trailing = trim_ascii_whitespace(trailing);
    if trailing.count != 0 return .NONE, .OPENGL, "", true, false;

    return languages[it_index], targets[it_index], arg, true, true;
  }

  return .NONE, .OPENGL, "", false, false;
}

parse_shader_mesh_note :: (note_text: string) -> (Shader_Language, GLSL_Target, string, string, bool, bool) {
  prefixes := string.[
    "shader_mesh_to_metal(",
    "shader_task_mesh_to_metal(",
  ];
  languages := Shader_Language.[.METAL, .METAL];
  targets := GLSL_Target.[.OPENGL, .OPENGL];

  for prefixes {
    prefix := it;
    if !begins_with(note_text, prefix) continue;

    rest: string = { note_text.count - prefix.count, note_text.data + prefix.count };
    if rest.count == 0 return .NONE, .OPENGL, "", "", true, false;

    close_paren_index: s64 = -1;
    for i: 0..rest.count-1 {
      if rest[i] == #char ")" {
        close_paren_index = i;
        break;
      }
    }
    if close_paren_index == -1 return .NONE, .OPENGL, "", "", true, false;

    args: string = { close_paren_index, rest.data };
    args = trim_ascii_whitespace(args);
    if args.count == 0 return .NONE, .OPENGL, "", "", true, false;

    quoted_pair := false;
    if args.count >= 2 && args[0] == #char "\"" && args[args.count-1] == #char "\"" {
      args = string.{ args.count - 2, args.data + 1 };
      quoted_pair = true;
    }

    comma_index := find_index_from_left(args, ",");
    mesh_name := "";
    fragment_name := "";
    if comma_index < 0 {
      mesh_name = "";
      fragment_name = trim_ascii_whitespace(args);
      if fragment_name.count == 0 return .NONE, .OPENGL, "", "", true, false;
    } else {
      first_arg: string = {comma_index, args.data};
      second_arg: string = {args.count - comma_index - 1, args.data + comma_index + 1};
      first_arg = trim_ascii_whitespace(first_arg);
      second_arg = trim_ascii_whitespace(second_arg);
      if first_arg.count == 0 || second_arg.count == 0 return .NONE, .OPENGL, "", "", true, false;
      mesh_name = first_arg;
      fragment_name = second_arg;
    }

    if quoted_pair && mesh_name.count == 0 return .NONE, .OPENGL, "", "", true, false;

    trailing: string = { rest.count - (close_paren_index + 1), rest.data + close_paren_index + 1 };
    trailing = trim_ascii_whitespace(trailing);
    if trailing.count != 0 return .NONE, .OPENGL, "", "", true, false;

    return languages[it_index], targets[it_index], mesh_name, fragment_name, true, true;
  }

  return .NONE, .OPENGL, "", "", false, false;
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

mesh_context_already_queued :: (plugin: *Jai_To_Shader_Plugin, language: Shader_Language, task: *Code_Procedure_Body, mesh: *Code_Procedure_Body, fragment: *Code_Procedure_Body, glsl_target: GLSL_Target) -> bool {
  for *plugin.currently_waiting_mesh_contexts {
    if it.task_fn != task continue;
    if it.mesh_fn != mesh continue;
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
  for procedure_bodies if it.header.name == name return it;
  return null;
}

collect_shader_requests_from_declaration :: (plugin: *Jai_To_Shader_Plugin, decl: *Code_Declaration, procedure_bodies: [] *Code_Procedure_Body) -> bool {
  if !decl return true;

  requested_languages: [..] Shader_Language;
  requested_glsl_targets: [..] GLSL_Target;
  pair_requested_languages: [..] Shader_Language;
  pair_requested_glsl_targets: [..] GLSL_Target;
  pair_fragment_names: [..] string;
  mesh_requested_languages: [..] Shader_Language;
  mesh_requested_glsl_targets: [..] GLSL_Target;
  mesh_task_names: [..] string;
  mesh_stage_names: [..] string;
  mesh_fragment_names: [..] string;
  for decl.notes {
    language, glsl_target, is_shader_request := shader_request_name_to_language(it.text);
    if is_shader_request {
      array_add(*requested_languages, language);
      array_add(*requested_glsl_targets, glsl_target);
      continue;
    }

    pair_language, pair_glsl_target, fragment_name, pair_matched, pair_valid := parse_shader_pair_note(it.text);
    if pair_matched {
      if !pair_valid {
        compiler_report("Jai Shader Transpiler: Invalid shader pair request note format. Use @shader_pair_to_metal(fragment_fn), @shader_pair_to_glsl(fragment_fn), or @shader_pair_to_vulkan(fragment_fn).", make_location(decl));
        continue;
      }
      array_add(*pair_requested_languages, pair_language);
      array_add(*pair_requested_glsl_targets, pair_glsl_target);
      array_add(*pair_fragment_names, fragment_name);
      continue;
    }

    mesh_language, mesh_glsl_target, mesh_name, mesh_fragment_name, mesh_matched, mesh_valid := parse_shader_mesh_note(it.text);
    if !mesh_matched continue;
    if !mesh_valid {
      compiler_report("Jai Shader Transpiler: Invalid mesh shader request note format. Use @shader_mesh_to_metal(fragment_fn) on a @mesh_shader declaration, or @shader_mesh_to_metal(mesh_fn, fragment_fn) on a @task_shader declaration.", make_location(decl));
      continue;
    }
    array_add(*mesh_requested_languages, mesh_language);
    array_add(*mesh_requested_glsl_targets, mesh_glsl_target);
    array_add(*mesh_task_names, "");
    array_add(*mesh_stage_names, mesh_name);
    array_add(*mesh_fragment_names, mesh_fragment_name);
  }
  if requested_languages.count == 0 && pair_requested_languages.count == 0 && mesh_requested_languages.count == 0 return true;

  vertex_proc := resolve_shader_request_target(decl.expression, procedure_bodies);
  if !vertex_proc {
    // Declarations can typecheck before the target procedure body is available in early passes.
    return false;
  }
  vertex_lookup_name := vertex_proc.header.name;
  if decl.expression && decl.expression.kind == .IDENT {
    ident := cast(*Code_Ident) decl.expression;
    vertex_lookup_name = ident.name;
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
      request_name := tprint("transpiled_single_%_%", request_target_ident_from_language(language, glsl_target), ctx.name);
      to_lower_in_place(request_name);
      symbol_name := source_symbol_name_for_request(request_name);
      queue_lookup_entry(plugin, target_name, vertex_lookup_name, "", symbol_name);
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

    vertex_is_valid   := proc_has_note(vertex_proc.header, "vertex_shader");
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
      symbol_name := source_symbol_name_for_request(pair_name);
      queue_lookup_entry(plugin, target_name, vertex_lookup_name, fragment_name, symbol_name);
    }
  }

  for mesh_requested_languages {
    language := it;
    glsl_target := mesh_requested_glsl_targets[it_index];
    _ = mesh_task_names[it_index];
    mesh_name := mesh_stage_names[it_index];
    fragment_name := mesh_fragment_names[it_index];
    task_proc: *Code_Procedure_Body = null;
    mesh_proc: *Code_Procedure_Body = null;
    if mesh_name.count == 0 {
      mesh_proc = vertex_proc;
    } else {
      task_proc = vertex_proc;
      mesh_proc = resolve_shader_request_target_by_name(mesh_name, procedure_bodies);
    }
    fragment_proc := resolve_shader_request_target_by_name(fragment_name, procedure_bodies);
    if !mesh_proc || !fragment_proc || (mesh_name.count != 0 && !task_proc) return false;

    task_is_valid := mesh_name.count == 0 || proc_has_note(task_proc.header, "task_shader");
    mesh_is_valid := proc_has_note(mesh_proc.header, "mesh_shader");
    fragment_is_valid := proc_has_note(fragment_proc.header, "fragment_shader");
    if !task_is_valid || !mesh_is_valid || !fragment_is_valid {
      compiler_report("Jai Shader Transpiler: shader_mesh_to_metal requires either a @mesh_shader declaration expression plus @fragment_shader note argument, or a @task_shader declaration expression plus @mesh_shader and @fragment_shader note arguments.", make_location(decl));
      continue;
    }

    if mesh_context_already_queued(plugin, language, task_proc, mesh_proc, fragment_proc, glsl_target) continue;
    mesh_ctx := Shader_Write_Mesh_Context.{
      name = ifx decl.name.count != 0 then decl.name else ifx task_proc then tprint("%_%_%", task_proc.header.name, mesh_proc.header.name, fragment_proc.header.name) else tprint("%_%", mesh_proc.header.name, fragment_proc.header.name),
      language = language,
      glsl_target = glsl_target,
      task_fn = task_proc,
      mesh_fn = mesh_proc,
      fragment_fn = fragment_proc,
    };
    array_add(*plugin.currently_waiting_mesh_contexts, mesh_ctx);

    target_name := target_name_from_language(language, glsl_target);
    if target_name.count != 0 {
      symbol_name := source_symbol_name_for_request(mesh_ctx.name);
      lookup_primary := ifx task_proc then task_proc.header.name else "";
      lookup_secondary := mesh_proc.header.name;
      queue_lookup_entry(plugin, target_name, lookup_primary, lookup_secondary, symbol_name, tertiary_name=fragment_name);
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

Shader_Type :: IR_Shader_Kind;

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
  
  // TODO: enum_flags
  metal_use_jai_radians: bool;
  metal_use_jai_degrees: bool;
  metal_allow_fragcoord_from_position: bool;
  metal_output_source_path: string;
  metal_output_air_path: string;
  metal_output_metallib_path: string;
  metal_vertex_entry_name: string;
  metal_fragment_entry_name: string;
  metal_compute_entry_name: string;
  metal_compute_binding_mode: string;
  function_constants: [..] IR_Function_Constant;
}

Shader_Write_Pair_Context :: struct {
  name: string;
  language: Shader_Language;
  glsl_target: GLSL_Target;
  vertex_fn: *Code_Procedure_Body;
  fragment_fn: *Code_Procedure_Body;
  metal_output_source_path: string;
  metal_output_air_path: string;
  metal_output_metallib_path: string;
  metal_vertex_entry_name: string;
  metal_fragment_entry_name: string;
  function_constants: [..] IR_Function_Constant;
}

Shader_Write_Mesh_Context :: struct {
  name: string;
  language: Shader_Language;
  glsl_target: GLSL_Target;
  task_fn: *Code_Procedure_Body;
  mesh_fn: *Code_Procedure_Body;
  fragment_fn: *Code_Procedure_Body;
  metal_output_source_path: string;
  metal_output_air_path: string;
  metal_output_metallib_path: string;
  metal_task_entry_name: string;
  metal_mesh_entry_name: string;
  metal_fragment_entry_name: string;
}

member_is_stage_builtin :: (member: *Type_Info_Struct_Member) -> bool {
  auto_release_temp();
  
  builtin_string_fragments :: []string.{
    "position", "fragcoord", "fragdepth", "vertexid", "instanceid",
    "frontfacing", "pointsize", "sampleid", "samplemask",
  };

  for member.notes {
    normalized_note = replace(it, "_", "",, temp);
    to_lower_in_place(normalized_note);
    for fragment: builtin_string_fragment {
      if contains(normalized_note, fragment) {
        return true;
      }
    }
  }
  return false;
}

#load "metal_build.jai";

#scope_file

#import "Basic";
#import "Compiler";
PP :: #import "Program_Print";
#import "String";
#import "Math";
#import "Hash_Table";
#import "Thread";
#import "System";
#import "File";
FU :: #import "File_Utilities";
Process :: #import "Process";

#load "ir.jai";
#load "jst_cache.jai";
#load "build_timings.jai";
#load "string_builder_util.jai";
#load "write_shader_manifest.jai";

proc_has_note :: (node: *Code_Procedure_Header, note: string) -> bool {
  for node.notes if it.text == note return true;
  return false;
}

create_shader_write_context :: (language: Shader_Language, proc: *Code_Procedure_Body, glsl_target: GLSL_Target = .OPENGL) -> Shader_Write_Context {
    shader_type: Shader_Type;
    if      proc_has_note(proc.header, "vertex_shader")    shader_type = .Vertex;
    else if proc_has_note(proc.header, "fragment_shader")  shader_type = .Fragment;
    else if proc_has_note(proc.header, "compute_shader")   shader_type = .Compute;
    else if proc_has_note(proc.header, "task_shader")      shader_type = .Task;
    else if proc_has_note(proc.header, "mesh_shader")      shader_type = .Mesh;
    else
      compiler_report("Jai Shader Transpiler: No shader type tag found. Use @vertex_shader, @fragment_shader, @compute_shader, @task_shader, or @mesh_shader.", make_location(proc.header));
    
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


unpack_result :: (result: IR_Result($R)) -> (R, bool, IR_Diagnostic) {
    return result.value, result.ok, result.diag;
}

add_code :: (plugin: *Jai_To_Shader_Plugin, code: string, ctx := "") {
    add_build_string(code, plugin.workspace);
}

generated_symbol_already_emitted :: (plugin: *Jai_To_Shader_Plugin, name: string) -> bool {
  for plugin.emitted_symbol_names if it == name return true;
  return false;
}

mark_generated_symbol_emitted :: (plugin: *Jai_To_Shader_Plugin, name: string) {
  if name.count == 0 return;
  if generated_symbol_already_emitted(plugin, name) return;
  array_add(*plugin.emitted_symbol_names, copy_string(name));
}
