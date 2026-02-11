METAL_HEADER :: "#include <metal_stdlib>\nusing namespace metal;\n\n";
METAL_UNIFORM_BUFFER_INDEX :: 0;
METAL_VERTEX_ID_PARAM_NAME :: "__jai_vertex_id";
METAL_INSTANCE_ID_PARAM_NAME :: "__jai_instance_id";

METAL_RADIANS_HELPERS :: "inline float jai_radians(float v) { return v * 0.01745329251994329577f; }\ninline float2 jai_radians(float2 v) { return v * 0.01745329251994329577f; }\ninline float3 jai_radians(float3 v) { return v * 0.01745329251994329577f; }\ninline float4 jai_radians(float4 v) { return v * 0.01745329251994329577f; }\n\n";
METAL_DEGREES_HELPERS :: "inline float jai_degrees(float v) { return v * 57.29577951308232088f; }\ninline float2 jai_degrees(float2 v) { return v * 57.29577951308232088f; }\ninline float3 jai_degrees(float3 v) { return v * 57.29577951308232088f; }\ninline float4 jai_degrees(float4 v) { return v * 57.29577951308232088f; }\n\n";

write_metal_shader_pair :: (pair_name: string, vertex_ctx: *Shader_Write_Context, fragment_ctx: *Shader_Write_Context, as_jai_string := true) -> string {
  if vertex_ctx.type != .Vertex || fragment_ctx.type != .Fragment {
    compiler_report("Metal Backend: shader_pair_to_metal requires a @vertex_shader and @fragment_shader pair", make_location(vertex_ctx.main_fn.header));
    return "";
  }

  fragment_ctx.metal_allow_fragcoord_from_position = true;

  write_metal_shader(vertex_ctx, vertex_ctx.main_fn, .Vertex);
  write_metal_shader(fragment_ctx, fragment_ctx.main_fn, .Fragment);

  sb: String_Builder;
  if as_jai_string {
    append(*sb, tprint("%_metal_string", pair_name), " :: #string END\n");
  }

  append(*sb, METAL_HEADER);
  if metal_shader_uses_function(vertex_ctx, "jai_radians(") || metal_shader_uses_function(fragment_ctx, "jai_radians(") {
    append(*sb, METAL_RADIANS_HELPERS);
  }
  if metal_shader_uses_function(vertex_ctx, "jai_degrees(") || metal_shader_uses_function(fragment_ctx, "jai_degrees(") {
    append(*sb, METAL_DEGREES_HELPERS);
  }

  append_unique_block :: (out: *String_Builder, block: string, seen: *[..] string) {
    if block.count == 0 return;
    for seen.* if it == block return;
    array_add(seen, block);
    append(out, block);
  }

  seen_blocks: [..] string;

  constants_v: String_Builder;
  print_metal_global_constants(*constants_v, vertex_ctx.main_fn.header);
  append_unique_block(*sb, builder_to_string(*constants_v), *seen_blocks);

  constants_f: String_Builder;
  print_metal_global_constants(*constants_f, fragment_ctx.main_fn.header);
  append_unique_block(*sb, builder_to_string(*constants_f), *seen_blocks);

  vertex_in: String_Builder;
  print_metal_in_struct(*vertex_in, vertex_ctx.main_fn.header);
  append_unique_block(*sb, builder_to_string(*vertex_in), *seen_blocks);

  bindless_decl_v, _, has_bindless_v := find_bindless_param(vertex_ctx.main_fn.header);
  if vertex_ctx.main_fn.header.arguments.count >= 2 {
    stage_block: String_Builder;
    if has_bindless_v print_metal_bindless_struct(*stage_block, bindless_decl_v);
    else print_metal_uniform_struct(*stage_block, vertex_ctx.main_fn.header);
    append_unique_block(*sb, builder_to_string(*stage_block), *seen_blocks);
  }

  vertex_out: String_Builder;
  print_metal_out_struct(*vertex_out, vertex_ctx.main_fn.header, .Vertex);
  append_unique_block(*sb, builder_to_string(*vertex_out), *seen_blocks);

  fragment_in_type := cast(*Type_Info_Struct) fragment_ctx.main_fn.header.arguments[0].type_inst.result;
  vertex_out_type := cast(*Type_Info_Struct) vertex_ctx.main_fn.header.returns[0].type_inst.result;
  if fragment_in_type != vertex_out_type {
    if fragment_in_type.name == vertex_out_type.name {
      compiler_report(tprint("Metal Backend: shader pair uses mismatched structs that share the same name '%'", fragment_in_type.name), make_location(fragment_ctx.main_fn.header.arguments[0]));
    }

    fragment_in: String_Builder;
    print_metal_in_struct(*fragment_in, fragment_ctx.main_fn.header);
    append_unique_block(*sb, builder_to_string(*fragment_in), *seen_blocks);
  }

  bindless_decl_f, _, has_bindless_f := find_bindless_param(fragment_ctx.main_fn.header);
  if fragment_ctx.main_fn.header.arguments.count >= 2 {
    stage_block: String_Builder;
    if has_bindless_f print_metal_bindless_struct(*stage_block, bindless_decl_f);
    else print_metal_uniform_struct(*stage_block, fragment_ctx.main_fn.header);
    append_unique_block(*sb, builder_to_string(*stage_block), *seen_blocks);
  }

  fragment_out: String_Builder;
  print_metal_out_struct(*fragment_out, fragment_ctx.main_fn.header, .Fragment);
  append_unique_block(*sb, builder_to_string(*fragment_out), *seen_blocks);

  function_decls: [..] Shader_Function;
  for vertex_ctx.functions {
    if it.name == "main" continue;
    array_add(*function_decls, it);
  }
  for fragment_ctx.functions {
    if it.name == "main" continue;
    candidate := it;

    already := false;
    for function_decls {
      existing := it;
      if existing.name != candidate.name continue;
      already = true;
      if existing.code != candidate.code {
        compiler_report(tprint("Metal Backend: helper function '%' differs between paired vertex/fragment shaders", candidate.name), make_location(fragment_ctx.main_fn.header));
      }
      break;
    }
    if !already array_add(*function_decls, candidate);
  }

  for function_decls print_metal_prototype(*sb, it.prototype);
  append(*sb, "\n");

  for function_decls append(*sb, it.code, "\n");
  for vertex_ctx.functions if it.name == "main" append(*sb, it.code, "\n");
  for fragment_ctx.functions if it.name == "main" append(*sb, it.code, "\n");

  if as_jai_string {
    append(*sb, "\nEND");
  }

  return builder_to_string(*sb);
}

