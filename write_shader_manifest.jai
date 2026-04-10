#import,file "./modules/shader_reload_manifest.jai";

manifest_target_from_language :: (language: Shader_Language, glsl_target: GLSL_Target) -> string {
  if language == .METAL return "METAL";
  if language == .HLSL return "HLSL";
  if language == .GLSL {
    if glsl_target == .VULKAN return "VULKAN_GLSL";
    return "OPENGL_GLSL";
  }
  return "UNKNOWN";
}

manifest_ext_from_target :: (target: string) -> string {
  if target == "METAL" return "metal";
  if target == "HLSL" return "hlsl";
  if target == "OPENGL_GLSL" return "glsl";
  if target == "VULKAN_GLSL" return "glsl";
  return "";
}

manifest_output_source_path :: (request_name: string, target: string) -> string {
  if request_name.count == 0 return "";
  ext := manifest_ext_from_target(target);
  if ext.count == 0 return "";
  return tprint("%/%.%", jst_generated_dir(), request_name, ext);
}

manifest_stage_from_shader_type :: (type: Shader_Type) -> string {
  if type == .Vertex return "vertex";
  if type == .Fragment return "fragment";
  if type == .Compute return "compute";
  if type == .Task return "task";
  if type == .Mesh return "mesh";
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
  
  array_add_if_unique(out_deps, rel);
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
  out.output_source_path = manifest_output_source_path(out.request_name, out.target);
  if ctx.metal_output_source_path.count != 0 out.output_source_path = copy_string(ctx.metal_output_source_path);
  out.output_air_path = copy_string(ctx.metal_output_air_path);
  out.output_metallib_path = copy_string(ctx.metal_output_metallib_path);
  out.primary_name = copy_string(ctx.main_fn.header.name);
  out.secondary_name = "";
  out.metal_vertex_entry = copy_string(ctx.metal_vertex_entry_name);
  out.metal_fragment_entry = copy_string(ctx.metal_fragment_entry_name);
  out.metal_compute_entry = copy_string(ctx.metal_compute_entry_name);
  out.metal_compute_binding_mode = copy_string(ctx.metal_compute_binding_mode);
  proc_sig := manifest_header_signature(ctx.main_fn.header);
  out.signature = tprint("kind=single;stage=%;target=%;%", out.stage, out.target, proc_sig);
  out.signature_hash = tprint("%", manifest_hash_u64(out.signature));

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
  out.output_source_path = manifest_output_source_path(out.request_name, out.target);
  if ctx.metal_output_source_path.count != 0 out.output_source_path = copy_string(ctx.metal_output_source_path);
  out.output_air_path = copy_string(ctx.metal_output_air_path);
  out.output_metallib_path = copy_string(ctx.metal_output_metallib_path);
  out.primary_name = copy_string(ctx.vertex_fn.header.name);
  out.secondary_name = copy_string(ctx.fragment_fn.header.name);
  out.tertiary_name = "";
  out.metal_vertex_entry = copy_string(ctx.metal_vertex_entry_name);
  out.metal_fragment_entry = copy_string(ctx.metal_fragment_entry_name);
  v_sig := manifest_header_signature(ctx.vertex_fn.header);
  f_sig := manifest_header_signature(ctx.fragment_fn.header);
  out.signature = tprint("kind=pair;target=%;vertex={%};fragment={%}", out.target, v_sig, f_sig);
  out.signature_hash = tprint("%", manifest_hash_u64(out.signature));

  seen_headers: [..] *Code_Procedure_Header;
  manifest_collect_header_dependencies(ctx.vertex_fn.header, workspace_root, *out.dependencies, *seen_headers);
  manifest_collect_header_dependencies(ctx.fragment_fn.header, workspace_root, *out.dependencies, *seen_headers);
  return out;
}

