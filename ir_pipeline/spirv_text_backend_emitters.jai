SAMPLE_2D_TEXTURES_BINDING :: 1;
SAMPLE_2D_SAMPLERS_BINDING :: 0;
SAMPLE_3D_TEXTURES_BINDING :: 1;
SAMPLE_3D_SAMPLERS_BINDING :: 0;
WRITE_2D_TEXTURES_BINDING :: 1;
WRITE_3D_TEXTURES_BINDING :: 1;

ps_get_storage_struct_ptr_type :: (s: *IR_SPV_Gen_State, ps_infos: *[..] IR_SPV_PS_Struct_Info, storage_struct_ptr_types: *[..] IR_SPV_PS_Ptr_To_Ptr, struct_name: string) -> s64 {
  assert(s != null);
  assert(ps_infos != null);
  assert(storage_struct_ptr_types != null);
  ps_info := find_ps_struct_info(ps_infos, struct_name);
  assert(ps_info != null);
  for storage_struct_ptr_types.* if it.ptr_type_id == ps_info.type_id return it.ptr_to_ptr_type_id;
  ptr_type_id := new_id(s);
  array_add(storage_struct_ptr_types, .{
    ptr_type_id = ps_info.type_id,
    ptr_to_ptr_type_id = ptr_type_id,
  });
  return ptr_type_id;
}

ps_emit_struct_type_decl_recursive :: (sb: *String_Builder, state: *IR_SPV_Gen_State, ps_infos: *[..] IR_SPV_PS_Struct_Info, struct_name: string, emitted: *[..] string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  assert(sb != null);
  assert(state != null);
  assert(ps_infos != null);
  assert(emitted != null);

  for emitted.* if it == struct_name return true, {};

  ps_info := find_ps_struct_info(ps_infos, struct_name);
  if !ps_info return_err("SPIR-V backend: missing pointer-struct type info for '%'.", struct_name);
  st := find_struct(state, struct_name);
  if !st return_err("SPIR-V backend: missing pointer-struct '%'.", struct_name);

  for st.fields {
    if it.type.kind == .STRUCT && it.type.struct_name.count != 0 &&
       struct_has_pointer_fields_recursive(state.extra_structs, it.type.struct_name) {
      nested_ok, nested_diag := ps_emit_struct_type_decl_recursive(sb, state, ps_infos, it.type.struct_name, emitted);
      if !nested_ok return false, nested_diag;
    }
  }

  type_line: String_Builder;
  append(*type_line, tprint("% = OpTypeStruct", id_text(ps_info.type_id)));
  for st.fields {
    field := it;
    member_type_id: s64 = 0;
    if field.type.kind == .POINTER {
      if field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.type.pointee_struct_name) {
        nested_info := find_ps_struct_info(ps_infos, field.type.pointee_struct_name);
        if !nested_info return_err("SPIR-V backend: missing pointer type info for nested struct '%'.", field.type.pointee_struct_name);
        member_type_id = nested_info.ptr_type_id;
      } else {
        leaf_path := tprint("%.%", ps_info.prefix, field.name);
        leaf_buffer := find_buffer(state, leaf_path);
        if !leaf_buffer return_err("SPIR-V backend: missing leaf buffer for path '%'.", leaf_path);
        member_type_id = leaf_buffer.ptr_wrapper_type_id;
      }
    } else if field.type.kind == .STRUCT && field.type.struct_name.count != 0 &&
              struct_has_pointer_fields_recursive(state.extra_structs, field.type.struct_name) {
      nested_info := find_ps_struct_info(ps_infos, field.type.struct_name);
      if !nested_info return_err("SPIR-V backend: missing nested struct type info for '%'.", field.type.struct_name);
      member_type_id = nested_info.type_id;
    } else {
      kind := spv_kind_from_ir_type(field.type);
      member_type_id = type_id_from_kind(state, kind);
    }
    if member_type_id == 0 return_err("SPIR-V backend: unsupported field type for pointer struct '%.%'.", struct_name, field.name);
    append(*type_line, " ", id_text(member_type_id));
  }
  append(*type_line, "\n");
  append_and_steal_buffers(sb, *type_line);
  array_add(emitted, struct_name);
  return true, {};
}

ps_emit_struct_type_decl_recursive_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State, ps_infos: *[..] IR_SPV_PS_Struct_Info, struct_name: string, emitted: *[..] string) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  assert(m != null);
  assert(state != null);
  assert(ps_infos != null);
  assert(emitted != null);

  for emitted.* if it == struct_name return true, {};

  ps_info := find_ps_struct_info(ps_infos, struct_name);
  if !ps_info return_err("SPIR-V backend: missing pointer-struct type info for '%'.", struct_name);
  st := find_struct(state, struct_name);
  if !st return_err("SPIR-V backend: missing pointer-struct '%'.", struct_name);

  for st.fields {
    if it.type.kind == .STRUCT && it.type.struct_name.count != 0 &&
       struct_has_pointer_fields_recursive(state.extra_structs, it.type.struct_name) {
      nested_ok, nested_diag := ps_emit_struct_type_decl_recursive_binary(m, state, ps_infos, it.type.struct_name, emitted);
      if !nested_ok return false, nested_diag;
    }
  }

  inst: SPV_Inst;
  inst.opcode = SPV_OP_TYPE_STRUCT;
  array_add(*inst.words, cast(u32) ps_info.type_id);
  for st.fields {
    field := it;
    member_type_id: s64 = 0;
    if field.type.kind == .POINTER {
      if field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.type.pointee_struct_name) {
        nested_info := find_ps_struct_info(ps_infos, field.type.pointee_struct_name);
        if !nested_info return_err("SPIR-V backend: missing pointer type info for nested struct '%'.", field.type.pointee_struct_name);
        member_type_id = nested_info.ptr_type_id;
      } else {
        leaf_path := tprint("%.%", ps_info.prefix, field.name);
        leaf_buffer := find_buffer(state, leaf_path);
        if !leaf_buffer return_err("SPIR-V backend: missing leaf buffer for path '%'.", leaf_path);
        member_type_id = leaf_buffer.ptr_wrapper_type_id;
      }
    } else if field.type.kind == .STRUCT && field.type.struct_name.count != 0 &&
              struct_has_pointer_fields_recursive(state.extra_structs, field.type.struct_name) {
      nested_info := find_ps_struct_info(ps_infos, field.type.struct_name);
      if !nested_info return_err("SPIR-V backend: missing nested struct type info for '%'.", field.type.struct_name);
      member_type_id = nested_info.type_id;
    } else {
      kind := spv_kind_from_ir_type(field.type);
      member_type_id = type_id_from_kind(state, kind);
    }
    if member_type_id == 0 return_err("SPIR-V backend: unsupported field type for pointer struct '%.%'.", struct_name, field.name);
    array_add(*inst.words, cast(u32) member_type_id);
  }
  spv_module_append_inst(m, .TYPES_CONSTANTS_GLOBALS, inst);
  array_add(emitted, struct_name);
  return true, {};
}

spv_append_sample_2d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_sample_2d return;
  append(sb, tprint("% = OpTypeImage % 2D 0 0 0 1 Unknown\n", id_text(s.id_image2d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeSampler\n", id_text(s.id_sampler)));
  append(sb, tprint("% = OpTypeSampledImage %\n", id_text(s.id_sampled_image2d), id_text(s.id_image2d)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_image2d_array), id_text(s.id_image2d), id_text(s.id_sampled_texture_array_len_const)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_sampler_array), id_text(s.id_sampler), id_text(s.id_sampler_array_len_const)));
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

spv_append_sample_3d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_sample_3d return;
  append(sb, tprint("% = OpTypeImage % 3D 0 0 0 1 Unknown\n", id_text(s.id_image3d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeSampler\n", id_text(s.id_sampler)));
  append(sb, tprint("% = OpTypeSampledImage %\n", id_text(s.id_sampled_image3d), id_text(s.id_image3d)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_image3d_array), id_text(s.id_image3d), id_text(s.id_sampled_texture_array_len_const)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_sampler_array), id_text(s.id_sampler), id_text(s.id_sampler_array_len_const)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_image3d_array), id_text(s.id_image3d_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_sampler_array), id_text(s.id_sampler_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_image3d), id_text(s.id_image3d)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_sampler), id_text(s.id_sampler)));
}

spv_append_sample_3d_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_sample_3d return;
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_sample_3d_textures_var), id_text(s.id_ptr_uniformconst_image3d_array)));
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_sample_3d_samplers_var), id_text(s.id_ptr_uniformconst_sampler_array)));
}

spv_append_write_2d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_2d return;
  append(sb, tprint("% = OpTypeImage % 2D 0 0 0 2 Unknown\n", id_text(s.id_storage_image2d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_storage_image2d_array), id_text(s.id_storage_image2d), id_text(s.id_storage_texture_array_len_const)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image2d_array), id_text(s.id_storage_image2d_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image2d), id_text(s.id_storage_image2d)));
}

spv_append_write_2d_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_2d return;
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_write_2d_textures_var), id_text(s.id_ptr_uniformconst_storage_image2d_array)));
}

spv_append_write_3d_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_3d return;
  append(sb, tprint("% = OpTypeImage % 3D 0 0 0 2 Unknown\n", id_text(s.id_storage_image3d), id_text(s.id_float)));
  append(sb, tprint("% = OpTypeArray % %\n", id_text(s.id_storage_image3d_array), id_text(s.id_storage_image3d), id_text(s.id_storage_texture_array_len_const)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image3d_array), id_text(s.id_storage_image3d_array)));
  append(sb, tprint("% = OpTypePointer UniformConstant %\n", id_text(s.id_ptr_uniformconst_storage_image3d), id_text(s.id_storage_image3d)));
}

spv_append_write_3d_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  if !s.uses_write_3d return;
  append(sb, tprint("% = OpVariable % UniformConstant\n", id_text(s.id_write_3d_textures_var), id_text(s.id_ptr_uniformconst_storage_image3d_array)));
}

spv_module_append_sampled_image_decls_binary :: (m: *SPV_Module, s: *IR_SPV_Gen_State) {
  assert(m != null && s != null);
  if s.uses_sample_2d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_IMAGE, cast(u32) s.id_image2d, cast(u32) s.id_float, SPV_DIM_2D, 0, 0, 0, 1, SPV_IMAGE_FORMAT_UNKNOWN);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_SAMPLER, cast(u32) s.id_sampler);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_SAMPLED_IMAGE, cast(u32) s.id_sampled_image2d, cast(u32) s.id_image2d);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_image2d_array, cast(u32) s.id_image2d, cast(u32) s.id_sampled_texture_array_len_const);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_sampler_array, cast(u32) s.id_sampler, cast(u32) s.id_sampler_array_len_const);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_image2d_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_image2d_array);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_sampler_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_sampler_array);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_image2d, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_image2d);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_sampler, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_sampler);
  }
  if s.uses_sample_3d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_IMAGE, cast(u32) s.id_image3d, cast(u32) s.id_float, SPV_DIM_3D, 0, 0, 0, 1, SPV_IMAGE_FORMAT_UNKNOWN);
    if !s.uses_sample_2d {
      spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_SAMPLER, cast(u32) s.id_sampler);
    }
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_SAMPLED_IMAGE, cast(u32) s.id_sampled_image3d, cast(u32) s.id_image3d);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_image3d_array, cast(u32) s.id_image3d, cast(u32) s.id_sampled_texture_array_len_const);
    if !s.uses_sample_2d {
      spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_sampler_array, cast(u32) s.id_sampler, cast(u32) s.id_sampler_array_len_const);
      spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_sampler_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_sampler_array);
      spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_sampler, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_sampler);
    }
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_image3d_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_image3d_array);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_image3d, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_image3d);
  }
}