write_metal_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, shader_type: Shader_Type) -> string {
  check_arguments(node.header, shader_type);

  if shader_type == .Compute {
    return write_metal_compute_shader(ctx, node);
  }
  
  main_function_name := tprint("%Main", shader_type);

  main_sb: String_Builder;
  if shader_type == {
  case .Vertex; append(*main_sb, "vertex ");
  case .Fragment; append(*main_sb, "fragment ");
  case .Compute; // nothing
  }
  append(*main_sb, get_struct_type_name(cast(*Type_Info_Struct) node.header.returns[0].type_inst.result));
  append(*main_sb, " ", main_function_name, "(");
  print_metal_stage_in_arg(*main_sb, node.header.arguments[0]);
  if shader_type == .Vertex {
    print_metal_vertex_builtin_args(*main_sb, node.header);
  }
  bindless_decl, binding, has_bindless := find_bindless_param(node.header);
  if has_bindless {
    append(*main_sb, ", ");
    print_metal_bindless_arg(*main_sb, bindless_decl, binding);
  } else if node.header.arguments.count >= 2 {
    append(*main_sb, ", ");
    print_metal_uniform_arg(*main_sb, node.header.arguments[1]);
  }
  append(*main_sb, ") {\n");
  print_metal_local_bindings(ctx, *main_sb, node.header, indent=1);
  print_metal_stmt(ctx, *main_sb, node.block, is_main=true);
  print_metal_output_return(ctx, *main_sb, node.header, indent=1);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  return write_metal_shader_code(ctx, node);
}

write_metal_compute_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  main_sb: String_Builder;
  append(*main_sb, "kernel void ComputeMain(");
  print_metal_compute_main_args(*main_sb, node.header);
  append(*main_sb, ") {\n");
  print_metal_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  return write_metal_shader_code(ctx, node);
}

write_metal_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  sb: String_Builder;
  use_jai_radians := metal_shader_uses_function(ctx, "jai_radians(");
  use_jai_degrees := metal_shader_uses_function(ctx, "jai_degrees(");
  if as_jai_string {
    append(*sb, tprint("%_metal_string", node.header.name), " :: #string END\n");
  }
  append(*sb, METAL_HEADER);
  if use_jai_radians append(*sb, METAL_RADIANS_HELPERS);
  if use_jai_degrees append(*sb, METAL_DEGREES_HELPERS);
  print_metal_global_constants(*sb, node.header);
  if ctx.type != .Compute {
    print_metal_in_struct(*sb, node.header);
    bindless_decl, _, has_bindless := find_bindless_param(node.header);
    if node.header.arguments.count >= 2 {
      if has_bindless print_metal_bindless_struct(*sb, bindless_decl);
      else print_metal_uniform_struct(*sb, node.header);
    }
    print_metal_out_struct(*sb, node.header, ctx.type);
  }
  for ctx.functions {
    if it.name != "main" print_metal_prototype(*sb, it.prototype);
  }
  append(*sb, "\n");
  for ctx.functions {
    append(*sb, it.code, "\n");
  }
  if as_jai_string {
    append(*sb, "\nEND");
  }

  return builder_to_string(*sb);
}

metal_shader_uses_function :: (ctx: *Shader_Write_Context, needle: string) -> bool {
  for ctx.functions {
    found, _ := contains(it.code, needle);
    if found return true;
  }
  return false;
}

print_metal_in_struct :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("Metal Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", get_struct_type_name(struct_type)));
  attribute_i := 0;
  for * struct_type.members {
    if it.flags & .OVERLAY {
      compiler_report(tprint("Metal Backend: #overlay is not supported in shader-transpiled structs (struct '%', member '%').",
                             get_struct_type_name(struct_type), it.name));
      return;
    }

    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;
    if !node_is_fragment_shader(node) && member_has_note_contains(it, "vertex_id") continue;
    if !node_is_fragment_shader(node) && member_has_note_contains(it, "instance_id") continue;
    if type_contains_array(it.type)
      compiler_report("Metal Backend: Array members are not supported in stage input/output structs. Use non-array varyings for now.", make_location(node.arguments[0]));

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);

    if member_is_stage_builtin(it) {
      if member_has_note_contains(it, "frag_coord") append(sb, " [[position]]");
      else if member_has_note_contains(it, "position") append(sb, " [[position]]");
      else if member_has_note_contains(it, "vertex_id") append(sb, " [[vertex_id]]");
      else if member_has_note_contains(it, "instance_id") append(sb, " [[instance_id]]");
      else if member_has_note_contains(it, "front_facing") append(sb, " [[front_facing]]");
    } else {
      if node_is_fragment_shader(node) append(sb, tprint(" [[user(%)]]", it.name));
      else append(sb, tprint(" [[attribute(%)]]", attribute_i));
      if !node_is_fragment_shader(node) attribute_i += 1;
    }
    append(sb, ";\n");
  }
  append(sb, "};\n\n");
}