manifest_make_mesh_entry :: (ctx: *Shader_Write_Mesh_Context, workspace_root: string) -> Shader_Reload_Manifest_Entry {
  out: Shader_Reload_Manifest_Entry;
  if !ctx || !ctx.mesh_fn || !ctx.fragment_fn || !ctx.mesh_fn.header || !ctx.fragment_fn.header return out;

  target := manifest_target_from_language(ctx.language, ctx.glsl_target);
  task_name := ifx ctx.task_fn && ctx.task_fn.header then ctx.task_fn.header.name else "";
  mesh_name := ctx.mesh_fn.header.name;
  fragment_name := ctx.fragment_fn.header.name;

  out.request_name = copy_string(ctx.name);
  out.entry_id = tprint("mesh|%|%|%|%", target, task_name, mesh_name, fragment_name);
  out.shader_kind = "mesh";
  out.stage = ifx task_name.count != 0 then "task_mesh" else "mesh";
  out.target = target;
  out.output_source_path = manifest_output_source_path(out.request_name, out.target);
  if ctx.metal_output_source_path.count != 0 out.output_source_path = copy_string(ctx.metal_output_source_path);
  out.output_air_path = copy_string(ctx.metal_output_air_path);
  out.output_metallib_path = copy_string(ctx.metal_output_metallib_path);
  out.primary_name = copy_string(task_name);
  out.secondary_name = copy_string(mesh_name);
  out.tertiary_name = copy_string(fragment_name);
  out.metal_task_entry = copy_string(ctx.metal_task_entry_name);
  out.metal_mesh_entry = copy_string(ctx.metal_mesh_entry_name);
  out.metal_fragment_entry = copy_string(ctx.metal_fragment_entry_name);

  task_sig := ifx ctx.task_fn && ctx.task_fn.header then manifest_header_signature(ctx.task_fn.header) else "";
  mesh_sig := manifest_header_signature(ctx.mesh_fn.header);
  fragment_sig := manifest_header_signature(ctx.fragment_fn.header);
  out.signature = tprint("kind=mesh;target=%;task={%};mesh={%};fragment={%}", out.target, task_sig, mesh_sig, fragment_sig);
  out.signature_hash = tprint("%", manifest_hash_u64(out.signature));

  seen_headers: [..] *Code_Procedure_Header;
  if ctx.task_fn && ctx.task_fn.header manifest_collect_header_dependencies(ctx.task_fn.header, workspace_root, *out.dependencies, *seen_headers);
  manifest_collect_header_dependencies(ctx.mesh_fn.header, workspace_root, *out.dependencies, *seen_headers);
  manifest_collect_header_dependencies(ctx.fragment_fn.header, workspace_root, *out.dependencies, *seen_headers);
  return out;
}

emit_shader_reload_manifest :: (plugin: *Jai_To_Shader_Plugin) {
  assert(plugin != null);

  make_directory_if_it_does_not_exist(DEBUG_OUTDIR, recursive=true);
  workspace_name := copy_string(get_name(plugin.workspace),, temp);
  if workspace_name.count == 0 workspace_name = "workspace";
  for workspace_name {
    if it == {
    case #char " "; #through;
    case #char "/"; #through;
    case #char "\\"; #through;
    case #char ":";
      workspace_name[it_index] = "_";
    }
  }

  manifest_set_hash: u64 = 0;
  for plugin.manifest_entries manifest_set_hash = manifest_set_hash ^ manifest_hash_u64(it.entry_id);
  if manifest_set_hash == 0 manifest_set_hash = manifest_hash_u64(workspace_name);

  path := tprint("%/shader_reload_manifest_%_%.txt", DEBUG_OUTDIR, workspace_name, formatInt(manifest_set_hash, base=16));
  manifest_text := manifest_build_text(plugin.manifest_entries, jst_pipeline_fingerprint());
  ok := write_entire_file(path, manifest_text);
  if !ok {
    log_error("Jai Shader Transpiler: failed to write shader reload manifest to '%'.", path);
    return;
  }

  app_latest_name := shader_reload_manifest_app_latest_alias_name(plugin);
  app_latest_path := ifx app_latest_name.count != 0 then tprint("%/%", DEBUG_OUTDIR, app_latest_name) else "";
  app_latest_tmp_path := ifx app_latest_name.count != 0 then tprint("%/%_%.tmp", DEBUG_OUTDIR, app_latest_name, formatInt(manifest_set_hash, base=16)) else "";

  if app_latest_path.count != 0 {
    tmp_ok := write_entire_file(app_latest_tmp_path, manifest_text);
    if !tmp_ok {
      compiler_report(tprint("Could not write temporary app manifest file '%'", app_latest_tmp_path));
      return;
    }

    move_ok := file_move(app_latest_tmp_path, app_latest_path);
    if !move_ok {
      compiler_report(tprint("Could not atomically update app manifest '%'", app_latest_path));
      return;
    }

  }
}