spv_module_append_storage_image_decls_binary :: (m: *SPV_Module, s: *IR_SPV_Gen_State) {
  assert(m != null && s != null);
  if s.uses_write_2d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_IMAGE, cast(u32) s.id_storage_image2d, cast(u32) s.id_float, SPV_DIM_2D, 0, 0, 0, 2, SPV_IMAGE_FORMAT_UNKNOWN);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_storage_image2d_array, cast(u32) s.id_storage_image2d, cast(u32) s.id_storage_texture_array_len_const);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_storage_image2d_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_storage_image2d_array);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_storage_image2d, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_storage_image2d);
  }
  if s.uses_write_3d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_IMAGE, cast(u32) s.id_storage_image3d, cast(u32) s.id_float, SPV_DIM_3D, 0, 0, 0, 2, SPV_IMAGE_FORMAT_UNKNOWN);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) s.id_storage_image3d_array, cast(u32) s.id_storage_image3d, cast(u32) s.id_storage_texture_array_len_const);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_storage_image3d_array, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_storage_image3d_array);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) s.id_ptr_uniformconst_storage_image3d, SPV_STORAGE_CLASS_UNIFORM_CONSTANT, cast(u32) s.id_storage_image3d);
  }
}

spv_module_append_sampled_storage_image_vars_binary :: (m: *SPV_Module, s: *IR_SPV_Gen_State) {
  assert(m != null && s != null);
  if s.uses_sample_2d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_image2d_array, cast(u32) s.id_sample_2d_textures_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_sampler_array, cast(u32) s.id_sample_2d_samplers_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
  }
  if s.uses_sample_3d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_image3d_array, cast(u32) s.id_sample_3d_textures_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_sampler_array, cast(u32) s.id_sample_3d_samplers_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
  }
  if s.uses_write_2d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_storage_image2d_array, cast(u32) s.id_write_2d_textures_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
  }
  if s.uses_write_3d {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) s.id_ptr_uniformconst_storage_image3d_array, cast(u32) s.id_write_3d_textures_var, SPV_STORAGE_CLASS_UNIFORM_CONSTANT);
  }
}

spv_module_append_uniform_block_decls_binary :: (m: *SPV_Module, s: *IR_SPV_Gen_State) {
  assert(m != null && s != null);
  for s.uniform_blocks {
    uniform := it;
    for uniform.fields {
      if !it.is_array continue;
      spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) it.array_type_id, cast(u32) type_id_from_kind(s, it.type), cast(u32) it.array_length_const_id);
    }
    inst: SPV_Inst;
    inst.opcode = SPV_OP_TYPE_STRUCT;
    array_add(*inst.words, cast(u32) uniform.struct_type_id);
    for uniform.fields array_add(*inst.words, cast(u32) it.field_type_id);
    spv_module_append_inst(m, .TYPES_CONSTANTS_GLOBALS, inst);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) uniform.ptr_uniform_struct_type_id, SPV_STORAGE_CLASS_UNIFORM, cast(u32) uniform.struct_type_id);
  }
}

spv_module_append_uniform_block_vars_binary :: (m: *SPV_Module, s: *IR_SPV_Gen_State) {
  assert(m != null && s != null);
  for s.uniform_blocks {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_uniform_struct_type_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_UNIFORM);
  }
}

spv_module_append_function_body :: (m: *SPV_Module, s: *IR_SPV_Gen_State, entry_label: s64) {
  assert(m != null);
  assert(s != null);

  function_words: [..] u32;
  array_add(*function_words, cast(u32) s.id_void, cast(u32) s.id_main, 0, cast(u32) s.id_fn_void);
  spv_module_append_inst(m, .FUNCTIONS, .{opcode = SPV_OP_FUNCTION, words = function_words});

  label_words: [..] u32;
  array_add(*label_words, cast(u32) entry_label);
  spv_module_append_inst(m, .FUNCTIONS, .{opcode = SPV_OP_LABEL, words = label_words});

  for s.local_var_insts spv_module_append_inst(m, .FUNCTIONS, it);
  for s.op_insts spv_module_append_inst(m, .FUNCTIONS, it);

  if !s.last_op_is_terminator {
    spv_module_append_inst(m, .FUNCTIONS, .{opcode = SPV_OP_RETURN});
  }

  spv_module_append_inst(m, .FUNCTIONS, .{opcode = SPV_OP_FUNCTION_END});
}