print_metal_vertex_builtin_args :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT return;
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  emit_vertex_id := false;
  emit_instance_id := false;
  for * struct_type.members {
    if member_has_note_contains(it, "vertex_id") emit_vertex_id = true;
    if member_has_note_contains(it, "instance_id") emit_instance_id = true;
  }

  if emit_vertex_id append(sb, tprint(", uint % [[vertex_id]]", METAL_VERTEX_ID_PARAM_NAME));
  if emit_instance_id append(sb, tprint(", uint % [[instance_id]]", METAL_INSTANCE_ID_PARAM_NAME));
}

metal_struct_already_emitted :: (emitted: *[..] *Type_Info_Struct, struct_type: *Type_Info_Struct) -> bool {
  for emitted.* if it == struct_type return true;
  return false;
}

emit_metal_struct_definitions_for_type :: (sb: *String_Builder, type: *Type_Info, emitted: *[..] *Type_Info_Struct) {
  if !type return;

  if type.type == {
    case .STRUCT; {
      struct_type := cast(*Type_Info_Struct) type;
      if metal_struct_already_emitted(emitted, struct_type) return;

      // Types that map directly to Metal builtins (Vector/Matrix/etc.) must not be emitted as structs.
      struct_name := get_struct_type_name(struct_type);
      if jai_to_metal_type_name(struct_name) != struct_name return;

      array_add(emitted, struct_type);

      for * struct_type.members {
        if it.flags & .OVERLAY {
          compiler_report(tprint("Metal Backend: #overlay is not supported in shader-transpiled structs (struct '%', member '%').",
                                 struct_name, it.name));
          return;
        }
        emit_metal_struct_definitions_for_type(sb, it.type, emitted);
      }

      append(sb, tprint("struct % {\n", struct_name));
      for * struct_type.members {
        append(sb, "    ");
        print_metal_member_with_typename(sb, it);
        append(sb, ";\n");
      }
      append(sb, "};\n\n");
    }
    case .POINTER; {
      pointer := cast(*Type_Info_Pointer) type;
      emit_metal_struct_definitions_for_type(sb, pointer.pointer_to, emitted);
    }
    case .ARRAY; {
      array_type := cast(*Type_Info_Array) type;
      emit_metal_struct_definitions_for_type(sb, array_type.element_type, emitted);
    }
  }
}

print_metal_uniform_struct :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Metal Backend: Shader uniforms are not a struct", make_location(node.arguments[1]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  emitted: [..] *Type_Info_Struct;
  emit_metal_struct_definitions_for_type(sb, struct_type, *emitted);
}

print_metal_out_struct :: (sb: *String_Builder, node: *Code_Procedure_Header, shader_type: Shader_Type) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Metal Backend: Shader Output is not a struct", make_location(node.returns[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", get_struct_type_name(struct_type)));
  color_i := 0;
  for * struct_type.members {
    if it.flags & .OVERLAY {
      compiler_report(tprint("Metal Backend: #overlay is not supported in shader-transpiled structs (struct '%', member '%').",
                             get_struct_type_name(struct_type), it.name));
      return;
    }

    if type_contains_array(it.type)
      compiler_report("Metal Backend: Array members are not supported in stage input/output structs. Use non-array varyings for now.", make_location(node.returns[0]));

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);
    if member_is_stage_builtin(it) {
      if member_has_note_contains(it, "position") append(sb, " [[position]]");
      else if member_has_note_contains(it, "frag_depth") append(sb, " [[depth(any)]]");
      else if shader_type == .Vertex && member_has_note_contains(it, "frag_coord") append(sb, tprint(" [[user(%)]]", it.name));
    } else if shader_type == .Fragment {
      append(sb, tprint(" [[color(%)]]", color_i));
      color_i += 1;
    } else if shader_type == .Vertex {
      append(sb, tprint(" [[user(%)]]", it.name));
    }
    append(sb, ";\n");
  }
  append(sb, "};\n\n");
}

print_metal_stage_in_arg :: (sb: *String_Builder, arg: *Code_Declaration) {
  print_metal_type(sb, arg.type_inst.result);
  append(sb, " ", arg.name, " [[stage_in]]");
}

print_metal_uniform_arg :: (sb: *String_Builder, arg: *Code_Declaration) {
  append(sb, "constant ");
  print_metal_type(sb, arg.type_inst.result);
  append(sb, tprint("& % [[buffer(%)]]", arg.name, METAL_UNIFORM_BUFFER_INDEX));
}


print_metal_bindless_struct :: (sb: *String_Builder, decl: *Code_Declaration) {
  struct_type_generic := decl.type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Metal Backend: Bindless param is not a struct", make_location(decl));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  emitted: [..] *Type_Info_Struct;
  emit_metal_struct_definitions_for_type(sb, struct_type, *emitted);
}

print_metal_bindless_arg :: (sb: *String_Builder, arg: *Code_Declaration, binding: s64) {
  append(sb, "constant ");
  print_metal_type(sb, arg.type_inst.result);
  append(sb, tprint("* %_ptr [[buffer(%)]]", arg.name, binding));
}


