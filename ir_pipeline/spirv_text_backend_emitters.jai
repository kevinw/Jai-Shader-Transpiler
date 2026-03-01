SAMPLE_2D_TEXTURES_BINDING :: 1;
SAMPLE_2D_SAMPLERS_BINDING :: 0;
WRITE_2D_TEXTURES_BINDING :: 1;

spv_append_sample_2d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_sample_2d return;
  append(sb, tprint("% = OpTypeImage % 2D 0 0 0 1 Unknown\n", id_text(s.id_image2d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeSampler\n", id_text(s.id_sampler)));
  append(sb, tprint("% = OpTypeSampledImage %\n", id_text(s.id_sampled_image2d), id_text(s.id_image2d)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_image2d_array), id_text(s.id_image2d), id_text(s.id_sample_2d_array_len_const)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_sampler_array), id_text(s.id_sampler), id_text(s.id_sample_2d_array_len_const)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_image2d_array), id_text(s.id_image2d_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_sampler_array), id_text(s.id_sampler_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_image2d), id_text(s.id_image2d)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_sampler), id_text(s.id_sampler)));
}

spv_append_sample_2d_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_sample_2d return;
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_sample_2d_textures_var), id_text(s.id_ptr_uniformconst_image2d_array)));
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_sample_2d_samplers_var), id_text(s.id_ptr_uniformconst_sampler_array)));
}

spv_append_write_2d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_2d return;
  append(sb, tprint("% = OpTypeImage % 2D 0 0 0 2 Unknown\n", id_text(s.id_storage_image2d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_storage_image2d_array), id_text(s.id_storage_image2d), id_text(s.id_sample_2d_array_len_const)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image2d_array), id_text(s.id_storage_image2d_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image2d), id_text(s.id_storage_image2d)));
}

spv_append_write_2d_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_2d return;
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_write_2d_textures_var), id_text(s.id_ptr_uniformconst_storage_image2d_array)));
}