emit_graphics_physical_pointer_abi :: (stage: IR_SPV_Gen_Stage,
                                       source_name: string,
                                       input: IR_Struct,
                                       output: IR_Struct,
                                       args: [] IR_Function_Arg,
                                       body: *IR_Block,
                                       functions: [] IR_Function,
                                       function_constants: [] IR_Function_Constant,
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
  state.emit_text = true;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, function_constants);
  if !function_constants_ok return "", false, function_constants_diag;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;

  root_struct := find_struct(*state, root_struct_name);
  if !root_struct return_err("SPIR-V backend: missing root pointer struct '%'.", root_struct_name);

  graphics_buffers: [..] IR_Compute_Buffer;
  saw_resource, saw_non_resource := collect_struct_resource_fields(*state, root_struct, root_arg.name, *graphics_buffers, root_arg.is_readonly);
  if !saw_resource return_err("SPIR-V backend: pointer root '%' has no resource fields.", root_arg.name);
  _ = saw_non_resource;

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
  storage_struct_ptr_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  root_var_ptr_type_id := new_id(*state);
  root_var_id := new_id(*state);
  root_info := find_ps_struct_info(*ps_infos, root_struct_name);
  if !root_info return_err("SPIR-V backend: missing pointer root type info for '%'.", root_struct_name);
  state.physical_root_name = root_arg.name;
  state.physical_root_struct_name = root_struct_name;
  state.physical_root_var_id = root_var_id;
  for ps_infos array_add(*state.physical_ps_infos, it);

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
      consumed_path = tprint("%.%", consumed_path, segments[i]);

      if field.type.kind == .STRUCT &&
         field.type.struct_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.type.struct_name) {
        nested_info := find_ps_struct_info(*ps_infos, field.type.struct_name);
        if !nested_info return_err("SPIR-V backend: missing nested struct type info for '%'.", field.type.struct_name);
        next_ptr_type_id := ifx current_ptr_from_storage then ps_get_storage_struct_ptr_type(*state, *ps_infos, *storage_struct_ptr_types, field.type.struct_name) else nested_info.ptr_type_id;
        field_index_id := get_i32_const(*state, cast(s32) field_index);
        next_ptr_access := new_id(*state);
        spv_emit_access_chain(*state, next_ptr_access, next_ptr_type_id, current_ptr, .[field_index_id]);
        current_ptr = next_ptr_access;
        current_struct_name = field.type.struct_name;
        continue;
      }

      if field.type.kind != .POINTER return_err("SPIR-V backend: physical-pointer path expects pointer or nested resource-struct field at '%.%'.", current_struct_name, segments[i]);

      next_ptr_type_id: s64 = 0;
      next_struct_name := "";
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
      spv_emit_access_chain(*state, next_ptr_access, ptr_to_next_ptr, current_ptr, .[field_index_id]);
      next_ptr_loaded := new_id(*state);
      if current_ptr_from_storage {
        spv_emit_load(*state, next_ptr_loaded, next_ptr_type_id, next_ptr_access);
      } else {
        spv_emit_load(*state, next_ptr_loaded, next_ptr_type_id, next_ptr_access, 8);
      }
      current_ptr = next_ptr_loaded;
      current_ptr_from_storage = false;
      if next_struct_name.count != 0 current_struct_name = next_struct_name;
    }

    it.var_id = current_ptr;
  }

  for storage_struct_ptr_types array_add(*state.physical_storage_struct_ptr_types, it);

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
    spv_emit_load(*state, value_id, type_id, it.var_id);
    spv_emit_store(*state, dst.ptr_id, value_id);
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
  spv_append_var_ids(*entry_point_sb, state.global_const_arrays);
  append(*entry_point_sb, " ", id_text(root_var_id));
  if state.uses_sample_2d {
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_samplers_var));
  }
  if state.uses_sample_3d {
    append(*entry_point_sb, " ", id_text(state.id_sample_3d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_3d_samplers_var));
  }
  if state.uses_write_2d {
    append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  }
  if state.uses_write_3d {
    append(*entry_point_sb, " ", id_text(state.id_write_3d_textures_var));
  }
  append(*entry_point_sb, "\n");
  append_and_steal_buffers(*sb, *entry_point_sb);
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
  if state.uses_sample_3d {
    append(*sb, tprint("               OpName % \"sample_3d_textures\"\n", id_text(state.id_sample_3d_textures_var)));
    append(*sb, tprint("               OpName % \"sample_3d_samplers\"\n", id_text(state.id_sample_3d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  }
  if state.uses_write_3d {
    append(*sb, tprint("               OpName % \"write_3d_textures\"\n", id_text(state.id_write_3d_textures_var)));
  }
  spv_append_function_constant_names(*sb, *state);
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
  spv_append_function_constant_decorations(*sb, *state);
  append(*sb, tprint("               OpDecorate % Binding 0\n", id_text(root_var_id)));
  append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(root_var_id)));
  if state.uses_sample_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_textures_var), SAMPLE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_samplers_var), SAMPLE_2D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_sample_3d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_3d_textures_var), SAMPLE_3D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_3d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_3d_samplers_var), SAMPLE_3D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_3d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }
  if state.uses_write_3d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_3d_textures_var), WRITE_3D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_3d_textures_var)));
  }
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  for ps_infos {
    ps_info := it;
    if ps_info.name == root_struct_name {
      append(*sb, tprint("               OpDecorate % Block\n", id_text(ps_info.type_id)));
    }
    st := find_struct(*state, ps_info.name);
    if !st continue;
    offset: s64 = 0;
    for st.fields {
      field := it;
      if field.type.kind == .POINTER {
        offset = align_up(offset, 8);
      } else {
        kind := spv_kind_from_ir_type(field.type);
        field_align := host_blit_align_for_kind(kind);
        if field_align <= 0 field_align = 4;
        offset = align_up(offset, field_align);
      }
      append(*sb, tprint("               OpMemberDecorate % % NonWritable\n", id_text(ps_info.type_id), it_index));
      append(*sb, tprint("               OpMemberDecorate % % Offset %\n", id_text(ps_info.type_id), it_index, offset));
      kind := spv_kind_from_ir_type(field.type);
      matrix_stride := spv_matrix_stride_for_kind(kind);
      if matrix_stride > 0 {
        append(*sb, tprint("               OpMemberDecorate % % RowMajor\n", id_text(ps_info.type_id), it_index));
        append(*sb, tprint("               OpMemberDecorate % % MatrixStride %\n", id_text(ps_info.type_id), it_index, matrix_stride));
      }
      if field.type.kind == .POINTER offset += 8;
      else {
        size := byte_size_of_kind(kind);
        if size <= 0 size = 4;
        offset += size;
      }
    }
  }

  spv_append_common_type_decls(*sb, *state, storage_class);
  spv_append_numeric_constants(*sb, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_append_function_constant_defs(*sb, *state);
  if !function_constant_defs_ok return "", false, function_constant_defs_diag;
  spv_append_sample_2d_type_decls(*sb, *state);
  spv_append_sample_3d_type_decls(*sb, *state);
  spv_append_write_2d_type_decls(*sb, *state);
  spv_append_write_3d_type_decls(*sb, *state);
  for ps_infos append(*sb, tprint("               OpTypeForwardPointer % %\n", id_text(it.ptr_type_id), storage_class));
  for state.buffers append(*sb, tprint("               OpTypeForwardPointer % %\n", id_text(it.ptr_wrapper_type_id), storage_class));
  emitted_ps_structs: [..] string;
  for ps_infos {
    emit_ok, emit_diag := ps_emit_struct_type_decl_recursive(*sb, *state, *ps_infos, it.name, *emitted_ps_structs);
    if !emit_ok return "", false, emit_diag;
  }

  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(root_var_ptr_type_id), id_text(root_info.type_id)));
  for storage_struct_ptr_types append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(it.ptr_to_ptr_type_id), id_text(it.ptr_type_id)));
  for ps_infos append(*sb, tprint("% = OpTypePointer % %\n", id_text(it.ptr_type_id), storage_class, id_text(it.type_id)));
  for ptr_to_ptr_types append(*sb, tprint("% = OpTypePointer % %\n", id_text(it.ptr_to_ptr_type_id), storage_class, id_text(it.ptr_type_id)));
  for ptr_to_ptr_storage_types append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(it.ptr_to_ptr_type_id), id_text(it.ptr_type_id)));

  spv_append_buffer_type_decls(*sb, *state, storage_class);

  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(root_var_id), id_text(root_var_ptr_type_id)));
  spv_append_sample_2d_vars(*sb, *state);
  spv_append_sample_3d_vars(*sb, *state);
  spv_append_write_2d_vars(*sb, *state);
  spv_append_write_3d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);
  spv_append_global_const_array_decls(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

emit_graphics_physical_pointer_abi_binary :: (stage: IR_SPV_Gen_Stage,
                                              source_name: string,
                                              input: IR_Struct,
                                              output: IR_Struct,
                                              args: [] IR_Function_Arg,
                                              body: *IR_Block,
                                              functions: [] IR_Function,
                                              function_constants: [] IR_Function_Constant,
                                              extra_structs: [] IR_Struct) -> (spv: []u8, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .[], false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  if !body return_err("SPIR-V backend: graphics shader '%' has no body.", source_name);

  root_arg, has_root := find_pointer_root_arg(args, extra_structs);
  if !has_root || !root_arg return_err("SPIR-V backend: physical-pointer graphics path requires one pointer root argument.");
  if args.count != 1 return_err("SPIR-V backend: physical-pointer graphics path currently supports exactly one shader argument.");
  root_struct_name := root_arg.type.pointee_struct_name;
  if root_struct_name.count == 0 return_err("SPIR-V backend: pointer root '%' is missing typed pointee struct metadata.", root_arg.name);

  state: IR_SPV_Gen_State;
  state.record_binary = true;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, function_constants);
  if !function_constants_ok return .[], false, function_constants_diag;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;

  root_struct := find_struct(*state, root_struct_name);
  if !root_struct return_err("SPIR-V backend: missing root pointer struct '%'.", root_struct_name);

  graphics_buffers: [..] IR_Compute_Buffer;
  saw_resource, saw_non_resource := collect_struct_resource_fields(*state, root_struct, root_arg.name, *graphics_buffers, root_arg.is_readonly);
  if !saw_resource return_err("SPIR-V backend: pointer root '%' has no resource fields.", root_arg.name);
  _ = saw_non_resource;

  init_ok, init_diag := init_base(*state, graphics_buffers, 1, use_physical_storage=true);
  if !init_ok return .[], false, init_diag;

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
  storage_struct_ptr_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  root_var_ptr_type_id := new_id(*state);
  root_var_id := new_id(*state);
  root_info := find_ps_struct_info(*ps_infos, root_struct_name);
  if !root_info return_err("SPIR-V backend: missing pointer root type info for '%'.", root_struct_name);
  state.physical_root_name = root_arg.name;
  state.physical_root_struct_name = root_struct_name;
  state.physical_root_var_id = root_var_id;
  for ps_infos array_add(*state.physical_ps_infos, it);

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
      consumed_path = tprint("%.%", consumed_path, segments[i]);

      if field.type.kind == .STRUCT &&
         field.type.struct_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.type.struct_name) {
        nested_info := find_ps_struct_info(*ps_infos, field.type.struct_name);
        if !nested_info return_err("SPIR-V backend: missing nested struct type info for '%'.", field.type.struct_name);
        next_ptr_type_id := ifx current_ptr_from_storage then ps_get_storage_struct_ptr_type(*state, *ps_infos, *storage_struct_ptr_types, field.type.struct_name) else nested_info.ptr_type_id;
        field_index_id := get_i32_const(*state, cast(s32) field_index);
        next_ptr_access := new_id(*state);
        spv_emit_access_chain(*state, next_ptr_access, next_ptr_type_id, current_ptr, .[field_index_id]);
        current_ptr = next_ptr_access;
        current_struct_name = field.type.struct_name;
        continue;
      }

      if field.type.kind != .POINTER return_err("SPIR-V backend: physical-pointer path expects pointer or nested resource-struct field at '%.%'.", current_struct_name, segments[i]);

      next_ptr_type_id: s64 = 0;
      next_struct_name := "";
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
      spv_emit_access_chain(*state, next_ptr_access, ptr_to_next_ptr, current_ptr, .[field_index_id]);
      next_ptr_loaded := new_id(*state);
      if current_ptr_from_storage {
        spv_emit_load(*state, next_ptr_loaded, next_ptr_type_id, next_ptr_access);
      } else {
        spv_emit_load(*state, next_ptr_loaded, next_ptr_type_id, next_ptr_access, 8);
      }
      current_ptr = next_ptr_loaded;
      current_ptr_from_storage = false;
      if next_struct_name.count != 0 current_struct_name = next_struct_name;
    }

    it.var_id = current_ptr;
  }

  for storage_struct_ptr_types array_add(*state.physical_storage_struct_ptr_types, it);

  entry_label := new_id(*state);
  input_local, input_ok, input_diag := alloc_local_struct(*state, "input", input.name);
  if !input_ok return .[], false, input_diag;
  output_local, output_ok, output_diag := alloc_local_struct(*state, "o", output.name);
  if !output_ok return .[], false, output_diag;

  for state.input_vars {
    dst := find_local_struct_field(input_local, it.name);
    if !dst return_err("SPIR-V backend: input local struct missing field '%'.", it.name);
    value_id := new_id(*state);
    type_id := type_id_from_kind(*state, it.type);
    spv_emit_load(*state, value_id, type_id, it.var_id);
    spv_emit_store(*state, dst.ptr_id, value_id);
  }

  block_ok, block_terminated, block_diag := emit_stmt_block(*state, body);
  if !block_ok return .[], false, block_diag;
  if !block_terminated {
    ret_ok, ret_diag := emit_output_return_from_struct(*state, output_local);
    if !ret_ok return .[], false, ret_diag;
  }

  module: SPV_Module;
  spv_module_append_capabilities_binary(*module, *state, use_physical_storage=true);
  spv_module_append_ext_inst_import(*module, cast(u32) state.id_extinst, "GLSL.std.450");
  spv_module_append_words(*module, .MEMORY_MODEL, SPV_OP_MEMORY_MODEL, SPV_ADDRESSING_MODEL_PHYSICAL_STORAGE_BUFFER_64, SPV_MEMORY_MODEL_GLSL450);
  entry_execution_model: u32 = ifx stage == .VERTEX then cast(u32) SPV_EXECUTION_MODEL_VERTEX else cast(u32) SPV_EXECUTION_MODEL_FRAGMENT;
  entry_name := ifx stage == .VERTEX then "VertexMain" else "FragmentMain";
  interface_ids: [..]u32;
  for state.input_vars array_add(*interface_ids, cast(u32) it.var_id);
  for state.output_vars array_add(*interface_ids, cast(u32) it.var_id);
  for state.global_const_arrays array_add(*interface_ids, cast(u32) it.var_id);
  array_add(*interface_ids, cast(u32) root_var_id);
  if state.uses_sample_2d array_add(*interface_ids, cast(u32) state.id_sample_2d_textures_var, cast(u32) state.id_sample_2d_samplers_var);
  if state.uses_sample_3d array_add(*interface_ids, cast(u32) state.id_sample_3d_textures_var, cast(u32) state.id_sample_3d_samplers_var);
  if state.uses_write_2d array_add(*interface_ids, cast(u32) state.id_write_2d_textures_var);
  if state.uses_write_3d array_add(*interface_ids, cast(u32) state.id_write_3d_textures_var);
  spv_module_append_entry_point(*module, entry_execution_model, cast(u32) state.id_main, entry_name, interface_ids);
  if stage == .FRAGMENT {
    spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_ORIGIN_UPPER_LEFT);
  }
  spv_module_append_source(*module, SPV_SOURCE_LANGUAGE_UNKNOWN, 100000);
  spv_module_append_name(*module, cast(u32) state.id_main, entry_name);
  spv_module_append_name(*module, cast(u32) root_var_id, root_arg.name);
  for state.input_vars spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  for state.output_vars spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  for state.buffers spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  if state.uses_sample_2d {
    spv_module_append_name(*module, cast(u32) state.id_sample_2d_textures_var, "sample_2d_textures");
    spv_module_append_name(*module, cast(u32) state.id_sample_2d_samplers_var, "sample_2d_samplers");
  }
  if state.uses_sample_3d {
    spv_module_append_name(*module, cast(u32) state.id_sample_3d_textures_var, "sample_3d_textures");
    spv_module_append_name(*module, cast(u32) state.id_sample_3d_samplers_var, "sample_3d_samplers");
  }
  if state.uses_write_2d spv_module_append_name(*module, cast(u32) state.id_write_2d_textures_var, "write_2d_textures");
  if state.uses_write_3d spv_module_append_name(*module, cast(u32) state.id_write_3d_textures_var, "write_3d_textures");
  for state.function_constants {
    spv_module_append_name(*module, cast(u32) it.id, it.name);
    if it.component_count <= 1 continue;
    suffixes : [4]string = .["x", "y", "z", "w"];
    for i: 0..it.component_count-1 spv_module_append_name(*module, cast(u32) it.component_ids[i], tprint("%_%", it.name, suffixes[i]));
  }
  for ps_infos {
    ps_info := it;
    spv_module_append_name(*module, cast(u32) ps_info.type_id, debug_type_name(*state, ps_info.name));
    st := find_struct(*state, ps_info.name);
    if st {
      for st.fields spv_module_append_member_name(*module, cast(u32) ps_info.type_id, cast(u32) it_index, it.name);
    }
  }
  for state.debug_names spv_module_append_name(*module, cast(u32) it.id, it.name);
  for state.debug_member_names spv_module_append_member_name(*module, cast(u32) it.type_id, cast(u32) it.member_index, it.name);
  spv_module_append_interface_var_decorations_binary(*module, state.input_vars);
  spv_module_append_interface_var_decorations_binary(*module, state.output_vars);
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.id, SPV_DECORATION_SPEC_ID, it.spec_id);
      continue;
    }
    for i: 0..it.component_count-1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.component_ids[i], SPV_DECORATION_SPEC_ID, it.spec_id + cast(u32) i);
    }
  }
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) root_var_id, SPV_DECORATION_BINDING, 0);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) root_var_id, SPV_DECORATION_DESCRIPTOR_SET, 0);
  if state.uses_sample_2d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_textures_var, SPV_DECORATION_BINDING, SAMPLE_2D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_samplers_var, SPV_DECORATION_BINDING, SAMPLE_2D_SAMPLERS_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_samplers_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_sample_3d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_textures_var, SPV_DECORATION_BINDING, SAMPLE_3D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_samplers_var, SPV_DECORATION_BINDING, SAMPLE_3D_SAMPLERS_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_samplers_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_write_2d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_BINDING, WRITE_2D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_write_3d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_BINDING, WRITE_3D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  spv_module_append_base_buffer_decorations_binary(*module, *state);
  spv_module_append_buffer_layout_decorations_binary(*module, *state);
  for ps_infos {
    ps_info := it;
    if ps_info.name == root_struct_name {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) ps_info.type_id, SPV_DECORATION_BLOCK);
    }
    st := find_struct(*state, ps_info.name);
    if !st continue;
    offset: s64 = 0;
    for st.fields {
      field := it;
      kind := spv_kind_from_ir_type(field.type);
      if field.type.kind == .POINTER {
        offset = align_up(offset, 8);
      } else {
        field_align := host_blit_align_for_kind(kind);
        if field_align <= 0 field_align = 4;
        offset = align_up(offset, field_align);
      }
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) ps_info.type_id, cast(u32) it_index, SPV_DECORATION_NON_WRITABLE);
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) ps_info.type_id, cast(u32) it_index, SPV_DECORATION_OFFSET, cast(u32) offset);
      matrix_stride := spv_matrix_stride_for_kind(kind);
      if matrix_stride > 0 {
        spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) ps_info.type_id, cast(u32) it_index, SPV_DECORATION_ROW_MAJOR);
        spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) ps_info.type_id, cast(u32) it_index, SPV_DECORATION_MATRIX_STRIDE, cast(u32) matrix_stride);
      }
      if field.type.kind == .POINTER offset += 8;
      else {
        size := byte_size_of_kind(kind);
        if size <= 0 size = 4;
        offset += size;
      }
    }
  }

  spv_module_append_common_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER);
  spv_module_append_numeric_constants_binary(*module, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_module_append_function_constant_defs_binary(*module, *state);
  if !function_constant_defs_ok return .[], false, function_constant_defs_diag;
  spv_module_append_sampled_image_decls_binary(*module, *state);
  spv_module_append_storage_image_decls_binary(*module, *state);
  for ps_infos spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_FORWARD_POINTER, cast(u32) it.ptr_type_id, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER);
  for state.buffers spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_FORWARD_POINTER, cast(u32) it.ptr_wrapper_type_id, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER);
  emitted_ps_structs: [..] string;
  for ps_infos {
    emit_ok, emit_diag := ps_emit_struct_type_decl_recursive_binary(*module, *state, *ps_infos, it.name, *emitted_ps_structs);
    if !emit_ok return .[], false, emit_diag;
  }
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) root_var_ptr_type_id, SPV_STORAGE_CLASS_STORAGE_BUFFER, cast(u32) root_info.type_id);
  for storage_struct_ptr_types spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_to_ptr_type_id, SPV_STORAGE_CLASS_STORAGE_BUFFER, cast(u32) it.ptr_type_id);
  for ps_infos spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_type_id, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER, cast(u32) it.type_id);
  for ptr_to_ptr_types spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_to_ptr_type_id, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER, cast(u32) it.ptr_type_id);
  for ptr_to_ptr_storage_types spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_to_ptr_type_id, SPV_STORAGE_CLASS_STORAGE_BUFFER, cast(u32) it.ptr_type_id);
  spv_module_append_buffer_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_PHYSICAL_STORAGE_BUFFER);
  for state.input_vars spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_INPUT);
  for state.output_vars spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_OUTPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) root_var_ptr_type_id, cast(u32) root_var_id, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_sampled_storage_image_vars_binary(*module, *state);
  spv_module_append_local_array_type_decls_binary(*module, *state);
  spv_module_append_null_constants_binary(*module, *state);
  spv_module_append_global_const_array_decls_binary(*module, *state);

  module.bound = cast(u32) state.next_id;
  spv_module_append_function_body(*module, *state, entry_label);
  return spv_serialize_module_binary(*module), true, diag;
}

