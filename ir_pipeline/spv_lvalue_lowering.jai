#scope_module

emit_lvalue_ptr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(msg, ..args); }

  assert(s != null);
  diag: IR_Diagnostic;
  if !expr return_err("null lvalue expression.");
  if expr.kind == .UNARY {
    if expr.unary_op == .DEREF {
      if !expr.left return_err("unary '*' missing operand.");
      if expr.left.kind == .IDENT {
        local_ptr := find_local(s, expr.left.text);
        if local_ptr return local_ptr.ptr_id, local_ptr.type, true, diag;
      }
      buffer_name, buffer_name_ok := resolve_buffer_name_from_expr(expr.left);
      if !buffer_name_ok return_err("unsupported unary '*' lvalue base.");
      buffer := find_buffer(s, buffer_name);
      if !buffer return_err("unknown unary '*' lvalue base '%'.", buffer_name);
      if buffer.element_kind == .STRUCT return_err("struct buffer '%' requires member access on lvalue.", buffer.name);
      idx := ifx buffer.has_base_index then buffer.base_index_id else s.id_uint_0;
      ptr := new_id(s);
      add_op(s, ptr, "OpAccessChain", buffer.ptr_storage_element_type_id, buffer.var_id, s.id_int_0, idx);
      return ptr, buffer.element_kind, true, diag;
    }
  }
  if expr.kind == .IDENT {
    local := find_local(s, expr.text);
    if !local return_err("unknown lvalue identifier '%'.", expr.text);
    return local.ptr_id, local.type, true, diag;
  }
  if expr.kind == .SUBSCRIPT {
    if expr.left && expr.left.kind == .IDENT {
      local_array := find_local_array(s, expr.left.text);
      if local_array {
        idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        elem_ptr := new_id(s);
        elem_ptr_type_id := func_ptr_type_id_from_kind(s, local_array.element_type);
        add_op(s, elem_ptr, "OpAccessChain", elem_ptr_type_id, local_array.var_id, idx);
        return elem_ptr, local_array.element_type, true, diag;
      }
    }

    if expr.left && expr.left.kind == .MEMBER {
      uniform_name, uniform_field, uniform_ok := resolve_member_root_and_field(expr.left);
      if uniform_ok {
        idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        ptr, elem_type, ptr_ok, ptr_diag := emit_uniform_array_element_ptr(s, uniform_name, uniform_field, idx, idx_type);
        if ptr_ok return ptr, elem_type, true, diag;
      }
    }

    buffer_name, base_ok := resolve_buffer_name_from_expr(expr.left);
    if !base_ok {
      return_err("unsupported lvalue subscript base.");
    }
    buffer := find_buffer(s, buffer_name);
    if !buffer return_err("unknown lvalue subscript base '%'.", buffer_name);
    idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    idx = apply_buffer_base_index(s, buffer, idx);
    if buffer.element_kind != .STRUCT {
      ptr := new_id(s);
      add_op(s, ptr, "OpAccessChain", buffer.ptr_storage_element_type_id, buffer.var_id, s.id_int_0, idx);
      return ptr, buffer.element_kind, true, diag;
    }
    return_err("struct buffer '%' requires member access on lvalue.", buffer.name);
  }
  if expr.kind == .MEMBER {
    if expr.left && expr.left.kind == .SUBSCRIPT {
      ptr_id, ptr_type, ptr_ok, ptr_diag := emit_buffer_struct_field_ptr(s, expr.left, expr.text);
      if ptr_ok return ptr_id, ptr_type, true, diag;

      // Fallback: component lvalue on raw vector buffer element, e.g. table[idx].x
      buffer_name, base_ok := resolve_buffer_name_from_expr(expr.left.left);
      buffer := ifx buffer_name.count > 0 then find_buffer(s, buffer_name) else null;
      if buffer && (buffer.element_kind == .FLOAT2 || buffer.element_kind == .FLOAT3 || buffer.element_kind == .FLOAT4) {
        comp_index, comp_ok := spv_member_component_index_u32(expr.member_access);
        if !comp_ok return_err("unsupported vector component '%' for lvalue.", expr.text);
        if !spv_vector_component_in_range(buffer.element_kind, cast(s64) comp_index) return_err("vector component '%' out of range for type % lvalue.", expr.text, buffer.element_kind);

        idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.left.right);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        idx = apply_buffer_base_index(s, buffer, idx);

        elem_ptr := new_id(s);
        add_op(s, elem_ptr, "OpAccessChain", buffer.ptr_storage_element_type_id, buffer.var_id, s.id_int_0, idx);
        comp_index_id := get_u32_const(s, comp_index);
        ptr := new_id(s);
        add_op(s, ptr, "OpAccessChain", s.id_ptr_storage_float, elem_ptr, comp_index_id);
        return ptr, .FLOAT, true, diag;
      }

      return ptr_id, ptr_type, false, ptr_diag;
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .SUBSCRIPT {
      field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left.left, expr.left.text);
      if !field_ok return 0, .UNKNOWN, false, field_diag;
      if field_type != .FLOAT2 && field_type != .FLOAT3 && field_type != .FLOAT4 return_err("lvalue component access requires float2/float3/float4 field, got %.", field_type);
      comp_index, comp_ok := spv_member_component_index_u32(expr.member_access);
      if !comp_ok return_err("unsupported vector component '%' for lvalue.", expr.text);
      if !spv_vector_component_in_range(field_type, cast(s64) comp_index) return_err("vector component '%' out of range for type % lvalue.", expr.text, field_type);
      comp_index_id := get_u32_const(s, comp_index);
      ptr := new_id(s);
      add_op(s, ptr, "OpAccessChain", s.id_ptr_storage_float, field_ptr, comp_index_id);
      return ptr, .FLOAT, true, diag;
    }
    if expr.left && expr.left.kind == .IDENT {
      local_vec := find_local(s, expr.left.text);
      if local_vec && (local_vec.type == .FLOAT2 || local_vec.type == .FLOAT3 || local_vec.type == .FLOAT4) {
        comp_index, comp_ok := spv_member_component_index_u32(expr.member_access);
        if !comp_ok return_err("unsupported vector component '%' for lvalue.", expr.text);
        if !spv_vector_component_in_range(local_vec.type, cast(s64) comp_index) return_err("vector component '%' out of range for type % lvalue.", expr.text, local_vec.type);
        comp_index_id := get_u32_const(s, comp_index);
        ptr := new_id(s);
        add_op(s, ptr, "OpAccessChain", s.id_ptr_func_float, local_vec.ptr_id, comp_index_id);
        return ptr, .FLOAT, true, diag;
      }
      local_struct := find_local_struct(s, expr.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.text);
        if !field return_err("unknown struct field '%.%'.", expr.left.text, expr.text);
        if field.type == .STRUCT return_err("struct field '%.%' must be accessed through a member.", expr.left.text, expr.text);
        return field.ptr_id, field.type, true, diag;
      }
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
      local_struct := find_local_struct(s, expr.left.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.left.text);
        if !field return_err("unknown struct field '%.%'.", expr.left.left.text, expr.left.text);
        if field.type == .STRUCT {
          nested_struct := find_local_struct(s, field.nested_struct_name);
          if !nested_struct return_err("nd: nested struct '%.%' is missing.", expr.left.left.text, expr.left.text);
          nested_field := find_local_struct_field(nested_struct, expr.text);
          if !nested_field return_err("unknown nested struct field '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          if nested_field.type == .STRUCT return_err("nested struct field '%.%.%' must be accessed through a member.", expr.left.left.text, expr.left.text, expr.text);
          return nested_field.ptr_id, nested_field.type, true, diag;
        }
        if field.type != .FLOAT2 && field.type != .FLOAT3 && field.type != .FLOAT4 return_err("component lvalue requires float2/float3/float4 field, got %.", field.type);
        comp_index, comp_ok := spv_member_component_index_u32(expr.member_access);
        if !comp_ok return_err("unsupported vector component '%' for lvalue.", expr.text);
        if !spv_vector_component_in_range(field.type, cast(s64) comp_index) return_err("vector component '%' out of range for type % lvalue.", expr.text, field.type);
        comp_index_id := get_u32_const(s, comp_index);
        ptr := new_id(s);
        add_op(s, ptr, "OpAccessChain", s.id_ptr_func_float, field.ptr_id, comp_index_id);
        return ptr, .FLOAT, true, diag;
      }
    }
    return_err("unsupported lvalue member expression '%'.", expr_text(expr));
  }
  return_err("unsupported lvalue expression kind %.", expr.kind);
}

lvalue_hits_storage_buffer :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> bool {
  assert(s != null);
  if !expr return false;
  if expr.kind == .SUBSCRIPT {
    if expr.left && expr.left.kind == .IDENT {
      if find_local_array(s, expr.left.text) return false;
      return find_buffer(s, expr.left.text) != null;
    }
    if expr.left && expr.left.kind == .MEMBER {
      uniform_name, _, uniform_ok := resolve_member_root_and_field(expr.left);
      if uniform_ok && find_uniform_block(s, uniform_name) != null return false;
    }
    if expr.left && expr.left.kind == .MEMBER {
      member_root, member_field, member_ok := resolve_member_root_and_field(expr.left);
      if member_ok return find_buffer(s, tprint("%.%", member_root, member_field)) != null;
      member_path, path_ok := resolve_member_path(expr.left);
      if path_ok return find_buffer(s, member_path) != null;
      return false;
    }
    return false;
  }
  if expr.kind == .MEMBER return lvalue_hits_storage_buffer(s, expr.left);
  return false;
}