emit_graphics_physical_pointer_abi :: (stage: IR_SPV_Gen_Stage,
                                       source_name: string,
                                       input: IR_Struct,
                                       output: IR_Struct,
                                       args: [] IR_Function_Arg,
                                       body: *IR_Block,
                                       functions: [] IR_Function,
                                       extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  if !body return_err("SPIR-V backend: graphics shader '%' has no body.", source_name);

  root_arg, has_root := find_pointer_root_arg(args, extra_structs);
  if !has_root || !root_arg return_err("SPIR-V backend: physical-pointer graphics path requires one pointer root argument.");
  if args.count != 1 return_err("SPIR-V backend: physical-pointer graphics path currently supports exactly one shader argument.");
  root_struct_name := root_arg.type.pointee_struct_name;
  if root_struct_name.count == 0 return_err("SPIR-V backend: pointer root '%' is missing typed pointee struct metadata.", root_arg.name);

  state: IR_SPV_Gen_State;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;

  root_struct := find_struct(*state, root_struct_name);
  if !root_struct return_err("SPIR-V backend: missing root pointer struct '%'.", root_struct_name);

  graphics_buffers: [..] IR_Compute_Buffer;
  saw_resource, saw_non_resource := collect_struct_resource_fields(*state, root_struct, root_arg.name, *graphics_buffers, root_arg.is_readonly);
  if !saw_resource return_err("SPIR-V backend: pointer root '%' has no resource fields.", root_arg.name);
  if saw_non_resource return_err("SPIR-V backend: pointer root '%' currently requires pointer-only members.", root_arg.name);

  init_ok, init_diag := init_base(*state, graphics_buffers, 1, use_physical_storage=true);
  if !init_ok return "", false, init_diag;

  for input.fields {
    field_type := spv_kind_from_ir_type(it.type);
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported input field type '%' on '%'.", field_type_name, it.name);
    ptr_type_id := input_ptr_type_id_from_kind(*state, field_type);
    if ptr_type_id == 0 return_err("SPIR-V backend: missing input pointer type for field '%'.", it.name);
    var_id := new_id(*state);
    builtin := interface_builtin_from_semantic(stage, it.name, it.semantic);
    array_add(*state.input_vars, .{
      name = it.name,
      type = field_type,
      ptr_id = ptr_type_id,
      var_id = var_id,
      location = -1,
      builtin = builtin,
    });
  }

  for output.fields {
    field_type := spv_kind_from_ir_type(it.type);
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported output field type '%' on '%'.", field_type_name, it.name);
    ptr_type_id := output_ptr_type_id_from_kind(*state, field_type);
    if ptr_type_id == 0 return_err("SPIR-V backend: missing output pointer type for field '%'.", it.name);
    var_id := new_id(*state);
    builtin := interface_builtin_from_semantic(stage, it.name, it.semantic);
    if stage == .FRAGMENT && (it.name == "out_color" || it.name == "color") builtin = .NONE;
    array_add(*state.output_vars, .{
      name = it.name,
      type = field_type,
      ptr_id = ptr_type_id,
      var_id = var_id,
      location = -1,
      builtin = builtin,
    });
  }

  ps_infos: [..] IR_SPV_PS_Struct_Info;
  if !ps_assign_struct_info(*state, *ps_infos, root_struct_name, root_arg.name) {
    return_err("SPIR-V backend: failed building pointer-struct type graph for '%'.", root_struct_name);
  }

  ptr_to_ptr_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  ptr_to_ptr_storage_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  root_var_ptr_type_id := new_id(*state);
  root_var_id := new_id(*state);
  root_info := find_ps_struct_info(*ps_infos, root_struct_name);
  if !root_info return_err("SPIR-V backend: missing pointer root type info for '%'.", root_struct_name);

  for *state.buffers {
    segments: [..] string;
    split_dotted_path(it.name, *segments);
    if segments.count < 2 return_err("SPIR-V backend: invalid resource path '%'.", it.name);
    if segments[0] != root_arg.name return_err("SPIR-V backend: resource path '%' does not match root arg '%'.", it.name, root_arg.name);
    current_ptr := root_var_id;
    current_ptr_from_storage := true;

    current_struct_name := root_struct_name;
    consumed_path := root_arg.name;
    for i: 1..segments.count-1 {
      current_struct := find_struct(*state, current_struct_name);
      if !current_struct return_err("SPIR-V backend: missing struct '%' while resolving '%'.", current_struct_name, it.name);
      field_index := find_field_index_by_name(current_struct, segments[i]);
      if field_index < 0 return_err("SPIR-V backend: field '%' not found in '%' while resolving '%' (segment %).", segments[i], current_struct_name, it.name, i);
      field := current_struct.fields[field_index];
      if field.type.kind != .POINTER return_err("SPIR-V backend: physical-pointer path expects pointer field at '%.%'.", current_struct_name, segments[i]);

      next_ptr_type_id: s64 = 0;
      next_struct_name := "";
      consumed_path = tprint("%.%", consumed_path, segments[i]);
      if field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.type.pointee_struct_name) {
        nested_info := find_ps_struct_info(*ps_infos, field.type.pointee_struct_name);
        if !nested_info return_err("SPIR-V backend: missing pointer type info for nested struct '%'.", field.type.pointee_struct_name);
        next_ptr_type_id = nested_info.ptr_type_id;
        next_struct_name = field.type.pointee_struct_name;
      } else {
        if i != segments.count-1 return_err("SPIR-V backend: non-struct pointer field reached before leaf at '%'.", consumed_path);
        if consumed_path != it.name return_err("SPIR-V backend: pointer path mismatch '%' vs '%'.", consumed_path, it.name);
        next_ptr_type_id = it.ptr_wrapper_type_id;
      }

      ptr_to_next_ptr: s64;
      if current_ptr_from_storage {
        ptr_to_next_ptr = ps_get_ptr_to_ptr_type(*state, *ptr_to_ptr_storage_types, next_ptr_type_id);
      } else {
        ptr_to_next_ptr = ps_get_ptr_to_ptr_type(*state, *ptr_to_ptr_types, next_ptr_type_id);
      }
      field_index_id := get_i32_const(*state, cast(s32) field_index);
      next_ptr_access := new_id(*state);
      add_op(*state, tprint("         % = OpAccessChain % % %",
                            id_text(next_ptr_access),
                            id_text(ptr_to_next_ptr),
                            id_text(current_ptr),
                            id_text(field_index_id)));
      next_ptr_loaded := new_id(*state);
      if current_ptr_from_storage {
        add_op(*state, tprint("         % = OpLoad % %",
                              id_text(next_ptr_loaded),
                              id_text(next_ptr_type_id),
                              id_text(next_ptr_access)));
      } else {
        add_op(*state, tprint("         % = OpLoad % % Aligned 8",
                              id_text(next_ptr_loaded),
                              id_text(next_ptr_type_id),
                              id_text(next_ptr_access)));
      }
      current_ptr = next_ptr_loaded;
      current_ptr_from_storage = false;
      if next_struct_name.count != 0 current_struct_name = next_struct_name;
    }

    it.var_id = current_ptr;
  }

  entry_label := new_id(*state);
  input_local, input_ok, input_diag := alloc_local_struct(*state, "input", input.name);
  if !input_ok return "", false, input_diag;
  output_local, output_ok, output_diag := alloc_local_struct(*state, "o", output.name);
  if !output_ok return "", false, output_diag;

  for state.input_vars {
    dst := find_local_struct_field(input_local, it.name);
    if !dst return_err("SPIR-V backend: input local struct missing field '%'.", it.name);
    value_id := new_id(*state);
    type_id := type_id_from_kind(*state, it.type);
    add_op(*state, tprint("         % = OpLoad % %", id_text(value_id), id_text(type_id), id_text(it.var_id)));
    add_op(*state, tprint("               OpStore % %", id_text(dst.ptr_id), id_text(value_id)));
  }

  block_ok, block_terminated, block_diag := emit_stmt_block(*state, body);
  if !block_ok return "", false, block_diag;
  if !block_terminated {
    ret_ok, ret_diag := emit_output_return_from_struct(*state, output_local);
    if !ret_ok return "", false, ret_diag;
  }

  entry_model := ifx stage == .VERTEX then "Vertex" else "Fragment";
  entry_name := ifx stage == .VERTEX then "VertexMain" else "FragmentMain";
  storage_class := "PhysicalStorageBuffer";

  sb: String_Builder;
  spv_append_module_preamble(*sb, *state, "PhysicalStorageBuffer64 GLSL450", use_physical_storage=true);
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint % % \"%\"", entry_model, id_text(state.id_main), entry_name));
  spv_append_var_ids(*entry_point_sb, state.input_vars);
  spv_append_var_ids(*entry_point_sb, state.output_vars);
  append(*entry_point_sb, " ", id_text(root_var_id));
  if state.uses_sample_2d {
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_samplers_var));
  }
  if state.uses_write_2d {
    append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  }
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  if stage == .FRAGMENT append(*sb, tprint("               OpExecutionMode % OriginUpperLeft\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"%\"\n", id_text(state.id_main), entry_name));
  append(*sb, tprint("               OpName % \"%\"\n", id_text(root_var_id), root_arg.name));
  for state.input_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.output_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  if state.uses_sample_2d {
    append(*sb, tprint("               OpName % \"sample_2d_textures\"\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpName % \"sample_2d_samplers\"\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  }
  for ps_infos {
    ps_info := it;
    append(*sb, tprint("               OpName % \"%\"\n", id_text(ps_info.type_id), debug_type_name(*state, ps_info.name)));
    st := find_struct(*state, ps_info.name);
    if st {
      for st.fields {
        field := it;
        append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(ps_info.type_id), it_index, field.name));
      }
    }
  }
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append_interface_var_decorations(*sb, state.input_vars);
  append_interface_var_decorations(*sb, state.output_vars);
  append(*sb, tprint("               OpDecorate % Binding 0\n", id_text(root_var_id)));
  append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(root_var_id)));
  if state.uses_sample_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_textures_var), SAMPLE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_samplers_var), SAMPLE_2D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  for ps_infos {
    ps_info := it;
    append(*sb, tprint("               OpDecorate % Block\n", id_text(ps_info.type_id)));
    st := find_struct(*state, ps_info.name);
    if !st continue;
    offset: s64 = 0;
    for st.fields {
      field := it;
      append(*sb, tprint("               OpMemberDecorate % % NonWritable\n", id_text(ps_info.type_id), it_index));
      append(*sb, tprint("               OpMemberDecorate % % Offset %\n", id_text(ps_info.type_id), it_index, offset));
      if field.type.kind == .POINTER offset += 8;
      else {
        kind := spv_kind_from_ir_type(field.type);
        size := byte_size_of_kind(kind);
        if size <= 0 size = 4;
        offset += size;
      }
    }
  }

  spv_append_common_type_decls(*sb, *state, storage_class);
  spv_append_numeric_constants(*sb, *state);
  spv_append_sample_2d_type_decls(*sb, *state);
  spv_append_write_2d_type_decls(*sb, *state);
  for ps_infos append(*sb, tprint("               OpTypeForwardPointer % %\n", id_text(it.ptr_type_id), storage_class));
  for state.buffers append(*sb, tprint("               OpTypeForwardPointer % %\n", id_text(it.ptr_wrapper_type_id), storage_class));
  for ps_infos {
    ps_info := it;
    st := find_struct(*state, ps_info.name);
    if !st continue;
    type_line: String_Builder;
    append(*type_line, tprint("% = OpTypeStruct", id_text(ps_info.type_id)));
    for st.fields {
      field := it;
      member_type_id: s64 = 0;
      if field.type.kind == .POINTER {
        if field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 &&
           struct_has_pointer_fields_recursive(state.extra_structs, field.type.pointee_struct_name) {
          nested_info := find_ps_struct_info(*ps_infos, field.type.pointee_struct_name);
          if !nested_info return_err("SPIR-V backend: missing nested pointer type info for '%'.", field.type.pointee_struct_name);
          member_type_id = nested_info.ptr_type_id;
        } else {
          leaf_path := tprint("%.%", ps_info.prefix, field.name);
          leaf_buffer := find_buffer(*state, leaf_path);
          if !leaf_buffer return_err("SPIR-V backend: missing leaf buffer for path '%'.", leaf_path);
          member_type_id = leaf_buffer.ptr_wrapper_type_id;
        }
      } else {
        kind := spv_kind_from_ir_type(field.type);
        member_type_id = type_id_from_kind(*state, kind);
      }
      if member_type_id == 0 return_err("SPIR-V backend: unsupported field type for pointer struct '%.%'.", ps_info.name, field.name);
      append(*type_line, " ", id_text(member_type_id));
    }
    append(*type_line, "\n");
    append(*sb, builder_to_string(*type_line));
  }

  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(root_var_ptr_type_id), id_text(root_info.type_id)));
  for ps_infos append(*sb, tprint("% = OpTypePointer % %\n", id_text(it.ptr_type_id), storage_class, id_text(it.type_id)));
  for ptr_to_ptr_types append(*sb, tprint("% = OpTypePointer % %\n", id_text(it.ptr_to_ptr_type_id), storage_class, id_text(it.ptr_type_id)));
  for ptr_to_ptr_storage_types append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(it.ptr_to_ptr_type_id), id_text(it.ptr_type_id)));

  spv_append_buffer_type_decls(*sb, *state, storage_class);

  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(root_var_id), id_text(root_var_ptr_type_id)));
  spv_append_sample_2d_vars(*sb, *state);
  spv_append_write_2d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