#scope_file

shader_reload_manifest_app_latest_alias_name :: (plugin: *Jai_To_Shader_Plugin) -> string {
  if !plugin return "";
  app_name := copy_string(plugin.manifest_app_name,, temp);
  if app_name.count == 0 {
    workspace_name := copy_string(get_name(plugin.workspace),, temp);
    app_name = shader_reload_manifest_app_name_from_workspace(workspace_name);
  }
  if app_name.count == 0 app_name = stable_metallib_workspace_name(plugin);
  app_name = sanitize_shader_reload_manifest_alias_component(app_name);
  if app_name.count == 0 return "";
  return tprint("shader_reload_manifest_app_%_latest.txt", app_name);
}

shader_reload_manifest_app_name_from_workspace :: (workspace_name: string) -> string {
  prefixes := string.["Build shaders ", "Build app "];
  for prefixes {
    prefix := it;
    if !begins_with(workspace_name, prefix) continue;
    out: string = {
      count = workspace_name.count - prefix.count,
      data = workspace_name.data + prefix.count,
    };
    return copy_string(out,, temp);
  }
  return "";
}

sanitize_shader_reload_manifest_alias_component :: (value: string) -> string {
  out := copy_string(value,, temp);
  for out {
    if it == {
    case #char " "; #through;
    case #char "/"; #through;
    case #char "\\"; #through;
    case #char ":"; #through;
    case #char "."; #through;
    case #char "-";
      out[it_index] = #char "_";
    }
  }
  return out;
}

manifest_build_text :: (entries: [] Shader_Reload_Manifest_Entry, pipeline_fingerprint: string) -> string {
  global_dependencies: [..] string;
  for entries {
    for it.dependencies {
      array_add_if_unique(*global_dependencies, it);
    }
  }

  sb: String_Builder;
  append(*sb, "version 3\n");
  append(*sb, tprint("pipeline_fingerprint %\n", pipeline_fingerprint));
  append(*sb, tprint("entry_count %\n", entries.count));
  append(*sb, tprint("global_dependency_count %\n", global_dependencies.count));
  for global_dependencies append(*sb, tprint("global_dependency %\n", it));

  for entries {
    entry := it;
    append(*sb, "entry_begin\n");
    append(*sb, tprint("entry_id %\n", entry.entry_id));
    append(*sb, tprint("request_name %\n", entry.request_name));
    append(*sb, tprint("output_source_path %\n", entry.output_source_path));
    append(*sb, tprint("output_air_path %\n", entry.output_air_path));
    append(*sb, tprint("output_metallib_path %\n", entry.output_metallib_path));
    append(*sb, tprint("shader_kind %\n", entry.shader_kind));
    append(*sb, tprint("stage %\n", entry.stage));
    append(*sb, tprint("target %\n", entry.target));
    append(*sb, tprint("primary_name %\n", entry.primary_name));
    append(*sb, tprint("secondary_name %\n", entry.secondary_name));
    append(*sb, tprint("tertiary_name %\n", entry.tertiary_name));
    append(*sb, tprint("metal_task_entry %\n", entry.metal_task_entry));
    append(*sb, tprint("metal_mesh_entry %\n", entry.metal_mesh_entry));
    append(*sb, tprint("metal_vertex_entry %\n", entry.metal_vertex_entry));
    append(*sb, tprint("metal_fragment_entry %\n", entry.metal_fragment_entry));
    append(*sb, tprint("metal_compute_entry %\n", entry.metal_compute_entry));
    append(*sb, tprint("metal_compute_binding_mode %\n", entry.metal_compute_binding_mode));
    append(*sb, tprint("signature_hash %\n", entry.signature_hash));
    append(*sb, tprint("signature %\n", entry.signature));
    append(*sb, tprint("dependency_count %\n", entry.dependencies.count));
    for entry.dependencies append(*sb, tprint("dependency %\n", it));
    append(*sb, "entry_end\n");
  }

  return builder_to_string(*sb);
}