print_metal_compute_main_args :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  first := true;
  next_arg :: () #expand {
    if first first = false;
    else append(sb, ", ");
  }

  next_buffer_index: s64 = 0;
  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if declaration_is_parameter_using(header, it) && arg_type.type == .STRUCT {
      struct_type := cast(*Type_Info_Struct) arg_type;
      for * struct_type.members {
        builtin_name, found := member_get_compute_builtin_note(it);
        if !found
          compiler_report("Metal Backend: Compute using-struct members must have a supported @thread_* note", make_location(header));

        next_arg();
        print_metal_type(sb, it.type);
        append(sb, tprint(" % [[%]]", it.name, builtin_name));
      }
      continue;
    }

    if arg_type.type != .POINTER
      compiler_report("Metal Backend: Compute non-using arguments must currently be pointers (bound as buffers)", make_location(it));

    pointer := cast(*Type_Info_Pointer) arg_type;
    next_arg();
    append(sb, "device ");
    print_metal_type(sb, pointer.pointer_to);
    append(sb, tprint("* % [[buffer(%)]]", it.name, next_buffer_index));
    next_buffer_index += 1;
  }
}

print_metal_local_bindings :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Procedure_Header, indent: s64) {
  in_struct_type := cast(*Type_Info_Struct) node.arguments[0].type_inst.result;
  has_in_gl_position := false;
  in_gl_position_type: *Type_Info = null;
  has_in_gl_fragcoord := false;
  for * in_struct_type.members {
    if it.name == "gl_Position" {
      has_in_gl_position = true;
      in_gl_position_type = it.type;
    }
    if it.name == "gl_FragCoord" {
      has_in_gl_fragcoord = true;
    }

    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;

    if !node_is_fragment_shader(node) && member_has_note_contains(it, "vertex_id") {
      print_metal_local_binding(sb, it.type, it.name, METAL_VERTEX_ID_PARAM_NAME, indent);
      continue;
    }
    if !node_is_fragment_shader(node) && member_has_note_contains(it, "instance_id") {
      print_metal_local_binding(sb, it.type, it.name, METAL_INSTANCE_ID_PARAM_NAME, indent);
      continue;
    }

    print_metal_local_binding(sb, it.type, it.name, tprint("%.%", node.arguments[0].name, it.name), indent);
  }

  if node_is_fragment_shader(node) && ctx.metal_allow_fragcoord_from_position && has_in_gl_position && !has_in_gl_fragcoord {
    // Fragment shaders often read gl_FragCoord even when the shared varyings struct only carries gl_Position.
    // Synthesize gl_FragCoord from the stage-in position so paired vertex/fragment outputs can share one struct.
    print_metal_local_binding(sb, in_gl_position_type, "gl_FragCoord", tprint("%.%", node.arguments[0].name, "gl_Position"), indent);
  }

  if node.arguments.count >= 2 {
    bindless_decl, _, has_bindless := find_bindless_param(node);
    if has_bindless {
      add_indents(sb, indent);
      print_metal_type(sb, bindless_decl.type_inst.result);
      append(sb, " ", bindless_decl.name, " = *", bindless_decl.name, "_ptr;\n");
    } else {
      un_struct_type := cast(*Type_Info_Struct) node.arguments[1].type_inst.result;
      for * un_struct_type.members {
        print_metal_local_binding(sb, it.type, it.name, tprint("%.%", node.arguments[1].name, it.name), indent);
      }
    }
  }

  out_struct_type := cast(*Type_Info_Struct) node.returns[0].type_inst.result;
  for * out_struct_type.members {
    if ctx.type == .Vertex && it.name == "gl_FragCoord" continue;

    add_indents(sb, indent);
    print_metal_typed_name(sb, it.type, it.name);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_metal_local_binding :: (sb: *String_Builder, type: *Type_Info, local_name: string, source_expr: string, indent: s64) {
  add_indents(sb, indent);
  print_metal_typed_name(sb, type, local_name);
  if type.type == .ARRAY {
    append(sb, ";\n");
    print_metal_array_copy(sb, type, local_name, source_expr, indent);
  } else {
    append(sb, " = ", source_expr, ";\n");
  }
}

print_metal_array_copy :: (sb: *String_Builder, type: *Type_Info, dst_expr: string, src_expr: string, indent: s64) {
  if type.type != .ARRAY {
    add_indents(sb, indent);
    append(sb, dst_expr, " = ", src_expr, ";\n");
    return;
  }

  array_type := cast(*Type_Info_Array) type;
  if array_type.array_type != .FIXED
    compiler_report("Metal Backend: Only fixed-size arrays are currently supported in Jai Shaders");

  for i: 0..array_type.array_count-1 {
    dst_member := tprint("%[%]", dst_expr, i);
    src_member := tprint("%[%]", src_expr, i);
    print_metal_array_copy(sb, array_type.element_type, dst_member, src_member, indent);
  }
}

print_metal_output_return :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Procedure_Header, indent: s64) {
  out_type := cast(*Type_Info_Struct) node.returns[0].type_inst.result;
  add_indents(sb, indent);
  append(sb, out_type.name, " out;\n");
  for * out_type.members {
    if ctx.type == .Vertex && it.name == "gl_FragCoord" {
      add_indents(sb, indent);
      append(sb, "out.gl_FragCoord = gl_Position;\n");
      continue;
    }

    add_indents(sb, indent);
    append(sb, "out.", it.name, " = ", it.name, ";\n");
  }
  add_indents(sb, indent);
  append(sb, "return out;\n");
}

print_metal_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: *Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    report_array_return_not_supported("Metal", ret);
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    report_array_parameter_not_supported("Metal", it);
    if it.type_inst
      print_metal_type(sb, it.type_inst.result);
    else
      print_metal_type(sb, it.expression.type);

    append(sb, " ", it.name);

    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_metal_stmt(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

print_metal_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    report_array_return_not_supported("Metal", ret);
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", header.name));
  for header.arguments {
    report_array_parameter_not_supported("Metal", it);
    if it.type_inst
      print_metal_type(sb, it.type_inst.result);
    else
      print_metal_type(sb, it.expression.type);
    append(sb, " ", it.name);
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}

print_metal_stmt :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        op := cast(*Code_Declaration) it;

        if op.type_inst
          print_metal_typed_name(sb, op.type_inst.result, op.name);
        else
          print_metal_typed_name(sb, op.expression.type, op.name);

        if op.expression {
          append(sb, " = ");
          print_metal_expr(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }

      case .BINARY_OPERATOR; {
        op := cast(*Code_Binary_Operator) it;
        add_indents(sb, indent);
        print_metal_binary_operator(ctx, sb, op);
        append(sb, ";\n");
      }

      case .IF; {
        op := cast(*Code_If) it;
        add_indents(sb, indent);

        if op.if_flags & .IS_SWITCH_STATEMENT {
          if op.condition.type.type == .INTEGER {
            append(sb, "switch (");
            print_metal_expr(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          } else {
            curr := 0;
            default_case: *Code_Case;
            while curr < op.then_block.statements.count {
              curr_case := cast(*Code_Case) op.then_block.statements[curr];

              if curr_case.condition == null {
                default_case = curr_case;
                curr += 1;
                continue;
              }
              append(sb, "if (");
              print_metal_expr(ctx, sb, op.condition);
              append(sb, " == ");
              print_metal_expr(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_metal_stmt(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);

              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else
                append(sb, "} else ");

              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_metal_stmt(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_metal_expr(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_metal_stmt(ctx, sb, op.else_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          }
        }
      }

      case .CASE; {
        add_indents(sb, indent);
        op := cast(*Code_Case) it;

        if op.condition {
          append(sb, "case ");
          print_metal_expr(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }

      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_metal_expr(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_metal_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }

      case .FOR; {
        add_indents(sb, indent);
        op := cast(*Code_For) it;
        if op.macro_expansion_procedure_call || !op.iteration_expression_right
          compiler_report("Can't use special iterators in Jai Shaders", make_location(op));
        if op.for_flags & .POINTER
          compiler_report("Iteration by Pointers is disallowed in Jai Shaders", make_location(op));

        append(sb, "for (int ", op.ident_decl.name, " = ");
        print_metal_expr(ctx, sb, op.iteration_expression);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_metal_expr(ctx, sb, op.iteration_expression_right);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_metal_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }

      case .RETURN; {
        add_indents(sb, indent);
        op := cast(*Code_Return) it;
        if is_main {
          if op.arguments_sorted.count == 0 continue;
          if op.arguments_sorted.count != 1 {
            compiler_report("Multiple Return Arguments Disallowed in Jai Shaders", make_location(op));
            continue;
          }

          ret_expr := op.arguments_sorted[0];
          if ret_expr.kind == .LITERAL {
            lit := cast(*Code_Literal) ret_expr;
            if lit.value_type == .STRUCT {
              out_type := cast(*Type_Info_Struct) ctx.main_fn.header.returns[0].type_inst.result;
              named_initializers := false;
              for lit.struct_literal_info.arguments {
                if it.kind != .BINARY_OPERATOR continue;
                bn := cast(*Code_Binary_Operator) it;
                if bn.left && bn.left.kind == .IDENT && operator_string(bn.operator_type) == "=" {
                  named_initializers = true;
                  break;
                }
              }

              if named_initializers {
                for *out_type.members {
                  member := it;
                  value_expr: *Code_Node = null;
                  for lit.struct_literal_info.arguments {
                    arg_node := it;
                    if arg_node.kind != .BINARY_OPERATOR continue;
                    bn := cast(*Code_Binary_Operator) arg_node;
                    if !bn.left || bn.left.kind != .IDENT continue;
                    if operator_string(bn.operator_type) != "=" continue;
                    lhs := cast(*Code_Ident) bn.left;
                    if lhs.name != member.name continue;
                    value_expr = bn.right;
                    break;
                  }
                  if !value_expr {
                    compiler_report(tprint("Metal Backend: Missing member '%' in struct literal return for shader '%'.",
                                           member.name, ctx.main_fn.header.name), make_location(op));
                    continue;
                  }

                  add_indents(sb, indent);
                  append(sb, member.name, " = ");
                  print_metal_array_member_expr(ctx, sb, value_expr, member.type);
                  append(sb, ";\n");
                }
                continue;
              }

              if lit.struct_literal_info.arguments.count != out_type.members.count {
                compiler_report(tprint("Metal Backend: Struct literal return member count mismatch in shader '%' (got %, expected %).",
                                       ctx.main_fn.header.name,
                                       lit.struct_literal_info.arguments.count,
                                       out_type.members.count), make_location(op));
                continue;
              }

              for i: 0..out_type.members.count-1 {
                member := out_type.members[i];
                add_indents(sb, indent);
                append(sb, member.name, " = ");
                print_metal_array_member_expr(ctx, sb, lit.struct_literal_info.arguments[i], member.type);
                append(sb, ";\n");
              }
              continue;
            }
          }

          continue;
        }

        append(sb, "return ");
        if op.arguments_sorted.count == 0 {
          append(sb, ";\n");
        } else if op.arguments_sorted.count == 1 {
          print_metal_expr(ctx, sb, op.arguments_sorted[0]);
          append(sb, ";\n");
        } else
          compiler_report("Multiple Return Arguments Disallowed in Jai Shaders", make_location(op));
      }

      case .PROCEDURE_CALL; {
        add_indents(sb, indent);

        pc := cast(*Code_Procedure_Call) it;
        if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
          compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
        name := cast(*Code_Ident) pc.procedure_expression;
        if !table_contains(*METAL_INBUILT_FUNCTIONS, name.name)
          handle_custom_procedure_call(ctx, sb, pc);
        print_metal_procedure_call(ctx, sb, pc);

        append(sb, ";\n");
      }

      case .USING; continue;

      case; {
        compiler_report(tprint("The statement of type '%' is not supported in Jai Shaders", it.kind), make_location(it));
      }
    }
  }
}

print_metal_expr :: (using ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  if node.kind == {
    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        print_metal_struct_literal(ctx, sb, lit);
      } else if lit.value_type == .ARRAY {
        print_metal_array_literal(ctx, sb, lit);
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_metal_expr(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_metal_binary_operator(ctx, sb, bn);
    }

    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
        compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));

      name := cast(*Code_Ident) pc.procedure_expression;
      if !table_contains(*METAL_INBUILT_FUNCTIONS, name.name)
        handle_custom_procedure_call(ctx, sb, pc);
      print_metal_procedure_call(ctx, sb, pc);
    }

    case; print_metal_fallback_expr(ctx, sb, node);
  }
}

metal_pointer_member_names_contains :: (names: *[..] string, name: string) -> bool {
  for names.* if it == name return true;
  return false;
}

collect_metal_pointer_member_names :: (type: *Type_Info, names: *[..] string) {
  if !type return;

  if type.type == .POINTER {
    pointer := cast(*Type_Info_Pointer) type;
    collect_metal_pointer_member_names(pointer.pointer_to, names);
    return;
  }

  if type.type != .STRUCT return;

  struct_type := cast(*Type_Info_Struct) type;
  for *struct_type.members {
    if it.type && it.type.type == .POINTER {
      if !metal_pointer_member_names_contains(names, it.name) {
        array_add(names, it.name);
      }
      pointer := cast(*Type_Info_Pointer) it.type;
      collect_metal_pointer_member_names(pointer.pointer_to, names);
    } else {
      collect_metal_pointer_member_names(it.type, names);
    }
  }
}

collect_metal_header_pointer_member_names :: (header: *Code_Procedure_Header) -> [..] string {
  names: [..] string;
  if !header return names;

  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
    collect_metal_pointer_member_names(arg_type, *names);
  }
  for header.returns {
    ret_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
    collect_metal_pointer_member_names(ret_type, *names);
  }
  return names;
}

rewrite_metal_pointer_member_accesses :: (expr: string, pointer_member_names: [] string) -> string {
  rewritten := copy_string(expr);
  for pointer_member_names {
    rewritten = replace(rewritten, tprint(".%.", it), tprint(".%->", it));
  }
  return rewritten;
}

print_metal_fallback_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  raw: String_Builder;
  PP.print_expression(*raw, node);
  expr := builder_to_string(*raw);

  pointer_member_names := collect_metal_header_pointer_member_names(ifx ctx && ctx.main_fn then ctx.main_fn.header else null);
  expr = rewrite_metal_pointer_member_accesses(expr, pointer_member_names);
  append(sb, expr);
}

print_metal_binary_operator :: (ctx: *Shader_Write_Context, sb: *String_Builder, bn: *Code_Binary_Operator) {
  op_str := operator_string(bn.operator_type);

  if bn.operator_type == .ARRAY_SUBSCRIPT {
    print_metal_expr(ctx, sb, bn.left);
    append(sb, "[");
    print_metal_subscript_index_expr(ctx, sb, bn.right);
    append(sb, "]");
    return;
  }

  if op_str == "." {
    needs_arrow := metal_member_access_needs_arrow(ctx, bn.left);
    if !needs_arrow {
      left_text := expression_to_source_string(bn.left);
      pointer_member_names := collect_metal_header_pointer_member_names(ifx ctx && ctx.main_fn then ctx.main_fn.header else null);
      for pointer_member_names {
        if ends_with(left_text, tprint(".%", it)) {
          needs_arrow = true;
          break;
        }
      }
    }

    print_metal_expr(ctx, sb, bn.left);
    if needs_arrow append(sb, "->");
    else append(sb, ".");
    print_metal_expr(ctx, sb, bn.right);
    return;
  }

  print_metal_expr(ctx, sb, bn.left);
  space := " ";
  append(sb, space, op_str, space);
  print_metal_expr(ctx, sb, bn.right);
}

metal_type_from_main_identifier :: (ctx: *Shader_Write_Context, ident_name: string) -> *Type_Info {
  if !ctx || !ctx.main_fn return null;
  header := ctx.main_fn.header;
  for header.arguments {
    if it.name != ident_name continue;
    if it.type_inst return it.type_inst.result;
    if it.expression return it.expression.type;
    return null;
  }
  for header.returns {
    if it.name != ident_name continue;
    if it.type_inst return it.type_inst.result;
    if it.expression return it.expression.type;
    return null;
  }
  return null;
}

metal_member_access_needs_arrow :: (ctx: *Shader_Write_Context, left: *Code_Node) -> bool {
  if !left return false;
  if left.type && left.type.type == .POINTER return true;

  // Covers expressions like params.fragment_data.color where the immediate left expression
  // may have been auto-dereferenced by Jai, but the member being chained is still a pointer field.
  if left.kind == .BINARY_OPERATOR {
    left_bn := cast(*Code_Binary_Operator) left;
    if operator_string(left_bn.operator_type) == "." && left_bn.right && left_bn.right.kind == .IDENT {
      if left_bn.right.type && left_bn.right.type.type == .POINTER return true;
      member_ident := cast(*Code_Ident) left_bn.right;
      if member_ident.resolved_declaration {
        member_decl := member_ident.resolved_declaration;
        member_type: *Type_Info = null;
        if member_decl.type_inst member_type = member_decl.type_inst.result;
        else if member_decl.expression member_type = member_decl.expression.type;
        if member_type && member_type.type == .POINTER return true;
      }

      base_type := left_bn.left.type;
      if !base_type && left_bn.left.kind == .IDENT {
        left_ident := cast(*Code_Ident) left_bn.left;
        if left_ident.resolved_declaration {
          decl := left_ident.resolved_declaration;
          if decl.type_inst base_type = decl.type_inst.result;
          else if decl.expression base_type = decl.expression.type;
        }
        if !base_type {
          base_type = metal_type_from_main_identifier(ctx, left_ident.name);
        }
      }
      if base_type && base_type.type == .POINTER {
        pointer := cast(*Type_Info_Pointer) base_type;
        base_type = pointer.pointer_to;
      }
      if base_type && base_type.type == .STRUCT {
        struct_type := cast(*Type_Info_Struct) base_type;
        member_name := cast(*Code_Ident) left_bn.right;
        for *struct_type.members {
          if it.name != member_name.name continue;
          if it.type && it.type.type == .POINTER return true;
          return false;
        }
      }
    }
  }

  return false;
}

print_metal_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  if pc.procedure_expression.kind == .IDENT {
    name := cast(*Code_Ident) pc.procedure_expression;
    update_metal_helper_usage(ctx, name.name);
    append(sb, map_metal_procedure_name(name.name));
  } else {
    PP.print_expression(sb, pc.procedure_expression);
  }
  append(sb, "(");
  for pc.arguments_sorted {
    print_metal_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}

map_metal_procedure_name :: (name: string) -> string {
  if name == "mod" return "fmod";
  if name == "radians" return "jai_radians";
  if name == "degrees" return "jai_degrees";
  return name;
}

update_metal_helper_usage :: (ctx: *Shader_Write_Context, name: string) {
  if name == "radians" ctx.metal_use_jai_radians = true;
  if name == "degrees" ctx.metal_use_jai_degrees = true;
}

print_metal_member_with_typename :: (sb: *String_Builder, thing: *Type_Info_Struct_Member) {
  print_metal_struct_member_typed_name(sb, thing.type, thing.name);
}

print_metal_struct_member_typed_name :: (sb: *String_Builder, type: *Type_Info, name: string) {
  base_type, array_suffix := split_array_type_and_suffix("Metal", type);

  if base_type.type == .STRUCT {
    structtype := cast(*Type_Info_Struct) base_type;
    struct_name := get_struct_type_name(structtype);
    if struct_name == "Vector3" {
      append(sb, "packed_float3 ", name, array_suffix);
      return;
    }
  }

  print_metal_type(sb, base_type);
  append(sb, " ", name, array_suffix);
}

print_metal_type :: (sb: *String_Builder, type: *Type_Info) {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      append(sb, ifx inttype.signed then "int" else "uint");
    }
    case .FLOAT; append(sb, ifx type.runtime_size == 64 then "double" else "float");
    case .BOOL; append(sb, "bool");
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      append(sb, jai_to_metal_type_name(get_struct_type_name(structtype)));
    }
    case .POINTER; {
      pointer := cast(*Type_Info_Pointer) type;
      inner: String_Builder;
      print_metal_type(*inner, pointer.pointer_to);
      append(sb, builder_to_string(*inner), " device*");
    }
    case .VOID; append(sb, "void");

    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

print_metal_typed_name :: (sb: *String_Builder, type: *Type_Info, name: string) {
  base_type, array_suffix := split_array_type_and_suffix("Metal", type);
  print_metal_type(sb, base_type);
  append(sb, " ", name, array_suffix);
}

print_metal_array_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal) {
  info := lit.array_literal_info;
  append(sb, "{");
  for info.array_members {
    if it_index != 0 append(sb, ", ");
    print_metal_array_member_expr(ctx, sb, it, info.element_type.result);
  }
  append(sb, "}");
}

print_metal_array_member_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node, expected_type: *Type_Info) {
  if node.kind == .LITERAL {
    lit := cast(*Code_Literal) node;
    if lit.value_type == .STRUCT {
      print_metal_struct_literal(ctx, sb, lit, expected_type);
      return;
    }
  }
  print_metal_expr(ctx, sb, node);
}