emit_graphics_generic :: (stage: IR_SPV_Gen_Stage, source_name: string, input: IR_Struct, output: IR_Struct, args: [] IR_Function_Arg, body: *IR_Block, functions: [] IR_Function, extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  analysis, analysis_ok, analysis_diag := spv_analyze_graphics_shader(stage, input, output, args, body, functions, extra_structs);
  if !analysis_ok return "", false, analysis_diag;
  if analysis.uses_pointer_abi {
    spvasm, ok, pointer_diag := emit_graphics_physical_pointer_abi(stage, source_name, input, output, args, body, functions, extra_structs);
    return spvasm, ok, pointer_diag;
  }

  state: IR_SPV_Gen_State;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_sample_2d = analysis.uses_sample_2d;
  init_ok, init_diag := init_base(*state, analysis.expanded_buffers, 1);
  if !init_ok return "", false, init_diag;

  for input.fields {
    field_type := spv_kind_from_ir_type(it.type);
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported input field type '%' on '%'.", field_type_name, it.name);
    ptr_type_id := input_ptr_type_id_from_kind(*state, field_type);
    if ptr_type_id == 0 return_err("SPIR-V backend: missing input pointer type for field '%'.", it.name);
    var_id := new_id(*state);
    builtin := interface_builtin_from_semantic(stage, it.name, it.semantic);
    array_add(*state.input_vars, .{
      name = it.name,
      type = field_type,
      ptr_id = ptr_type_id,
      var_id = var_id,
      location = -1,
      builtin = builtin,
    });
  }

  for output.fields {
    field_type := spv_kind_from_ir_type(it.type);
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported output field type '%' on '%'.", field_type_name, it.name);
    ptr_type_id := output_ptr_type_id_from_kind(*state, field_type);
    if ptr_type_id == 0 return_err("SPIR-V backend: missing output pointer type for field '%'.", it.name);
    var_id := new_id(*state);
    builtin := interface_builtin_from_semantic(stage, it.name, it.semantic);
    if stage == .FRAGMENT && (it.name == "out_color" || it.name == "color") builtin = .NONE;
    array_add(*state.output_vars, .{
      name = it.name,
      type = field_type,
      ptr_id = ptr_type_id,
      var_id = var_id,
      location = -1,
      builtin = builtin,
    });
  }

  binding_index: s64 = state.buffers.count;
  for args {
    arg := it;
    struct_name := arg.type.struct_name;
    is_param_block := arg.type.flags & .PARAMETER_BLOCK;
    if !is_param_block continue;
    if struct_name.count == 0 {
      return_err("SPIR-V backend: parameter block arg '%' is missing typed struct metadata.", arg.name);
    }
    struct_def := find_struct(*state, struct_name);
    if !struct_def return_err("SPIR-V backend: missing lowered uniform struct '%'.", struct_name);
    uniform_struct_type_id := new_id(*state);
    uniform_ptr_type_id := new_id(*state);
    uniform_var_id := new_id(*state);
    uniform_block: IR_SPV_Gen_Uniform_Block;
    uniform_block.name = arg.name;
    uniform_block.type_name = struct_name;
    uniform_block.binding_index = binding_index;
    uniform_block.var_id = uniform_var_id;
    uniform_block.struct_type_id = uniform_struct_type_id;
    uniform_block.ptr_uniform_struct_type_id = uniform_ptr_type_id;
    offset: s64 = 0;
    for struct_def.fields {
      field := it;
      nested_struct_name := spv_struct_name_from_ir_type(field.type);
      if nested_struct_name.count == 0 && field.type.kind == .POINTER && field.type.pointee_kind == .STRUCT {
        nested_struct_name = field.type.pointee_struct_name;
      }
      nested_struct := find_struct(*state, nested_struct_name);
      if nested_struct {
        nested_has_resource, nested_has_non_resource := collect_struct_resource_fields(*state, nested_struct, "", null);
        if nested_has_resource {
          if nested_has_non_resource {
            return_err("SPIR-V backend: nested resource/uniform struct field '%.%' is unsupported (mixed fields).", struct_name, field.name);
          }
          // Resource container fields in parameter blocks are flattened as storage buffers.
          continue;
        }
      }
      _, is_resource_field, _ := resource_element_type_from_field(*state, *field);
      if is_resource_field continue;
      field_type := IR_SPV_Gen_Type.UNKNOWN;
      field_type_id: s64 = 0;
      is_array := false;
      array_count: s64 = 0;
      array_stride: s64 = 0;
      array_type_id: s64 = 0;
      array_length_const_id: s64 = 0;
      field_align: s64 = 0;
      field_size: s64 = 0;

      array_elem_type_name := field.type.element_display_name;
      parsed_array_count: s64;
      parsed_array := field.type.kind == .FIXED_ARRAY;
      if parsed_array {
        parsed_array_count = field.type.array_count;
        array_elem_type_name = ir_string_first_non_empty(array_elem_type_name, field.type.element_struct_name);
      }
      if parsed_array {
        field_type = spv_kind_from_ir_type_kind(field.type.element_kind);
        if field_type == .UNKNOWN || field_type == .STRUCT {
          return_err("SPIR-V backend: uniform array field '%.%' has unsupported element type '%'.", struct_name, field.name, array_elem_type_name);
        }
        is_array = true;
        array_count = parsed_array_count;
        array_stride = 16; // std140-style stride for uniform arrays.
        array_length_const_id = get_u32_const(*state, cast(u32) array_count);
        array_type_id = new_id(*state);
        add_debug_name(*state, array_type_id, debug_type_name(*state, tprint("%_%_array", uniform_block.type_name, field.name)));
        field_type_id = array_type_id;
        field_align = 16;
        field_size = array_stride * array_count;
      } else {
        field_type = spv_kind_from_ir_type(field.type);
        if field_type == .UNKNOWN || field_type == .STRUCT {
          field_type_name := ir_string_first_non_empty(field.type.display_name, field.type.struct_name);
          return_err("SPIR-V backend: uniform field '%.%' has unsupported type '%'.", struct_name, field.name, field_type_name);
        }
        field_type_id = type_id_from_kind(*state, field_type);
        if field_type_id == 0 return_err("SPIR-V backend: missing type id for uniform field '%.%'.", struct_name, field.name);
        field_align = 4;
        if field_type == .FLOAT2 field_align = 8;
        if field_type == .FLOAT3 field_align = 16;
        if field_type == .FLOAT4 field_align = 16;
        field_size = byte_size_of_kind(field_type);
        if field_type == .FLOAT3 field_size = 16;
      }

      offset = align_up(offset, field_align);
      array_add(*uniform_block.fields, .{
        name = field.name,
        index = uniform_block.fields.count,
        type = field_type,
        field_type_id = field_type_id,
        is_array = is_array,
        array_count = array_count,
        array_stride = array_stride,
        array_type_id = array_type_id,
        array_length_const_id = array_length_const_id,
        offset = offset,
      });
      add_debug_member_name(*state, uniform_block.struct_type_id, uniform_block.fields.count-1, field.name);
      offset += field_size;
    }
    if uniform_block.fields.count == 0 continue;
    add_debug_name(*state, uniform_block.struct_type_id, debug_type_name(*state, uniform_block.type_name));
    array_add(*state.uniform_blocks, uniform_block);
    binding_index += 1;
  }

  entry_label := new_id(*state);
  input_local, input_ok, input_diag := alloc_local_struct(*state, "input", input.name);
  if !input_ok return "", false, input_diag;
  output_local, output_ok, output_diag := alloc_local_struct(*state, "o", output.name);
  if !output_ok return "", false, output_diag;

  for state.input_vars {
    dst := find_local_struct_field(input_local, it.name);
    if !dst return_err("SPIR-V backend: input local struct missing field '%'.", it.name);
    value_id := new_id(*state);
    type_id := type_id_from_kind(*state, it.type);
    add_op(*state, tprint("         % = OpLoad % %", id_text(value_id), id_text(type_id), id_text(it.var_id)));
    add_op(*state, tprint("               OpStore % %", id_text(dst.ptr_id), id_text(value_id)));
  }

  block_ok, block_terminated, block_diag := emit_stmt_block(*state, body);
  if !block_ok return "", false, block_diag;
  if !block_terminated {
    ret_ok, ret_diag := emit_output_return_from_struct(*state, output_local);
    if !ret_ok return "", false, ret_diag;
  }

  entry_model := ifx stage == .VERTEX then "Vertex" else "Fragment";
  entry_name := ifx stage == .VERTEX then "VertexMain" else "FragmentMain";

  sb: String_Builder;
  spv_append_module_preamble(*sb, *state, "Logical GLSL450");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint % % \"%\"", entry_model, id_text(state.id_main), entry_name));
  spv_append_var_ids(*entry_point_sb, state.input_vars);
  spv_append_var_ids(*entry_point_sb, state.output_vars);
  spv_append_var_ids(*entry_point_sb, state.buffers);
  spv_append_var_ids(*entry_point_sb, state.uniform_blocks);
  if state.uses_sample_2d {
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_samplers_var));
  }
  if state.uses_write_2d {
    append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  }
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  if stage == .FRAGMENT append(*sb, tprint("               OpExecutionMode % OriginUpperLeft\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"%\"\n", id_text(state.id_main), entry_name));
  for state.input_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.output_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.uniform_blocks append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  if state.uses_sample_2d {
    append(*sb, tprint("               OpName % \"sample_2d_textures\"\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpName % \"sample_2d_samplers\"\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  }
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append_interface_var_decorations(*sb, state.input_vars);
  append_interface_var_decorations(*sb, state.output_vars);
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);
  if state.uses_sample_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_textures_var), SAMPLE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_samplers_var), SAMPLE_2D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }
  for state.uniform_blocks {
    uniform := it;
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(uniform.var_id), uniform.binding_index));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(uniform.var_id)));
    append(*sb, tprint("               OpDecorate % Block\n", id_text(uniform.struct_type_id)));
    for uniform.fields {
      if it.is_array append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(it.array_type_id), it.array_stride));
      append(*sb, tprint("               OpMemberDecorate % % Offset %\n", id_text(uniform.struct_type_id), it.index, it.offset));
    }
  }

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  spv_append_numeric_constants(*sb, *state);
  spv_append_sample_2d_type_decls(*sb, *state);
  spv_append_write_2d_type_decls(*sb, *state);
  for state.uniform_blocks {
    type_line: String_Builder;
    for it.fields {
      if !it.is_array continue;
      append(*sb, tprint("% = OpTypeArray % %\n",
                         id_text(it.array_type_id),
                         id_text(type_id_from_kind(*state, it.type)),
                         id_text(it.array_length_const_id)));
    }
    append(*type_line, tprint("% = OpTypeStruct", id_text(it.struct_type_id)));
    for it.fields append(*type_line, " ", id_text(it.field_type_id));
    append(*type_line, "\n");
    append(*sb, builder_to_string(*type_line));
    append(*sb, tprint("% = OpTypePointer Uniform %\n", id_text(it.ptr_uniform_struct_type_id), id_text(it.struct_type_id)));
  }
  spv_append_buffer_type_decls(*sb, *state, "StorageBuffer");
  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  spv_append_buffer_vars(*sb, *state, "StorageBuffer");
  for state.uniform_blocks append(*sb, tprint("% = OpVariable % Uniform\n", id_text(it.var_id), id_text(it.ptr_uniform_struct_type_id)));
  spv_append_sample_2d_vars(*sb, *state);
  spv_append_write_2d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