emit_graphics_generic :: (stage: IR_SPV_Gen_Stage, source_name: string, input: IR_Struct, output: IR_Struct, args: [] IR_Function_Arg, body: *IR_Block, functions: [] IR_Function, function_constants: [] IR_Function_Constant, extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  analysis, analysis_ok, analysis_diag := spv_analyze_graphics_shader(stage, input, output, args, body, functions, extra_structs);
  if !analysis_ok return "", false, analysis_diag;
  if analysis.uses_pointer_abi {
    spvasm, ok, pointer_diag := emit_graphics_physical_pointer_abi(stage, source_name, input, output, args, body, functions, function_constants, extra_structs);
    return spvasm, ok, pointer_diag;
  }

  state: IR_SPV_Gen_State;
  state.emit_text = true;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, function_constants);
  if !function_constants_ok return "", false, function_constants_diag;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_write_3d = analysis.uses_write_3d;
  state.uses_sample_2d = analysis.uses_sample_2d;
  state.uses_sample_3d = analysis.uses_sample_3d;
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
        if field_type == {
        case .FLOAT2; field_align = 8;
        case .FLOAT3; #through;
        case .FLOAT4; #through;
        case .FLOAT2X2; #through;
        case .FLOAT3X3; #through;
        case .FLOAT4X4; field_align = 16;
        }
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
    spv_emit_load(*state, value_id, type_id, it.var_id);
    spv_emit_store(*state, dst.ptr_id, value_id);
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
  spv_append_var_ids(*entry_point_sb, state.global_const_arrays);
  if state.uses_sample_2d {
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_2d_samplers_var));
  }
  if state.uses_sample_3d {
    append(*entry_point_sb, " ", id_text(state.id_sample_3d_textures_var));
    append(*entry_point_sb, " ", id_text(state.id_sample_3d_samplers_var));
  }
  if state.uses_write_2d {
    append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  }
  if state.uses_write_3d {
    append(*entry_point_sb, " ", id_text(state.id_write_3d_textures_var));
  }
  append(*entry_point_sb, "\n");
  append_and_steal_buffers(*sb, *entry_point_sb);
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
  if state.uses_sample_3d {
    append(*sb, tprint("               OpName % \"sample_3d_textures\"\n", id_text(state.id_sample_3d_textures_var)));
    append(*sb, tprint("               OpName % \"sample_3d_samplers\"\n", id_text(state.id_sample_3d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  }
  if state.uses_write_3d {
    append(*sb, tprint("               OpName % \"write_3d_textures\"\n", id_text(state.id_write_3d_textures_var)));
  }
  spv_append_function_constant_names(*sb, *state);
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append_interface_var_decorations(*sb, state.input_vars);
  append_interface_var_decorations(*sb, state.output_vars);
  spv_append_function_constant_decorations(*sb, *state);
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);
  if state.uses_sample_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_textures_var), SAMPLE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_2d_samplers_var), SAMPLE_2D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_2d_samplers_var)));
  }
  if state.uses_sample_3d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_3d_textures_var), SAMPLE_3D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_3d_textures_var)));
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_sample_3d_samplers_var), SAMPLE_3D_SAMPLERS_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_sample_3d_samplers_var)));
  }
  if state.uses_write_2d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }
  if state.uses_write_3d {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(state.id_write_3d_textures_var), WRITE_3D_TEXTURES_BINDING));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(state.id_write_3d_textures_var)));
  }
  for state.uniform_blocks {
    uniform := it;
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(uniform.var_id), uniform.binding_index));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(uniform.var_id)));
    append(*sb, tprint("               OpDecorate % Block\n", id_text(uniform.struct_type_id)));
    for uniform.fields {
      if it.is_array append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(it.array_type_id), it.array_stride));
      append(*sb, tprint("               OpMemberDecorate % % Offset %\n", id_text(uniform.struct_type_id), it.index, it.offset));
      matrix_stride := spv_matrix_stride_for_kind(it.type);
      if matrix_stride > 0 {
        append(*sb, tprint("               OpMemberDecorate % % RowMajor\n", id_text(uniform.struct_type_id), it.index));
        append(*sb, tprint("               OpMemberDecorate % % MatrixStride %\n", id_text(uniform.struct_type_id), it.index, matrix_stride));
      }
    }
  }

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  spv_append_numeric_constants(*sb, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_append_function_constant_defs(*sb, *state);
  if !function_constant_defs_ok return "", false, function_constant_defs_diag;
  spv_append_sample_2d_type_decls(*sb, *state);
  spv_append_sample_3d_type_decls(*sb, *state);
  spv_append_write_2d_type_decls(*sb, *state);
  spv_append_write_3d_type_decls(*sb, *state);
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
    append_and_steal_buffers(*sb, *type_line);
    append(*sb, tprint("% = OpTypePointer Uniform %\n", id_text(it.ptr_uniform_struct_type_id), id_text(it.struct_type_id)));
  }
  spv_append_buffer_type_decls(*sb, *state, "StorageBuffer");
  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  spv_append_buffer_vars(*sb, *state, "StorageBuffer");
  for state.uniform_blocks append(*sb, tprint("% = OpVariable % Uniform\n", id_text(it.var_id), id_text(it.ptr_uniform_struct_type_id)));
  spv_append_sample_2d_vars(*sb, *state);
  spv_append_sample_3d_vars(*sb, *state);
  spv_append_write_2d_vars(*sb, *state);
  spv_append_write_3d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);
  spv_append_global_const_array_decls(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

emit_graphics_generic_binary :: (stage: IR_SPV_Gen_Stage, source_name: string, input: IR_Struct, output: IR_Struct, args: [] IR_Function_Arg, body: *IR_Block, functions: [] IR_Function, function_constants: [] IR_Function_Constant, extra_structs: [] IR_Struct) -> (spv: [] u8, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .[], false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  analysis, analysis_ok, analysis_diag := spv_analyze_graphics_shader(stage, input, output, args, body, functions, extra_structs);
  if !analysis_ok return .[], false, analysis_diag;
  if analysis.uses_pointer_abi {
    pointer_spv, pointer_ok, pointer_diag := emit_graphics_physical_pointer_abi_binary(stage, source_name, input, output, args, body, functions, function_constants, extra_structs);
    return pointer_spv, pointer_ok, pointer_diag;
  }

  state: IR_SPV_Gen_State;
  state.record_binary = true;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, function_constants);
  if !function_constants_ok return .[], false, function_constants_diag;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;
  state.uses_sample_2d = analysis.uses_sample_2d;
  state.uses_sample_3d = analysis.uses_sample_3d;
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_write_3d = analysis.uses_write_3d;
  init_ok, init_diag := init_base(*state, analysis.expanded_buffers, 1);
  if !init_ok return .[], false, init_diag;

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
        array_stride = 16;
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
        if field_type == {
        case .FLOAT2; field_align = 8;
        case .FLOAT3; #through;
        case .FLOAT4; #through;
        case .FLOAT2X2; #through;
        case .FLOAT3X3; #through;
        case .FLOAT4X4; field_align = 16;
        }
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
  if !input_ok return .[], false, input_diag;
  output_local, output_ok, output_diag := alloc_local_struct(*state, "o", output.name);
  if !output_ok return .[], false, output_diag;

  for state.input_vars {
    dst := find_local_struct_field(input_local, it.name);
    if !dst return_err("SPIR-V backend: input local struct missing field '%'.", it.name);
    value_id := new_id(*state);
    type_id := type_id_from_kind(*state, it.type);
    spv_emit_load(*state, value_id, type_id, it.var_id);
    spv_emit_store(*state, dst.ptr_id, value_id);
  }

  block_ok, block_terminated, block_diag := emit_stmt_block(*state, body);
  if !block_ok return .[], false, block_diag;
  if !block_terminated {
    ret_ok, ret_diag := emit_output_return_from_struct(*state, output_local);
    if !ret_ok return .[], false, ret_diag;
  }

  entry_model := ifx stage == .VERTEX then "Vertex" else "Fragment";
  entry_name := ifx stage == .VERTEX then "VertexMain" else "FragmentMain";

  module: SPV_Module;
  spv_module_append_capabilities_binary(*module, *state);
  spv_module_append_ext_inst_import(*module, cast(u32) state.id_extinst, "GLSL.std.450");
  spv_module_append_words(*module, .MEMORY_MODEL, SPV_OP_MEMORY_MODEL, SPV_ADDRESSING_MODEL_LOGICAL, SPV_MEMORY_MODEL_GLSL450);
  entry_execution_model: u32 = ifx stage == .VERTEX then cast(u32) SPV_EXECUTION_MODEL_VERTEX else cast(u32) SPV_EXECUTION_MODEL_FRAGMENT;
  interface_ids: [..]u32;
  for state.input_vars array_add(*interface_ids, cast(u32) it.var_id);
  for state.output_vars array_add(*interface_ids, cast(u32) it.var_id);
  for state.buffers array_add(*interface_ids, cast(u32) it.var_id);
  for state.uniform_blocks array_add(*interface_ids, cast(u32) it.var_id);
  for state.global_const_arrays array_add(*interface_ids, cast(u32) it.var_id);
  if state.uses_sample_2d {
    array_add(*interface_ids, cast(u32) state.id_sample_2d_textures_var, cast(u32) state.id_sample_2d_samplers_var);
  }
  if state.uses_sample_3d {
    array_add(*interface_ids, cast(u32) state.id_sample_3d_textures_var, cast(u32) state.id_sample_3d_samplers_var);
  }
  if state.uses_write_2d array_add(*interface_ids, cast(u32) state.id_write_2d_textures_var);
  if state.uses_write_3d array_add(*interface_ids, cast(u32) state.id_write_3d_textures_var);
  spv_module_append_entry_point(*module, entry_execution_model, cast(u32) state.id_main, entry_name, interface_ids);
  if stage == .FRAGMENT {
    spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_ORIGIN_UPPER_LEFT);
  }
  spv_module_append_source(*module, SPV_SOURCE_LANGUAGE_UNKNOWN, 100000);
  spv_module_append_name(*module, cast(u32) state.id_main, entry_name);
  for state.input_vars spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  for state.output_vars spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  for state.buffers spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  for state.uniform_blocks spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  if state.uses_sample_2d {
    spv_module_append_name(*module, cast(u32) state.id_sample_2d_textures_var, "sample_2d_textures");
    spv_module_append_name(*module, cast(u32) state.id_sample_2d_samplers_var, "sample_2d_samplers");
  }
  if state.uses_sample_3d {
    spv_module_append_name(*module, cast(u32) state.id_sample_3d_textures_var, "sample_3d_textures");
    spv_module_append_name(*module, cast(u32) state.id_sample_3d_samplers_var, "sample_3d_samplers");
  }
  if state.uses_write_2d spv_module_append_name(*module, cast(u32) state.id_write_2d_textures_var, "write_2d_textures");
  if state.uses_write_3d spv_module_append_name(*module, cast(u32) state.id_write_3d_textures_var, "write_3d_textures");
  for state.function_constants {
    spv_module_append_name(*module, cast(u32) it.id, it.name);
    if it.component_count <= 1 continue;
    suffixes : [4]string = .["x", "y", "z", "w"];
    for i: 0..it.component_count-1 {
      spv_module_append_name(*module, cast(u32) it.component_ids[i], tprint("%_%", it.name, suffixes[i]));
    }
  }
  for state.debug_names spv_module_append_name(*module, cast(u32) it.id, it.name);
  for state.debug_member_names spv_module_append_member_name(*module, cast(u32) it.type_id, cast(u32) it.member_index, it.name);
  spv_module_append_interface_var_decorations_binary(*module, state.input_vars);
  spv_module_append_interface_var_decorations_binary(*module, state.output_vars);
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.id, SPV_DECORATION_SPEC_ID, it.spec_id);
      continue;
    }
    for i: 0..it.component_count-1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.component_ids[i], SPV_DECORATION_SPEC_ID, it.spec_id + cast(u32) i);
    }
  }
  spv_module_append_base_buffer_decorations_binary(*module, *state);
  spv_module_append_buffer_layout_decorations_binary(*module, *state);
  spv_module_append_buffer_binding_decorations_binary(*module, *state);
  if state.uses_sample_2d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_textures_var, SPV_DECORATION_BINDING, SAMPLE_2D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_samplers_var, SPV_DECORATION_BINDING, SAMPLE_2D_SAMPLERS_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_2d_samplers_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_sample_3d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_textures_var, SPV_DECORATION_BINDING, SAMPLE_3D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_samplers_var, SPV_DECORATION_BINDING, SAMPLE_3D_SAMPLERS_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_sample_3d_samplers_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_write_2d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_BINDING, WRITE_2D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_write_3d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_BINDING, WRITE_3D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  for state.uniform_blocks {
    uniform := it;
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) uniform.var_id, SPV_DECORATION_BINDING, cast(u32) uniform.binding_index);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) uniform.var_id, SPV_DECORATION_DESCRIPTOR_SET, 0);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) uniform.struct_type_id, SPV_DECORATION_BLOCK);
    for uniform.fields {
      if it.is_array spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.array_type_id, SPV_DECORATION_ARRAY_STRIDE, cast(u32) it.array_stride);
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) uniform.struct_type_id, cast(u32) it.index, SPV_DECORATION_OFFSET, cast(u32) it.offset);
      matrix_stride := spv_matrix_stride_for_kind(it.type);
      if matrix_stride > 0 {
        spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) uniform.struct_type_id, cast(u32) it.index, SPV_DECORATION_ROW_MAJOR);
        spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_MEMBER_DECORATE, cast(u32) uniform.struct_type_id, cast(u32) it.index, SPV_DECORATION_MATRIX_STRIDE, cast(u32) matrix_stride);
      }
    }
  }

  sb: String_Builder;
  spv_module_append_common_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_numeric_constants_binary(*module, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_module_append_function_constant_defs_binary(*module, *state);
  if !function_constant_defs_ok return .[], false, function_constant_defs_diag;
  spv_module_append_sampled_image_decls_binary(*module, *state);
  spv_module_append_storage_image_decls_binary(*module, *state);
  spv_module_append_uniform_block_decls_binary(*module, *state);
  spv_module_append_buffer_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  for state.input_vars spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_INPUT);
  for state.output_vars spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_OUTPUT);
  spv_module_append_buffer_vars_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_uniform_block_vars_binary(*module, *state);
  spv_module_append_sampled_storage_image_vars_binary(*module, *state);
  spv_module_append_local_array_type_decls_binary(*module, *state);
  spv_module_append_null_constants_binary(*module, *state);
  spv_module_append_global_const_array_decls_binary(*module, *state);

  _ = sb;
  module.bound = cast(u32) state.next_id;
  spv_module_append_function_body(*module, *state, entry_label);
  return spv_serialize_module_binary(*module), true, diag;
}