print_metal_struct_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal, expected_type: *Type_Info = null) {
  constructor_name: string;
  if lit.struct_literal_info.type_expression {
    name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
    constructor_name = jai_to_metal_type_name(name.name);
  } else if expected_type && expected_type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) expected_type;
    constructor_name = jai_to_metal_type_name(get_struct_type_name(struct_type));
  } else if lit.type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) lit.type;
    constructor_name = jai_to_metal_type_name(get_struct_type_name(struct_type));
  } else {
    compiler_report("Unfortunately, we can't easily know enough about types without the explicit name here.", make_location(lit));
    return;
  }

  append(sb, constructor_name);
  matrix_dim, matrix_scalar_type := metal_matrix_info_from_constructor_name(constructor_name);
  if matrix_dim != 0 {
    print_metal_matrix_literal_args(ctx, sb, lit, matrix_dim, matrix_scalar_type);
    return;
  }

  append(sb, "(");
  for lit.struct_literal_info.arguments {
    if it_index != 0 append(sb, ", ");
    print_metal_expr(ctx, sb, it);
  }
  append(sb, ")");
}

metal_matrix_info_from_constructor_name :: (name: string) -> (dim: s64, scalar_type: string) {
  if ends_with(name, "2x2") {
    return 2, slice(name, 0, name.count-3);
  }
  if ends_with(name, "3x3") {
    return 3, slice(name, 0, name.count-3);
  }
  if ends_with(name, "4x4") {
    return 4, slice(name, 0, name.count-3);
  }

  return 0, "";
}