// -----------------------------------------------------------------------------
// Module Assembly
// -----------------------------------------------------------------------------

IR_SPV_Compute_Analysis :: struct {
  bound_value: u32;
  uses_write_2d: bool;
  uses_sample_2d: bool;
  expanded_buffers: [..] IR_Compute_Buffer;
}

IR_SPV_Graphics_Analysis :: struct {
  uses_pointer_abi: bool;
  uses_write_2d: bool;
  uses_sample_2d: bool;
  expanded_buffers: [..] IR_Compute_Buffer;
}

spv_analyze_builtin_usage_expr :: (expr: *IR_Expr, uses_write_2d: *bool, uses_sample_2d: *bool) {
  if !expr return;
  if expr.kind == .CALL {
    call_builtin := call_builtin_kind_for_expr(expr);
    if call_builtin == .WRITE_2D uses_write_2d.* = true;
    if call_builtin == .SAMPLE_2D uses_sample_2d.* = true;
  }
  spv_analyze_builtin_usage_expr(expr.left, uses_write_2d, uses_sample_2d);
  spv_analyze_builtin_usage_expr(expr.right, uses_write_2d, uses_sample_2d);
  for expr.args spv_analyze_builtin_usage_expr(it, uses_write_2d, uses_sample_2d);
}

spv_analyze_builtin_usage_block :: (block: *IR_Block, uses_write_2d: *bool, uses_sample_2d: *bool) {
  if !block return;
  for block.statements {
    stmt := it;
    if stmt.kind == {
      case .DECL; {
        spv_analyze_builtin_usage_expr(stmt.decl_init, uses_write_2d, uses_sample_2d);
      }
      case .BINARY; {
        spv_analyze_builtin_usage_expr(stmt.binary_left, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_expr(stmt.binary_right, uses_write_2d, uses_sample_2d);
      }
      case .IF; {
        spv_analyze_builtin_usage_expr(stmt.if_condition, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_block(stmt.if_then, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_block(stmt.if_else, uses_write_2d, uses_sample_2d);
      }
      case .SWITCH; {
        spv_analyze_builtin_usage_expr(stmt.switch_condition, uses_write_2d, uses_sample_2d);
        for stmt.switch_cases {
          spv_analyze_builtin_usage_expr(it.condition, uses_write_2d, uses_sample_2d);
          spv_analyze_builtin_usage_block(it.body, uses_write_2d, uses_sample_2d);
        }
      }
      case .FOR; {
        spv_analyze_builtin_usage_expr(stmt.for_start, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_expr(stmt.for_end, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_block(stmt.for_body, uses_write_2d, uses_sample_2d);
      }
      case .WHILE; {
        spv_analyze_builtin_usage_expr(stmt.while_condition, uses_write_2d, uses_sample_2d);
        spv_analyze_builtin_usage_block(stmt.while_body, uses_write_2d, uses_sample_2d);
      }
      case .CALL; {
        spv_analyze_builtin_usage_expr(stmt.call_expr, uses_write_2d, uses_sample_2d);
      }
      case .RETURN; {
        spv_analyze_builtin_usage_expr(stmt.return_expr, uses_write_2d, uses_sample_2d);
      }
      case .BREAK;
      case .CONTINUE;
    }
  }
}

spv_analyze_graphics_shader :: (stage: IR_SPV_Gen_Stage,
                                input: IR_Struct,
                                output: IR_Struct,
                                args: [] IR_Function_Arg,
                                body: *IR_Block,
                                functions: [] IR_Function,
                                extra_structs: [] IR_Struct) -> (analysis: IR_SPV_Graphics_Analysis, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .{}, false, make_diag(msg, ..args); }
  if !body return_err("SPIR-V backend: graphics shader has no body.");

  out: IR_SPV_Graphics_Analysis;
  root_arg, use_pointer_abi := find_pointer_root_arg(args, extra_structs);
  out.uses_pointer_abi = use_pointer_abi && root_arg;

  spv_analyze_builtin_usage_block(body, *out.uses_write_2d, *out.uses_sample_2d);
  for functions spv_analyze_builtin_usage_block(*it.body, *out.uses_write_2d, *out.uses_sample_2d);

  if out.uses_pointer_abi return out, true, .{};

  state: IR_SPV_Gen_State;
  state.stage = stage;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);

  for args {
    arg := it;
    if arg.type.kind == .POINTER && arg.type.pointee_kind == .STRUCT && arg.type.pointee_struct_name.count != 0 {
      pointee_struct := find_struct(*state, arg.type.pointee_struct_name);
      if pointee_struct {
        saw_resource_field, saw_non_resource_field := collect_struct_resource_fields(*state, pointee_struct, arg.name, *out.expanded_buffers, arg.is_readonly);
        if saw_resource_field {
          if saw_non_resource_field {
            return_err("SPIR-V backend: resource-container arg '%' currently requires all fields to be StructuredBuffer/RWStructuredBuffer.", arg.name);
          }
          continue;
        }
      }

      elem_type_name := ir_string_first_non_empty(arg.type.pointee_display_name, arg.type.pointee_struct_name);
      array_add(*out.expanded_buffers, .{
        name = arg.name,
        element_type = .{
          kind = .STRUCT,
          display_name = elem_type_name,
          struct_name = arg.type.pointee_struct_name,
        },
        is_readonly = arg.is_readonly,
      });
      continue;
    }
    if arg.type.kind == .POINTER && arg.type.pointee_kind != .STRUCT && arg.type.pointee_display_name.count != 0 {
      elem_type := IR_Type.{
        kind = arg.type.pointee_kind,
        display_name = arg.type.pointee_display_name,
        struct_name = arg.type.pointee_struct_name,
      };
      if arg.type.pointee_kind == .FIXED_ARRAY {
        elem_type.array_count = arg.type.pointee_array_count;
        elem_type.element_kind = arg.type.pointee_element_kind;
        elem_type.element_display_name = arg.type.pointee_element_display_name;
        elem_type.element_struct_name = arg.type.pointee_element_struct_name;
      }
      array_add(*out.expanded_buffers, .{
        name = arg.name,
        element_type = elem_type,
        is_readonly = arg.is_readonly,
      });
      continue;
    }
    is_param_block := false;
    container_type_name := arg.type.struct_name;
    if arg.type.flags & .PARAMETER_BLOCK is_param_block = true;
    if arg.type.kind == .POINTER && arg.type.pointee_kind == .STRUCT && arg.type.pointee_struct_name.count != 0 {
      container_type_name = arg.type.pointee_struct_name;
    }
    if container_type_name.count == 0 continue;
    struct_def := find_struct(*state, container_type_name);
    if !struct_def continue;
    saw_resource_field, saw_non_resource_field := collect_struct_resource_fields(*state, struct_def, arg.name, *out.expanded_buffers, arg.is_readonly);
    if !is_param_block && saw_resource_field && saw_non_resource_field {
      return_err("SPIR-V backend: resource-container arg '%' currently requires all fields to be StructuredBuffer/RWStructuredBuffer.", arg.name);
    }
  }

  return out, true, .{};
}

spv_analyze_compute_shader :: (shader: IR_Compute_Shader) -> (analysis: IR_SPV_Compute_Analysis, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .{}, false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  if shader.buffers.count == 0 return_err("SPIR-V generic backend: expected at least one compute buffer.");
  if shader.body.statements.count == 0 return_err("SPIR-V generic backend: empty compute body.");

  out: IR_SPV_Compute_Analysis;
  out.bound_value = cast(u32) 64;
  if shader.body.statements[0].kind == .IF {
    b, bound_ok := match_branch_condition_outer(shader.body.statements[0].if_condition);
    if bound_ok out.bound_value = b;
  }

  spv_analyze_builtin_usage_block(*shader.body, *out.uses_write_2d, *out.uses_sample_2d);
  for shader.functions {
    spv_analyze_builtin_usage_block(*it.body, *out.uses_write_2d, *out.uses_sample_2d);
  }

  expand_state: IR_SPV_Gen_State;
  for shader.extra_structs array_add(*expand_state.extra_structs, it);
  expand_ok, expand_diag := expand_compute_resource_root_buffers(*expand_state, shader.buffers, *out.expanded_buffers);
  if !expand_ok return .{}, false, expand_diag;

  return out, true, diag;
}

emit_compute_generic_uint_buffer :: (shader: IR_Compute_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  analysis, analysis_ok, analysis_diag := spv_analyze_compute_shader(shader);
  if !analysis_ok return "", false, analysis_diag;

  state: IR_SPV_Gen_State;
  state.stage = .COMPUTE;
  state.debug_type_prefix = tprint("compute_%", shader.source_name);
  state.functions = shader.functions;
  for shader.extra_structs array_add(*state.extra_structs, it);
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_sample_2d = analysis.uses_sample_2d;
  init_ok, init_diag := init_base(*state, analysis.expanded_buffers, analysis.bound_value);
  if !init_ok return "", false, init_diag;

  entry_label := new_id(*state);
  ok, body_terminated, body_diag := emit_stmt_block(*state, *shader.body);
  if !ok return "", false, body_diag;

  // Build module text sections after IDs are finalized.
  sb: String_Builder;
  spv_append_module_preamble(*sb, *state, "Logical GLSL450");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint GLCompute % \"%\" % % % %",
                                 id_text(state.id_main),
                                 shader.entry_name,
                                 id_text(state.id_gl_global_invocation_id),
                                 id_text(state.id_gl_local_invocation_id),
                                 id_text(state.id_gl_workgroup_id),
                                 id_text(state.id_gl_local_invocation_index)));
  spv_append_var_ids(*entry_point_sb, state.buffers);
  if state.uses_write_2d append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  append(*sb, tprint("               OpExecutionMode % LocalSize 1 1 1\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"ComputeMain\"\n", id_text(state.id_main)));
  append(*sb, tprint("               OpName % \"gl_GlobalInvocationID\"\n", id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("               OpName % \"gl_LocalInvocationID\"\n", id_text(state.id_gl_local_invocation_id)));
  append(*sb, tprint("               OpName % \"gl_WorkGroupID\"\n", id_text(state.id_gl_workgroup_id)));
  append(*sb, tprint("               OpName % \"gl_LocalInvocationIndex\"\n", id_text(state.id_gl_local_invocation_index)));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  if state.uses_write_2d append(*sb, tprint("               OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append(*sb, tprint("               OpDecorate % BuiltIn GlobalInvocationId\n", id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("               OpDecorate % BuiltIn LocalInvocationId\n", id_text(state.id_gl_local_invocation_id)));
  append(*sb, tprint("               OpDecorate % BuiltIn WorkgroupId\n", id_text(state.id_gl_workgroup_id)));
  append(*sb, tprint("               OpDecorate % BuiltIn LocalInvocationIndex\n", id_text(state.id_gl_local_invocation_index)));
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);
  if state.uses_write_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  // OpTypeArray length operands must be declared constants beforehand.
  spv_append_numeric_constants(*sb, *state);
  spv_append_write_2d_type_decls(*sb, *state);
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_global_invocation_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_local_invocation_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_workgroup_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_local_invocation_index), id_text(state.id_ptr_input_uint)));
  spv_append_buffer_type_decls(*sb, *state, "StorageBuffer");
  spv_append_buffer_vars(*sb, *state, "StorageBuffer");
  spv_append_write_2d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);

  _ = body_terminated;
  spv_append_function_and_body(*sb, *state, entry_label, "      ", "         ");

  out := builder_to_string(*sb);
  return out, true, diag;
}
