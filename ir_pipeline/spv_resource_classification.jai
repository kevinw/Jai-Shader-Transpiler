#scope_module

find_field_index_by_name :: (st: *IR_Struct, field_name: string) -> s64 {
  assert(st != null);
  for st.fields if it.name == field_name return it_index;
  return -1;
}

split_dotted_path :: (path: string, out_segments: *[..] string) {
  assert(out_segments != null);
  start: s64 = 0;
  i: s64 = 0;
  while i <= path.count {
    at_end := i == path.count;
    if !at_end && path[i] != #char "." {
      i += 1;
      continue;
    }
    seg_count := i - start;
    seg := slice(path, start, seg_count);
    if seg.count > 0 array_add(out_segments, seg);
    start = i + 1;
    i += 1;
  }
}

struct_has_pointer_fields_recursive :: (extra_structs: [] IR_Struct, struct_name: string, depth := 0) -> bool {
  if depth > 24 return false;
  st: *IR_Struct = null;
  for *extra_structs {
    candidate := it;
    if candidate.name == struct_name {
      st = candidate;
      break;
    }
  }
  if !st return false;
  for st.fields {
    field := it;
    if field.type.kind == .POINTER return true;
    nested_field_struct_name := field.type.struct_name;
    if nested_field_struct_name.count == 0 continue;
    for *extra_structs {
      nested := it;
      if nested.name != nested_field_struct_name continue;
      if struct_has_pointer_fields_recursive(extra_structs, nested_field_struct_name, depth + 1) return true;
      break;
    }
  }
  return false;
}

IR_SPV_Buffer_Element_Info :: struct {
  element_type_name: string;
  elem_kind: IR_SPV_Gen_Type;
  parsed_fixed_array: bool;
  parsed_array_count: s64;
}

parse_buffer_element_info :: (buffer: IR_Compute_Buffer) -> IR_SPV_Buffer_Element_Info {
  using info: IR_SPV_Buffer_Element_Info;
  element_type_name = buffer.element_type.display_name;
  elem_kind = spv_kind_from_ir_type_kind(buffer.element_type.kind);

  if buffer.element_type.kind == .FIXED_ARRAY {
    parsed_fixed_array = true;
    parsed_array_count = buffer.element_type.array_count;
    element_type_name = ir_string_first_non_empty(buffer.element_type.element_display_name, buffer.element_type.element_struct_name);
    elem_kind = spv_kind_from_ir_type_kind(buffer.element_type.element_kind);
  }

  return info;
}

struct_has_pointer_fields :: (st: *IR_Struct) -> bool {
  assert(st != null);
  for st.fields if it.type.kind == .POINTER return true;
  return false;
}

resource_element_type_from_field :: (s: *IR_SPV_Gen_State, field: *IR_Field) -> (element_type_name: string, is_resource: bool, is_readonly: bool) {
  assert(s != null);
  assert(field != null);

  if field.type.kind == .POINTER {
    pointee_name := ir_string_first_non_empty(field.type.pointee_struct_name, field.type.pointee_display_name);
    if pointee_name.count == 0 return "", false, false;
    if field.type.pointee_kind == .STRUCT {
      nested_struct := find_struct(s, pointee_name);
      if nested_struct && struct_has_pointer_fields(nested_struct) return "", false, false;
    }
    return pointee_name, true, false;
  }

  return "", false, false;
}

resource_walk_nested_struct :: (s: *IR_SPV_Gen_State, field: *IR_Field) -> *IR_Struct {
  assert(s != null);
  assert(field != null);

  if field.type.kind == .POINTER && field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 {
    nested := find_struct(s, field.type.pointee_struct_name);
    if nested && struct_has_pointer_fields(nested) return nested;
  }
  if field.type.kind == .STRUCT && field.type.struct_name.count != 0 {
    return find_struct(s, field.type.struct_name);
  }
  return null;
}

collect_struct_resource_fields :: (s: *IR_SPV_Gen_State, st: *IR_Struct, name_prefix: string, out_buffers: *[..] IR_Compute_Buffer, default_readonly: bool = false) -> (has_resource: bool, has_non_resource: bool) {
  assert(s != null);
  assert(st != null);

  has_resource := false;
  has_non_resource := false;
  for st.fields {
    field_path := ifx name_prefix.count == 0 then it.name else tprint("%.%", name_prefix, it.name);
    elem_type_name, is_resource_field, field_readonly := resource_element_type_from_field(s, *it);
    if is_resource_field {
      has_resource = true;
      if out_buffers {
        elem_type: IR_Type;
        elem_type.kind = it.type.pointee_kind;
        elem_type.display_name = it.type.pointee_display_name;
        elem_type.struct_name = it.type.pointee_struct_name;
        array_add(out_buffers, .{
          name = field_path,
          element_type = elem_type,
          is_readonly = field_readonly || default_readonly,
        });
      }
      continue;
    }

    nested_struct := resource_walk_nested_struct(s, *it);
    if nested_struct {
      nested_has_resource, nested_has_non_resource := collect_struct_resource_fields(s, nested_struct, field_path, out_buffers, default_readonly);
      if nested_has_resource has_resource = true;
      if nested_has_non_resource has_non_resource = true;
      if !nested_has_resource has_non_resource = true;
      continue;
    }

    has_non_resource = true;
  }
  return has_resource, has_non_resource;
}

expand_compute_resource_root_buffers :: (s: *IR_SPV_Gen_State, in_buffers: [] IR_Compute_Buffer, out_buffers: *[..] IR_Compute_Buffer) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return false, make_diag(message, ..args); }

  assert(s != null);
  assert(out_buffers != null);
  diag: IR_Diagnostic;

  for in_buffers {
    buf := it;
    if buf.element_type.kind != .STRUCT {
      array_add(out_buffers, buf);
      continue;
    }
    struct_name := buf.element_type.struct_name;
    if struct_name.count == 0 {
      return_err("SPIR-V generic backend: compute root '%' struct buffer is missing typed struct metadata.", buf.name);
    }
    struct_def := find_struct(s, struct_name);
    if !struct_def return_err("SPIR-V generic backend: compute root '%' references missing struct '%'.", buf.name, struct_name);

    saw_resource, saw_non_resource := collect_struct_resource_fields(s, struct_def, buf.name, out_buffers, buf.is_readonly);
    if saw_resource {
      if saw_non_resource {
        return_err("SPIR-V generic backend: compute resource-root '%' mixes resource and non-resource fields.", buf.name);
      }
      continue;
    }

    array_add(out_buffers, buf);
  }

  return true, diag;
}