print_metal_matrix_literal_args :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal, dim: s64, scalar_type: string) {
  needed := dim * dim;
  if lit.struct_literal_info.arguments.count != needed {
    compiler_report(
      tprint("Metal Backend: Matrix literal '%' requires exactly % scalar arguments (got %)",
             scalar_type, needed, lit.struct_literal_info.arguments.count),
      make_location(lit));
    return;
  }

  append(sb, "(");
  for col: 0..dim-1 {
    if col != 0 append(sb, ", ");
    append(sb, tprint("%%(", scalar_type, dim));
    for row: 0..dim-1 {
      if row != 0 append(sb, ", ");
      arg_index := col * dim + row;
      print_metal_expr(ctx, sb, lit.struct_literal_info.arguments[arg_index]);
    }
    append(sb, ")");
  }
  append(sb, ")");
}

print_metal_subscript_index_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  inner: String_Builder;
  print_metal_expr(ctx, *inner, node);
  expr := strip_redundant_outer_parens(builder_to_string(*inner));
  append(sb, expr);
}

#scope_file

print_metal_global_constants :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if !header.constants_block return;
  for header.constants_block.statements {
    if it.kind != .DECLARATION continue;
    decl := cast(*Code_Declaration) it;
    if !(decl.flags & .IS_GLOBAL) continue;
    if !(decl.flags & .IS_CONSTANT)
      compiler_report("Metal Backend: Only global constant declarations are currently supported in Jai Shaders", make_location(decl));

    append(sb, "constant ");
    if decl.type_inst
      print_metal_typed_name(sb, decl.type_inst.result, decl.name);
    else
      print_metal_typed_name(sb, decl.expression.type, decl.name);

    if decl.expression {
      append(sb, " = ");
      print_metal_expr(xx null, sb, decl.expression);
    }
    append(sb, ";\n");
  }
  if header.constants_block.statements.count != 0 append(sb, "\n");
}