// -----------------------------------------------------------------------------
// Module Assembly
// -----------------------------------------------------------------------------

IR_SPV_Compute_Analysis :: struct {
  bound_value: u32;
  uses_write_2d: bool;
  uses_write_3d: bool;
  uses_sample_2d: bool;
  uses_sample_3d: bool;
  expanded_buffers: [..] IR_Compute_Buffer;
}

IR_SPV_Graphics_Analysis :: struct {
  uses_pointer_abi: bool;
  uses_write_2d: bool;
  uses_write_3d: bool;
  uses_sample_2d: bool;
  uses_sample_3d: bool;
  expanded_buffers: [..] IR_Compute_Buffer;
}

spv_analyze_builtin_usage_expr :: (expr: *IR_Expr, uses_write_2d: *bool, uses_write_3d: *bool, uses_sample_2d: *bool, uses_sample_3d: *bool) {
  if !expr return;
  if expr.kind == .CALL {
    call_builtin := call_builtin_kind_for_expr(expr);
    if call_builtin == .WRITE_2D uses_write_2d.* = true;
    if call_builtin == .WRITE_3D uses_write_3d.* = true;
    if call_builtin == .SAMPLE_2D uses_sample_2d.* = true;
    if call_builtin == .SAMPLE_3D uses_sample_3d.* = true;
  }
  spv_analyze_builtin_usage_expr(expr.left, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
  spv_analyze_builtin_usage_expr(expr.right, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
  for expr.args spv_analyze_builtin_usage_expr(it, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
}

spv_analyze_builtin_usage_block :: (block: *IR_Block, uses_write_2d: *bool, uses_write_3d: *bool, uses_sample_2d: *bool, uses_sample_3d: *bool) {
  if !block return;
  for block.statements {
    stmt := it;
    if stmt.kind == {
      case .DECL; {
        spv_analyze_builtin_usage_expr(stmt.decl_init, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .BINARY; {
        spv_analyze_builtin_usage_expr(stmt.binary_left, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_expr(stmt.binary_right, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .IF; {
        spv_analyze_builtin_usage_expr(stmt.if_condition, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_block(stmt.if_then, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_block(stmt.if_else, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .SWITCH; {
        spv_analyze_builtin_usage_expr(stmt.switch_condition, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        for stmt.switch_cases {
          spv_analyze_builtin_usage_expr(it.condition, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
          spv_analyze_builtin_usage_block(it.body, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        }
      }
      case .FOR; {
        spv_analyze_builtin_usage_expr(stmt.for_start, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_expr(stmt.for_end, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_block(stmt.for_body, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .WHILE; {
        spv_analyze_builtin_usage_expr(stmt.while_condition, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
        spv_analyze_builtin_usage_block(stmt.while_body, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .CALL; {
        spv_analyze_builtin_usage_expr(stmt.call_expr, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
      }
      case .RETURN; {
        spv_analyze_builtin_usage_expr(stmt.return_expr, uses_write_2d, uses_write_3d, uses_sample_2d, uses_sample_3d);
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

  spv_analyze_builtin_usage_block(body, *out.uses_write_2d, *out.uses_write_3d, *out.uses_sample_2d, *out.uses_sample_3d);
  for functions spv_analyze_builtin_usage_block(*it.body, *out.uses_write_2d, *out.uses_write_3d, *out.uses_sample_2d, *out.uses_sample_3d);
  if out.uses_sample_2d && out.uses_sample_3d {
    return_err("SPIR-V backend: sample_2d and sample_3d cannot currently be used in the same shader.");
  }
  if out.uses_write_2d && out.uses_write_3d {
    return_err("SPIR-V backend: write_2d and write_3d cannot currently be used in the same shader.");
  }

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

  spv_analyze_builtin_usage_block(*shader.body, *out.uses_write_2d, *out.uses_write_3d, *out.uses_sample_2d, *out.uses_sample_3d);
  for shader.functions {
    spv_analyze_builtin_usage_block(*it.body, *out.uses_write_2d, *out.uses_write_3d, *out.uses_sample_2d, *out.uses_sample_3d);
  }
  if out.uses_sample_2d && out.uses_sample_3d {
    return_err("SPIR-V backend: sample_2d and sample_3d cannot currently be used in the same shader.");
  }
  if out.uses_write_2d && out.uses_write_3d {
    return_err("SPIR-V backend: write_2d and write_3d cannot currently be used in the same shader.");
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
  state.emit_text = true;
  state.stage = .COMPUTE;
  state.debug_type_prefix = tprint("compute_%", shader.source_name);
  state.functions = shader.functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, shader.function_constants);
  if !function_constants_ok return "", false, function_constants_diag;
  for shader.extra_structs array_add(*state.extra_structs, it);
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_write_3d = analysis.uses_write_3d;
  state.uses_sample_2d = analysis.uses_sample_2d;
  state.uses_sample_3d = analysis.uses_sample_3d;
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
  spv_append_var_ids(*entry_point_sb, state.global_const_arrays);
  if state.uses_write_2d append(*entry_point_sb, " ", id_text(state.id_write_2d_textures_var));
  if state.uses_write_3d append(*entry_point_sb, " ", id_text(state.id_write_3d_textures_var));
  append(*entry_point_sb, "\n");
  append_and_steal_buffers(*sb, *entry_point_sb);
  append(*sb, tprint("OpExecutionMode % LocalSize 1 1 1\n", id_text(state.id_main)));
  append(*sb, "OpSource Unknown 100000\n");
  append(*sb, tprint("OpName % \"ComputeMain\"\n", id_text(state.id_main)));
  append(*sb, tprint("OpName % \"gl_GlobalInvocationID\"\n", id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("OpName % \"gl_LocalInvocationID\"\n", id_text(state.id_gl_local_invocation_id)));
  append(*sb, tprint("OpName % \"gl_WorkGroupID\"\n", id_text(state.id_gl_workgroup_id)));
  append(*sb, tprint("OpName % \"gl_LocalInvocationIndex\"\n", id_text(state.id_gl_local_invocation_index)));
  for state.buffers append(*sb, tprint("OpName % \"%\"\n", id_text(it.var_id), it.name));
  if state.uses_write_2d append(*sb, tprint("OpName % \"write_2d_textures\"\n", id_text(state.id_write_2d_textures_var)));
  if state.uses_write_3d append(*sb, tprint("OpName % \"write_3d_textures\"\n", id_text(state.id_write_3d_textures_var)));
  spv_append_function_constant_names(*sb, *state);
  for state.debug_names append(*sb, tprint("OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append(*sb, tprint("OpDecorate % BuiltIn GlobalInvocationId\n", id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("OpDecorate % BuiltIn LocalInvocationId\n", id_text(state.id_gl_local_invocation_id)));
  append(*sb, tprint("OpDecorate % BuiltIn WorkgroupId\n", id_text(state.id_gl_workgroup_id)));
  append(*sb, tprint("OpDecorate % BuiltIn LocalInvocationIndex\n", id_text(state.id_gl_local_invocation_index)));
  spv_append_function_constant_decorations(*sb, *state);
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);
  if state.uses_write_2d {
    append(*sb, tprint("OpDecorate % Binding %\n", id_text(state.id_write_2d_textures_var), WRITE_2D_TEXTURES_BINDING));
    append(*sb, tprint("OpDecorate % DescriptorSet 0\n", id_text(state.id_write_2d_textures_var)));
  }
  if state.uses_write_3d {
    append(*sb, tprint("OpDecorate % Binding %\n", id_text(state.id_write_3d_textures_var), WRITE_3D_TEXTURES_BINDING));
    append(*sb, tprint("OpDecorate % DescriptorSet 0\n", id_text(state.id_write_3d_textures_var)));
  }

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  // OpTypeArray length operands must be declared constants beforehand.
  spv_append_numeric_constants(*sb, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_append_function_constant_defs(*sb, *state);
  if !function_constant_defs_ok return "", false, function_constant_defs_diag;
  spv_append_write_2d_type_decls(*sb, *state);
  spv_append_write_3d_type_decls(*sb, *state);
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_global_invocation_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_local_invocation_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_workgroup_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_local_invocation_index), id_text(state.id_ptr_input_uint)));
  spv_append_buffer_type_decls(*sb, *state, "StorageBuffer");
  spv_append_buffer_vars(*sb, *state, "StorageBuffer");
  spv_append_write_2d_vars(*sb, *state);
  spv_append_write_3d_vars(*sb, *state);
  spv_append_local_array_type_decls(*sb, *state);
  spv_append_null_constants(*sb, *state);
  spv_append_global_const_array_decls(*sb, *state);

  _ = body_terminated;
  spv_append_function_and_body(*sb, *state, entry_label, "      ", "         ");

  out := builder_to_string(*sb);
  return out, true, diag;
}

emit_compute_generic_uint_buffer_binary :: (shader: *IR_Compute_Shader) -> (spv: [] u8, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .[], false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  analysis, analysis_ok, analysis_diag := spv_analyze_compute_shader(shader.*);
  if !analysis_ok return .[], false, analysis_diag;

  state: IR_SPV_Gen_State;
  state.record_binary = true;
  state.stage = .COMPUTE;
  state.debug_type_prefix = tprint("compute_%", shader.source_name);
  state.functions = shader.functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, shader.function_constants);
  if !function_constants_ok return .[], false, function_constants_diag;
  for shader.extra_structs array_add(*state.extra_structs, it);
  state.uses_write_2d = analysis.uses_write_2d;
  state.uses_write_3d = analysis.uses_write_3d;
  state.uses_sample_2d = analysis.uses_sample_2d;
  state.uses_sample_3d = analysis.uses_sample_3d;
  init_ok, init_diag := init_base(*state, analysis.expanded_buffers, analysis.bound_value);
  if !init_ok return .[], false, init_diag;

  entry_label := new_id(*state);
  body_ok, body_terminated, body_diag := emit_stmt_block(*state, *shader.body);
  if !body_ok return .[], false, body_diag;
  _ = body_terminated;

  module: SPV_Module;
  spv_module_append_capabilities_binary(*module, *state);
  spv_module_append_ext_inst_import(*module, cast(u32) state.id_extinst, "GLSL.std.450");
  spv_module_append_words(*module, .MEMORY_MODEL, SPV_OP_MEMORY_MODEL, SPV_ADDRESSING_MODEL_LOGICAL, SPV_MEMORY_MODEL_GLSL450);

  interface_ids: [..]u32;
  array_add(*interface_ids,
            cast(u32) state.id_gl_global_invocation_id,
            cast(u32) state.id_gl_local_invocation_id,
            cast(u32) state.id_gl_workgroup_id,
            cast(u32) state.id_gl_local_invocation_index);
  for state.buffers array_add(*interface_ids, cast(u32) it.var_id);
  for state.global_const_arrays array_add(*interface_ids, cast(u32) it.var_id);
  if state.uses_write_2d array_add(*interface_ids, cast(u32) state.id_write_2d_textures_var);
  if state.uses_write_3d array_add(*interface_ids, cast(u32) state.id_write_3d_textures_var);
  spv_module_append_entry_point(*module, SPV_EXECUTION_MODEL_GLCOMPUTE, cast(u32) state.id_main, shader.entry_name, interface_ids);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_LOCAL_SIZE, 1, 1, 1);
  spv_module_append_source(*module, SPV_SOURCE_LANGUAGE_UNKNOWN, 100000);
  spv_module_append_name(*module, cast(u32) state.id_main, "ComputeMain");
  spv_module_append_name(*module, cast(u32) state.id_gl_global_invocation_id, "gl_GlobalInvocationID");
  spv_module_append_name(*module, cast(u32) state.id_gl_local_invocation_id, "gl_LocalInvocationID");
  spv_module_append_name(*module, cast(u32) state.id_gl_workgroup_id, "gl_WorkGroupID");
  spv_module_append_name(*module, cast(u32) state.id_gl_local_invocation_index, "gl_LocalInvocationIndex");
  for state.buffers spv_module_append_name(*module, cast(u32) it.var_id, it.name);
  if state.uses_write_2d spv_module_append_name(*module, cast(u32) state.id_write_2d_textures_var, "write_2d_textures");
  if state.uses_write_3d spv_module_append_name(*module, cast(u32) state.id_write_3d_textures_var, "write_3d_textures");
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_name(*module, cast(u32) it.id, it.name);
      continue;
    }
    suffixes : [4]string = .["x", "y", "z", "w"];
    for i: 0..it.component_count-1 {
      spv_module_append_name(*module, cast(u32) it.component_ids[i], tprint("%_%", it.name, suffixes[i]));
    }
  }
  for state.debug_names spv_module_append_name(*module, cast(u32) it.id, it.name);
  for state.debug_member_names spv_module_append_member_name(*module, cast(u32) it.type_id, cast(u32) it.member_index, it.name);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_global_invocation_id, SPV_DECORATION_BUILTIN, SPV_BUILTIN_GLOBAL_INVOCATION_ID);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_local_invocation_id, SPV_DECORATION_BUILTIN, SPV_BUILTIN_LOCAL_INVOCATION_ID);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_workgroup_id, SPV_DECORATION_BUILTIN, SPV_BUILTIN_WORKGROUP_ID);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_local_invocation_index, SPV_DECORATION_BUILTIN, SPV_BUILTIN_LOCAL_INVOCATION_INDEX);
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.id, SPV_DECORATION_SPEC_ID, it.spec_id);
      continue;
    }
    for i: 0..it.component_count-1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.component_ids[i], SPV_DECORATION_SPEC_ID, it.spec_id + cast(u32) i);
    }
  }
  spv_module_append_base_buffer_decorations_binary(*module, *state);
  spv_module_append_buffer_layout_decorations_binary(*module, *state);
  spv_module_append_buffer_binding_decorations_binary(*module, *state);
  if state.uses_write_2d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_BINDING, WRITE_2D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_2d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }
  if state.uses_write_3d {
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_BINDING, WRITE_3D_TEXTURES_BINDING);
    spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_write_3d_textures_var, SPV_DECORATION_DESCRIPTOR_SET, 0);
  }

  sb: String_Builder;
  spv_module_append_common_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_numeric_constants_binary(*module, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_module_append_function_constant_defs_binary(*module, *state);
  if !function_constant_defs_ok return .[], false, function_constant_defs_diag;
  spv_module_append_storage_image_decls_binary(*module, *state);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_v3uint, cast(u32) state.id_gl_global_invocation_id, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_v3uint, cast(u32) state.id_gl_local_invocation_id, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_v3uint, cast(u32) state.id_gl_workgroup_id, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_uint, cast(u32) state.id_gl_local_invocation_index, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_buffer_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_buffer_vars_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_sampled_storage_image_vars_binary(*module, *state);
  spv_module_append_local_array_type_decls_binary(*module, *state);
  spv_module_append_null_constants_binary(*module, *state);
  spv_module_append_global_const_array_decls_binary(*module, *state);

  _ = sb;
  module.bound = cast(u32) state.next_id;
  spv_module_append_function_body(*module, *state, entry_label);
  return spv_serialize_module_binary(*module), true, diag;
}

emit_mesh_set_outputs_ext :: (s: *IR_SPV_Gen_State, vertex_count_id: s64, primitive_count_id: s64) {
  if s.record_binary {
    words: [..]u32;
    array_add(*words, cast(u32) vertex_count_id, cast(u32) primitive_count_id);
    array_add(*s.op_insts, .{opcode = SPV_OP_SET_MESH_OUTPUTS_EXT, words = words});
  }
  if s.emit_text {
    append(*s.op_lines, tprint("               OpSetMeshOutputsEXT % %\n", id_text(vertex_count_id), id_text(primitive_count_id)));
  }
  s.last_op_is_terminator = false;
}

emit_mesh_store_array_value :: (s: *IR_SPV_Gen_State, ptr_elem_type_id: s64, array_var_id: s64, index_id: s64, value_id: s64) {
  ptr_id := new_id(s);
  spv_emit_access_chain(s, ptr_id, ptr_elem_type_id, array_var_id, .[index_id]);
  spv_emit_store(s, ptr_id, value_id);
}

emit_task_set_mesh_groups_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if s.stage != .TASK return false, make_diag("task_set_mesh_groups is currently task-stage only.");
  if args.count != 3 return false, make_diag("task_set_mesh_groups expects 3 args.");
  group_ids: [3]s64;
  for args {
    value_id, value_type, value_ok, value_diag := emit_expr(s, it);
    if !value_ok return false, value_diag;
    value_id, _, value_ok, value_diag = coerce_to_exact_kind(s, value_id, value_type, .UINT);
    if !value_ok return false, value_diag;
    group_ids[it_index] = value_id;
  }
  if s.uses_task_payload {
    add_op(s, "OpEmitMeshTasksEXT", group_ids[0], group_ids[1], group_ids[2], s.id_task_payload_var, is_terminator=true);
  } else {
    add_op(s, "OpEmitMeshTasksEXT", group_ids[0], group_ids[1], group_ids[2], is_terminator=true);
  }
  return true, {};
}

emit_payload_type_decls_binary :: (module: *SPV_Module, state: *IR_SPV_Gen_State) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }
  if !state.payload_struct_name.count return_err("payload struct name is missing.");

  payload_struct := find_struct(state, state.payload_struct_name);
  if !payload_struct return_err("payload struct '%' is missing from IR extra structs.", state.payload_struct_name);

  inst: SPV_Inst;
  inst.opcode = SPV_OP_TYPE_STRUCT;
  array_add(*inst.words, cast(u32) state.id_task_payload_struct);
  for payload_struct.fields {
    field_kind := spv_kind_from_ir_type(it.type);
    if field_kind == .UNKNOWN || field_kind == .STRUCT return_err("payload field '%.%' type '%' is not yet supported.", payload_struct.name, it.name, it.type.display_name);
    field_type_id := type_id_from_kind(state, field_kind);
    if field_type_id == 0 return_err("payload field '%.%' type '%' has no SPIR-V type id.", payload_struct.name, it.name, field_kind);
    array_add(*inst.words, cast(u32) field_type_id);
    add_debug_member_name(state, state.id_task_payload_struct, it_index, it.name);
  }
  spv_module_append_inst(module, .TYPES_CONSTANTS_GLOBALS, inst);
  spv_module_append_words(module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_task_payload_struct, SPV_STORAGE_CLASS_TASK_PAYLOAD_WORKGROUP_EXT, cast(u32) state.id_task_payload_struct);
  for state.task_payload_field_ptr_types {
    field_type_id := type_id_from_kind(state, it.kind);
    if field_type_id == 0 return_err("payload field pointer kind '%' has no SPIR-V type id.", it.kind);
    spv_module_append_words(module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.type_id, SPV_STORAGE_CLASS_TASK_PAYLOAD_WORKGROUP_EXT, cast(u32) field_type_id);
  }
  spv_module_append_words(module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_task_payload_struct, cast(u32) state.id_task_payload_var, SPV_STORAGE_CLASS_TASK_PAYLOAD_WORKGROUP_EXT);
  return true, {};
}

emit_mesh_set_output_counts_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if s.stage != .MESH return false, make_diag("mesh_set_output_counts is currently mesh-stage only.");
  if args.count != 2 return false, make_diag("mesh_set_output_counts expects 2 args.");
  vertex_count_id, vertex_count_type, vertex_count_ok, vertex_count_diag := emit_expr(s, args[0]);
  if !vertex_count_ok return false, vertex_count_diag;
  vertex_count_id, _, vertex_count_ok, vertex_count_diag = coerce_to_exact_kind(s, vertex_count_id, vertex_count_type, .UINT);
  if !vertex_count_ok return false, vertex_count_diag;
  primitive_count_id, primitive_count_type, primitive_count_ok, primitive_count_diag := emit_expr(s, args[1]);
  if !primitive_count_ok return false, primitive_count_diag;
  primitive_count_id, _, primitive_count_ok, primitive_count_diag = coerce_to_exact_kind(s, primitive_count_id, primitive_count_type, .UINT);
  if !primitive_count_ok return false, primitive_count_diag;
  emit_mesh_set_outputs_ext(s, vertex_count_id, primitive_count_id);
  return true, {};
}

emit_mesh_set_vertex_position_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if s.stage != .MESH return false, make_diag("mesh_set_vertex_position is currently mesh-stage only.");
  if args.count != 2 return false, make_diag("mesh_set_vertex_position expects 2 args.");
  index_id, index_type, index_ok, index_diag := emit_expr(s, args[0]);
  if !index_ok return false, index_diag;
  index_id, _, index_ok, index_diag = coerce_to_exact_kind(s, index_id, index_type, .UINT);
  if !index_ok return false, index_diag;
  value_id, value_type, value_ok, value_diag := emit_expr(s, args[1]);
  if !value_ok return false, value_diag;
  value_id, _, value_ok, value_diag = coerce_to_exact_kind(s, value_id, value_type, .FLOAT4);
  if !value_ok return false, value_diag;
  emit_mesh_store_array_value(s, s.id_ptr_output_mesh_position, s.id_mesh_positions_var, index_id, value_id);
  return true, {};
}

emit_mesh_set_vertex_color_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if s.stage != .MESH return false, make_diag("mesh_set_vertex_color is currently mesh-stage only.");
  if args.count != 2 return false, make_diag("mesh_set_vertex_color expects 2 args.");
  index_id, index_type, index_ok, index_diag := emit_expr(s, args[0]);
  if !index_ok return false, index_diag;
  index_id, _, index_ok, index_diag = coerce_to_exact_kind(s, index_id, index_type, .UINT);
  if !index_ok return false, index_diag;
  value_id, value_type, value_ok, value_diag := emit_expr(s, args[1]);
  if !value_ok return false, value_diag;
  value_id, _, value_ok, value_diag = coerce_to_exact_kind(s, value_id, value_type, .FLOAT3);
  if !value_ok return false, value_diag;
  emit_mesh_store_array_value(s, s.id_ptr_output_mesh_color, s.id_mesh_colors_var, index_id, value_id);
  return true, {};
}

emit_mesh_set_triangle_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if s.stage != .MESH return false, make_diag("mesh_set_triangle is currently mesh-stage only.");
  if args.count != 4 return false, make_diag("mesh_set_triangle expects 4 args.");
  prim_index_id, prim_index_type, prim_index_ok, prim_index_diag := emit_expr(s, args[0]);
  if !prim_index_ok return false, prim_index_diag;
  prim_index_id, _, prim_index_ok, prim_index_diag = coerce_to_exact_kind(s, prim_index_id, prim_index_type, .UINT);
  if !prim_index_ok return false, prim_index_diag;

  index_ids: [3]s64;
  for i: 1..3 {
    value_id, value_type, value_ok, value_diag := emit_expr(s, args[i]);
    if !value_ok return false, value_diag;
    value_id, _, value_ok, value_diag = coerce_to_exact_kind(s, value_id, value_type, .UINT);
    if !value_ok return false, value_diag;
    index_ids[i-1] = value_id;
  }

  triangle_value_id := add_op(s, new_id(s), "OpCompositeConstruct", s.id_v3uint, index_ids[0], index_ids[1], index_ids[2]);
  emit_mesh_store_array_value(s, s.id_ptr_output_mesh_triangle_indices, s.id_mesh_triangle_indices_var, prim_index_id, triangle_value_id);
  return true, {};
}

emit_mesh_generic_binary :: (shader: *IR_Mesh_Shader) -> (spv: [] u8, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .[], false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  assert(shader != null);

  state: IR_SPV_Gen_State;
  state.record_binary = true;
  state.stage = .MESH;
  state.debug_type_prefix = tprint("mesh_%", shader.source_name);
  state.functions = shader.functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, shader.function_constants);
  if !function_constants_ok return .[], false, function_constants_diag;
  for shader.extra_structs array_add(*state.extra_structs, it);
  init_ok, init_diag := init_base(*state, .[], 1);
  if !init_ok return .[], false, init_diag;

  state.id_mesh_positions_array_type = new_id(*state);
  state.id_ptr_output_mesh_positions_array = new_id(*state);
  state.id_ptr_output_mesh_position = new_id(*state);
  state.id_mesh_positions_var = new_id(*state);
  state.id_mesh_colors_array_type = new_id(*state);
  state.id_ptr_output_mesh_colors_array = new_id(*state);
  state.id_ptr_output_mesh_color = new_id(*state);
  state.id_mesh_colors_var = new_id(*state);
  state.id_mesh_triangle_indices_array_type = new_id(*state);
  state.id_ptr_output_mesh_triangle_indices_array = new_id(*state);
  state.id_ptr_output_mesh_triangle_indices = new_id(*state);
  state.id_mesh_triangle_indices_var = new_id(*state);
  state.id_task_payload_struct = new_id(*state);
  state.id_ptr_task_payload_struct = new_id(*state);
  state.id_task_payload_var = new_id(*state);
  mesh_vertex_count_const := get_i32_const(*state, 3);
  mesh_primitive_count_const := get_i32_const(*state, 1);

  add_debug_name(*state, state.id_mesh_positions_var, "gl_Position");
  add_debug_name(*state, state.id_mesh_colors_var, "verts_color");
  add_debug_name(*state, state.id_mesh_triangle_indices_var, "primitive_triangle_indices");

  entry_label := new_id(*state);
  block_ok, block_terminated, block_diag := emit_stmt_block(*state, *shader.body);
  if !block_ok return .[], false, block_diag;
  if !block_terminated spv_emit_terminator0(*state, "OpReturn");

  module: SPV_Module;
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_SHADER);
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_MESH_SHADING_EXT);
  if state_uses_int64(*state) spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_INT64);
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_FLOAT16);
  spv_module_append_extension(*module, "SPV_EXT_mesh_shader");
  spv_module_append_ext_inst_import(*module, cast(u32) state.id_extinst, "GLSL.std.450");
  spv_module_append_words(*module, .MEMORY_MODEL, SPV_OP_MEMORY_MODEL, SPV_ADDRESSING_MODEL_LOGICAL, SPV_MEMORY_MODEL_GLSL450);
  interface_ids: [..]u32;
  array_add(*interface_ids,
    cast(u32) state.id_gl_workgroup_id,
    cast(u32) state.id_mesh_positions_var,
    cast(u32) state.id_mesh_colors_var,
    cast(u32) state.id_mesh_triangle_indices_var);
  if state.uses_mesh_payload array_add(*interface_ids, cast(u32) state.id_task_payload_var);
  spv_module_append_entry_point(*module, SPV_EXECUTION_MODEL_MESH_EXT, cast(u32) state.id_main, shader.entry_name, interface_ids);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_OUTPUT_PRIMITIVES_EXT, 1);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_OUTPUT_VERTICES, 3);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_LOCAL_SIZE, 1, 1, 1);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_OUTPUT_TRIANGLES_EXT);
  spv_module_append_source(*module, SPV_SOURCE_LANGUAGE_UNKNOWN, 100000);
  spv_module_append_name(*module, cast(u32) state.id_main, shader.entry_name);
  spv_module_append_name(*module, cast(u32) state.id_gl_workgroup_id, "gl_WorkGroupID");
  for state.debug_names spv_module_append_name(*module, cast(u32) it.id, it.name);
  for state.debug_member_names spv_module_append_member_name(*module, cast(u32) it.type_id, cast(u32) it.member_index, it.name);
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.id, SPV_DECORATION_SPEC_ID, it.spec_id);
      continue;
    }
    for i: 0..it.component_count-1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.component_ids[i], SPV_DECORATION_SPEC_ID, it.spec_id + cast(u32) i);
    }
  }
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_mesh_positions_var, SPV_DECORATION_BUILTIN, SPV_BUILTIN_POSITION);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_mesh_colors_var, SPV_DECORATION_LOCATION, 0);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_mesh_triangle_indices_var, SPV_DECORATION_BUILTIN, SPV_BUILTIN_PRIMITIVE_TRIANGLE_INDICES_EXT);
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_workgroup_id, SPV_DECORATION_BUILTIN, SPV_BUILTIN_WORKGROUP_ID);

  spv_module_append_common_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_numeric_constants_binary(*module, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_module_append_function_constant_defs_binary(*module, *state);
  if !function_constant_defs_ok return .[], false, function_constant_defs_diag;
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) state.id_mesh_positions_array_type, cast(u32) state.id_float4, cast(u32) mesh_vertex_count_const);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_positions_array, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_mesh_positions_array_type);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_position, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float4);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) state.id_mesh_colors_array_type, cast(u32) state.id_float3, cast(u32) mesh_vertex_count_const);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_colors_array, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_mesh_colors_array_type);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_color, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float3);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) state.id_mesh_triangle_indices_array_type, cast(u32) state.id_v3uint, cast(u32) mesh_primitive_count_const);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_triangle_indices_array, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_mesh_triangle_indices_array_type);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_mesh_triangle_indices, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_v3uint);
  if state.uses_mesh_payload {
    payload_ok, payload_diag := emit_payload_type_decls_binary(*module, *state);
    if !payload_ok return .[], false, payload_diag;
  }
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_v3uint, cast(u32) state.id_gl_workgroup_id, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_output_mesh_positions_array, cast(u32) state.id_mesh_positions_var, SPV_STORAGE_CLASS_OUTPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_output_mesh_colors_array, cast(u32) state.id_mesh_colors_var, SPV_STORAGE_CLASS_OUTPUT);
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_output_mesh_triangle_indices_array, cast(u32) state.id_mesh_triangle_indices_var, SPV_STORAGE_CLASS_OUTPUT);
  spv_module_append_null_constants_binary(*module, *state);
  spv_module_append_global_const_array_decls_binary(*module, *state);

  module.bound = cast(u32) state.next_id;
  spv_module_append_function_body(*module, *state, entry_label);
  return spv_serialize_module_binary(*module), true, diag;
}

