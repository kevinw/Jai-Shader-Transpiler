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

  state: IR_SPV_Gen_State;
  state.stage = stage;
  stage_prefix := ifx stage == .VERTEX then "vert" else ifx stage == .FRAGMENT then "frag" else "compute";
  state.debug_type_prefix = tprint("%_%", stage_prefix, source_name);
  state.functions = functions;
  for extra_structs array_add(*state.extra_structs, it);
  array_add(*state.extra_structs, input);
  array_add(*state.extra_structs, output);
  state.output_struct_type_name = output.name;

  root_struct := find_struct(*state, root_arg.pointer_pointee_type_name);
  if !root_struct return_err("SPIR-V backend: missing root pointer struct '%'.", root_arg.pointer_pointee_type_name);

  graphics_buffers: [..] IR_Compute_Buffer;
  saw_resource, saw_non_resource := collect_struct_resource_fields(*state, root_struct, root_arg.name, *graphics_buffers);
  if !saw_resource return_err("SPIR-V backend: pointer root '%' has no resource fields.", root_arg.name);
  if saw_non_resource return_err("SPIR-V backend: pointer root '%' currently requires pointer-only members.", root_arg.name);

  init_ok, init_diag := init_base(*state, graphics_buffers, 1, use_physical_storage=true);
  if !init_ok return "", false, init_diag;

  for input.fields {
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported input field type '%' on '%'.", it.type_name, it.name);
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
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported output field type '%' on '%'.", it.type_name, it.name);
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
  if !ps_assign_struct_info(*state, *ps_infos, root_arg.pointer_pointee_type_name, root_arg.name) {
    return_err("SPIR-V backend: failed building pointer-struct type graph for '%'.", root_arg.pointer_pointee_type_name);
  }

  ptr_to_ptr_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  ptr_to_ptr_storage_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  root_var_ptr_type_id := new_id(*state);
  root_var_id := new_id(*state);
  root_info := find_ps_struct_info(*ps_infos, root_arg.pointer_pointee_type_name);
  if !root_info return_err("SPIR-V backend: missing pointer root type info for '%'.", root_arg.pointer_pointee_type_name);

  for *state.buffers {
    segments: [..] string;
    split_dotted_path(it.name, *segments);
    if segments.count < 2 return_err("SPIR-V backend: invalid resource path '%'.", it.name);
    if segments[0] != root_arg.name return_err("SPIR-V backend: resource path '%' does not match root arg '%'.", it.name, root_arg.name);
    current_ptr := root_var_id;
    current_ptr_from_storage := true;

    current_struct_name := root_arg.pointer_pointee_type_name;
    consumed_path := root_arg.name;
    for i: 1..segments.count-1 {
      current_struct := find_struct(*state, current_struct_name);
      if !current_struct return_err("SPIR-V backend: missing struct '%' while resolving '%'.", current_struct_name, it.name);
      field_index := find_field_index_by_name(current_struct, segments[i]);
      if field_index < 0 return_err("SPIR-V backend: field '%' not found in '%' while resolving '%' (segment %).", segments[i], current_struct_name, it.name, i);
      field := current_struct.fields[field_index];
      if !field.is_pointer return_err("SPIR-V backend: physical-pointer path expects pointer field at '%.%'.", current_struct_name, segments[i]);

      next_ptr_type_id: s64 = 0;
      next_struct_name := "";
      consumed_path = tprint("%.%", consumed_path, segments[i]);
      if field.pointer_pointee_is_struct && field.pointer_pointee_type_name.count != 0 &&
         struct_has_pointer_fields_recursive(state.extra_structs, field.pointer_pointee_type_name) {
        nested_info := find_ps_struct_info(*ps_infos, field.pointer_pointee_type_name);
        if !nested_info return_err("SPIR-V backend: missing pointer type info for nested struct '%'.", field.pointer_pointee_type_name);
        next_ptr_type_id = nested_info.ptr_type_id;
        next_struct_name = field.pointer_pointee_type_name;
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
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  if stage == .FRAGMENT append(*sb, tprint("               OpExecutionMode % OriginUpperLeft\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"%\"\n", id_text(state.id_main), entry_name));
  append(*sb, tprint("               OpName % \"%\"\n", id_text(root_var_id), root_arg.name));
  for state.input_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.output_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
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
      if field.is_pointer offset += 8;
      else {
        kind := spv_kind_from_ir_type_kind(field.type.kind);
        if kind == .UNKNOWN kind = expr_type_from_decl(field.type_name);
        size := byte_size_of_kind(kind);
        if size <= 0 size = 4;
        offset += size;
      }
    }
  }

  spv_append_common_type_decls(*sb, *state, storage_class);
  spv_append_numeric_constants(*sb, *state);
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
      if field.is_pointer {
        if field.pointer_pointee_is_struct && field.pointer_pointee_type_name.count != 0 &&
           struct_has_pointer_fields_recursive(state.extra_structs, field.pointer_pointee_type_name) {
          nested_info := find_ps_struct_info(*ps_infos, field.pointer_pointee_type_name);
          if !nested_info return_err("SPIR-V backend: missing nested pointer type info for '%'.", field.pointer_pointee_type_name);
          member_type_id = nested_info.ptr_type_id;
        } else {
          leaf_path := tprint("%.%", ps_info.prefix, field.name);
          leaf_buffer := find_buffer(*state, leaf_path);
          if !leaf_buffer return_err("SPIR-V backend: missing leaf buffer for path '%'.", leaf_path);
          member_type_id = leaf_buffer.ptr_wrapper_type_id;
        }
      } else {
        kind := spv_kind_from_ir_type_kind(field.type.kind);
        if kind == .UNKNOWN kind = expr_type_from_decl(field.type_name);
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
  spv_append_local_array_type_decls(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

emit_graphics_generic :: (stage: IR_SPV_Gen_Stage, source_name: string, input: IR_Struct, output: IR_Struct, args: [] IR_Function_Arg, body: *IR_Block, functions: [] IR_Function, extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }
  diag: IR_Diagnostic;
  if !body return_err("SPIR-V backend: graphics shader '%' has no body.", source_name);

  root_arg, use_pointer_abi := find_pointer_root_arg(args, extra_structs);
  if use_pointer_abi && root_arg {
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

  graphics_buffers: [..] IR_Compute_Buffer;
  for args {
    arg := it;
    if arg.type.kind == .POINTER && arg.type.pointee_kind != .STRUCT && arg.type.pointee_display_name.count != 0 {
      array_add(*graphics_buffers, .{
        name = arg.name,
        element_type = .{
          kind = arg.type.pointee_kind,
          display_name = arg.type.pointee_display_name,
          struct_name = arg.type.pointee_struct_name,
        },
        element_type_name = arg.type.pointee_display_name,
      });
      continue;
    }
    if arg.is_pointer && !arg.pointer_pointee_is_struct && arg.pointer_pointee_type_name.count != 0 {
      array_add(*graphics_buffers, .{
        name = arg.name,
        element_type = .{display_name = arg.pointer_pointee_type_name},
        element_type_name = arg.pointer_pointee_type_name,
      });
      continue;
    }
    elem_type_name, is_resource_buffer := parse_structured_buffer_element_type(arg.type_name);
    if is_resource_buffer {
      array_add(*graphics_buffers, .{
        name = arg.name,
        element_type = .{display_name = elem_type_name},
        element_type_name = elem_type_name,
      });
      continue;
    }
    is_param_block := false;
    container_type_name := arg.type.struct_name;
    if container_type_name.count == 0 container_type_name = arg.type_name;
    if arg.type.flags & .PARAMETER_BLOCK {
      is_param_block = true;
    }
    if arg.type.kind == .POINTER && arg.type.pointee_kind == .STRUCT && arg.type.pointee_struct_name.count != 0 {
      container_type_name = arg.type.pointee_struct_name;
    } else if arg.is_pointer && arg.pointer_pointee_is_struct && arg.pointer_pointee_type_name.count != 0 {
      container_type_name = arg.pointer_pointee_type_name;
    } else if !is_param_block {
      struct_name, parsed_param_block := parse_parameter_block_struct_name(arg.type_name);
      if parsed_param_block {
        container_type_name = struct_name;
        is_param_block = true;
      }
    }
    struct_def := find_struct(*state, container_type_name);
    if !struct_def continue;
    saw_resource_field, saw_non_resource_field := collect_struct_resource_fields(*state, struct_def, arg.name, *graphics_buffers);
    if !is_param_block && saw_resource_field && saw_non_resource_field {
      return_err("SPIR-V backend: resource-container arg '%' currently requires all fields to be StructuredBuffer/RWStructuredBuffer.", arg.name);
    }
  }

  init_ok, init_diag := init_base(*state, graphics_buffers, 1);
  if !init_ok return "", false, init_diag;

  for input.fields {
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported input field type '%' on '%'.", it.type_name, it.name);
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
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN return_err("SPIR-V backend: unsupported output field type '%' on '%'.", it.type_name, it.name);
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
    is_param_block: bool;
    if arg.type.flags & .PARAMETER_BLOCK is_param_block = true;
    if is_param_block && struct_name.count == 0 {
      struct_name = arg.type_name;
    }
    if !is_param_block {
      parsed_struct_name, parsed_param_block := parse_parameter_block_struct_name(arg.type_name);
      if parsed_param_block {
        struct_name = parsed_struct_name;
        is_param_block = true;
      }
    }
    if !is_param_block continue;
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
      nested_struct_name := field.type.struct_name;
      if nested_struct_name.count == 0 nested_struct_name = field.type_name;
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
      _, is_resource_field := parse_structured_buffer_element_type(field.type_name);
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

      array_elem_type_name := "";
      parsed_array_count: s64;
      parsed_array := field.type.kind == .FIXED_ARRAY;
      if parsed_array {
        array_elem_type_name = field.type.element_display_name;
        parsed_array_count = field.type.array_count;
      } else {
        array_elem_type_name, parsed_array_count, parsed_array = parse_fixed_array_type_name(field.type_name);
      }
      if parsed_array {
        field_type = spv_kind_from_ir_type_kind(field.type.element_kind);
        if field_type == .UNKNOWN field_type = expr_type_from_decl(array_elem_type_name);
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
        field_type = spv_kind_from_ir_type_kind(field.type.kind);
        if field_type == .UNKNOWN field_type = expr_type_from_decl(field.type_name);
        if field_type == .UNKNOWN || field_type == .STRUCT {
          return_err("SPIR-V backend: uniform field '%.%' has unsupported type '%'.", struct_name, field.name, field.type_name);
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
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  if stage == .FRAGMENT append(*sb, tprint("               OpExecutionMode % OriginUpperLeft\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"%\"\n", id_text(state.id_main), entry_name));
  for state.input_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.output_vars append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.uniform_blocks append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append_interface_var_decorations(*sb, state.input_vars);
  append_interface_var_decorations(*sb, state.output_vars);
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);
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
  spv_append_local_array_type_decls(*sb, *state);

  spv_append_function_and_body(*sb, *state, entry_label, "    ", "     ");
  return builder_to_string(*sb), true, diag;
}

// -----------------------------------------------------------------------------
// Module Assembly
// -----------------------------------------------------------------------------

emit_compute_generic_uint_buffer :: (shader: IR_Compute_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  if shader.buffers.count == 0 return_err("SPIR-V generic backend: expected at least one compute buffer.");
  if shader.body.statements.count == 0 return_err("SPIR-V generic backend: empty compute body.");

  bound_value := cast(u32) 64;
  if shader.body.statements[0].kind == .IF {
    b, ok := match_branch_condition_outer(shader.body.statements[0].if_condition);
    if ok bound_value = b;
  }

  state: IR_SPV_Gen_State;
  state.debug_type_prefix = tprint("compute_%", shader.source_name);
  state.functions = shader.functions;
  for shader.extra_structs array_add(*state.extra_structs, it);
  compute_buffers: [..] IR_Compute_Buffer;
  expand_ok, expand_diag := expand_compute_resource_root_buffers(*state, shader.buffers, *compute_buffers);
  if !expand_ok return "", false, expand_diag;
  init_ok, init_diag := init_base(*state, compute_buffers, bound_value);
  if !init_ok return "", false, init_diag;

  entry_label := new_id(*state);
  ok, body_terminated, body_diag := emit_stmt_block(*state, *shader.body);
  if !ok return "", false, body_diag;

  // Build module text sections after IDs are finalized.
  sb: String_Builder;
  spv_append_module_preamble(*sb, *state, "Logical GLSL450");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint GLCompute % \"%\" %", id_text(state.id_main), shader.entry_name, id_text(state.id_gl_global_invocation_id)));
  spv_append_var_ids(*entry_point_sb, state.buffers);
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  append(*sb, tprint("               OpExecutionMode % LocalSize 1 1 1\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"ComputeMain\"\n", id_text(state.id_main)));
  append(*sb, tprint("               OpName % \"gl_GlobalInvocationID\"\n", id_text(state.id_gl_global_invocation_id)));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  for state.debug_names append(*sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
  for state.debug_member_names append(*sb, tprint("               OpMemberName % % \"%\"\n", id_text(it.type_id), it.member_index, it.name));
  append(*sb, tprint("               OpDecorate % BuiltIn GlobalInvocationId\n", id_text(state.id_gl_global_invocation_id)));
  spv_append_base_buffer_decorations(*sb, *state);
  spv_append_buffer_layout_decorations(*sb, *state);
  spv_append_buffer_binding_decorations(*sb, *state);

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  // OpTypeArray length operands must be declared constants beforehand.
  spv_append_numeric_constants(*sb, *state);
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_global_invocation_id), id_text(state.id_ptr_input_v3uint)));
  spv_append_buffer_type_decls(*sb, *state, "StorageBuffer");
  spv_append_buffer_vars(*sb, *state, "StorageBuffer");
  spv_append_local_array_type_decls(*sb, *state);

  _ = body_terminated;
  spv_append_function_and_body(*sb, *state, entry_label, "      ", "         ");

  out := builder_to_string(*sb);
  return out, true, diag;
}