check_arguments :: (using header: *Code_Procedure_Header, shader_type: Shader_Type) {
  err :: (msg: string) #expand {
    compiler_report(tprint("Metal Backend: Jai % Shader %", shader_type, msg), make_location(header));
  }

  if shader_type == .Compute {
    if returns.count != 0 err("must not return a value (use buffer arguments instead)");
    if arguments.count == 0 err("must get AT LEAST 1 structure as an argument");
    if arguments.count != 0 {
      first_arg_type := ifx arguments[0].type_inst then arguments[0].type_inst.result else arguments[0].expression.type;
      if first_arg_type.type != .STRUCT err("must have a structure as the first input argument");
      if !declaration_is_parameter_using(header, arguments[0]) err("must mark the first struct input argument as 'using'");
    }
  } else {
    if returns.count != 1 err("must return a structure");
    bindless_decl, _, has_bindless := find_bindless_param(header);
    if has_bindless {
      if arguments.count != 2 {
        if shader_type == .Fragment err("must get input struct and bindless params");
        else err("must get input struct and bindless params");
      }
      if parameter_usings.count != 1 err("must have exactly one using struct argument when using bindless params");

      in_arg := arguments[0];
      if !declaration_is_parameter_using(header, in_arg) err("first argument must be a using input struct");
      in_type := ifx in_arg.type_inst then in_arg.type_inst.result else in_arg.expression.type;
      if in_type.type != .STRUCT err("first argument must be a struct");

      bindless_type := ifx bindless_decl.type_inst then bindless_decl.type_inst.result else bindless_decl.expression.type;
      if bindless_type.type != .STRUCT err("bindless param must be a struct");
      if declaration_is_parameter_using(header, bindless_decl) err("bindless param must not be marked using");
    } else {
      if arguments.count != 2 {
        if shader_type == .Fragment err("must get two structures as arguments (Vertex output and Uniforms)");
        else err("must get two structures as arguments (Vertex Input and Uniforms)");
      }
      if parameter_usings.count != 2 err("must have struct arguments marked 'using'");
    }
  }

  check_array_signature_support("Metal", header);
}