emit_task_generic_binary :: (shader: *IR_Task_Shader) -> (spv: [] u8, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return .[], false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  assert(shader != null);

  state: IR_SPV_Gen_State;
  state.record_binary = true;
  state.stage = .TASK;
  state.debug_type_prefix = tprint("task_%", shader.source_name);
  state.functions = shader.functions;
  function_constants_ok, function_constants_diag := register_function_constants(*state, shader.function_constants);
  if !function_constants_ok return .[], false, function_constants_diag;
  for shader.extra_structs array_add(*state.extra_structs, it);
  init_ok, init_diag := init_base(*state, .[], 1);
  if !init_ok return .[], false, init_diag;
  state.id_task_payload_struct = new_id(*state);
  state.id_ptr_task_payload_struct = new_id(*state);
  state.id_task_payload_var = new_id(*state);

  entry_label := new_id(*state);
  block_ok, block_terminated, block_diag := emit_stmt_block(*state, *shader.body);
  if !block_ok return .[], false, block_diag;
  if !block_terminated return_err("task shader must terminate with task_set_mesh_groups exactly once.");

  module: SPV_Module;
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_SHADER);
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_MESH_SHADING_EXT);
  if state_uses_int64(*state) spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_INT64);
  spv_module_append_words(*module, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_FLOAT16);
  spv_module_append_extension(*module, "SPV_EXT_mesh_shader");
  spv_module_append_ext_inst_import(*module, cast(u32) state.id_extinst, "GLSL.std.450");
  spv_module_append_words(*module, .MEMORY_MODEL, SPV_OP_MEMORY_MODEL, SPV_ADDRESSING_MODEL_LOGICAL, SPV_MEMORY_MODEL_GLSL450);
  interface_ids: [..]u32;
  array_add(*interface_ids, cast(u32) state.id_gl_workgroup_id);
  if state.uses_task_payload array_add(*interface_ids, cast(u32) state.id_task_payload_var);
  spv_module_append_entry_point(*module, SPV_EXECUTION_MODEL_TASK_EXT, cast(u32) state.id_main, shader.entry_name, interface_ids);
  spv_module_append_words(*module, .EXECUTION_MODES, SPV_OP_EXECUTION_MODE, cast(u32) state.id_main, SPV_EXECUTION_MODE_LOCAL_SIZE, 1, 1, 1);
  spv_module_append_source(*module, SPV_SOURCE_LANGUAGE_UNKNOWN, 100000);
  spv_module_append_name(*module, cast(u32) state.id_main, shader.entry_name);
  spv_module_append_name(*module, cast(u32) state.id_gl_workgroup_id, "gl_WorkGroupID");
  for state.debug_names spv_module_append_name(*module, cast(u32) it.id, it.name);
  for state.debug_member_names spv_module_append_member_name(*module, cast(u32) it.type_id, cast(u32) it.member_index, it.name);
  for state.function_constants {
    if it.component_count <= 1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.id, SPV_DECORATION_SPEC_ID, it.spec_id);
      continue;
    }
    for i: 0..it.component_count-1 {
      spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) it.component_ids[i], SPV_DECORATION_SPEC_ID, it.spec_id + cast(u32) i);
    }
  }
  spv_module_append_words(*module, .ANNOTATIONS, SPV_OP_DECORATE, cast(u32) state.id_gl_workgroup_id, SPV_DECORATION_BUILTIN, SPV_BUILTIN_WORKGROUP_ID);

  spv_module_append_common_type_decls_binary(*module, *state, SPV_STORAGE_CLASS_STORAGE_BUFFER);
  spv_module_append_numeric_constants_binary(*module, *state);
  function_constant_defs_ok, function_constant_defs_diag := spv_module_append_function_constant_defs_binary(*module, *state);
  if !function_constant_defs_ok return .[], false, function_constant_defs_diag;
  if state.uses_task_payload {
    payload_ok, payload_diag := emit_payload_type_decls_binary(*module, *state);
    if !payload_ok return .[], false, payload_diag;
  }
  spv_module_append_words(*module, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) state.id_ptr_input_v3uint, cast(u32) state.id_gl_workgroup_id, SPV_STORAGE_CLASS_INPUT);
  spv_module_append_null_constants_binary(*module, *state);
  spv_module_append_global_const_array_decls_binary(*module, *state);

  module.bound = cast(u32) state.next_id;
  spv_module_append_function_body(*module, *state, entry_label);
  return spv_serialize_module_binary(*module), true, diag;
}

spv_binary_from_text_module :: (spvasm: string) -> (spv: [] u8, ok: bool, diag: IR_Diagnostic) {
  module: SPV_Module;
  ingest_ok, ingest_diag := spv_ingest_text_into_module(*module, spvasm);
  if !ingest_ok return .[], false, ingest_diag;

  max_id: u32 = 0;
  i: s64 = 0;
  while i < spvasm.count {
    if spvasm[i] != #char "%" {
      i += 1;
      continue;
    }
    i += 1;
    start := i;
    while i < spvasm.count && spvasm[i] >= #char "0" && spvasm[i] <= #char "9" i += 1;
    if i == start continue;
    value, value_ok := string_to_int(string.{i - start, spvasm.data + start});
    if value_ok && value > cast(s64) max_id max_id = cast(u32) value;
  }
  module.bound = max_id + 1;
  return spv_serialize_module_binary(*module), true, {};
}