jai_to_metal_type_map :: #run -> Table(string, string) {
  ret: Table(string, string);
  table_add(*ret, "s32", "int");
  table_add(*ret, "u32", "uint");
  table_add(*ret, "float32", "float");
  table_add(*ret, "float64", "double");
  table_add(*ret, "Vector2", "float2");
  table_add(*ret, "Vector3", "float3");
  table_add(*ret, "Vector4", "float4");
  table_add(*ret, "IVector2", "int2");
  table_add(*ret, "IVector3", "int3");
  table_add(*ret, "IVector4", "int4");
  table_add(*ret, "UVector2", "uint2");
  table_add(*ret, "UVector3", "uint3");
  table_add(*ret, "UVector4", "uint4");
  table_add(*ret, "BVector2", "bool2");
  table_add(*ret, "BVector3", "bool3");
  table_add(*ret, "BVector4", "bool4");
  table_add(*ret, "Matrix2", "float2x2");
  table_add(*ret, "Matrix3", "float3x3");
  table_add(*ret, "Matrix4", "float4x4");
  return ret;
}
jai_to_metal_type_name :: (in: string) -> string {
  success, val := table_find(*jai_to_metal_type_map, in);
  return ifx success then val else in;
}

METAL_INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  "sin", "cos", "tan", "asin", "acos", "atan",
  "degrees", "radians",

  "abs", "ceil", "exp", "exp2", "floor", "isinf", "isnan", "log", "log2", "max", "min",
  "mix", "mod", "pow", "round", "roundEven", "sign", "smoothstep", "sqrt", "step", "trunc",

  "cross", "distance", "dot", "equal", "faceforward", "length", "normalize", "notEqual",
  "all", "any", "greaterThan", "lessThan", "greaterThanEqual", "lessThanEqual", "not",

  "texture",

  "reflect", "refract", "fract",
];
METAL_INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for METAL_INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
