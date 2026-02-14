//
// Jai IR -> SPIR-V text
// 
#scope_export

emit_ir_compute_to_spirv_text_branch :: (shader: IR_Compute_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  generic_out, generic_ok, generic_diag := emit_compute_generic_uint_buffer(shader);
  if generic_ok return generic_out, true, diag;

  if generic_diag.message.count == 0 {
    generic_diag.message = tprint("SPIR-V generic backend: unsupported compute shader '%'.", shader.source_name);
  }
  return "", false, generic_diag;
}

emit_ir_graphics_pair_to_spirv_text_branch :: (vertex: IR_Vertex_Shader, fragment: IR_Fragment_Shader) -> (vertex_spvasm: string, fragment_spvasm: string, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  assert(vertex.entry_name.count != 0);
  assert(fragment.entry_name.count != 0);
  vertex_spv, vertex_ok, vertex_diag := emit_ir_vertex_to_spirv_text_branch(vertex);
  if !vertex_ok return "", "", false, vertex_diag;
  fragment_spv, fragment_ok, fragment_diag := emit_ir_fragment_to_spirv_text_branch(fragment);
  if !fragment_ok return "", "", false, fragment_diag;
  return vertex_spv, fragment_spv, true, diag;
}

emit_ir_vertex_to_spirv_text_branch :: (shader: IR_Vertex_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  spvasm, ok, diag := emit_graphics_generic(.VERTEX, shader.source_name, shader.input, shader.output, shader.args, *shader.body, shader.functions, shader.extra_structs);
  return spvasm, ok, diag;
}

emit_ir_fragment_to_spirv_text_branch :: (shader: IR_Fragment_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  spvasm, ok, diag := emit_graphics_generic(.FRAGMENT, shader.source_name, shader.input, shader.output, shader.args, *shader.body, shader.functions, shader.extra_structs);
  return spvasm, ok, diag;
}

#scope_module
// -----------------------------------------------------------------------------
// Parsing / Text Helpers
// -----------------------------------------------------------------------------

parse_u32_literal_text :: (text: string) -> (u32, bool) {
  if text.count == 0 return 0, false;
  compact := compact_text(text);
  if compact.count == 0 return 0, false;
  for compact {
    if it == #char "." || it == #char "e" || it == #char "E" {
      return 0, false;
    }
  }

  if compact[compact.count-1] == #char "u" || compact[compact.count-1] == #char "U" {
    compact.count -= 1;
  }

  v, ok := string_to_int(compact);
  if !ok return 0, false;
  if v < 0 || v > 0xFFFF_FFFF return 0, false;
  return cast(u32) v, true;
}

parse_u32_literal_expr :: (expr: *IR_Expr) -> (u32, bool) {
  if !expr || expr.kind != .LITERAL return 0, false;
  value, ok := parse_u32_literal_text(expr.text);
  return value, ok;
}

parse_i64_literal_text :: (text: string) -> (s64, bool) {
  if text.count == 0 return 0, false;
  compact := compact_text(text);
  if compact.count == 0 return 0, false;
  for compact {
    if it == #char "." || it == #char "e" || it == #char "E" {
      return 0, false;
    }
  }

  if compact.count >= 2 {
    end2: string;
    end2.data = compact.data + compact.count - 2;
    end2.count = 2;
    if end2 == "ll" || end2 == "LL" {
      compact.count -= 2;
    }
  }
  if compact.count >= 1 {
    last := compact[compact.count-1];
    if last == #char "l" || last == #char "L" || last == #char "i" || last == #char "I" {
      compact.count -= 1;
    }
  }

  v, ok := string_to_int(compact);
  if !ok return 0, false;
  return v, true;
}

parse_i64_literal_expr :: (expr: *IR_Expr) -> (s64, bool) {
  if !expr || expr.kind != .LITERAL return 0, false;
  value, ok := parse_i64_literal_text(expr.text);
  return value, ok;
}

resolve_ident_or_zero_deref :: (expr: *IR_Expr) -> (name: string, ok: bool) {
  if !expr return "", false;
  if expr.kind == .IDENT return expr.text, true;
  if expr.kind == .CAST && expr.left {
    name, ok := resolve_ident_or_zero_deref(expr.left);
    return name, ok;
  }
  if expr.kind == .UNARY && expr.left && expr.text == "*" {
    name, ok := resolve_ident_or_zero_deref(expr.left);
    return name, ok;
  }
  if expr.kind == .SUBSCRIPT && expr.left && expr.left.kind == .IDENT {
    index_u32, index_u32_ok := parse_u32_literal_expr(expr.right);
    if index_u32_ok && index_u32 == 0 return expr.left.text, true;
    index_i64, index_i64_ok := parse_i64_literal_expr(expr.right);
    if index_i64_ok && index_i64 == 0 return expr.left.text, true;
  }
  return "", false;
}

resolve_member_root_and_field :: (expr: *IR_Expr) -> (root_name: string, field_name: string, ok: bool) {
  if !expr || expr.kind != .MEMBER return "", "", false;
  root_name, root_ok := resolve_ident_or_zero_deref(expr.left);
  if !root_ok return "", "", false;
  return root_name, expr.text, true;
}

expr_text :: (expr: *IR_Expr) -> string {
  text, ok := ir_expr_to_slang_from_ir(expr);
  if !ok return "";
  return text;
}

compact_text :: (in: string) -> string {
  out: [..] u8;
  for in {
    ch := it;
    if ch == #char " " || ch == #char "\t" || ch == #char "\n" || ch == #char "\r" continue;
    array_add(*out, ch);
  }
  return string.{data=out.data, count=out.count};
}

is_thread_x_text :: (text: string) -> bool {
  return text == "thread_id.x" || text == "input.thread_id.x";
}

thread_x_expr :: (expr: *IR_Expr) -> bool {
  return is_thread_x_text(expr_text(expr));
}

values_at_thread_x_expr :: (expr: *IR_Expr, buffer_name: string) -> bool {
  text := expr_text(expr);
  return text == tprint("%[thread_id.x]", buffer_name) || text == tprint("%[input.thread_id.x]", buffer_name);
}

match_branch_condition_outer :: (expr: *IR_Expr) -> (u32, bool) {
  if !expr || expr.kind != .BINARY || expr.text != "<" return 0, false;
  if !thread_x_expr(expr.left) return 0, false;
  bound, ok := parse_u32_literal_expr(expr.right);
  if !ok return 0, false;
  return bound, true;
}

// -----------------------------------------------------------------------------
// IR Data Model
// -----------------------------------------------------------------------------

IR_SPV_Gen_Type :: enum {
  UNKNOWN;
  STRUCT;
  INT;
  UINT;
  INT64;
  UINT64;
  FLOAT;
  FLOAT2;
  FLOAT3;
  FLOAT4;
  FLOAT2X2;
  BOOL;
}

IR_SPV_Gen_Stage :: enum {
  COMPUTE;
  VERTEX;
  FRAGMENT;
}

IR_SPV_Gen_Interface_Builtin :: enum {
  NONE;
  POSITION;
  FRAG_COORD;
  VERTEX_INDEX;
  INSTANCE_INDEX;
}

IR_SPV_Gen_Interface_Var :: struct {
  name: string;
  type: IR_SPV_Gen_Type;
  ptr_id: s64;
  var_id: s64;
  location: s64;
  builtin: IR_SPV_Gen_Interface_Builtin;
}

IR_SPV_Gen_Local :: struct {
  name: string;
  ptr_id: s64;
  type: IR_SPV_Gen_Type;
}

IR_SPV_Gen_Local_Array :: struct {
  name: string;
  element_type: IR_SPV_Gen_Type;
  count: s64;
  var_id: s64;
  array_type_id: s64;
  ptr_func_array_type_id: s64;
  count_const_id: s64;
}

IR_SPV_Gen_Local_Struct_Field :: struct {
  name: string;
  ptr_id: s64;
  type: IR_SPV_Gen_Type;
  nested_struct_name: string;
}

IR_SPV_Gen_Local_Struct :: struct {
  name: string;
  type_name: string;
  fields: [..] IR_SPV_Gen_Local_Struct_Field;
}

IR_SPV_Gen_Buffer_Field :: struct {
  name: string;
  index: s64;
  type: IR_SPV_Gen_Type;
  offset: s64;
}

IR_SPV_Gen_Uniform_Field :: struct {
  name: string;
  index: s64;
  type: IR_SPV_Gen_Type;
  field_type_id: s64;
  is_array: bool;
  array_count: s64;
  array_stride: s64;
  array_type_id: s64;
  array_length_const_id: s64;
  offset: s64;
}

IR_SPV_Gen_Uniform_Block :: struct {
  name: string;
  type_name: string;
  binding_index: s64;
  var_id: s64;
  struct_type_id: s64;
  ptr_uniform_struct_type_id: s64;
  fields: [..] IR_SPV_Gen_Uniform_Field;
}

IR_SPV_Gen_Const_U32 :: struct {
  value: u32;
  id: s64;
}

IR_SPV_Gen_Const_I32 :: struct {
  value: s32;
  id: s64;
}

IR_SPV_Gen_Const_I64 :: struct {
  value: s64;
  id: s64;
}

IR_SPV_Gen_Const_U64 :: struct {
  value: u64;
  id: s64;
}

IR_SPV_Gen_Const_F32 :: struct {
  text: string;
  id: s64;
}

IR_SPV_Gen_Buffer :: struct {
  name: string;
  var_id: s64;
  binding_index: s64;
  element_type_name: string;
  element_kind: IR_SPV_Gen_Type;
  element_type_id: s64;
  runtimearr_type_id: s64;
  fixed_array_count: s64;
  fixed_array_count_const_id: s64;
  wrapper_struct_type_id: s64;
  ptr_wrapper_type_id: s64;
  ptr_storage_element_type_id: s64;
  array_stride: s64;
  fields: [..] IR_SPV_Gen_Buffer_Field;
}

IR_SPV_Gen_Loop_Target :: struct {
  merge_label: s64;
  continue_label: s64;
}

IR_SPV_Gen_Debug_Name :: struct {
  id: s64;
  name: string;
}

IR_SPV_Gen_Debug_Member_Name :: struct {
  type_id: s64;
  member_index: s64;
  name: string;
}

IR_SPV_PS_Struct_Info :: struct {
  name: string;
  prefix: string;
  type_id: s64;
  ptr_type_id: s64;
}

IR_SPV_PS_Ptr_To_Ptr :: struct {
  ptr_type_id: s64;
  ptr_to_ptr_type_id: s64;
}

IR_SPV_Gen_State :: struct {
  next_id: s64;
  locals: [..] IR_SPV_Gen_Local;
  local_arrays: [..] IR_SPV_Gen_Local_Array;
  local_array_types: [..] IR_SPV_Gen_Local_Array;
  local_structs: [..] IR_SPV_Gen_Local_Struct;
  const_u32: [..] IR_SPV_Gen_Const_U32;
  const_i32: [..] IR_SPV_Gen_Const_I32;
  const_i64: [..] IR_SPV_Gen_Const_I64;
  const_u64: [..] IR_SPV_Gen_Const_U64;
  const_f32: [..] IR_SPV_Gen_Const_F32;
  buffers: [..] IR_SPV_Gen_Buffer;
  uniform_blocks: [..] IR_SPV_Gen_Uniform_Block;
  loop_targets: [..] IR_SPV_Gen_Loop_Target;
  break_targets: [..] s64;
  functions: [] IR_Function;
  extra_structs: [..] IR_Struct;
  local_var_lines: [..] string;
  op_lines: [..] string;
  debug_names: [..] IR_SPV_Gen_Debug_Name;
  debug_member_names: [..] IR_SPV_Gen_Debug_Member_Name;
  stage: IR_SPV_Gen_Stage;
  debug_type_prefix: string;
  output_struct_type_name: string;
  input_vars: [..] IR_SPV_Gen_Interface_Var;
  output_vars: [..] IR_SPV_Gen_Interface_Var;
  use_physical_storage: bool;

  id_extinst: s64;
  id_void: s64;
  id_fn_void: s64;
  id_uint: s64;
  id_float: s64;
  id_float2: s64;
  id_float3: s64;
  id_float4: s64;
  id_float2x2: s64;
  id_bool: s64;
  id_bool_true: s64;
  id_bool_false: s64;
  id_v3uint: s64;
  id_ptr_input_v3uint: s64;
  id_gl_global_invocation_id: s64;
  id_ptr_input_uint: s64;
  id_int: s64;
  id_int64: s64;
  id_uint64: s64;
  id_int_0: s64;
  id_int64_0: s64;
  id_uint64_0: s64;
  id_uint_0: s64;
  id_runtimearr_uint: s64;
  id_buffer_struct: s64;
  id_ptr_storage_buffer_struct: s64;
  id_ptr_storage_uint: s64;
  id_ptr_storage_int: s64;
  id_ptr_storage_int64: s64;
  id_ptr_storage_uint64: s64;
  id_ptr_storage_float: s64;
  id_ptr_storage_float2: s64;
  id_ptr_storage_float3: s64;
  id_ptr_input_float: s64;
  id_ptr_input_float2: s64;
  id_ptr_input_float3: s64;
  id_ptr_input_float4: s64;
  id_ptr_output_float: s64;
  id_ptr_output_float2: s64;
  id_ptr_output_float3: s64;
  id_ptr_output_float4: s64;
  id_ptr_uniform_float: s64;
  id_ptr_uniform_float2: s64;
  id_ptr_uniform_float3: s64;
  id_ptr_uniform_float4: s64;
  id_ptr_uniform_int: s64;
  id_ptr_uniform_uint: s64;
  id_ptr_uniform_int64: s64;
  id_ptr_uniform_uint64: s64;
  id_ptr_func_float: s64;
  id_ptr_func_float2: s64;
  id_ptr_func_float3: s64;
  id_ptr_func_float4: s64;
  id_ptr_func_float2x2: s64;
  id_ptr_func_bool: s64;
  id_ptr_func_int: s64;
  id_ptr_func_uint: s64;
  id_ptr_func_int64: s64;
  id_ptr_func_uint64: s64;
  id_main: s64;
  id_bound_const: s64;

  bound_value: u32;
}

// -----------------------------------------------------------------------------
// Core State Helpers
// -----------------------------------------------------------------------------

id_text :: (id: s64) -> string {
  return tprint("%%", "%", id);
}

new_id :: (s: *IR_SPV_Gen_State) -> s64 {
  assert(s != null);
  id := s.next_id;
  s.next_id += 1;
  return id;
}

add_op :: (s: *IR_SPV_Gen_State, line: string) {
  assert(s != null);
  array_add(*s.op_lines, line);
}

add_local_decl :: (s: *IR_SPV_Gen_State, line: string) {
  assert(s != null);
  array_add(*s.local_var_lines, line);
}

sanitize_debug_name :: (name: string) -> string {
  if name.count == 0 return "";
  out: String_Builder;
  for name {
    ch := it;
    if ch == #char "\"" || ch == #char "\\" || ch == #char "\n" || ch == #char "\r" || ch == #char "\t" {
      append(*out, "_");
    } else {
      append(*out, ch);
    }
  }
  return builder_to_string(*out);
}

sanitize_identifier_name :: (name: string) -> string {
  if name.count == 0 return "";
  out: String_Builder;
  for name {
    ch := it;
    is_lower := ch >= #char "a" && ch <= #char "z";
    is_upper := ch >= #char "A" && ch <= #char "Z";
    is_digit := ch >= #char "0" && ch <= #char "9";
    if is_lower || is_upper || is_digit || ch == #char "_" {
      append(*out, ch);
    } else {
      append(*out, "_");
    }
  }
  result := builder_to_string(*out);
  if result.count > 0 {
    first := result[0];
    if first >= #char "0" && first <= #char "9" {
      result = tprint("_%", result);
    }
  }
  return result;
}

debug_type_name :: (s: *IR_SPV_Gen_State, base: string) -> string {
  assert(s != null);
  base_name := sanitize_identifier_name(base);
  prefix := sanitize_identifier_name(s.debug_type_prefix);
  if prefix.count == 0 return base_name;
  if base_name.count == 0 return prefix;
  return tprint("%_%", prefix, base_name);
}

add_debug_name :: (s: *IR_SPV_Gen_State, id: s64, name: string) {
  assert(s != null);
  if id == 0 || name.count == 0 return;
  safe_name := sanitize_debug_name(name);
  if safe_name.count == 0 return;
  for *s.debug_names if it.id == id return;
  array_add(*s.debug_names, .{id=id, name=safe_name});
}

add_debug_member_name :: (s: *IR_SPV_Gen_State, type_id: s64, member_index: s64, name: string) {
  assert(s != null);
  if type_id == 0 || member_index < 0 || name.count == 0 return;
  safe_name := sanitize_debug_name(name);
  if safe_name.count == 0 return;
  for *s.debug_member_names if it.type_id == type_id && it.member_index == member_index return;
  array_add(*s.debug_member_names, .{type_id=type_id, member_index=member_index, name=safe_name});
}

find_by_name :: (arr: *[]$T, name: string) -> *T {
  assert(arr != null);
  for * arr.* if it.name == name return it;
  return null;
}

find_local  :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Local  {
  i := s.locals.count - 1;
  while i >= 0 {
    candidate := s.locals.data + i;
    if candidate.name == name return candidate;
    if i == 0 break;
    i -= 1;
  }
  return null;
}

find_local_array :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Local_Array {
  i := s.local_arrays.count - 1;
  while i >= 0 {
    candidate := s.local_arrays.data + i;
    if candidate.name == name return candidate;
    if i == 0 break;
    i -= 1;
  }
  return null;
}
find_buffer :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Buffer { return find_by_name(*s.buffers, name); }
find_uniform_block :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Uniform_Block { return find_by_name(*s.uniform_blocks, name); }
find_function :: (s: *IR_SPV_Gen_State, name: string) -> *IR_Function { return find_by_name(*s.functions, name); }
find_struct :: (s: *IR_SPV_Gen_State, name: string) -> *IR_Struct { return find_by_name(*s.extra_structs, name); }
find_local_struct :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Local_Struct {
  i := s.local_structs.count - 1;
  while i >= 0 {
    candidate := s.local_structs.data + i;
    if candidate.name == name return candidate;
    if i == 0 break;
    i -= 1;
  }
  return null;
}
find_local_struct_field :: (s: *IR_SPV_Gen_Local_Struct, name: string) -> *IR_SPV_Gen_Local_Struct_Field { return find_by_name(*s.fields, name); }
find_interface_var :: (arr: *[]IR_SPV_Gen_Interface_Var, name: string) -> *IR_SPV_Gen_Interface_Var { return find_by_name(arr, name); }
find_uniform_field :: (uniform: *IR_SPV_Gen_Uniform_Block, name: string) -> *IR_SPV_Gen_Uniform_Field { return find_by_name(*uniform.fields, name); }

find_ps_struct_info :: (arr: *[]IR_SPV_PS_Struct_Info, name: string) -> *IR_SPV_PS_Struct_Info { return find_by_name(arr, name); }

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
    if field.is_pointer return true;
    nested_field_struct_name := field.type.struct_name;
    if nested_field_struct_name.count == 0 nested_field_struct_name = field.type_name;
    for *extra_structs {
      nested := it;
      if nested.name != nested_field_struct_name continue;
      if struct_has_pointer_fields_recursive(extra_structs, nested_field_struct_name, depth + 1) return true;
      break;
    }
  }
  return false;
}

is_uint_type_name :: (name: string) -> bool {
  return name == "uint" || name == "u32";
}

parse_structured_buffer_element_type :: (type_name: string) -> (string, bool) {
  ro_prefix :: "StructuredBuffer<";
  rw_prefix :: "RWStructuredBuffer<";
  prefix := "";
  if begins_with(type_name, ro_prefix) prefix = ro_prefix;
  else if begins_with(type_name, rw_prefix) prefix = rw_prefix;
  else return "", false;
  if type_name.count < prefix.count + 2 return "", false;
  if type_name[type_name.count-1] != #char ">" return "", false;
  out: string;
  out.data = type_name.data + prefix.count;
  out.count = type_name.count - prefix.count - 1;
  if out.count == 0 return "", false;
  return out, true;
}

parse_fixed_array_type_name :: (type_name: string) -> (element_type_name: string, array_count: s64, ok: bool) {
  compact := compact_text(type_name);
  if compact.count < 4 return "", 0, false;
  close_idx := find_index_from_right(compact, "]");
  if close_idx != compact.count-1 return "", 0, false;
  open_idx := find_index_from_right(compact, "[");
  if open_idx <= 0 || open_idx >= close_idx return "", 0, false;
  count_text := slice(compact, open_idx+1, close_idx);
  count_val, count_ok := string_to_int(count_text);
  if !count_ok || count_val <= 0 return "", 0, false;
  elem := slice(compact, 0, open_idx);
  if elem.count == 0 return "", 0, false;
  return elem, count_val, true;
}

struct_has_pointer_fields :: (st: *IR_Struct) -> bool {
  assert(st != null);
  for st.fields if it.is_pointer return true;
  return false;
}

resource_element_type_from_field :: (s: *IR_SPV_Gen_State, field: *IR_Field) -> (string, bool) {
  assert(s != null);
  assert(field != null);

  if field.is_pointer {
    pointee_name := field.pointer_pointee_type_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_struct_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_display_name;
    if pointee_name.count == 0 return "", false;
    if field.pointer_pointee_is_struct {
      nested_struct := find_struct(s, pointee_name);
      if nested_struct && struct_has_pointer_fields(nested_struct) return "", false;
    }
    return pointee_name, true;
  }

  if field.type.kind == .POINTER {
    pointee_name := field.type.pointee_struct_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_display_name;
    if pointee_name.count == 0 return "", false;
    if field.type.pointee_kind == .STRUCT {
      nested_struct := find_struct(s, pointee_name);
      if nested_struct && struct_has_pointer_fields(nested_struct) return "", false;
    }
    return pointee_name, true;
  }

  elem_type_name, is_resource := parse_structured_buffer_element_type(field.type_name);
  return elem_type_name, is_resource;
}

resource_walk_nested_struct :: (s: *IR_SPV_Gen_State, field: *IR_Field) -> *IR_Struct {
  assert(s != null);
  assert(field != null);

  if field.is_pointer && field.pointer_pointee_is_struct && field.pointer_pointee_type_name.count != 0 {
    nested := find_struct(s, field.pointer_pointee_type_name);
    if nested && struct_has_pointer_fields(nested) return nested;
  }
  if field.type.kind == .POINTER && field.type.pointee_kind == .STRUCT && field.type.pointee_struct_name.count != 0 {
    nested := find_struct(s, field.type.pointee_struct_name);
    if nested && struct_has_pointer_fields(nested) return nested;
  }
  if field.type.kind == .STRUCT && field.type.struct_name.count != 0 {
    return find_struct(s, field.type.struct_name);
  }
  return find_struct(s, field.type_name);
}

collect_struct_resource_fields :: (s: *IR_SPV_Gen_State, st: *IR_Struct, name_prefix: string, out_buffers: *[..] IR_Compute_Buffer) -> (has_resource: bool, has_non_resource: bool) {
  assert(s != null);
  assert(st != null);

  has_resource := false;
  has_non_resource := false;
  for st.fields {
    field_path := ifx name_prefix.count == 0 then it.name else tprint("%.%", name_prefix, it.name);
    elem_type_name, is_resource_field := resource_element_type_from_field(s, *it);
    if is_resource_field {
      has_resource = true;
      if out_buffers {
        array_add(out_buffers, .{
          name = field_path,
          element_type = .{display_name = elem_type_name},
          element_type_name = elem_type_name,
        });
      }
      continue;
    }

    nested_struct := resource_walk_nested_struct(s, *it);
    if nested_struct {
      nested_has_resource, nested_has_non_resource := collect_struct_resource_fields(s, nested_struct, field_path, out_buffers);
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
  return_err :: (message: string, args: ..Any) #expand { `return false, { message = sprint(message, ..args) }; }

  assert(s != null);
  assert(out_buffers != null);
  diag: IR_Diagnostic;

  for in_buffers {
    buf := it;
    struct_def := find_struct(s, buf.element_type_name);
    if !struct_def {
      array_add(out_buffers, buf);
      continue;
    }

    saw_resource, saw_non_resource := collect_struct_resource_fields(s, struct_def, buf.name, out_buffers);
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

normalize_f32_literal_text :: (text: string) -> string {
  out := compact_text(text);
  if out.count > 0 {
    last := out[out.count-1];
    if last == #char "f" || last == #char "F" {
      out.count -= 1;
    }
  }
  return out;
}

parse_f32_literal_text :: (text: string) -> (string, bool) {
  normalized := normalize_f32_literal_text(text);
  if normalized.count == 0 return "", false;
  _, ok, remainder := string_to_float(normalized);
  if !ok || remainder.count != 0 return "", false;
  return normalized, true;
}

get_u32_const :: (s: *IR_SPV_Gen_State, value: u32) -> s64 {
  for s.const_u32 if it.value == value return it.id;
  id := new_id(s);
  array_add(*s.const_u32, .{value=value, id=id});
  return id;
}

get_i32_const :: (s: *IR_SPV_Gen_State, value: s32) -> s64 {
  for s.const_i32 if it.value == value return it.id;
  id := new_id(s);
  array_add(*s.const_i32, .{value=value, id=id});
  return id;
}

get_i64_const :: (s: *IR_SPV_Gen_State, value: s64) -> s64 {
  for s.const_i64 if it.value == value return it.id;
  id := new_id(s);
  array_add(*s.const_i64, .{value=value, id=id});
  return id;
}

get_u64_const :: (s: *IR_SPV_Gen_State, value: u64) -> s64 {
  for s.const_u64 if it.value == value return it.id;
  id := new_id(s);
  array_add(*s.const_u64, .{value=value, id=id});
  return id;
}

get_f32_const :: (s: *IR_SPV_Gen_State, text: string) -> s64 {
  for s.const_f32 if it.text == text return it.id;
  id := new_id(s);
  array_add(*s.const_f32, .{text=text, id=id});
  return id;
}

get_current_loop_target :: (s: *IR_SPV_Gen_State) -> (IR_SPV_Gen_Loop_Target, bool) {
  if s.loop_targets.count == 0 return .{}, false;
  return s.loop_targets[s.loop_targets.count-1], true;
}

get_current_break_target :: (s: *IR_SPV_Gen_State) -> (s64, bool) {
  if s.break_targets.count == 0 return 0, false;
  return s.break_targets[s.break_targets.count-1], true;
}

// -----------------------------------------------------------------------------
// Type Mapping / Layout
// -----------------------------------------------------------------------------

init_base :: (s: *IR_SPV_Gen_State, buffers: [] IR_Compute_Buffer, bound_value: u32, use_physical_storage := false) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, { message = sprint(msg, ..args) }; }

  diag: IR_Diagnostic;
  assert(s != null);
  s.next_id = 1;
  s.bound_value = bound_value;
  s.use_physical_storage = use_physical_storage;

  s.id_extinst = new_id(s);
  s.id_void = new_id(s);
  s.id_fn_void = new_id(s);
  s.id_uint = new_id(s);
  s.id_float = new_id(s);
  s.id_float2 = new_id(s);
  s.id_float3 = new_id(s);
  s.id_float4 = new_id(s);
  s.id_float2x2 = new_id(s);
  s.id_bool = new_id(s);
  s.id_bool_true = new_id(s);
  s.id_bool_false = new_id(s);
  s.id_v3uint = new_id(s);
  s.id_ptr_input_v3uint = new_id(s);
  s.id_gl_global_invocation_id = new_id(s);
  s.id_uint_0 = get_u32_const(s, 0);
  s.id_ptr_input_uint = new_id(s);
  s.id_bound_const = get_u32_const(s, bound_value);
  s.id_runtimearr_uint = new_id(s);
  s.id_buffer_struct = new_id(s);
  s.id_ptr_storage_buffer_struct = new_id(s);
  s.id_int = new_id(s);
  s.id_int64 = new_id(s);
  s.id_uint64 = new_id(s);
  s.id_int_0 = get_i32_const(s, 0);
  s.id_int64_0 = get_i64_const(s, 0);
  s.id_uint64_0 = get_u64_const(s, 0);
  s.id_ptr_storage_uint = new_id(s);
  s.id_ptr_storage_int = new_id(s);
  s.id_ptr_storage_int64 = new_id(s);
  s.id_ptr_storage_uint64 = new_id(s);
  s.id_ptr_storage_float = new_id(s);
  s.id_ptr_storage_float2 = new_id(s);
  s.id_ptr_storage_float3 = new_id(s);
  s.id_ptr_input_float = new_id(s);
  s.id_ptr_input_float2 = new_id(s);
  s.id_ptr_input_float3 = new_id(s);
  s.id_ptr_input_float4 = new_id(s);
  s.id_ptr_output_float = new_id(s);
  s.id_ptr_output_float2 = new_id(s);
  s.id_ptr_output_float3 = new_id(s);
  s.id_ptr_output_float4 = new_id(s);
  s.id_ptr_uniform_int = new_id(s);
  s.id_ptr_uniform_uint = new_id(s);
  s.id_ptr_uniform_int64 = new_id(s);
  s.id_ptr_uniform_uint64 = new_id(s);
  s.id_ptr_uniform_float = new_id(s);
  s.id_ptr_uniform_float2 = new_id(s);
  s.id_ptr_uniform_float3 = new_id(s);
  s.id_ptr_uniform_float4 = new_id(s);
  s.id_ptr_func_float = new_id(s);
  s.id_ptr_func_float2 = new_id(s);
  s.id_ptr_func_float3 = new_id(s);
  s.id_ptr_func_float4 = new_id(s);
  s.id_ptr_func_float2x2 = new_id(s);
  s.id_ptr_func_bool = new_id(s);
  s.id_ptr_func_int = new_id(s);
  s.id_ptr_func_uint = new_id(s);
  s.id_ptr_func_int64 = new_id(s);
  s.id_ptr_func_uint64 = new_id(s);
  s.id_main = new_id(s);

  for buffers {
    var_id := new_id(s);
    buffer_info: IR_SPV_Gen_Buffer;
    buffer_info.name = it.name;
    buffer_info.var_id = var_id;
    buffer_info.binding_index = it_index;

    element_type_name := it.element_type_name;
    parsed_array_count: s64;
    parsed_fixed_array := false;
    elem_kind := spv_kind_from_ir_type_kind(it.element_type.kind);

    if it.element_type.kind == .FIXED_ARRAY {
      parsed_fixed_array = true;
      parsed_array_count = it.element_type.array_count;
      element_type_name = it.element_type.element_display_name;
      if element_type_name.count == 0 element_type_name = it.element_type_name;
      elem_kind = spv_kind_from_ir_type_kind(it.element_type.element_kind);
    } else {
      parsed_elem_type_name, parsed_count, parsed_array := parse_fixed_array_type_name(element_type_name);
      if parsed_array {
        parsed_fixed_array = true;
        parsed_array_count = parsed_count;
        element_type_name = parsed_elem_type_name;
      }
    }

    if parsed_fixed_array {
      if parsed_array_count > 0xFFFF_FFFF {
        return_err("SPIR-V generic backend: buffer '%' fixed array count % exceeds u32.", it.name, parsed_array_count);
      }
      buffer_info.fixed_array_count = parsed_array_count;
      buffer_info.fixed_array_count_const_id = get_u32_const(s, cast(u32) parsed_array_count);
    }
    buffer_info.element_type_name = element_type_name;
    if elem_kind == .UNKNOWN elem_kind = expr_type_from_decl(element_type_name);
    if elem_kind != .UNKNOWN && elem_kind != .STRUCT {
      buffer_info.element_kind = elem_kind;
      buffer_info.element_type_id = type_id_from_kind(s, elem_kind);
      if buffer_info.element_type_id == 0 {
        return_err("SPIR-V generic backend: buffer '%' has unsupported primitive element type '%'.", it.name, element_type_name);
      }

      if elem_kind == .UINT && !parsed_fixed_array {
        buffer_info.runtimearr_type_id = s.id_runtimearr_uint;
        buffer_info.wrapper_struct_type_id = s.id_buffer_struct;
        buffer_info.ptr_wrapper_type_id = s.id_ptr_storage_buffer_struct;
        buffer_info.ptr_storage_element_type_id = s.id_ptr_storage_uint;
        buffer_info.array_stride = 4;
      } else {
        buffer_info.runtimearr_type_id = new_id(s);
        buffer_info.wrapper_struct_type_id = new_id(s);
        buffer_info.ptr_wrapper_type_id = new_id(s);
        buffer_info.ptr_storage_element_type_id = new_id(s);
        buffer_info.array_stride = byte_size_of_kind(elem_kind);
        add_debug_name(s, buffer_info.runtimearr_type_id, debug_type_name(s, tprint("%_data_array", buffer_info.name)));
        add_debug_name(s, buffer_info.wrapper_struct_type_id, debug_type_name(s, tprint("%_buffer", buffer_info.name)));
        add_debug_member_name(s, buffer_info.wrapper_struct_type_id, 0, "data");
      }
      array_add(*s.buffers, buffer_info);
      continue;
    }

    struct_type_name := element_type_name;
    if it.element_type.kind == .STRUCT && it.element_type.struct_name.count != 0 {
      struct_type_name = it.element_type.struct_name;
    } else if it.element_type.kind == .FIXED_ARRAY && it.element_type.element_kind == .STRUCT && it.element_type.element_struct_name.count != 0 {
      struct_type_name = it.element_type.element_struct_name;
    }

    struct_def := find_struct(s, struct_type_name);
    if !struct_def {
      return_err("SPIR-V generic backend: buffer '%' has unsupported element type '%'.", it.name, struct_type_name);
    }

    element_struct_type_id := new_id(s);
    runtimearr_type_id := new_id(s);
    wrapper_struct_type_id := new_id(s);
    ptr_wrapper_type_id := new_id(s);
    ptr_storage_element_type_id := new_id(s);

    buffer_info.element_kind = .STRUCT;
    buffer_info.element_type_id = element_struct_type_id;
    buffer_info.runtimearr_type_id = runtimearr_type_id;
    buffer_info.wrapper_struct_type_id = wrapper_struct_type_id;
    buffer_info.ptr_wrapper_type_id = ptr_wrapper_type_id;
    buffer_info.ptr_storage_element_type_id = ptr_storage_element_type_id;

    offset: s64 = 0;
    for struct_def.fields {
      field_type := spv_kind_from_ir_type_kind(it.type.kind);
      if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
      if field_type == .UNKNOWN {
        return_err("SPIR-V generic backend: buffer struct '%' field '%' type '%' is unsupported.", struct_def.name, it.name, it.type_name);
      }
      field_size := byte_size_of_kind(field_type);
      if field_size <= 0 {
        return_err("SPIR-V generic backend: buffer struct '%' field '%' has unsupported layout type '%'.", struct_def.name, it.name, it.type_name);
      }
      array_add(*buffer_info.fields, .{
        name = it.name,
        index = it_index,
        type = field_type,
        offset = offset,
      });
      add_debug_member_name(s, buffer_info.element_type_id, it_index, it.name);
      offset += field_size;
    }
    buffer_info.array_stride = offset;
    add_debug_name(s, buffer_info.element_type_id, debug_type_name(s, element_type_name));
    add_debug_name(s, buffer_info.runtimearr_type_id, debug_type_name(s, tprint("%_data_array", buffer_info.name)));
    add_debug_name(s, buffer_info.wrapper_struct_type_id, debug_type_name(s, tprint("%_buffer", buffer_info.name)));
    add_debug_member_name(s, buffer_info.wrapper_struct_type_id, 0, "data");
    array_add(*s.buffers, buffer_info);
  }

  return true, diag;
}

load_thread_x :: (s: *IR_SPV_Gen_State) -> s64 {
  return load_thread_component(s, 0);
}

load_thread_component :: (s: *IR_SPV_Gen_State, component_index: s64) -> s64 {
  assert(s != null);
  assert(component_index >= 0 && component_index <= 2);
  thread_id_ptr := new_id(s);
  add_op(s, tprint("         % = OpAccessChain % % %",
                              id_text(thread_id_ptr),
                              id_text(s.id_ptr_input_uint),
                              id_text(s.id_gl_global_invocation_id),
                              id_text(get_u32_const(s, cast(u32) component_index))));
  thread_id := new_id(s);
  add_op(s, tprint("         % = OpLoad % %",
                              id_text(thread_id),
                              id_text(s.id_uint),
                              id_text(thread_id_ptr)));
  return thread_id;
}

physical_aligned_suffix :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> string {
  assert(s != null);
  if !s.use_physical_storage return "";
  align := byte_size_of_kind(kind);
  if align <= 0 align = 4;
  return tprint(" Aligned %", align);
}

emit_load :: (s: *IR_SPV_Gen_State, result_id: s64, type_id: s64, ptr_id: s64, kind: IR_SPV_Gen_Type, needs_physical_align := false) {
  assert(s != null);
  suffix := "";
  if needs_physical_align suffix = physical_aligned_suffix(s, kind);
  add_op(s, tprint("         % = OpLoad % %%", id_text(result_id), id_text(type_id), id_text(ptr_id), suffix));
}

emit_store :: (s: *IR_SPV_Gen_State, ptr_id: s64, value_id: s64, kind: IR_SPV_Gen_Type, needs_physical_align := false) {
  assert(s != null);
  suffix := "";
  if needs_physical_align suffix = physical_aligned_suffix(s, kind);
  add_op(s, tprint("               OpStore % %%", id_text(ptr_id), id_text(value_id), suffix));
}

align_up :: (value: s64, alignment: s64) -> s64 {
  if alignment <= 1 return value;
  mask := alignment - 1;
  return (value + mask) & ~mask;
}

find_buffer_field :: (buffer: *IR_SPV_Gen_Buffer, name: string) -> *IR_SPV_Gen_Buffer_Field {
  assert(buffer != null);
  return find_by_name(*buffer.fields, name);
}

alloc_local_struct :: (s: *IR_SPV_Gen_State, name: string, type_name: string) -> (local_struct: *IR_SPV_Gen_Local_Struct, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  struct_def := find_struct(s, type_name);
  if !struct_def {
    diag.message = tprint("SPIR-V backend: unknown local struct type '%'.", type_name);
    return null, false, diag;
  }

  local_struct: IR_SPV_Gen_Local_Struct;
  local_struct.name = name;
  local_struct.type_name = type_name;
  for struct_def.fields {
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN || field_type == .STRUCT {
      nested_def := find_struct(s, it.type_name);
      if !nested_def {
        diag.message = tprint("SPIR-V backend: local struct '%' field '%' has unsupported type '%'.", type_name, it.name, it.type_name);
        return null, false, diag;
      }
      nested_name := tprint("%.%", name, it.name);
      _, nested_ok, nested_diag := alloc_local_struct(s, nested_name, it.type_name);
      if !nested_ok return null, false, nested_diag;
      array_add(*local_struct.fields, .{
        name = it.name,
        ptr_id = 0,
        type = .STRUCT,
        nested_struct_name = nested_name,
      });
      continue;
    }
    field_ptr_type := func_ptr_type_id_from_kind(s, field_type);
    if field_ptr_type == 0 {
      diag.message = tprint("SPIR-V backend: local struct '%' field '%' type '%' has no function pointer type.", type_name, it.name, it.type_name);
      return null, false, diag;
    }
    field_ptr := new_id(s);
    add_local_decl(s, tprint("         % = OpVariable % Function",
                             id_text(field_ptr),
                             id_text(field_ptr_type)));
    add_debug_name(s, field_ptr, tprint("%.%", name, it.name));
    array_add(*local_struct.fields, .{name=it.name, ptr_id=field_ptr, type=field_type});
  }

  array_add(*s.local_structs, local_struct);
  out_struct := find_local_struct(s, name);
  if !out_struct {
    diag.message = tprint("SPIR-V backend: failed to register local struct '%'.", name);
    return null, false, diag;
  }
  return out_struct, true, diag;
}

copy_local_struct_fields :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, src: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !dst || !src {
    return false, { message="SPIR-V backend: null struct while copying fields." };
  }
  if dst.type_name != src.type_name {
    return false, { message=tprint("SPIR-V backend: struct copy type mismatch ('%' vs '%').", dst.type_name, src.type_name) };
  }
  for dst.fields {
    src_field := find_local_struct_field(src, it.name);
    if !src_field  return false, { message = tprint("SPIR-V backend: source struct '%' missing field '%'.", src.type_name, it.name) };
    if it.type == .STRUCT {
      if src_field.type != .STRUCT {
        return false, { message = tprint("SPIR-V backend: struct field '%' type mismatch.", it.name) };
      }
      dst_nested := find_local_struct(s, it.nested_struct_name);
      src_nested := find_local_struct(s, src_field.nested_struct_name);
      if !dst_nested || !src_nested {
        return false, { message = tprint("SPIR-V backend: nested struct field '%' could not be resolved.", it.name) };
      }
      nested_ok, nested_diag := copy_local_struct_fields(s, dst_nested, src_nested);
      if !nested_ok return false, nested_diag;
      continue;
    }
    if src_field.type != it.type {
      return false, { message = tprint("SPIR-V backend: struct field '%' type mismatch.", it.name) };
    }
    value_id := new_id(s);
    type_id := type_id_from_kind(s, it.type);
    add_op(s, tprint("         % = OpLoad % %",
                     id_text(value_id),
                     id_text(type_id),
                     id_text(src_field.ptr_id)));
    add_op(s, tprint("               OpStore % %",
                     id_text(it.ptr_id),
                     id_text(value_id)));
  }
  return true, diag;
}

init_local_struct_from_expr :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !dst || !expr {
    diag.message = "SPIR-V backend: null struct init inputs.";
    return false, diag;
  }

  if expr.kind == .IDENT {
    src := find_local_struct(s, expr.text);
    if !src {
      diag.message = tprint("SPIR-V backend: struct init source '%' is not a local struct.", expr.text);
      return false, diag;
    }
    if src.type_name != dst.type_name {
      diag.message = tprint("SPIR-V backend: struct init type mismatch ('%' vs '%').", dst.type_name, src.type_name);
      return false, diag;
    }
    copy_ok, copy_diag := copy_local_struct_fields(s, dst, src);
    return copy_ok, copy_diag;
  }

  if expr.kind != .CONSTRUCTOR || expr.text != dst.type_name {
    diag.message = tprint("SPIR-V backend: unsupported struct init expression for type '%'.", dst.type_name);
    return false, diag;
  }
  if expr.args.count > dst.fields.count {
    diag.message = tprint("SPIR-V backend: struct constructor for '%' has too many arguments.", dst.type_name);
    return false, diag;
  }

  resolved_args: [..] *IR_Expr;
  array_resize(*resolved_args, dst.fields.count);
  for 0..resolved_args.count-1 resolved_args[it] = null;

  field_index_from_name :: (fields: [] IR_SPV_Gen_Local_Struct_Field, name: string) -> s64 {
    for fields if it.name == name return it_index;
    return -1;
  }

  positional_index: s64 = 0;
  for expr.args {
    arg_expr := it;
    if arg_expr && arg_expr.kind == .BINARY && arg_expr.text == "=" &&
       arg_expr.left && arg_expr.left.kind == .IDENT {
      field_name := arg_expr.left.text;
      named_index := field_index_from_name(dst.fields, field_name);
      if named_index < 0 {
        diag.message = tprint("SPIR-V backend: constructor for '%' has unknown named field '%'.", dst.type_name, field_name);
        return false, diag;
      }
      if resolved_args[named_index] {
        diag.message = tprint("SPIR-V backend: constructor for '%' sets field '%' more than once.", dst.type_name, field_name);
        return false, diag;
      }
      resolved_args[named_index] = arg_expr.right;
      continue;
    }

    while positional_index < resolved_args.count && resolved_args[positional_index] positional_index += 1;
    if positional_index >= resolved_args.count {
      diag.message = tprint("SPIR-V backend: constructor for '%' has too many positional arguments.", dst.type_name);
      return false, diag;
    }
    resolved_args[positional_index] = arg_expr;
    positional_index += 1;
  }

  for 0..resolved_args.count-1 {
    if !resolved_args[it] {
      diag.message = tprint("SPIR-V backend: constructor for '%' is missing field '%'.", dst.type_name, dst.fields[it].name);
      return false, diag;
    }
  }

  for dst.fields {
    arg_expr := resolved_args[it_index];
    if it.type == .STRUCT {
      nested_dst := find_local_struct(s, it.nested_struct_name);
      if !nested_dst {
        diag.message = tprint("SPIR-V backend: nested struct destination missing for field '%'.", it.name);
        return false, diag;
      }
      nested_ok, nested_diag := init_local_struct_from_expr(s, nested_dst, arg_expr);
      if !nested_ok return false, nested_diag;
      continue;
    }

    value_id, value_type, value_ok, value_diag := emit_expr(s, arg_expr);
    if !value_ok return false, value_diag;
    if value_type != it.type {
      diag.message = tprint("SPIR-V backend: struct constructor field '%' type mismatch.", it.name);
      return false, diag;
    }
    add_op(s, tprint("               OpStore % %",
                     id_text(it.ptr_id),
                     id_text(value_id)));
  }

  return true, diag;
}

emit_buffer_struct_field_ptr :: (s: *IR_SPV_Gen_State, subscript: *IR_Expr, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(message, ..args) }; }
  
  assert(s != null);
  diag: IR_Diagnostic;
  if !subscript || subscript.kind != .SUBSCRIPT return_err("SPIR-V backend: expected subscript expression for buffer struct field access.");

  buffer_name, base_ok := resolve_ident_or_zero_deref(subscript.left);
  if base_ok {
    // already resolved
  } else if subscript.left && subscript.left.kind == .MEMBER {
    member_root, member_field, member_ok := resolve_member_root_and_field(subscript.left);
    if member_ok {
      buffer_name = tprint("%.%", member_root, member_field);
    } else {
      buffer_name = expr_text(subscript.left);
    }
  } else {
    return_err("SPIR-V backend: subscript base must resolve to a buffer identifier/member.");
  }

  buffer := find_buffer(s, buffer_name);
  if !buffer return_err("SPIR-V backend: unknown subscript base '%'.", buffer_name);
  
  if buffer.element_kind != .STRUCT return_err("SPIR-V backend: buffer '%' is not a struct buffer.", buffer.name);
  field := find_buffer_field(buffer, field_name);
  if !field {
    diag.message = tprint("SPIR-V backend: unknown field '%.%'.", buffer.name, field_name);
    return 0, .UNKNOWN, false, diag;
  }

  idx_id, idx_type, idx_ok, idx_diag := emit_expr(s, subscript.right);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;
  idx_id, idx_ok, idx_diag = coerce_to_kind(s, idx_id, idx_type, .UINT);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;

  field_ptr_type_id := storage_ptr_type_id_from_kind(s, field.type);
  if field_ptr_type_id == 0 return_err("SPIR-V backend: unsupported struct buffer field type for '%.%'.", buffer.name, field.name);

  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, tprint("         % = OpAccessChain % % % % %",
                   id_text(ptr),
                   id_text(field_ptr_type_id),
                   id_text(buffer.var_id),
                   id_text(s.id_int_0),
                   id_text(idx_id),
                   id_text(field_index_id)));
  return ptr, field.type, true, diag;
}

emit_uniform_field_ptr :: (s: *IR_SPV_Gen_State, uniform_name: string, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(message, ..args) }; }

  assert(s != null);
  diag: IR_Diagnostic;
  uniform := find_uniform_block(s, uniform_name);
  if !uniform return_err("SPIR-V backend: unknown uniform block '%'.", uniform_name);
  field := find_uniform_field(uniform, field_name);
  if !field return_err("SPIR-V backend: unknown uniform field '%.%'.", uniform_name, field_name);
  if field.is_array return_err("SPIR-V backend: uniform field '%.%' is an array; index it first.", uniform_name, field_name);
  ptr_type_id := uniform_ptr_type_id_from_kind(s, field.type);
  if ptr_type_id == 0 return_err("SPIR-V backend: unsupported uniform field type for '%.%'.", uniform_name, field_name);
  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, tprint("         % = OpAccessChain % % %",
                   id_text(ptr),
                   id_text(ptr_type_id),
                   id_text(uniform.var_id),
                   id_text(field_index_id)));
  return ptr, field.type, true, diag;
}

emit_uniform_array_element_ptr :: (s: *IR_SPV_Gen_State, uniform_name: string, field_name: string, index_id: s64, index_type: IR_SPV_Gen_Type) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(message, ..args) }; }

  assert(s != null);
  diag: IR_Diagnostic;
  index_id, index_ok, index_diag := coerce_to_kind(s, index_id, index_type, .UINT);
  if !index_ok return 0, .UNKNOWN, false, index_diag;
  uniform := find_uniform_block(s, uniform_name);
  if !uniform return_err("SPIR-V backend: unknown uniform block '%'.", uniform_name);
  field := find_uniform_field(uniform, field_name);
  if !field return_err("SPIR-V backend: unknown uniform field '%.%'.", uniform_name, field_name);
  if !field.is_array return_err("SPIR-V backend: uniform field '%.%' is not an array.", uniform_name, field_name);
  elem_ptr_type_id := uniform_ptr_type_id_from_kind(s, field.type);
  if elem_ptr_type_id == 0 return_err("SPIR-V backend: unsupported uniform array element type for '%.%'.", uniform_name, field_name);
  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, tprint("         % = OpAccessChain % % % %",
                   id_text(ptr),
                   id_text(elem_ptr_type_id),
                   id_text(uniform.var_id),
                   id_text(field_index_id),
                   id_text(index_id)));
  return ptr, field.type, true, diag;
}

emit_int_binary_op :: (s: *IR_SPV_Gen_State, op: string, kind: IR_SPV_Gen_Type, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  assert(is_integral_kind(kind));
  diag: IR_Diagnostic;
  type_id := type_id_from_kind(s, kind);
  if type_id == 0 {
    diag.message = tprint("SPIR-V backend: missing SPIR-V type for integer kind %.", kind);
    return 0, .UNKNOWN, false, diag;
  }
  is_signed := is_signed_integral_kind(kind);
  result_id := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpIAdd % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpISub % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpIMul % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "/" {
    op_name := ifx is_signed then "OpSDiv" else "OpUDiv";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(type_id), id_text(left_id), id_text(right_id)));
    return result_id, kind, true, diag;
  }
  if op == "%" {
    op_name := ifx is_signed then "OpSMod" else "OpUMod";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(type_id), id_text(left_id), id_text(right_id)));
    return result_id, kind, true, diag;
  }
  if op == "|" { add_op(s, tprint("         % = OpBitwiseOr % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "&" { add_op(s, tprint("         % = OpBitwiseAnd % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "^" { add_op(s, tprint("         % = OpBitwiseXor % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == "<<" { add_op(s, tprint("         % = OpShiftLeftLogical % % %", id_text(result_id), id_text(type_id), id_text(left_id), id_text(right_id))); return result_id, kind, true, diag; }
  if op == ">>" {
    op_name := ifx is_signed then "OpShiftRightArithmetic" else "OpShiftRightLogical";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(type_id), id_text(left_id), id_text(right_id)));
    return result_id, kind, true, diag;
  }
  if op == "<"  {
    op_name := ifx is_signed then "OpSLessThan" else "OpULessThan";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(s.id_bool), id_text(left_id), id_text(right_id)));
    return result_id, .BOOL, true, diag;
  }
  if op == ">"  {
    op_name := ifx is_signed then "OpSGreaterThan" else "OpUGreaterThan";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(s.id_bool), id_text(left_id), id_text(right_id)));
    return result_id, .BOOL, true, diag;
  }
  if op == "<=" {
    op_name := ifx is_signed then "OpSLessThanEqual" else "OpULessThanEqual";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(s.id_bool), id_text(left_id), id_text(right_id)));
    return result_id, .BOOL, true, diag;
  }
  if op == ">=" {
    op_name := ifx is_signed then "OpSGreaterThanEqual" else "OpUGreaterThanEqual";
    add_op(s, tprint("         % = % % % %", id_text(result_id), op_name, id_text(s.id_bool), id_text(left_id), id_text(right_id)));
    return result_id, .BOOL, true, diag;
  }
  if op == "==" { add_op(s, tprint("         % = OpIEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == "!=" { add_op(s, tprint("         % = OpINotEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported integer binary op '%' for kind %.", op, kind);
  return 0, .UNKNOWN, false, diag;
}

coerce_to_float :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT return value_id, true, diag;
  if value_type == .UINT || value_type == .UINT64 {
    converted := new_id(s);
    add_op(s, tprint("         % = OpConvertUToF % %",
                     id_text(converted),
                     id_text(s.id_float),
                     id_text(value_id)));
    return converted, true, diag;
  }
  if value_type == .INT || value_type == .INT64 {
    converted := new_id(s);
    add_op(s, tprint("         % = OpConvertSToF % %",
                     id_text(converted),
                     id_text(s.id_float),
                     id_text(value_id)));
    return converted, true, diag;
  }
  diag.message = "SPIR-V backend: cannot coerce value to float.";
  return 0, false, diag;
}

coerce_to_float2 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float2_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT2 return value_id, true, diag;
  if value_type == .FLOAT return splat_float2(s, value_id), true, diag;
  diag.message = "SPIR-V backend: cannot coerce value to float2.";
  return 0, false, diag;
}

coerce_to_float3 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float3_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT3 return value_id, true, diag;
  if value_type == .FLOAT return splat_float3(s, value_id), true, diag;
  diag.message = "SPIR-V backend: cannot coerce value to float3.";
  return 0, false, diag;
}

coerce_to_float4 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float4_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT4 return value_id, true, diag;
  if value_type == .FLOAT return splat_float4(s, value_id), true, diag;
  diag.message = "SPIR-V backend: cannot coerce value to float4.";
  return 0, false, diag;
}

coerce_to_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if src_type == dst_type return value_id, true, diag;
  dst_type_id := type_id_from_kind(s, dst_type);
  if dst_type_id == 0 {
    diag.message = tprint("SPIR-V backend: unsupported coercion destination type %.", dst_type);
    return 0, false, diag;
  }

  out := new_id(s);
  if dst_type == .FLOAT {
    if src_type == .UINT || src_type == .UINT64 {
      add_op(s, tprint("         % = OpConvertUToF % %",
                       id_text(out),
                       id_text(s.id_float),
                       id_text(value_id)));
      return out, true, diag;
    }
    if src_type == .INT || src_type == .INT64 {
      add_op(s, tprint("         % = OpConvertSToF % %",
                       id_text(out),
                       id_text(s.id_float),
                       id_text(value_id)));
      return out, true, diag;
    }
  }

  if dst_type == .BOOL && src_type == .BOOL return value_id, true, diag;

  if is_integral_kind(dst_type) {
    if src_type == .FLOAT {
      op_name := ifx is_signed_integral_kind(dst_type) then "OpConvertFToS" else "OpConvertFToU";
      add_op(s, tprint("         % = % % %",
                       id_text(out),
                       op_name,
                       id_text(dst_type_id),
                       id_text(value_id)));
      return out, true, diag;
    }
    if is_integral_kind(src_type) {
      if is_signed_integral_kind(dst_type) {
        add_op(s, tprint("         % = OpSConvert % %",
                         id_text(out),
                         id_text(dst_type_id),
                         id_text(value_id)));
      } else {
        add_op(s, tprint("         % = OpUConvert % %",
                         id_text(out),
                         id_text(dst_type_id),
                         id_text(value_id)));
      }
      return out, true, diag;
    }
  }

  diag.message = tprint("SPIR-V backend: unsupported coercion from % to %.", src_type, dst_type);
  return 0, false, diag;
}

coerce_to_exact_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, out_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if src_type == dst_type return value_id, src_type, true, diag;
  if dst_type == .FLOAT2 {
    coerced, coerced_ok, coerced_diag := coerce_to_float2(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT2, true, diag;
  }
  if dst_type == .FLOAT3 {
    coerced, coerced_ok, coerced_diag := coerce_to_float3(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT3, true, diag;
  }
  if dst_type == .FLOAT4 {
    coerced, coerced_ok, coerced_diag := coerce_to_float4(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT4, true, diag;
  }
  coerced, coerced_ok, coerced_diag := coerce_to_kind(s, value_id, src_type, dst_type);
  if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
  return coerced, dst_type, true, diag;
}

emit_float_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  result := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpFAdd % % %", id_text(result), id_text(s.id_float), id_text(left_id), id_text(right_id))); return result, .FLOAT, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpFSub % % %", id_text(result), id_text(s.id_float), id_text(left_id), id_text(right_id))); return result, .FLOAT, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpFMul % % %", id_text(result), id_text(s.id_float), id_text(left_id), id_text(right_id))); return result, .FLOAT, true, diag; }
  if op == "/" { add_op(s, tprint("         % = OpFDiv % % %", id_text(result), id_text(s.id_float), id_text(left_id), id_text(right_id))); return result, .FLOAT, true, diag; }
  if op == "<"  { add_op(s, tprint("         % = OpFOrdLessThan % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  if op == ">"  { add_op(s, tprint("         % = OpFOrdGreaterThan % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  if op == "<=" { add_op(s, tprint("         % = OpFOrdLessThanEqual % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  if op == ">=" { add_op(s, tprint("         % = OpFOrdGreaterThanEqual % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  if op == "==" { add_op(s, tprint("         % = OpFOrdEqual % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  if op == "!=" { add_op(s, tprint("         % = OpFOrdNotEqual % % %", id_text(result), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result, .BOOL, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported float binary op '%'.", op);
  return 0, .UNKNOWN, false, diag;
}

splat_float2 :: (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 {
  assert(s != null);
  out := new_id(s);
  add_op(s, tprint("         % = OpCompositeConstruct % % %",
                   id_text(out),
                   id_text(s.id_float2),
                   id_text(scalar_id),
                   id_text(scalar_id)));
  return out;
}

splat_float3 :: (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 {
  assert(s != null);
  out := new_id(s);
  add_op(s, tprint("         % = OpCompositeConstruct % % % %",
                   id_text(out),
                   id_text(s.id_float3),
                   id_text(scalar_id),
                   id_text(scalar_id),
                   id_text(scalar_id)));
  return out;
}

splat_float4 :: (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 {
  assert(s != null);
  out := new_id(s);
  add_op(s, tprint("         % = OpCompositeConstruct % % % % %",
                   id_text(out),
                   id_text(s.id_float4),
                   id_text(scalar_id),
                   id_text(scalar_id),
                   id_text(scalar_id),
                   id_text(scalar_id)));
  return out;
}

emit_float2_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  result := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpFAdd % % %", id_text(result), id_text(s.id_float2), id_text(left_id), id_text(right_id))); return result, .FLOAT2, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpFSub % % %", id_text(result), id_text(s.id_float2), id_text(left_id), id_text(right_id))); return result, .FLOAT2, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpFMul % % %", id_text(result), id_text(s.id_float2), id_text(left_id), id_text(right_id))); return result, .FLOAT2, true, diag; }
  if op == "/" { add_op(s, tprint("         % = OpFDiv % % %", id_text(result), id_text(s.id_float2), id_text(left_id), id_text(right_id))); return result, .FLOAT2, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported float2 binary op '%'.", op);
  return 0, .UNKNOWN, false, diag;
}

emit_float3_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  result := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpFAdd % % %", id_text(result), id_text(s.id_float3), id_text(left_id), id_text(right_id))); return result, .FLOAT3, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpFSub % % %", id_text(result), id_text(s.id_float3), id_text(left_id), id_text(right_id))); return result, .FLOAT3, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpFMul % % %", id_text(result), id_text(s.id_float3), id_text(left_id), id_text(right_id))); return result, .FLOAT3, true, diag; }
  if op == "/" { add_op(s, tprint("         % = OpFDiv % % %", id_text(result), id_text(s.id_float3), id_text(left_id), id_text(right_id))); return result, .FLOAT3, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported float3 binary op '%'.", op);
  return 0, .UNKNOWN, false, diag;
}

emit_float4_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  result := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpFAdd % % %", id_text(result), id_text(s.id_float4), id_text(left_id), id_text(right_id))); return result, .FLOAT4, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpFSub % % %", id_text(result), id_text(s.id_float4), id_text(left_id), id_text(right_id))); return result, .FLOAT4, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpFMul % % %", id_text(result), id_text(s.id_float4), id_text(left_id), id_text(right_id))); return result, .FLOAT4, true, diag; }
  if op == "/" { add_op(s, tprint("         % = OpFDiv % % %", id_text(result), id_text(s.id_float4), id_text(left_id), id_text(right_id))); return result, .FLOAT4, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported float4 binary op '%'.", op);
  return 0, .UNKNOWN, false, diag;
}

emit_float_builtin_call :: (s: *IR_SPV_Gen_State, builtin_name: string, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if builtin_name == "min" || builtin_name == "max" {
    if args.count != 2 {
      diag.message = tprint("SPIR-V backend: builtin '%' expects 2 arguments.", builtin_name);
      return 0, .UNKNOWN, false, diag;
    }
    a_id, a_type, a_ok, a_diag := emit_expr(s, args[0]);
    if !a_ok return 0, .UNKNOWN, false, a_diag;
    b_id, b_type, b_ok, b_diag := emit_expr(s, args[1]);
    if !b_ok return 0, .UNKNOWN, false, b_diag;
    af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
    if !af_ok return 0, .UNKNOWN, false, af_diag;
    bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
    if !bf_ok return 0, .UNKNOWN, false, bf_diag;
    op_name := ifx builtin_name == "min" then "FMin" else "FMax";
    result := new_id(s);
    add_op(s, tprint("         % = OpExtInst % % % % %",
                     id_text(result), id_text(s.id_float), id_text(s.id_extinst), op_name, id_text(af), id_text(bf)));
    return result, .FLOAT, true, diag;
  }

  if args.count != 1 {
    diag.message = tprint("SPIR-V backend: builtin '%' expects 1 argument.", builtin_name);
    return 0, .UNKNOWN, false, diag;
  }
  value_id, value_type, value_ok, value_diag := emit_expr(s, args[0]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  op_name: string;
  if builtin_name == "floor" op_name = "Floor";
  else if builtin_name == "abs" op_name = "FAbs";
  else if builtin_name == "sqrt" op_name = "Sqrt";
  else if builtin_name == "sin" op_name = "Sin";
  else if builtin_name == "cos" op_name = "Cos";
  else if builtin_name == "fract" op_name = "Fract";
  else {
    diag.message = tprint("SPIR-V backend: unsupported float builtin '%'.", builtin_name);
    return 0, .UNKNOWN, false, diag;
  }

  if value_type == .FLOAT2 {
    if builtin_name == "sin" || builtin_name == "cos" || builtin_name == "sqrt" {
      diag.message = tprint("SPIR-V backend: builtin '%' on float2 is not supported yet.", builtin_name);
      return 0, .UNKNOWN, false, diag;
    }
    out_v2 := new_id(s);
    add_op(s, tprint("         % = OpExtInst % % % %",
                     id_text(out_v2), id_text(s.id_float2), id_text(s.id_extinst), op_name, id_text(value_id)));
    return out_v2, .FLOAT2, true, diag;
  }

  vf, vf_ok, vf_diag := coerce_to_float(s, value_id, value_type);
  if !vf_ok return 0, .UNKNOWN, false, vf_diag;
  result := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % % %",
                   id_text(result), id_text(s.id_float), id_text(s.id_extinst), op_name, id_text(vf)));
  return result, .FLOAT, true, diag;
}

eval_inline_function_return_chain :: (s: *IR_SPV_Gen_State, helper: *IR_Function, return_kind: IR_SPV_Gen_Type) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, handled: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !helper return 0, .UNKNOWN, false, false, diag;

  eval_return_block_value :: (s: *IR_SPV_Gen_State, helper: *IR_Function, return_kind: IR_SPV_Gen_Type, block: *IR_Block) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, handled: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !block || block.statements.count == 0 return 0, .UNKNOWN, false, false, diag;

    // Canonical helper-return block:
    //   <side-effect statements...>
    //   return X;
    // or:
    //   <side-effect statements...>
    //   if (...) { ...return... } else { ...return... }
    for i: 0..block.statements.count-2 {
      pre_stmt := *block.statements[i];
      pre_ok, pre_terminated, pre_diag := emit_stmt(s, pre_stmt);
      if !pre_ok return 0, .UNKNOWN, false, true, pre_diag;
      if pre_terminated {
        diag.message = tprint("SPIR-V backend: helper '%' has unsupported early control-flow termination in return prelude.", helper.name);
        return 0, .UNKNOWN, false, true, diag;
      }
    }

    stmt := *block.statements[block.statements.count-1];

    if stmt.kind == .RETURN {
      if !stmt.return_expr {
        diag.message = tprint("SPIR-V backend: helper '%' must return a value.", helper.name);
        return 0, .UNKNOWN, false, true, diag;
      }
      raw_id, raw_type, raw_ok, raw_diag := emit_expr(s, stmt.return_expr);
      if !raw_ok return 0, .UNKNOWN, false, true, raw_diag;
      coerced_id, coerced_type, coerced_ok, coerced_diag := coerce_to_exact_kind(s, raw_id, raw_type, return_kind);
      if !coerced_ok {
        if coerced_diag.message.count == 0 coerced_diag.message = tprint("SPIR-V backend: helper '%' return expression must lower to %.", helper.name, return_kind);
        return 0, .UNKNOWN, false, true, coerced_diag;
      }
      return coerced_id, coerced_type, true, true, diag;
    }

    if stmt.kind == .IF && stmt.if_then && stmt.if_else {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.if_condition);
      if !cond_ok return 0, .UNKNOWN, false, true, cond_diag;
      if cond_type != .BOOL {
        diag.message = tprint("SPIR-V backend: helper '%' if-condition must lower to bool.", helper.name);
        return 0, .UNKNOWN, false, true, diag;
      }

      then_id, then_type, then_ok, then_handled, then_diag := eval_return_block_value(s, helper, return_kind, stmt.if_then);
      if !then_handled return 0, .UNKNOWN, false, false, diag;
      if !then_ok return 0, .UNKNOWN, false, true, then_diag;

      else_id, else_type, else_ok, else_handled, else_diag := eval_return_block_value(s, helper, return_kind, stmt.if_else);
      if !else_handled return 0, .UNKNOWN, false, false, diag;
      if !else_ok return 0, .UNKNOWN, false, true, else_diag;
      if then_type != else_type {
        diag.message = tprint("SPIR-V backend: helper '%' if-return branches must resolve to same type.", helper.name);
        return 0, .UNKNOWN, false, true, diag;
      }
      result_type_id := type_id_from_kind(s, then_type);
      if result_type_id == 0 {
        diag.message = tprint("SPIR-V backend: helper '%' return type % is unsupported for OpSelect.", helper.name, then_type);
        return 0, .UNKNOWN, false, true, diag;
      }
      selected := new_id(s);
      add_op(s, tprint("         % = OpSelect % % % %",
                       id_text(selected),
                       id_text(result_type_id),
                       id_text(cond_id),
                       id_text(then_id),
                       id_text(else_id)));
      return selected, then_type, true, true, diag;
    }

    return 0, .UNKNOWN, false, false, diag;
  }

  // Canonical helper bodies:
  //   <prelude...>; return X;
  //   <prelude...>; if (...) ...return... else ...return...
  value_id, value_type, ok, handled, chain_diag := eval_return_block_value(s, helper, return_kind, *helper.body);
  if handled return value_id, value_type, ok, true, chain_diag;
  diag.message = tprint("SPIR-V backend: helper '%' body is not in canonical return form (normalize pass required).", helper.name);
  return 0, .UNKNOWN, false, true, diag;
}

spv_kind_from_ir_type_kind :: (kind: IR_Type_Kind) -> IR_SPV_Gen_Type {
  if kind == .BOOL return .BOOL;
  if kind == .I32 return .INT;
  if kind == .U32 return .UINT;
  if kind == .I64 return .INT64;
  if kind == .U64 return .UINT64;
  if kind == .F32 return .FLOAT;
  if kind == .F32x2 return .FLOAT2;
  if kind == .F32x3 return .FLOAT3;
  if kind == .F32x4 return .FLOAT4;
  if kind == .F32x2x2 return .FLOAT2X2;
  if kind == .STRUCT return .STRUCT;
  return .UNKNOWN;
}

bind_inline_helper_pointer_arg :: (s: *IR_SPV_Gen_State, helper_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (handled: bool, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if arg.type.kind != .POINTER return false, true, diag;

  if !arg_expr || arg_expr.kind != .IDENT {
    diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' must be a buffer identifier.", helper_name, arg.name);
    return true, false, diag;
  }
  source_buffer := find_buffer(s, arg_expr.text);
  if !source_buffer {
    diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' expected storage buffer identifier, got '%'.", helper_name, arg.name, arg_expr.text);
    return true, false, diag;
  }

  expected_kind := spv_kind_from_ir_type_kind(arg.type.pointee_kind);
  if arg.type.pointee_kind == .STRUCT || expected_kind == .STRUCT {
    if source_buffer.element_kind != .STRUCT {
      diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' expected struct buffer pointee '%'.", helper_name, arg.name, arg.type.pointee_struct_name);
      return true, false, diag;
    }
    if arg.type.pointee_struct_name.count != 0 && source_buffer.element_type_name != arg.type.pointee_struct_name {
      diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' pointee mismatch (expected '%', got '%').", helper_name, arg.name, arg.type.pointee_struct_name, source_buffer.element_type_name);
      return true, false, diag;
    }
  } else {
    if expected_kind == .UNKNOWN {
      diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' has unsupported pointee kind %.", helper_name, arg.name, arg.type.pointee_kind);
      return true, false, diag;
    }
    if source_buffer.element_kind != expected_kind {
      diag.message = tprint("SPIR-V backend: helper '%' pointer arg '%' pointee mismatch (expected %, got %).", helper_name, arg.name, expected_kind, source_buffer.element_kind);
      return true, false, diag;
    }
  }

  if arg.name != arg_expr.text {
    alias := source_buffer.*;
    alias.name = arg.name;
    array_add(*s.buffers, alias);
  }
  return true, true, diag;
}

eval_inline_function :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !helper {
    diag.message = "SPIR-V backend: missing helper metadata for inline call.";
    return 0, .UNKNOWN, false, diag;
  }
  return_kind := spv_kind_from_ir_type_kind(helper.return_type.kind);
  if return_kind == .UNKNOWN return_kind = expr_type_from_decl(helper.return_type_name);
  if return_kind == .UNKNOWN || return_kind == .STRUCT {
    diag.message = tprint("SPIR-V backend: helper '%' has unsupported return type '%'.", helper.name, helper.return_type_name);
    return 0, .UNKNOWN, false, diag;
  }
  if helper.args.count != call_args.count {
    diag.message = tprint("SPIR-V backend: helper '%' expected % args but got %.", helper.name, helper.args.count, call_args.count);
    return 0, .UNKNOWN, false, diag;
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }
  for helper.args {
    pointer_handled, pointer_ok, pointer_diag := bind_inline_helper_pointer_arg(s, helper.name, it, call_args[it_index]);
    if pointer_handled {
      if !pointer_ok return 0, .UNKNOWN, false, pointer_diag;
      continue;
    }

    arg_kind := spv_kind_from_ir_type_kind(it.type.kind);
    if arg_kind == .UNKNOWN arg_kind = expr_type_from_decl(it.type_name);
    if arg_kind != .UNKNOWN && arg_kind != .STRUCT {
      arg_value, arg_type, arg_ok, arg_diag := emit_expr(s, call_args[it_index]);
      if !arg_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return 0, .UNKNOWN, false, arg_diag;
      }

      final_value := arg_value;
      final_type := arg_type;
      if arg_kind == .FLOAT || is_integral_kind(arg_kind) || arg_kind == .BOOL {
        coerced, coerced_ok, coerced_diag := coerce_to_kind(s, arg_value, arg_type, arg_kind);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return 0, .UNKNOWN, false, coerced_diag;
        }
        final_value = coerced;
        final_type = arg_kind;
      } else if arg_kind == .FLOAT2 && arg_type != .FLOAT2 {
        coerced, coerced_ok, coerced_diag := coerce_to_float2(s, arg_value, arg_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return 0, .UNKNOWN, false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT2;
      } else if arg_kind == .FLOAT3 && arg_type != .FLOAT3 {
        coerced, coerced_ok, coerced_diag := coerce_to_float3(s, arg_value, arg_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return 0, .UNKNOWN, false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT3;
      } else if arg_kind == .FLOAT4 && arg_type != .FLOAT4 {
        coerced, coerced_ok, coerced_diag := coerce_to_float4(s, arg_value, arg_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return 0, .UNKNOWN, false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT4;
      }
      if final_type != arg_kind {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' arg '%' type mismatch (expected %, got %).", helper.name, it.name, arg_kind, final_type);
        return 0, .UNKNOWN, false, diag;
      }

      arg_ptr_type_id := func_ptr_type_id_from_kind(s, arg_kind);
      if arg_ptr_type_id == 0 {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' arg '%' has unsupported pointer type %.", helper.name, it.name, arg_kind);
        return 0, .UNKNOWN, false, diag;
      }
      arg_ptr := new_id(s);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                               id_text(arg_ptr),
                               id_text(arg_ptr_type_id)));
      add_debug_name(s, arg_ptr, it.name);
      add_op(s, tprint("               OpStore % %", id_text(arg_ptr), id_text(final_value)));
      array_add(*s.locals, .{name=it.name, ptr_id=arg_ptr, type=arg_kind});
      continue;
    }

    arg_struct_name := it.type.struct_name;
    if arg_struct_name.count == 0 arg_struct_name = it.type_name;
    arg_struct_def := find_struct(s, arg_struct_name);
    if !arg_struct_def {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' arg '%' has unsupported type '%'.", helper.name, it.name, it.type_name);
      return 0, .UNKNOWN, false, diag;
    }

    struct_arg := call_args[it_index];
    arg_local_struct: IR_SPV_Gen_Local_Struct;
    arg_local_struct.name = it.name;
    arg_local_struct.type_name = arg_struct_name;

    if struct_arg && struct_arg.kind == .IDENT {
      source_struct := find_local_struct(s, struct_arg.text);
      if !source_struct {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' expects local struct value '%'.", helper.name, it.name, struct_arg.text);
        return 0, .UNKNOWN, false, diag;
      }
      if source_struct.type_name != arg_struct_name {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' type mismatch ('%' vs '%').", helper.name, it.name, source_struct.type_name, it.type_name);
        return 0, .UNKNOWN, false, diag;
      }
      for source_struct.fields {
        array_add(*arg_local_struct.fields, .{name=it.name, ptr_id=it.ptr_id, type=it.type});
      }
      array_add(*s.local_structs, arg_local_struct);
      continue;
    }

    if !struct_arg || struct_arg.kind != .CONSTRUCTOR || struct_arg.text != arg_struct_name {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' only supports constructor or identifier values.", helper.name, it.name);
      return 0, .UNKNOWN, false, diag;
    }
    if struct_arg.args.count != arg_struct_def.fields.count {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' field count mismatch.", helper.name, it.name);
      return 0, .UNKNOWN, false, diag;
    }
    for arg_struct_def.fields {
      field_kind := spv_kind_from_ir_type_kind(it.type.kind);
      field_is_uint := field_kind == .UINT;
      if !field_is_uint field_is_uint = is_uint_type_name(it.type_name);
      if !field_is_uint {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' field '%' has unsupported type '%'.", helper.name, arg_struct_def.name, it.name, it.type_name);
        return 0, .UNKNOWN, false, diag;
      }
      field_value, field_type, field_ok, field_diag := emit_expr(s, struct_arg.args[it_index]);
      if !field_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return 0, .UNKNOWN, false, field_diag;
      }
      if field_type != .UINT {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg field '%' must lower to uint.", helper.name, it.name);
        return 0, .UNKNOWN, false, diag;
      }
      field_ptr := new_id(s);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                               id_text(field_ptr),
                               id_text(s.id_ptr_func_uint)));
      add_debug_name(s, field_ptr, tprint("%.%", arg_local_struct.name, it.name));
      add_op(s, tprint("               OpStore % %", id_text(field_ptr), id_text(field_value)));
      array_add(*arg_local_struct.fields, .{name=it.name, ptr_id=field_ptr, type=.UINT});
    }
    array_add(*s.local_structs, arg_local_struct);
  }

  return_id, return_type, return_ok, return_handled, return_diag := eval_inline_function_return_chain(s, helper, return_kind);
  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  if !return_handled {
    diag.message = tprint("SPIR-V backend: helper '%' body shape is unsupported for inline value return.", helper.name);
    return 0, .UNKNOWN, false, diag;
  }
  if !return_ok return 0, .UNKNOWN, false, return_diag;
  return return_id, return_type, true, diag;
}

eval_inline_function_to_struct :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr, out_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !helper {
    diag.message = "SPIR-V backend: missing helper metadata for inline struct call.";
    return false, diag;
  }
  if !out_struct {
    diag.message = "SPIR-V backend: null destination struct for inline helper call.";
    return false, diag;
  }
  out_struct_name := out_struct.name;
  out_struct_type := out_struct.type_name;
  helper_return_struct_name := helper.return_type.struct_name;
  if helper_return_struct_name.count == 0 helper_return_struct_name = helper.return_type_name;
  if helper_return_struct_name != out_struct_type {
    diag.message = tprint("SPIR-V backend: helper '%' return type '%' does not match destination struct '%'.", helper.name, helper.return_type_name, out_struct_type);
    return false, diag;
  }
  if helper.args.count != call_args.count {
    diag.message = tprint("SPIR-V backend: helper '%' expected % args but got %.", helper.name, helper.args.count, call_args.count);
    return false, diag;
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }

  for helper.args {
    pointer_handled, pointer_ok, pointer_diag := bind_inline_helper_pointer_arg(s, helper.name, it, call_args[it_index]);
    if pointer_handled {
      if !pointer_ok return false, pointer_diag;
      continue;
    }

    arg_type := spv_kind_from_ir_type_kind(it.type.kind);
    if arg_type == .UNKNOWN arg_type = expr_type_from_decl(it.type_name);
    if arg_type != .UNKNOWN && arg_type != .STRUCT {
      arg_value, value_type, value_ok, value_diag := emit_expr(s, call_args[it_index]);
      if !value_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return false, value_diag;
      }

      final_value := arg_value;
      final_type := value_type;
      if arg_type == .FLOAT || is_integral_kind(arg_type) || arg_type == .BOOL {
        coerced, coerced_ok, coerced_diag := coerce_to_kind(s, arg_value, value_type, arg_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, coerced_diag;
        }
        final_value = coerced;
        final_type = arg_type;
      } else if arg_type == .FLOAT2 && value_type != .FLOAT2 {
        coerced, coerced_ok, coerced_diag := coerce_to_float2(s, arg_value, value_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT2;
      } else if arg_type == .FLOAT3 && value_type != .FLOAT3 {
        coerced, coerced_ok, coerced_diag := coerce_to_float3(s, arg_value, value_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT3;
      } else if arg_type == .FLOAT4 && value_type != .FLOAT4 {
        coerced, coerced_ok, coerced_diag := coerce_to_float4(s, arg_value, value_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT4;
      }

      if final_type != arg_type {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' arg '%' type mismatch (expected %, got %).", helper.name, it.name, arg_type, final_type);
        return false, diag;
      }

      arg_ptr_type := func_ptr_type_id_from_kind(s, arg_type);
      if arg_ptr_type == 0 {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' arg '%' type '%' has no function pointer representation.", helper.name, it.name, arg_type);
        return false, diag;
      }
      arg_ptr := new_id(s);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                               id_text(arg_ptr),
                               id_text(arg_ptr_type)));
      add_debug_name(s, arg_ptr, it.name);
      add_op(s, tprint("               OpStore % %", id_text(arg_ptr), id_text(final_value)));
      array_add(*s.locals, .{name=it.name, ptr_id=arg_ptr, type=arg_type});
      continue;
    }

    arg_struct_name := it.type.struct_name;
    if arg_struct_name.count == 0 arg_struct_name = it.type_name;
    arg_struct, arg_struct_ok, arg_struct_diag := alloc_local_struct(s, it.name, arg_struct_name);
    if !arg_struct_ok {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      return false, arg_struct_diag;
    }

    arg_expr := call_args[it_index];
    if arg_expr && arg_expr.kind == .IDENT {
      src_struct := find_local_struct(s, arg_expr.text);
      if !src_struct {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' expects local struct value '%'.", helper.name, it.name, arg_expr.text);
        return false, diag;
      }
      copy_ok, copy_diag := copy_local_struct_fields(s, arg_struct, src_struct);
      if !copy_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return false, copy_diag;
      }
      continue;
    }

    if arg_expr && arg_expr.kind == .SUBSCRIPT && arg_expr.left && arg_expr.left.kind == .IDENT {
      src_buffer := find_buffer(s, arg_expr.left.text);
      if src_buffer && src_buffer.element_kind == .STRUCT && src_buffer.element_type_name == arg_struct_name {
        for arg_struct.fields {
          src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, arg_expr, it.name);
          if !src_ok {
            s.locals.count = local_count_before;
            s.local_structs.count = local_struct_count_before;
            return false, src_diag;
          }
          if src_type != it.type {
            s.locals.count = local_count_before;
            s.local_structs.count = local_struct_count_before;
            diag.message = tprint("SPIR-V backend: helper '%' struct arg field '%' type mismatch.", helper.name, it.name);
            return false, diag;
          }
          value_id := new_id(s);
          type_id := type_id_from_kind(s, src_type);
          emit_load(s, value_id, type_id, src_ptr, src_type, needs_physical_align=true);
          add_op(s, tprint("               OpStore % %",
                           id_text(it.ptr_id),
                           id_text(value_id)));
        }
        continue;
      }
    }

    if arg_expr && arg_expr.kind == .CONSTRUCTOR && arg_expr.text == arg_struct_name {
      if arg_expr.args.count != arg_struct.fields.count {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' constructor field count mismatch.", helper.name, it.name);
        return false, diag;
      }
      for arg_struct.fields {
        value_id, value_type, value_ok, value_diag := emit_expr(s, arg_expr.args[it_index]);
        if !value_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, value_diag;
        }
        if value_type != it.type {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          diag.message = tprint("SPIR-V backend: helper '%' struct arg field '%' constructor type mismatch.", helper.name, it.name);
          return false, diag;
        }
        add_op(s, tprint("               OpStore % %",
                         id_text(it.ptr_id),
                         id_text(value_id)));
      }
      continue;
    }

    s.locals.count = local_count_before;
    s.local_structs.count = local_struct_count_before;
    diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' has unsupported expression kind %.", helper.name, it.name, ifx arg_expr then arg_expr.kind else .IDENT);
    return false, diag;
  }

  apply_return_expr_to_out :: (s: *IR_SPV_Gen_State, helper_name: string, out_struct: *IR_SPV_Gen_Local_Struct, out_struct_type: string, dst_name: string, expr: *IR_Expr) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !expr {
      diag.message = tprint("SPIR-V backend: helper '%' must return a struct value.", helper_name);
      return false, true, diag;
    }
    if expr.kind != .IDENT return false, false, diag;
    dst_struct := find_local_struct(s, dst_name);
    if !dst_struct dst_struct = out_struct;
    src_struct := find_local_struct(s, expr.text);
    if !src_struct {
      diag.message = tprint("SPIR-V backend: helper '%' return identifier '%' is not a local struct value.", helper_name, expr.text);
      return false, true, diag;
    }
    if src_struct.type_name != out_struct_type {
      diag.message = tprint("SPIR-V backend: helper '%' return struct type mismatch ('%' vs '%').", helper_name, src_struct.type_name, out_struct_type);
      return false, true, diag;
    }
    copy_ok, copy_diag := copy_local_struct_fields(s, dst_struct, src_struct);
    if !copy_ok return false, true, copy_diag;
    return true, true, diag;
  }

  select_struct_fields :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, then_src: *IR_SPV_Gen_Local_Struct, else_src: *IR_SPV_Gen_Local_Struct, cond_id: s64) -> (ok: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !dst || !then_src || !else_src {
      diag.message = "SPIR-V backend: null struct while selecting return fields.";
      return false, diag;
    }
    if dst.type_name != then_src.type_name || dst.type_name != else_src.type_name {
      diag.message = tprint("SPIR-V backend: struct select type mismatch ('%', '%', '%').", dst.type_name, then_src.type_name, else_src.type_name);
      return false, diag;
    }

    for dst.fields {
      then_field := find_local_struct_field(then_src, it.name);
      else_field := find_local_struct_field(else_src, it.name);
      if !then_field || !else_field {
        diag.message = tprint("SPIR-V backend: selected struct '%' missing field '%'.", dst.type_name, it.name);
        return false, diag;
      }

      if it.type == .STRUCT {
        dst_nested := find_local_struct(s, it.nested_struct_name);
        then_nested := find_local_struct(s, then_field.nested_struct_name);
        else_nested := find_local_struct(s, else_field.nested_struct_name);
        nested_ok, nested_diag := select_struct_fields(s, dst_nested, then_nested, else_nested, cond_id);
        if !nested_ok return false, nested_diag;
        continue;
      }

      if then_field.type != it.type || else_field.type != it.type {
        diag.message = tprint("SPIR-V backend: selected struct field '%' type mismatch.", it.name);
        return false, diag;
      }

      type_id := type_id_from_kind(s, it.type);
      if type_id == 0 {
        diag.message = tprint("SPIR-V backend: selected struct field '%' has unsupported type %.", it.name, it.type);
        return false, diag;
      }
      then_val := new_id(s);
      else_val := new_id(s);
      emit_load(s, then_val, type_id, then_field.ptr_id, then_field.type);
      emit_load(s, else_val, type_id, else_field.ptr_id, else_field.type);
      selected := new_id(s);
      add_op(s, tprint("         % = OpSelect % % % %",
                       id_text(selected),
                       id_text(type_id),
                       id_text(cond_id),
                       id_text(then_val),
                       id_text(else_val)));
      emit_store(s, it.ptr_id, selected, it.type);
    }

    return true, diag;
  }

  eval_struct_return_block :: (s: *IR_SPV_Gen_State, helper_name: string, out_struct: *IR_SPV_Gen_Local_Struct, out_struct_type: string, dst_name: string, block: *IR_Block) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !block || block.statements.count == 0 return false, false, diag;

    // Canonical struct-return block:
    //   <side-effect statements...>
    //   return <struct expr>;
    // or:
    //   <side-effect statements...>
    //   if (...) { ...return struct... } else { ...return struct... }
    for i: 0..block.statements.count-2 {
      pre_stmt := *block.statements[i];
      pre_ok, pre_terminated, pre_diag := emit_stmt(s, pre_stmt);
      if !pre_ok return false, true, pre_diag;
      if pre_terminated {
        diag.message = tprint("SPIR-V backend: helper '%' has unsupported early control-flow termination in struct-return prelude.", helper_name);
        return false, true, diag;
      }
    }

    stmt := *block.statements[block.statements.count-1];

    if stmt.kind == .RETURN {
      ok, handled, diag := apply_return_expr_to_out(s, helper_name, out_struct, out_struct_type, dst_name, stmt.return_expr);
      return ok, handled, diag;
    }

    if stmt.kind == .IF && stmt.if_then && stmt.if_else {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.if_condition);
      if !cond_ok return false, true, cond_diag;
      if cond_type != .BOOL {
        diag.message = tprint("SPIR-V backend: helper '%' if-condition must lower to bool.", helper_name);
        return false, true, diag;
      }

      then_tmp_name := tprint("__ret_then_%", new_id(s));
      else_tmp_name := tprint("__ret_else_%", new_id(s));
      then_tmp, then_tmp_ok, then_tmp_diag := alloc_local_struct(s, then_tmp_name, out_struct_type);
      if !then_tmp_ok return false, true, then_tmp_diag;
      else_tmp, else_tmp_ok, else_tmp_diag := alloc_local_struct(s, else_tmp_name, out_struct_type);
      if !else_tmp_ok return false, true, else_tmp_diag;

      then_ok, then_handled, then_diag := eval_struct_return_block(s, helper_name, out_struct, out_struct_type, then_tmp_name, stmt.if_then);
      else_ok, else_handled, else_diag := eval_struct_return_block(s, helper_name, out_struct, out_struct_type, else_tmp_name, stmt.if_else);

      if !then_handled || !else_handled return false, false, diag;
      if !then_ok return false, true, then_diag;
      if !else_ok return false, true, else_diag;

      dst_struct := find_local_struct(s, dst_name);
      if !dst_struct dst_struct = out_struct;
      select_ok, select_diag := select_struct_fields(s, dst_struct, then_tmp, else_tmp, cond_id);
      if !select_ok return false, true, select_diag;
      return true, true, diag;
    }

    return false, false, diag;
  }

  fast_ok, fast_handled, fast_diag := eval_struct_return_block(s, helper.name, out_struct, out_struct_type, out_struct_name, *helper.body);
  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  if fast_handled return fast_ok, fast_diag;
  diag.message = tprint("SPIR-V backend: helper '%' body is not in canonical struct-return form (normalize pass required).", helper.name);
  return false, diag;
}

// -----------------------------------------------------------------------------
// Expression Emission
// -----------------------------------------------------------------------------

emit_expr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(msg, ..args) }; }

  assert(s != null);
  diag: IR_Diagnostic;
  if !expr return_err("SPIR-V backend: null IR expression.");

  if expr.kind == {
    case .LITERAL; {
      literal_text := compact_text(expr.text);
      if literal_text == "true" return s.id_bool_true, .BOOL, true, diag;
      if literal_text == "false" return s.id_bool_false, .BOOL, true, diag;
      v, ok := parse_u32_literal_expr(expr);
      if ok {
        return get_u32_const(s, v), .UINT, true, diag;
      }
      i64, i64_ok := parse_i64_literal_expr(expr);
      if i64_ok {
        return get_i64_const(s, i64), .INT64, true, diag;
      }
      ftext, fok := parse_f32_literal_text(expr.text);
      if fok return get_f32_const(s, ftext), .FLOAT, true, diag;
      return_err("SPIR-V backend: unsupported literal '%'.", expr.text);
    }

    case .IDENT; {
      local := find_local(s, expr.text);
      if !local return_err("SPIR-V backend: unknown identifier '%'.", expr.text);
      value_id := new_id(s);
      result_type_id := type_id_from_kind(s, local.type);
      assert(result_type_id != 0);
      add_op(s, tprint("         % = OpLoad % %",
                                  id_text(value_id),
                                  id_text(result_type_id),
                                  id_text(local.ptr_id)));
      return value_id, local.type, true, diag;
    }

    case .MEMBER; {
      path := expr_text(expr);
      if path == "thread_id.x" || path == "input.thread_id.x" return load_thread_component(s, 0), .UINT, true, diag;
      if path == "thread_id.y" || path == "input.thread_id.y" return load_thread_component(s, 1), .UINT, true, diag;
      if path == "thread_id.z" || path == "input.thread_id.z" return load_thread_component(s, 2), .UINT, true, diag;
      if expr.left && expr.left.kind == .CALL && expr.left.left && expr.left.left.kind == .IDENT {
        helper := find_function(s, expr.left.left.text);
        if !helper return_err("SPIR-V backend: unknown helper '%'.", expr.left.left.text);
        helper_ret_kind := spv_kind_from_ir_type_kind(helper.return_type.kind);
        if helper_ret_kind == .UNKNOWN helper_ret_kind = expr_type_from_decl(helper.return_type_name);
        if helper_ret_kind != .STRUCT return_err("SPIR-V backend: member access on non-struct call return '%'.", helper.return_type_name);
        temp_name := tprint("__call_ret_%", new_id(s));
        helper_ret_struct_name := helper.return_type.struct_name;
        if helper_ret_struct_name.count == 0 helper_ret_struct_name = helper.return_type_name;
        temp_struct, temp_ok, temp_diag := alloc_local_struct(s, temp_name, helper_ret_struct_name);
        if !temp_ok return 0, .UNKNOWN, false, temp_diag;
        call_ok, call_diag := eval_inline_function_to_struct(s, helper, expr.left.args, temp_struct);
        if !call_ok return 0, .UNKNOWN, false, call_diag;
        temp_struct = find_local_struct(s, temp_name);
        if !temp_struct return_err("SPIR-V backend: inline helper result struct '%' went missing.", temp_name);
        field := find_local_struct_field(temp_struct, expr.text);
        if !field return_err("SPIR-V backend: helper call return type '%' has no field '%'.", helper.return_type_name, expr.text);
        value_id := new_id(s);
        type_id := type_id_from_kind(s, field.type);
        add_op(s, tprint("         % = OpLoad % %",
                         id_text(value_id),
                         id_text(type_id),
                         id_text(field.ptr_id)));
        return value_id, field.type, true, diag;
      }
      if expr.left && expr.left.kind == .SUBSCRIPT {
        field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left, expr.text);
        if field_ok {
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, field_type);
          if value_type_id == 0 return_err("SPIR-V backend: unsupported loaded field type for '%'.", path);
          emit_load(s, value_id, value_type_id, field_ptr, field_type, needs_physical_align=true);
          return value_id, field_type, true, diag;
        }
        // Non-buffer subscripts (for example uniform-array or local-array indexing) should
        // continue through the generic member-expression path below.
      }
      if expr.left {
        skip_direct_left_eval := false;
        if expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
          parent_struct := find_local_struct(s, expr.left.left.text);
          if parent_struct {
            parent_field := find_local_struct_field(parent_struct, expr.left.text);
            if parent_field && parent_field.type == .STRUCT skip_direct_left_eval = true;
          }
        }
        if !skip_direct_left_eval {
          left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
          if left_ok && (left_type == .FLOAT2 || left_type == .FLOAT3 || left_type == .FLOAT4) {
            if expr.text == "xy" {
              if left_type == .FLOAT2 return left_id, .FLOAT2, true, diag;
              swz := new_id(s);
              add_op(s, tprint("         % = OpVectorShuffle % % % 0 1",
                               id_text(swz),
                               id_text(s.id_float2),
                               id_text(left_id),
                               id_text(left_id)));
              return swz, .FLOAT2, true, diag;
            }
            comp_index: s64 = -1;
            if expr.text == "x" comp_index = 0;
            if expr.text == "y" comp_index = 1;
            if expr.text == "z" comp_index = 2;
            if expr.text == "w" comp_index = 3;
            if comp_index >= 0 {
              if left_type == .FLOAT2 && comp_index > 1 return_err("SPIR-V backend: component '%' out of range for float2.", expr.text);
              if left_type == .FLOAT3 && comp_index > 2 return_err("SPIR-V backend: component '%' out of range for float3.", expr.text);
              scalar_value := new_id(s);
              add_op(s, tprint("         % = OpCompositeExtract % % %",
                               id_text(scalar_value),
                               id_text(s.id_float),
                               id_text(left_id),
                               comp_index));
              return scalar_value, .FLOAT, true, diag;
            }
          }
          if !left_ok && expr.left.kind != .IDENT {
            return 0, .UNKNOWN, false, left_diag;
          }
        }
      }
      if expr.left {
        uniform_name, uniform_field, uniform_ok := resolve_member_root_and_field(expr);
        uniform := ifx uniform_ok then find_uniform_block(s, uniform_name) else null;
        if uniform {
          field_ptr, field_type, field_ok, field_diag := emit_uniform_field_ptr(s, uniform_name, uniform_field);
          if !field_ok return 0, .UNKNOWN, false, field_diag;
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, field_type);
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(value_id),
                           id_text(value_type_id),
                           id_text(field_ptr)));
          return value_id, field_type, true, diag;
        }
        local := find_local(s, expr.left.text);
        if local && (local.type == .FLOAT2 || local.type == .FLOAT3 || local.type == .FLOAT4) {
          comp_index: s64 = -1;
          if expr.text == "x" comp_index = 0;
          if expr.text == "y" comp_index = 1;
          if expr.text == "z" comp_index = 2;
          if expr.text == "w" comp_index = 3;
          vec_value := new_id(s);
          vec_type_id := s.id_float4;
          if local.type == .FLOAT2 vec_type_id = s.id_float2;
          if local.type == .FLOAT3 vec_type_id = s.id_float3;
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(vec_value),
                           id_text(vec_type_id),
                           id_text(local.ptr_id)));
          if expr.text == "xy" {
            if local.type == .FLOAT2 return vec_value, .FLOAT2, true, diag;
            swz := new_id(s);
            add_op(s, tprint("         % = OpVectorShuffle % % % 0 1",
                             id_text(swz),
                             id_text(s.id_float2),
                             id_text(vec_value),
                             id_text(vec_value)));
            return swz, .FLOAT2, true, diag;
          }
          if comp_index >= 0 {
            if local.type == .FLOAT2 && comp_index > 1 return_err("SPIR-V backend: component '%' out of range for float2.", expr.text);
            if local.type == .FLOAT3 && comp_index > 2 return_err("SPIR-V backend: component '%' out of range for float3.", expr.text);
            scalar_value := new_id(s);
            add_op(s, tprint("         % = OpCompositeExtract % % %",
                             id_text(scalar_value),
                             id_text(s.id_float),
                             id_text(vec_value),
                             comp_index));
            return scalar_value, .FLOAT, true, diag;
          }
        }
      }
      if expr.left && expr.left.kind == .IDENT {
        local_struct := find_local_struct(s, expr.left.text);
        if local_struct {
          field := find_local_struct_field(local_struct, expr.text);
          if !field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.text, expr.text);
          if field.type == .STRUCT return_err("SPIR-V backend: struct field '%.%' must be accessed through a member.", expr.left.text, expr.text);
          value_id := new_id(s);
          result_type_id := type_id_from_kind(s, field.type);
          assert(result_type_id != 0);
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(value_id),
                           id_text(result_type_id),
                           id_text(field.ptr_id)));
          return value_id, field.type, true, diag;
        }
      }
      if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
        local_struct := find_local_struct(s, expr.left.left.text);
        if local_struct {
          parent_field := find_local_struct_field(local_struct, expr.left.text);
          if !parent_field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.left.text, expr.left.text);
          if parent_field.type != .STRUCT return_err("SPIR-V backend: unsupported member expression '%'.", path);
          nested_struct := find_local_struct(s, parent_field.nested_struct_name);
          if !nested_struct return_err("SPIR-V backend: nested struct '%.%' is missing.", expr.left.left.text, expr.left.text);
          nested_field := find_local_struct_field(nested_struct, expr.text);
          if !nested_field return_err("SPIR-V backend: unknown nested struct field '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          if nested_field.type == .STRUCT return_err("SPIR-V backend: nested struct field '%.%.%' must be accessed through a member.", expr.left.left.text, expr.left.text, expr.text);
          value_id := new_id(s);
          result_type_id := type_id_from_kind(s, nested_field.type);
          if result_type_id == 0 return_err("SPIR-V backend: unsupported nested struct field type for '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(value_id),
                           id_text(result_type_id),
                           id_text(nested_field.ptr_id)));
          return value_id, nested_field.type, true, diag;
        }
      }
      return_err("SPIR-V backend: unsupported member expression '%'.", path);
    }

    case .SUBSCRIPT; {
      if expr.left && expr.left.kind == .MEMBER {
        uniform_name, uniform_field, uniform_ok := resolve_member_root_and_field(expr.left);
        if uniform_ok {
          idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
          if !idx_ok return 0, .UNKNOWN, false, idx_diag;
          ptr, elem_type, ptr_ok, ptr_diag := emit_uniform_array_element_ptr(s, uniform_name, uniform_field, idx, idx_type);
          if ptr_ok {
            value_id := new_id(s);
            value_type_id := type_id_from_kind(s, elem_type);
            add_op(s, tprint("         % = OpLoad % %",
                                        id_text(value_id),
                                        id_text(value_type_id),
                                        id_text(ptr)));
            return value_id, elem_type, true, diag;
          }
        }
      }

      if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
        idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        ptr, elem_type, ptr_ok, ptr_diag := emit_uniform_array_element_ptr(s, expr.left.left.text, expr.left.text, idx, idx_type);
        if ptr_ok {
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, elem_type);
          add_op(s, tprint("         % = OpLoad % %",
                                      id_text(value_id),
                                      id_text(value_type_id),
                                      id_text(ptr)));
          return value_id, elem_type, true, diag;
        }
      }

      if expr.left && expr.left.kind == .IDENT {
        local_array := find_local_array(s, expr.left.text);
        if local_array {
          idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
          if !idx_ok return 0, .UNKNOWN, false, idx_diag;
          idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
          if !idx_ok return 0, .UNKNOWN, false, idx_diag;
          elem_ptr := new_id(s);
          elem_ptr_type_id := func_ptr_type_id_from_kind(s, local_array.element_type);
          add_op(s, tprint("         % = OpAccessChain % % %",
                                      id_text(elem_ptr),
                                      id_text(elem_ptr_type_id),
                                      id_text(local_array.var_id),
                                      id_text(idx)));
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, local_array.element_type);
          add_op(s, tprint("         % = OpLoad % %",
                                      id_text(value_id),
                                      id_text(value_type_id),
                                      id_text(elem_ptr)));
          return value_id, local_array.element_type, true, diag;
        }
      }

      buffer_name, base_ok := resolve_ident_or_zero_deref(expr.left);
      if base_ok {
        // already resolved
      } else if expr.left && expr.left.kind == .MEMBER {
        member_root, member_field, member_ok := resolve_member_root_and_field(expr.left);
        if member_ok {
          buffer_name = tprint("%.%", member_root, member_field);
        } else {
          buffer_name = expr_text(expr.left);
        }
      } else {
        return_err("SPIR-V backend: subscript base must resolve to an identifier/member.");
      }
      buffer := find_buffer(s, buffer_name);
      if !buffer return_err("SPIR-V backend: unknown subscript base '%'.", buffer_name);
      idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      if buffer.element_kind != .STRUCT {
        value_ptr_id := new_id(s);
        add_op(s, tprint("         % = OpAccessChain % % % %",
                                    id_text(value_ptr_id),
                                    id_text(buffer.ptr_storage_element_type_id),
                                    id_text(buffer.var_id),
                                    id_text(s.id_int_0),
                                    id_text(idx)));
        value_id := new_id(s);
        value_type_id := type_id_from_kind(s, buffer.element_kind);
        assert(value_type_id != 0);
        emit_load(s, value_id, value_type_id, value_ptr_id, buffer.element_kind, needs_physical_align=true);
        return value_id, buffer.element_kind, true, diag;
      }
      return_err("SPIR-V backend: subscript value access for struct buffer '%' is unsupported; access a field instead.", buffer.name);
    }

    case .BINARY; {
      left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
      if !left_ok return 0, .UNKNOWN, false, left_diag;
      right_id, right_type, right_ok, right_diag := emit_expr(s, expr.right);
      if !right_ok return 0, .UNKNOWN, false, right_diag;

      op := expr.text;
      if is_integral_kind(left_type) && is_integral_kind(right_type) {
        promoted := promote_integral_kind(left_type, right_type);
        left_id, left_ok, left_diag = coerce_to_kind(s, left_id, left_type, promoted);
        if !left_ok return 0, .UNKNOWN, false, left_diag;
        right_id, right_ok, right_diag = coerce_to_kind(s, right_id, right_type, promoted);
        if !right_ok return 0, .UNKNOWN, false, right_diag;
        result_id, result_type, result_ok, result_diag := emit_int_binary_op(s, op, promoted, left_id, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .BOOL && right_type == .BOOL {
        result_id := new_id(s);
        if op == "&&" {
          add_op(s, tprint("         % = OpLogicalAnd % % %",
                           id_text(result_id),
                           id_text(s.id_bool),
                           id_text(left_id),
                           id_text(right_id)));
          return result_id, .BOOL, true, diag;
        }
        if op == "||" {
          add_op(s, tprint("         % = OpLogicalOr % % %",
                           id_text(result_id),
                           id_text(s.id_bool),
                           id_text(left_id),
                           id_text(right_id)));
          return result_id, .BOOL, true, diag;
        }
      }
      if left_type == .FLOAT2 && right_type == .FLOAT2 {
        result_id, result_type, result_ok, result_diag := emit_float2_binary_op(s, op, left_id, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT2 && right_type == .FLOAT {
        right_v2 := splat_float2(s, right_id);
        result_id, result_type, result_ok, result_diag := emit_float2_binary_op(s, op, left_id, right_v2);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT2 && is_integral_kind(right_type) {
        right_f, right_f_ok, right_f_diag := coerce_to_float(s, right_id, right_type);
        if !right_f_ok return 0, .UNKNOWN, false, right_f_diag;
        right_v2 := splat_float2(s, right_f);
        result_id, result_type, result_ok, result_diag := emit_float2_binary_op(s, op, left_id, right_v2);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT && right_type == .FLOAT2 {
        left_v2 := splat_float2(s, left_id);
        result_id, result_type, result_ok, result_diag := emit_float2_binary_op(s, op, left_v2, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if is_integral_kind(left_type) && right_type == .FLOAT2 {
        left_f, left_f_ok, left_f_diag := coerce_to_float(s, left_id, left_type);
        if !left_f_ok return 0, .UNKNOWN, false, left_f_diag;
        left_v2 := splat_float2(s, left_f);
        result_id, result_type, result_ok, result_diag := emit_float2_binary_op(s, op, left_v2, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT2X2 && right_type == .FLOAT2 && op == "*" {
        result_id := new_id(s);
        add_op(s, tprint("         % = OpMatrixTimesVector % % %",
                         id_text(result_id),
                         id_text(s.id_float2),
                         id_text(left_id),
                         id_text(right_id)));
        return result_id, .FLOAT2, true, diag;
      }
      if left_type == .FLOAT3 && right_type == .FLOAT3 {
        result_id, result_type, result_ok, result_diag := emit_float3_binary_op(s, op, left_id, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT3 && right_type == .FLOAT {
        right_v3 := splat_float3(s, right_id);
        result_id, result_type, result_ok, result_diag := emit_float3_binary_op(s, op, left_id, right_v3);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT3 && is_integral_kind(right_type) {
        right_f, right_f_ok, right_f_diag := coerce_to_float(s, right_id, right_type);
        if !right_f_ok return 0, .UNKNOWN, false, right_f_diag;
        right_v3 := splat_float3(s, right_f);
        result_id, result_type, result_ok, result_diag := emit_float3_binary_op(s, op, left_id, right_v3);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT && right_type == .FLOAT3 {
        left_v3 := splat_float3(s, left_id);
        result_id, result_type, result_ok, result_diag := emit_float3_binary_op(s, op, left_v3, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if is_integral_kind(left_type) && right_type == .FLOAT3 {
        left_f, left_f_ok, left_f_diag := coerce_to_float(s, left_id, left_type);
        if !left_f_ok return 0, .UNKNOWN, false, left_f_diag;
        left_v3 := splat_float3(s, left_f);
        result_id, result_type, result_ok, result_diag := emit_float3_binary_op(s, op, left_v3, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT4 && right_type == .FLOAT4 {
        result_id, result_type, result_ok, result_diag := emit_float4_binary_op(s, op, left_id, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT4 && right_type == .FLOAT {
        right_v4 := splat_float4(s, right_id);
        result_id, result_type, result_ok, result_diag := emit_float4_binary_op(s, op, left_id, right_v4);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT4 && is_integral_kind(right_type) {
        right_f, right_f_ok, right_f_diag := coerce_to_float(s, right_id, right_type);
        if !right_f_ok return 0, .UNKNOWN, false, right_f_diag;
        right_v4 := splat_float4(s, right_f);
        result_id, result_type, result_ok, result_diag := emit_float4_binary_op(s, op, left_id, right_v4);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT && right_type == .FLOAT4 {
        left_v4 := splat_float4(s, left_id);
        result_id, result_type, result_ok, result_diag := emit_float4_binary_op(s, op, left_v4, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if is_integral_kind(left_type) && right_type == .FLOAT4 {
        left_f, left_f_ok, left_f_diag := coerce_to_float(s, left_id, left_type);
        if !left_f_ok return 0, .UNKNOWN, false, left_f_diag;
        left_v4 := splat_float4(s, left_f);
        result_id, result_type, result_ok, result_diag := emit_float4_binary_op(s, op, left_v4, right_id);
        return result_id, result_type, result_ok, result_diag;
      }
      if left_type == .FLOAT || right_type == .FLOAT {
        left_float, left_float_ok, left_float_diag := coerce_to_float(s, left_id, left_type);
        if !left_float_ok return 0, .UNKNOWN, false, left_float_diag;
        right_float, right_float_ok, right_float_diag := coerce_to_float(s, right_id, right_type);
        if !right_float_ok return 0, .UNKNOWN, false, right_float_diag;
        result_id, result_type, result_ok, result_diag := emit_float_binary_op(s, op, left_float, right_float);
        return result_id, result_type, result_ok, result_diag;
      }

      return_err("SPIR-V backend: unsupported binary op '%' for emitted types (% and %).", op, left_type, right_type);
    }

    case .CAST; {
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;

      target := compact_text(expr.text);
      target_kind := IR_SPV_Gen_Type.UNKNOWN;
      if target == "uint" || target == "u32" {
        target_kind = .UINT;
      } else if target == "int32_t" || target == "s32" {
        target_kind = .INT;
      } else if target == "int" {
        target_kind = .INT64;
      } else if target == "int64_t" || target == "s64" {
        target_kind = .INT64;
      } else if target == "uint64_t" || target == "u64" {
        target_kind = .UINT64;
      } else if target == "bool" {
        target_kind = .BOOL;
      } else if target == "float" {
        target_kind = .FLOAT;
      }
      if target_kind == .UNKNOWN return_err("SPIR-V backend: unsupported cast target '%'.", expr.text);
      converted_id, converted_ok, converted_diag := coerce_to_kind(s, inner_id, inner_type, target_kind);
      if !converted_ok return 0, .UNKNOWN, false, converted_diag;
      return converted_id, target_kind, true, diag;
    }

    case .UNARY; {
      if !expr.left return_err("SPIR-V backend: unary expression missing operand.");
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;
      if expr.text == "+" return inner_id, inner_type, true, diag;
      if expr.text == "-" {
        if inner_type == .FLOAT {
          out := new_id(s);
          add_op(s, tprint("         % = OpFNegate % %",
                           id_text(out), id_text(s.id_float), id_text(inner_id)));
          return out, .FLOAT, true, diag;
        }
        if inner_type == .FLOAT2 {
          out := new_id(s);
          add_op(s, tprint("         % = OpFNegate % %",
                           id_text(out), id_text(s.id_float2), id_text(inner_id)));
          return out, .FLOAT2, true, diag;
        }
        if inner_type == .FLOAT3 {
          out := new_id(s);
          add_op(s, tprint("         % = OpFNegate % %",
                           id_text(out), id_text(s.id_float3), id_text(inner_id)));
          return out, .FLOAT3, true, diag;
        }
        if inner_type == .FLOAT4 {
          out := new_id(s);
          add_op(s, tprint("         % = OpFNegate % %",
                           id_text(out), id_text(s.id_float4), id_text(inner_id)));
          return out, .FLOAT4, true, diag;
        }
        if is_integral_kind(inner_type) {
          out := new_id(s);
          type_id := type_id_from_kind(s, inner_type);
          add_op(s, tprint("         % = OpSNegate % %",
                           id_text(out), id_text(type_id), id_text(inner_id)));
          return out, inner_type, true, diag;
        }
        return_err("SPIR-V backend: unary '-' unsupported for type %.", inner_type);
      }
      if expr.text == "!" {
        if inner_type != .BOOL return_err("SPIR-V backend: unary '!' requires bool.");
        out := new_id(s);
        add_op(s, tprint("         % = OpLogicalNot % %", id_text(out), id_text(s.id_bool), id_text(inner_id)));
        return out, .BOOL, true, diag;
      }
      if expr.text == "~" {
        if !is_integral_kind(inner_type) return_err("SPIR-V backend: unary '~' requires integer.");
        out := new_id(s);
        type_id := type_id_from_kind(s, inner_type);
        add_op(s, tprint("         % = OpNot % %", id_text(out), id_text(type_id), id_text(inner_id)));
        return out, inner_type, true, diag;
      }
      return_err("SPIR-V backend: unsupported unary op '%'.", expr.text);
    }

    case .CALL; {
      if !expr.left return_err("SPIR-V backend: unsupported call target expression.");
      callee := "";
      if expr.left.kind == .IDENT callee = expr.left.text;
      else if expr.left.kind == .MEMBER callee = expr.left.text;
      if callee.count == 0 return_err("SPIR-V backend: unsupported call target expression.");
      if callee == "radians" {
        if expr.args.count != 1 return_err("SPIR-V backend: radians expects 1 arg.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        k := get_f32_const(s, "0.017453292519943295");
        out := new_id(s);
        add_op(s, tprint("         % = OpFMul % % %",
                         id_text(out), id_text(s.id_float), id_text(af), id_text(k)));
        return out, .FLOAT, true, diag;
      }
      if callee == "mod" || callee == "fmod_cycling" {
        if expr.args.count != 2 return_err("SPIR-V backend: mod expects 2 args.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
        if !bf_ok return 0, .UNKNOWN, false, bf_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpFRem % % %", id_text(out), id_text(s.id_float), id_text(af), id_text(bf)));
        return out, .FLOAT, true, diag;
      }
      if callee == "saturate" {
        if expr.args.count != 1 return_err("SPIR-V backend: saturate expects 1 arg.");
        v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
        if !v_ok return 0, .UNKNOWN, false, v_diag;
        vf, vf_ok, vf_diag := coerce_to_float(s, v_id, v_type);
        if !vf_ok return 0, .UNKNOWN, false, vf_diag;
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        out := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %",
                         id_text(out),
                         id_text(s.id_float),
                         id_text(s.id_extinst),
                         "FClamp",
                         id_text(vf),
                         id_text(zero),
                         id_text(one)));
        return out, .FLOAT, true, diag;
      }
      if callee == "step" {
        if expr.args.count != 2 return_err("SPIR-V backend: step expects 2 args.");
        edge_id, edge_type, edge_ok, edge_diag := emit_expr(s, expr.args[0]);
        if !edge_ok return 0, .UNKNOWN, false, edge_diag;
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[1]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        edgef, edgef_ok, edgef_diag := coerce_to_float(s, edge_id, edge_type);
        if !edgef_ok return 0, .UNKNOWN, false, edgef_diag;
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        cond := new_id(s);
        add_op(s, tprint("         % = OpFOrdLessThan % % %", id_text(cond), id_text(s.id_bool), id_text(xf), id_text(edgef)));
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        out := new_id(s);
        add_op(s, tprint("         % = OpSelect % % % %", id_text(out), id_text(s.id_float), id_text(cond), id_text(zero), id_text(one)));
        return out, .FLOAT, true, diag;
      }
      if callee == "mix" {
        if expr.args.count != 3 return_err("SPIR-V backend: mix expects 3 args.");
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[0]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        y_id, y_type, y_ok, y_diag := emit_expr(s, expr.args[1]);
        if !y_ok return 0, .UNKNOWN, false, y_diag;
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[2]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        yf, yf_ok, yf_diag := coerce_to_float(s, y_id, y_type);
        if !yf_ok return 0, .UNKNOWN, false, yf_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        y_minus_x := new_id(s);
        add_op(s, tprint("         % = OpFSub % % %", id_text(y_minus_x), id_text(s.id_float), id_text(yf), id_text(xf)));
        scaled := new_id(s);
        add_op(s, tprint("         % = OpFMul % % %", id_text(scaled), id_text(s.id_float), id_text(af), id_text(y_minus_x)));
        out := new_id(s);
        add_op(s, tprint("         % = OpFAdd % % %", id_text(out), id_text(s.id_float), id_text(xf), id_text(scaled)));
        return out, .FLOAT, true, diag;
      }
      if callee == "pow" {
        if expr.args.count != 2 return_err("SPIR-V backend: pow expects 2 args.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
        if !bf_ok return 0, .UNKNOWN, false, bf_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % %",
                         id_text(out), id_text(s.id_float), id_text(s.id_extinst), "Pow", id_text(af), id_text(bf)));
        return out, .FLOAT, true, diag;
      }
      if callee == "smoothstep" {
        if expr.args.count != 3 return_err("SPIR-V backend: smoothstep expects 3 args.");
        e0_id, e0_type, e0_ok, e0_diag := emit_expr(s, expr.args[0]);
        if !e0_ok return 0, .UNKNOWN, false, e0_diag;
        e1_id, e1_type, e1_ok, e1_diag := emit_expr(s, expr.args[1]);
        if !e1_ok return 0, .UNKNOWN, false, e1_diag;
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[2]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        e0f, e0f_ok, e0f_diag := coerce_to_float(s, e0_id, e0_type);
        if !e0f_ok return 0, .UNKNOWN, false, e0f_diag;
        e1f, e1f_ok, e1f_diag := coerce_to_float(s, e1_id, e1_type);
        if !e1f_ok return 0, .UNKNOWN, false, e1f_diag;
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        num := new_id(s);
        add_op(s, tprint("         % = OpFSub % % %", id_text(num), id_text(s.id_float), id_text(xf), id_text(e0f)));
        den := new_id(s);
        add_op(s, tprint("         % = OpFSub % % %", id_text(den), id_text(s.id_float), id_text(e1f), id_text(e0f)));
        t_raw := new_id(s);
        add_op(s, tprint("         % = OpFDiv % % %", id_text(t_raw), id_text(s.id_float), id_text(num), id_text(den)));
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        t := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(t), id_text(s.id_float), id_text(s.id_extinst), "FClamp", id_text(t_raw), id_text(zero), id_text(one)));
        t2 := new_id(s);
        add_op(s, tprint("         % = OpFMul % % %", id_text(t2), id_text(s.id_float), id_text(t), id_text(t)));
        two := get_f32_const(s, "2.0");
        three := get_f32_const(s, "3.0");
        two_t := new_id(s);
        add_op(s, tprint("         % = OpFMul % % %", id_text(two_t), id_text(s.id_float), id_text(two), id_text(t)));
        three_minus_two_t := new_id(s);
        add_op(s, tprint("         % = OpFSub % % %", id_text(three_minus_two_t), id_text(s.id_float), id_text(three), id_text(two_t)));
        out := new_id(s);
        add_op(s, tprint("         % = OpFMul % % %", id_text(out), id_text(s.id_float), id_text(t2), id_text(three_minus_two_t)));
        return out, .FLOAT, true, diag;
      }
      if callee == "mul" {
        if expr.args.count != 2 return_err("SPIR-V backend: mul expects 2 args.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        out := new_id(s);
        if a_type == .FLOAT2 && b_type == .FLOAT2X2 {
          // IR normalizes Jai's `m * v` into `mul(v, m)` for shader backends.
          // Preserve Jai semantics by evaluating as matrix-times-vector here.
          add_op(s, tprint("         % = OpMatrixTimesVector % % %",
                           id_text(out),
                           id_text(s.id_float2),
                           id_text(b_id),
                           id_text(a_id)));
          return out, .FLOAT2, true, diag;
        }
        if a_type == .FLOAT2X2 && b_type == .FLOAT2 {
          add_op(s, tprint("         % = OpMatrixTimesVector % % %",
                           id_text(out),
                           id_text(s.id_float2),
                           id_text(a_id),
                           id_text(b_id)));
          return out, .FLOAT2, true, diag;
        }
        return_err("SPIR-V backend: unsupported mul argument types (%, %).", a_type, b_type);
      }
      if callee == "floor" || callee == "min" || callee == "max" ||
         callee == "abs" || callee == "sqrt" || callee == "sin" || callee == "cos" || callee == "fract" || callee == "length" {
        if callee == "length" {
          if expr.args.count != 1 return_err("SPIR-V backend: length expects 1 arg.");
          v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
          if !v_ok return 0, .UNKNOWN, false, v_diag;
          v2, v2_ok, v2_diag := coerce_to_float2(s, v_id, v_type);
          if !v2_ok return 0, .UNKNOWN, false, v2_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float), id_text(s.id_extinst), "Length", id_text(v2)));
          return out, .FLOAT, true, diag;
        }
        builtin_id, builtin_type, builtin_ok, builtin_diag := emit_float_builtin_call(s, callee, expr.args);
        if !builtin_ok return 0, .UNKNOWN, false, builtin_diag;
        return builtin_id, builtin_type, true, diag;
      }
      helper := find_function(s, callee);
      if !helper return_err("SPIR-V backend: unsupported call target '%'.", callee);
      helper_id, helper_type, helper_ok, helper_diag := eval_inline_function(s, helper, expr.args);
      return helper_id, helper_type, helper_ok, helper_diag;
    }

    case .CONSTRUCTOR; {
      ctor_type := expr_type_from_decl(expr.text);
      if ctor_type == .FLOAT2 {
        if expr.args.count != 2 return_err("SPIR-V backend: float2 constructor expects 2 args, got %.", expr.args.count);
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
        if !bf_ok return 0, .UNKNOWN, false, bf_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % %",
                         id_text(out),
                         id_text(s.id_float2),
                         id_text(af),
                         id_text(bf)));
        return out, .FLOAT2, true, diag;
      }
      if ctor_type == .FLOAT3 {
        if expr.args.count != 3 return_err("SPIR-V backend: float3 constructor expects 3 args, got %.", expr.args.count);
        a0_id, a0_type, a0_ok, a0_diag := emit_expr(s, expr.args[0]);
        if !a0_ok return 0, .UNKNOWN, false, a0_diag;
        a1_id, a1_type, a1_ok, a1_diag := emit_expr(s, expr.args[1]);
        if !a1_ok return 0, .UNKNOWN, false, a1_diag;
        a2_id, a2_type, a2_ok, a2_diag := emit_expr(s, expr.args[2]);
        if !a2_ok return 0, .UNKNOWN, false, a2_diag;
        f0, f0_ok, f0_diag := coerce_to_float(s, a0_id, a0_type);
        if !f0_ok return 0, .UNKNOWN, false, f0_diag;
        f1, f1_ok, f1_diag := coerce_to_float(s, a1_id, a1_type);
        if !f1_ok return 0, .UNKNOWN, false, f1_diag;
        f2, f2_ok, f2_diag := coerce_to_float(s, a2_id, a2_type);
        if !f2_ok return 0, .UNKNOWN, false, f2_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % % %",
                         id_text(out),
                         id_text(s.id_float3),
                         id_text(f0),
                         id_text(f1),
                         id_text(f2)));
        return out, .FLOAT3, true, diag;
      }
      if ctor_type == .FLOAT4 {
        if expr.args.count != 4 return_err("SPIR-V backend: float4 constructor expects 4 args, got %.", expr.args.count);
        a0_id, a0_type, a0_ok, a0_diag := emit_expr(s, expr.args[0]);
        if !a0_ok return 0, .UNKNOWN, false, a0_diag;
        a1_id, a1_type, a1_ok, a1_diag := emit_expr(s, expr.args[1]);
        if !a1_ok return 0, .UNKNOWN, false, a1_diag;
        a2_id, a2_type, a2_ok, a2_diag := emit_expr(s, expr.args[2]);
        if !a2_ok return 0, .UNKNOWN, false, a2_diag;
        a3_id, a3_type, a3_ok, a3_diag := emit_expr(s, expr.args[3]);
        if !a3_ok return 0, .UNKNOWN, false, a3_diag;
        f0, f0_ok, f0_diag := coerce_to_float(s, a0_id, a0_type);
        if !f0_ok return 0, .UNKNOWN, false, f0_diag;
        f1, f1_ok, f1_diag := coerce_to_float(s, a1_id, a1_type);
        if !f1_ok return 0, .UNKNOWN, false, f1_diag;
        f2, f2_ok, f2_diag := coerce_to_float(s, a2_id, a2_type);
        if !f2_ok return 0, .UNKNOWN, false, f2_diag;
        f3, f3_ok, f3_diag := coerce_to_float(s, a3_id, a3_type);
        if !f3_ok return 0, .UNKNOWN, false, f3_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % % % %",
                         id_text(out),
                         id_text(s.id_float4),
                         id_text(f0),
                         id_text(f1),
                         id_text(f2),
                         id_text(f3)));
        return out, .FLOAT4, true, diag;
      }
      if ctor_type == .FLOAT2X2 {
        if expr.args.count != 4 return_err("SPIR-V backend: float2x2 constructor expects 4 scalar args, got %.", expr.args.count);
        a0_id, a0_type, a0_ok, a0_diag := emit_expr(s, expr.args[0]);
        if !a0_ok return 0, .UNKNOWN, false, a0_diag;
        a1_id, a1_type, a1_ok, a1_diag := emit_expr(s, expr.args[1]);
        if !a1_ok return 0, .UNKNOWN, false, a1_diag;
        a2_id, a2_type, a2_ok, a2_diag := emit_expr(s, expr.args[2]);
        if !a2_ok return 0, .UNKNOWN, false, a2_diag;
        a3_id, a3_type, a3_ok, a3_diag := emit_expr(s, expr.args[3]);
        if !a3_ok return 0, .UNKNOWN, false, a3_diag;

        f0, f0_ok, f0_diag := coerce_to_float(s, a0_id, a0_type);
        if !f0_ok return 0, .UNKNOWN, false, f0_diag;
        f1, f1_ok, f1_diag := coerce_to_float(s, a1_id, a1_type);
        if !f1_ok return 0, .UNKNOWN, false, f1_diag;
        f2, f2_ok, f2_diag := coerce_to_float(s, a2_id, a2_type);
        if !f2_ok return 0, .UNKNOWN, false, f2_diag;
        f3, f3_ok, f3_diag := coerce_to_float(s, a3_id, a3_type);
        if !f3_ok return 0, .UNKNOWN, false, f3_diag;

        // Jai Matrix2.{a,b,c,d} maps to columns (a,c) and (b,d) in float2x2.
        col0 := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % %",
                         id_text(col0),
                         id_text(s.id_float2),
                         id_text(f0),
                         id_text(f2)));
        col1 := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % %",
                         id_text(col1),
                         id_text(s.id_float2),
                         id_text(f1),
                         id_text(f3)));
        out := new_id(s);
        add_op(s, tprint("         % = OpCompositeConstruct % % %",
                         id_text(out),
                         id_text(s.id_float2x2),
                         id_text(col0),
                         id_text(col1)));
        return out, .FLOAT2X2, true, diag;
      }
      return_err("SPIR-V backend: unsupported constructor type '%'.", expr.text);
    }
  }

  return_err("SPIR-V backend: unsupported expression kind %.", expr.kind);
}

emit_lvalue_ptr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(msg, ..args) }; }

  assert(s != null);
  diag: IR_Diagnostic;
  if !expr return_err("SPIR-V backend: null lvalue expression.");
  if expr.kind == .IDENT {
    local := find_local(s, expr.text);
    if !local return_err("SPIR-V backend: unknown lvalue identifier '%'.", expr.text);
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
        add_op(s, tprint("         % = OpAccessChain % % %",
                                    id_text(elem_ptr),
                                    id_text(elem_ptr_type_id),
                                    id_text(local_array.var_id),
                                    id_text(idx)));
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

    buffer_name, base_ok := resolve_ident_or_zero_deref(expr.left);
    if base_ok {
      // already resolved
    } else if expr.left && expr.left.kind == .MEMBER {
      member_root, member_field, member_ok := resolve_member_root_and_field(expr.left);
      if member_ok {
        buffer_name = tprint("%.%", member_root, member_field);
      } else {
        buffer_name = expr_text(expr.left);
      }
    } else {
      return_err("SPIR-V backend: unsupported lvalue subscript base.");
    }
    buffer := find_buffer(s, buffer_name);
    if !buffer return_err("SPIR-V backend: unknown lvalue subscript base '%'.", buffer_name);
    idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    if buffer.element_kind != .STRUCT {
      ptr := new_id(s);
      add_op(s, tprint("         % = OpAccessChain % % % %",
                                  id_text(ptr),
                                  id_text(buffer.ptr_storage_element_type_id),
                                  id_text(buffer.var_id),
                                  id_text(s.id_int_0),
                                  id_text(idx)));
      return ptr, buffer.element_kind, true, diag;
    }
    return_err("SPIR-V backend: struct buffer '%' requires member access on lvalue.", buffer.name);
  }
  if expr.kind == .MEMBER {
    if expr.left && expr.left.kind == .SUBSCRIPT {
      ptr_id, ptr_type, ptr_ok, ptr_diag := emit_buffer_struct_field_ptr(s, expr.left, expr.text);
      return ptr_id, ptr_type, ptr_ok, ptr_diag;
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .SUBSCRIPT {
      field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left.left, expr.left.text);
      if !field_ok return 0, .UNKNOWN, false, field_diag;
      if field_type != .FLOAT2 && field_type != .FLOAT3 && field_type != .FLOAT4 return_err("SPIR-V backend: lvalue component access requires float2/float3/float4 field, got %.", field_type);
      comp_index: u32 = 0;
      if expr.text == "x" comp_index = 0;
      else if expr.text == "y" comp_index = 1;
      else if expr.text == "z" comp_index = 2;
      else if expr.text == "w" comp_index = 3;
      else return_err("SPIR-V backend: unsupported vector component '%' for lvalue.", expr.text);
      if field_type == .FLOAT2 && comp_index > 1 return_err("SPIR-V backend: vector component '%' out of range for float2 lvalue.", expr.text);
      if field_type == .FLOAT3 && comp_index > 2 return_err("SPIR-V backend: vector component '%' out of range for float3 lvalue.", expr.text);
      comp_index_id := get_u32_const(s, comp_index);
      ptr := new_id(s);
      add_op(s, tprint("         % = OpAccessChain % % %",
                       id_text(ptr),
                       id_text(s.id_ptr_storage_float),
                       id_text(field_ptr),
                       id_text(comp_index_id)));
      return ptr, .FLOAT, true, diag;
    }
    if expr.left && expr.left.kind == .IDENT {
      local_vec := find_local(s, expr.left.text);
      if local_vec && (local_vec.type == .FLOAT2 || local_vec.type == .FLOAT3 || local_vec.type == .FLOAT4) {
        comp_index: u32 = 0;
        if expr.text == "x" comp_index = 0;
        else if expr.text == "y" comp_index = 1;
        else if expr.text == "z" comp_index = 2;
        else if expr.text == "w" comp_index = 3;
        else return_err("SPIR-V backend: unsupported vector component '%' for lvalue.", expr.text);
        if local_vec.type == .FLOAT2 && comp_index > 1 return_err("SPIR-V backend: vector component '%' out of range for float2 lvalue.", expr.text);
        if local_vec.type == .FLOAT3 && comp_index > 2 return_err("SPIR-V backend: vector component '%' out of range for float3 lvalue.", expr.text);
        comp_index_id := get_u32_const(s, comp_index);
        ptr := new_id(s);
        add_op(s, tprint("         % = OpAccessChain % % %",
                         id_text(ptr),
                         id_text(s.id_ptr_func_float),
                         id_text(local_vec.ptr_id),
                         id_text(comp_index_id)));
        return ptr, .FLOAT, true, diag;
      }
      local_struct := find_local_struct(s, expr.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.text);
        if !field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.text, expr.text);
        if field.type == .STRUCT return_err("SPIR-V backend: struct field '%.%' must be accessed through a member.", expr.left.text, expr.text);
        return field.ptr_id, field.type, true, diag;
      }
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
      local_struct := find_local_struct(s, expr.left.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.left.text);
        if !field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.left.text, expr.left.text);
        if field.type == .STRUCT {
          nested_struct := find_local_struct(s, field.nested_struct_name);
          if !nested_struct return_err("SPIR-V backend: nested struct '%.%' is missing.", expr.left.left.text, expr.left.text);
          nested_field := find_local_struct_field(nested_struct, expr.text);
          if !nested_field return_err("SPIR-V backend: unknown nested struct field '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          if nested_field.type == .STRUCT return_err("SPIR-V backend: nested struct field '%.%.%' must be accessed through a member.", expr.left.left.text, expr.left.text, expr.text);
          return nested_field.ptr_id, nested_field.type, true, diag;
        }
        if field.type != .FLOAT2 && field.type != .FLOAT3 && field.type != .FLOAT4 return_err("SPIR-V backend: component lvalue requires float2/float3/float4 field, got %.", field.type);
        comp_index: u32 = 0;
        if expr.text == "x" comp_index = 0;
        else if expr.text == "y" comp_index = 1;
        else if expr.text == "z" comp_index = 2;
        else if expr.text == "w" comp_index = 3;
        else return_err("SPIR-V backend: unsupported vector component '%' for lvalue.", expr.text);
        if field.type == .FLOAT2 && comp_index > 1 return_err("SPIR-V backend: vector component '%' out of range for float2 lvalue.", expr.text);
        if field.type == .FLOAT3 && comp_index > 2 return_err("SPIR-V backend: vector component '%' out of range for float3 lvalue.", expr.text);
        comp_index_id := get_u32_const(s, comp_index);
        ptr := new_id(s);
        add_op(s, tprint("         % = OpAccessChain % % %",
                         id_text(ptr),
                         id_text(s.id_ptr_func_float),
                         id_text(field.ptr_id),
                         id_text(comp_index_id)));
        return ptr, .FLOAT, true, diag;
      }
    }
    return_err("SPIR-V backend: unsupported lvalue member expression '%'.", expr_text(expr));
  }
  return_err("SPIR-V backend: unsupported lvalue expression kind %.", expr.kind);
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
      return find_buffer(s, expr_text(expr.left)) != null;
    }
    return false;
  }
  if expr.kind == .MEMBER return lvalue_hits_storage_buffer(s, expr.left);
  return false;
}

// -----------------------------------------------------------------------------
// Statement Emission
// -----------------------------------------------------------------------------

emit_stmt :: (s: *IR_SPV_Gen_State, stmt: *IR_Stmt) -> (ok: bool, terminated: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, { message = sprint(msg, ..args) }; }
  
  assert(s != null);
  diag: IR_Diagnostic;
  if !stmt return_err("SPIR-V backend: null statement.");
  
  if stmt.kind == {
    case .DECL; {
      decl_type := spv_kind_from_ir_type_kind(stmt.decl_type.kind);
      if decl_type == .UNKNOWN {
        decl_type = expr_type_from_decl(stmt.decl_type_name);
      }
      if decl_type == .INT || decl_type == .UINT || decl_type == .INT64 || decl_type == .UINT64 ||
         decl_type == .BOOL || decl_type == .FLOAT || decl_type == .FLOAT2 || decl_type == .FLOAT3 || decl_type == .FLOAT4 || decl_type == .FLOAT2X2 {
        ptr_id := new_id(s);
        ptr_type_id := func_ptr_type_id_from_kind(s, decl_type);
        assert(ptr_type_id != 0);
        add_local_decl(s, tprint("         % = OpVariable % Function",
                                 id_text(ptr_id),
                                 id_text(ptr_type_id)));
        add_debug_name(s, ptr_id, stmt.decl_name);
        array_add(*s.locals, .{name=stmt.decl_name, ptr_id=ptr_id, type=decl_type});
        if stmt.decl_init {
          init_id, init_type, init_ok, init_diag := emit_expr(s, stmt.decl_init);
          if !init_ok return false, false, init_diag;
          init_id, init_ok, init_diag = coerce_to_kind(s, init_id, init_type, decl_type);
          if !init_ok return false, false, init_diag;
          add_op(s, tprint("               OpStore % %",
                           id_text(ptr_id),
                           id_text(init_id)));
        }
        return true, false, diag;
      }

      array_elem_type_name: string;
      array_count: s64;
      is_fixed_array := stmt.decl_type.kind == .FIXED_ARRAY;
      elem_type := spv_kind_from_ir_type_kind(stmt.decl_type.element_kind);
      if is_fixed_array {
        array_elem_type_name = stmt.decl_type.element_display_name;
        array_count = stmt.decl_type.array_count;
        if elem_type == .UNKNOWN {
          elem_type = expr_type_from_decl(array_elem_type_name);
        }
      } else {
        array_elem_type_name, array_count, is_fixed_array = parse_fixed_array_type_name(stmt.decl_type_name);
        elem_type = expr_type_from_decl(array_elem_type_name);
      }
      if is_fixed_array {
        if elem_type == .UNKNOWN || elem_type == .STRUCT {
          return_err("SPIR-V backend: unsupported local array element type '%'.", array_elem_type_name);
        }
        count_const_id := get_u32_const(s, cast(u32) array_count);
        array_type_id := new_id(s);
        ptr_func_array_type_id := new_id(s);
        ptr_id := new_id(s);
        add_debug_name(s, array_type_id, tprint("%_array", stmt.decl_name));
        add_debug_name(s, ptr_func_array_type_id, tprint("%_array_ptr", stmt.decl_name));
        add_local_decl(s, tprint("         % = OpVariable % Function",
                                 id_text(ptr_id),
                                 id_text(ptr_func_array_type_id)));
        add_debug_name(s, ptr_id, stmt.decl_name);
        array_add(*s.local_arrays, .{
          name = stmt.decl_name,
          element_type = elem_type,
          count = array_count,
          var_id = ptr_id,
          array_type_id = array_type_id,
          ptr_func_array_type_id = ptr_func_array_type_id,
          count_const_id = count_const_id,
        });
        array_add(*s.local_array_types, .{
          name = stmt.decl_name,
          element_type = elem_type,
          count = array_count,
          var_id = ptr_id,
          array_type_id = array_type_id,
          ptr_func_array_type_id = ptr_func_array_type_id,
          count_const_id = count_const_id,
        });

        if stmt.decl_init {
          if stmt.decl_init.kind != .ARRAY_LITERAL {
            return_err("SPIR-V backend: local array '%' initializer must be an array literal.", stmt.decl_name);
          }
          if stmt.decl_init.args.count != array_count {
            return_err("SPIR-V backend: local array '%' initializer count mismatch (expected %, got %).",
                       stmt.decl_name, array_count, stmt.decl_init.args.count);
          }
          elem_ptr_type_id := func_ptr_type_id_from_kind(s, elem_type);
          for stmt.decl_init.args {
            value_id, value_type, value_ok, value_diag := emit_expr(s, it);
            if !value_ok return false, false, value_diag;
            if value_type != elem_type {
              return_err("SPIR-V backend: local array '%' initializer type mismatch at index %.", stmt.decl_name, it_index);
            }
            idx_const := get_u32_const(s, cast(u32) it_index);
            elem_ptr := new_id(s);
            add_op(s, tprint("         % = OpAccessChain % % %",
                             id_text(elem_ptr),
                             id_text(elem_ptr_type_id),
                             id_text(ptr_id),
                             id_text(idx_const)));
            add_op(s, tprint("               OpStore % %",
                             id_text(elem_ptr),
                             id_text(value_id)));
          }
        }
        return true, false, diag;
      }

      struct_type_name := stmt.decl_type_name;
      if stmt.decl_type.kind == .STRUCT && stmt.decl_type.struct_name.count != 0 {
        struct_type_name = stmt.decl_type.struct_name;
      }
      struct_def := find_struct(s, struct_type_name);
      if !struct_def {
        return_err("SPIR-V backend: unsupported declaration type '%'.", stmt.decl_type_name);
      }
      local_struct, local_struct_ok, local_struct_diag := alloc_local_struct(s, stmt.decl_name, struct_type_name);
      if !local_struct_ok return false, false, local_struct_diag;

      if stmt.decl_init {
        if stmt.decl_init.kind == .CONSTRUCTOR && stmt.decl_init.text == struct_type_name {
          init_ok, init_diag := init_local_struct_from_expr(s, local_struct, stmt.decl_init);
          if !init_ok return false, false, init_diag;
        } else if stmt.decl_init.kind == .IDENT {
          src_struct := find_local_struct(s, stmt.decl_init.text);
          if !src_struct || src_struct.type_name != struct_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            src_field := find_local_struct_field(src_struct, it.name);
            if !src_field {
              return_err("SPIR-V backend: missing struct field '%' on initializer '%'.", it.name, stmt.decl_init.text);
            }
            if dst_field.type == .STRUCT {
              if src_field.type != .STRUCT {
                return_err("SPIR-V backend: nested struct field '%' type mismatch.", it.name);
              }
              dst_nested := find_local_struct(s, dst_field.nested_struct_name);
              src_nested := find_local_struct(s, src_field.nested_struct_name);
              if !dst_nested || !src_nested {
                return_err("SPIR-V backend: nested struct field '%' could not be resolved.", it.name);
              }
              copy_ok, copy_diag := copy_local_struct_fields(s, dst_nested, src_nested);
              if !copy_ok return false, false, copy_diag;
              continue;
            }
            src_value := new_id(s);
            src_type_id := type_id_from_kind(s, src_field.type);
            if src_type_id == 0 {
              return_err("SPIR-V backend: unsupported struct field type while copying '%'.", it.name);
            }
            add_op(s, tprint("         % = OpLoad % %",
                             id_text(src_value),
                             id_text(src_type_id),
                             id_text(src_field.ptr_id)));
            add_op(s, tprint("               OpStore % %",
                             id_text(dst_field.ptr_id),
                             id_text(src_value)));
          }
        } else if stmt.decl_init.kind == .SUBSCRIPT && stmt.decl_init.left && stmt.decl_init.left.kind == .IDENT {
          buffer := find_buffer(s, stmt.decl_init.left.text);
          if !buffer || buffer.element_kind != .STRUCT || buffer.element_type_name != struct_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            if dst_field.type == .STRUCT {
              return_err("SPIR-V backend: struct declaration '%': nested struct buffer initializers are unsupported for field '%'.", stmt.decl_name, it.name);
            }
            src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, stmt.decl_init, it.name);
            if !src_ok return false, false, src_diag;
            if src_type != dst_field.type {
              return_err("SPIR-V backend: struct declaration '%': field '%' type mismatch in buffer initializer.", stmt.decl_name, it.name);
            }
            src_value := new_id(s);
            src_type_id := type_id_from_kind(s, src_type);
            emit_load(s, src_value, src_type_id, src_ptr, src_type, needs_physical_align=true);
            add_op(s, tprint("               OpStore % %",
                             id_text(dst_field.ptr_id),
                             id_text(src_value)));
          }
        } else if stmt.decl_init.kind == .CALL && stmt.decl_init.left && stmt.decl_init.left.kind == .IDENT {
          helper := find_function(s, stmt.decl_init.left.text);
          helper_return_struct_name := "";
          if helper {
            helper_return_struct_name = helper.return_type.struct_name;
            if helper_return_struct_name.count == 0 helper_return_struct_name = helper.return_type_name;
          }
          if !helper || helper_return_struct_name != struct_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported call initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          call_ok, call_diag := eval_inline_function_to_struct(s, helper, stmt.decl_init.args, local_struct);
          if !call_ok return false, false, call_diag;
        } else {
          return_err("SPIR-V backend: struct declaration '%': unsupported initializer expression kind %.", stmt.decl_name, stmt.decl_init.kind);
        }
      }
      return true, false, diag;
    }

    case .BINARY; {
      op := stmt.binary_op;

      if op == "=" && stmt.binary_left && stmt.binary_left.kind == .SUBSCRIPT &&
         stmt.binary_left.left && stmt.binary_left.left.kind == .IDENT {
        dst_buffer := find_buffer(s, stmt.binary_left.left.text);
        if dst_buffer && dst_buffer.element_kind == .STRUCT {
          src_struct: *IR_SPV_Gen_Local_Struct = null;
          if stmt.binary_right && stmt.binary_right.kind == .IDENT {
            src_struct = find_local_struct(s, stmt.binary_right.text);
            if !src_struct {
              return_err("SPIR-V backend: assignment source '%' is not a local struct.", stmt.binary_right.text);
            }
            if src_struct.type_name != dst_buffer.element_type_name {
              return_err("SPIR-V backend: struct buffer assignment type mismatch ('%' vs '%').",
                         dst_buffer.element_type_name, src_struct.type_name);
            }
          } else if stmt.binary_right && stmt.binary_right.kind == .CALL &&
                    stmt.binary_right.left && stmt.binary_right.left.kind == .IDENT {
            helper := find_function(s, stmt.binary_right.left.text);
            helper_return_struct_name := "";
            if helper {
              helper_return_struct_name = helper.return_type.struct_name;
              if helper_return_struct_name.count == 0 helper_return_struct_name = helper.return_type_name;
            }
            if !helper || helper_return_struct_name != dst_buffer.element_type_name {
              return_err("SPIR-V backend: struct buffer assignment call '%' has incompatible return type.", expr_text(stmt.binary_right));
            }
            tmp_name := tprint("__assign_src_%", new_id(s));
            tmp_struct, tmp_ok, tmp_diag := alloc_local_struct(s, tmp_name, helper_return_struct_name);
            if !tmp_ok return false, false, tmp_diag;
            call_ok, call_diag := eval_inline_function_to_struct(s, helper, stmt.binary_right.args, tmp_struct);
            if !call_ok return false, false, call_diag;
            src_struct = find_local_struct(s, tmp_name);
            if !src_struct {
              return_err("SPIR-V backend: inline helper assignment source struct '%' went missing.", tmp_name);
            }
          } else {
            return_err("SPIR-V backend: unsupported struct buffer assignment rhs '%'.", expr_text(stmt.binary_right));
          }

          for dst_buffer.fields {
            dst_ptr, dst_type, dst_ok, dst_diag := emit_buffer_struct_field_ptr(s, stmt.binary_left, it.name);
            if !dst_ok return false, false, dst_diag;
            if dst_type != it.type {
              return_err("SPIR-V backend: struct buffer field '%' type mismatch on destination.", it.name);
            }
            src_field := find_local_struct_field(src_struct, it.name);
            if !src_field {
              return_err("SPIR-V backend: struct assignment source missing field '%'.", it.name);
            }
            if src_field.type != it.type {
              return_err("SPIR-V backend: struct assignment field '%' type mismatch.", it.name);
            }
            value_id := new_id(s);
            value_type_id := type_id_from_kind(s, it.type);
            add_op(s, tprint("         % = OpLoad % %",
                             id_text(value_id),
                             id_text(value_type_id),
                             id_text(src_field.ptr_id)));
            emit_store(s, dst_ptr, value_id, it.type, needs_physical_align=true);
          }
          return true, false, diag;
        }
      }

      ptr_id, lhs_type, lhs_ok, lhs_diag := emit_lvalue_ptr(s, stmt.binary_left);
      if !lhs_ok return false, false, lhs_diag;
      lhs_is_storage_buffer := lvalue_hits_storage_buffer(s, stmt.binary_left);

      if op == "=" {
        rhs_id, rhs_type, rhs_ok, rhs_diag := emit_expr(s, stmt.binary_right);
        if !rhs_ok return false, false, rhs_diag;
        rhs_id, rhs_ok, rhs_diag = coerce_to_kind(s, rhs_id, rhs_type, lhs_type);
        if !rhs_ok return false, false, rhs_diag;
        emit_store(s, ptr_id, rhs_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
        return true, false, diag;
      }

      if lhs_type == .FLOAT || lhs_type == .FLOAT2 || lhs_type == .FLOAT3 || lhs_type == .FLOAT4 {
        base_op: string = "";
        if op == "+=" base_op = "+";
        if op == "-=" base_op = "-";
        if op == "*=" base_op = "*";
        if op == "/=" base_op = "/";
        if base_op.count == 0 return_err("SPIR-V backend: unsupported float compound assignment op '%'.", op);

        lhs_value := new_id(s);
        lhs_type_id := type_id_from_kind(s, lhs_type);
        emit_load(s, lhs_value, lhs_type_id, ptr_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
        rhs_id, rhs_type, rhs_ok, rhs_diag := emit_expr(s, stmt.binary_right);
        if !rhs_ok return false, false, rhs_diag;

        result_id: s64;
        result_type := IR_SPV_Gen_Type.UNKNOWN;
        result_ok := false;
        result_diag: IR_Diagnostic;
        if lhs_type == .FLOAT {
          rhs_float, rhs_float_ok, rhs_float_diag := coerce_to_float(s, rhs_id, rhs_type);
          if !rhs_float_ok return false, false, rhs_float_diag;
          result_id, result_type, result_ok, result_diag = emit_float_binary_op(s, base_op, lhs_value, rhs_float);
        } else if lhs_type == .FLOAT2 {
          lhs_vec := lhs_value;
          rhs_vec := rhs_id;
          if rhs_type == .FLOAT rhs_vec = splat_float2(s, rhs_id);
          if rhs_type == .FLOAT2 {
            // keep
          } else if rhs_type != .FLOAT {
            return_err("SPIR-V backend: float2 compound assignment rhs must be float or float2.");
          }
          result_id, result_type, result_ok, result_diag = emit_float2_binary_op(s, base_op, lhs_vec, rhs_vec);
        } else if lhs_type == .FLOAT3 {
          lhs_vec := lhs_value;
          rhs_vec := rhs_id;
          if rhs_type == .FLOAT rhs_vec = splat_float3(s, rhs_id);
          if rhs_type == .FLOAT3 {
            // keep
          } else if rhs_type != .FLOAT {
            return_err("SPIR-V backend: float3 compound assignment rhs must be float or float3.");
          }
          result_id, result_type, result_ok, result_diag = emit_float3_binary_op(s, base_op, lhs_vec, rhs_vec);
        } else {
          assert(lhs_type == .FLOAT4);
          lhs_vec := lhs_value;
          rhs_vec := rhs_id;
          if rhs_type == .FLOAT rhs_vec = splat_float4(s, rhs_id);
          if rhs_type == .FLOAT4 {
            // keep
          } else if rhs_type != .FLOAT {
            return_err("SPIR-V backend: float4 compound assignment rhs must be float or float4.");
          }
          result_id, result_type, result_ok, result_diag = emit_float4_binary_op(s, base_op, lhs_vec, rhs_vec);
        }
        if !result_ok return false, false, result_diag;
        if result_type != lhs_type return_err("SPIR-V backend: float compound assignment produced wrong type.");
        emit_store(s, ptr_id, result_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
        return true, false, diag;
      }

      if !is_integral_kind(lhs_type) return_err("SPIR-V backend: non-integer compound assignment is not supported yet.");

      base_op: string = "";
      if op == "+=" base_op = "+";
      if op == "-=" base_op = "-";
      if op == "*=" base_op = "*";
      if op == "%=" base_op = "%";
      if op == "|=" base_op = "|";
      if op == "&=" base_op = "&";
      if op == "^=" base_op = "^";
      if op == "<<=" base_op = "<<";
      if op == ">>=" base_op = ">>";
      if base_op.count == 0 {
        return_err("SPIR-V backend: unsupported statement binary op '%'.", stmt.binary_op);
      }

      lhs_value := new_id(s);
      lhs_type_id := type_id_from_kind(s, lhs_type);
      emit_load(s, lhs_value, lhs_type_id, ptr_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
      rhs_id, rhs_type, rhs_ok, rhs_diag := emit_expr(s, stmt.binary_right);
      if !rhs_ok return false, false, rhs_diag;
      rhs_id, rhs_ok, rhs_diag = coerce_to_kind(s, rhs_id, rhs_type, lhs_type);
      if !rhs_ok return false, false, rhs_diag;
      result_id, result_type, result_ok, result_diag := emit_int_binary_op(s, base_op, lhs_type, lhs_value, rhs_id);
      if !result_ok return false, false, result_diag;
      if result_type != lhs_type {
        return_err("SPIR-V backend: compound assignment operator must produce matching integer type.");
      }

      emit_store(s, ptr_id, result_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
      return true, false, diag;
    }

    case .IF; {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.if_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .BOOL return_err("SPIR-V backend: if condition must be bool.");

      then_label := new_id(s);
      merge_label := new_id(s);
      else_label := merge_label;
      if stmt.if_else else_label = new_id(s);

      add_op(s, tprint("               OpSelectionMerge % None", id_text(merge_label)));
      add_op(s, tprint("               OpBranchConditional % % %",
                                  id_text(cond_id),
                                  id_text(then_label),
                                  id_text(else_label)));

      add_op(s, tprint("         % = OpLabel", id_text(then_label)));
      then_ok, then_terminated, then_diag := emit_stmt_block(s, stmt.if_then);
      if !then_ok return false, false, then_diag;
      if !then_terminated {
        add_op(s, tprint("               OpBranch %", id_text(merge_label)));
      }

      else_terminated := false;
      if stmt.if_else {
        add_op(s, tprint("         % = OpLabel", id_text(else_label)));
        else_ok, local_else_terminated, else_diag := emit_stmt_block(s, stmt.if_else);
        else_terminated = local_else_terminated;
        if !else_ok return false, false, else_diag;
        if !else_terminated {
          add_op(s, tprint("               OpBranch %", id_text(merge_label)));
        }
      }

      add_op(s, tprint("         % = OpLabel", id_text(merge_label)));
      all_terminated := false;
      if stmt.if_else {
        all_terminated = then_terminated && else_terminated;
      }
      return true, all_terminated, diag;
    }

    case .SWITCH; {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.switch_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .UINT return_err("SPIR-V backend: switch condition must be uint.");

      merge_label := new_id(s);
      case_labels: [..] s64;
      default_label := merge_label;
      for stmt.switch_cases {
        label := new_id(s);
        array_add(*case_labels, label);
        if !it.condition default_label = label;
      }

      add_op(s, tprint("               OpSelectionMerge % None", id_text(merge_label)));
      switch_line_sb: String_Builder;
      append(*switch_line_sb, tprint("               OpSwitch % %", id_text(cond_id), id_text(default_label)));
      for stmt.switch_cases {
        if !it.condition continue;
        value, value_ok := parse_u32_literal_expr(it.condition);
        if !value_ok return_err("SPIR-V backend: switch case values must be uint literals.");
        append(*switch_line_sb, tprint(" % %", value, id_text(case_labels[it_index])));
      }
      add_op(s, builder_to_string(*switch_line_sb));

      array_add(*s.break_targets, merge_label);
      for stmt.switch_cases {
        case_block := it.body;
        if !case_block {
          if s.break_targets.count > 0 s.break_targets.count -= 1;
          return_err("SPIR-V backend: switch case body is missing.");
        }
        add_op(s, tprint("         % = OpLabel", id_text(case_labels[it_index])));
        case_ok, case_terminated, case_diag := emit_stmt_block(s, case_block);
        if !case_ok {
          if s.break_targets.count > 0 s.break_targets.count -= 1;
          return false, false, case_diag;
        }
        if !case_terminated {
          target_label := merge_label;
          if it.falls_through && it_index + 1 < case_labels.count {
            target_label = case_labels[it_index+1];
          }
          add_op(s, tprint("               OpBranch %", id_text(target_label)));
        }
      }
      if s.break_targets.count > 0 s.break_targets.count -= 1;

      add_op(s, tprint("         % = OpLabel", id_text(merge_label)));
      return true, false, diag;
    }

    case .FOR; {
      if !stmt.for_body return_err("SPIR-V backend: for-loop body is missing.");

      loop_name := stmt.for_loop_name;
      if loop_name.count == 0 loop_name = "__for_it";

      local_count_before := s.locals.count;

      start_id, start_type, start_ok, start_diag := emit_expr(s, stmt.for_start);
      if !start_ok return false, false, start_diag;
      if !is_integral_kind(start_type) return_err("SPIR-V backend: for-loop start expression must be integer.");

      loop_ptr := new_id(s);
      loop_ptr_type_id := func_ptr_type_id_from_kind(s, start_type);
      if loop_ptr_type_id == 0 return_err("SPIR-V backend: for-loop start type is unsupported (%).", start_type);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                                          id_text(loop_ptr),
                                          id_text(loop_ptr_type_id)));
      add_debug_name(s, loop_ptr, loop_name);
      array_add(*s.locals, .{name=loop_name, ptr_id=loop_ptr, type=start_type});
      add_op(s, tprint("               OpStore % %", id_text(loop_ptr), id_text(start_id)));

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, tprint("               OpBranch %", id_text(header_label)));
      add_op(s, tprint("         % = OpLabel", id_text(header_label)));

      it_value := new_id(s);
      start_type_id := type_id_from_kind(s, start_type);
      add_op(s, tprint("         % = OpLoad % %", id_text(it_value), id_text(start_type_id), id_text(loop_ptr)));
      end_id, end_type, end_ok, end_diag := emit_expr(s, stmt.for_end);
      if !end_ok return false, false, end_diag;
      end_id, end_ok, end_diag = coerce_to_kind(s, end_id, end_type, start_type);
      if !end_ok return false, false, end_diag;
      cmp_id, cmp_type, cmp_ok, cmp_diag := emit_int_binary_op(s, stmt.for_cmp, start_type, it_value, end_id);
      if !cmp_ok return false, false, cmp_diag;
      if cmp_type != .BOOL return_err("SPIR-V backend: for-loop comparison '%' must produce bool.", stmt.for_cmp);
      add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
      add_op(s, tprint("               OpBranchConditional % % %",
                                  id_text(cmp_id),
                                  id_text(body_label),
                                  id_text(merge_label)));

      add_op(s, tprint("         % = OpLabel", id_text(body_label)));
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.for_body);
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, tprint("               OpBranch %", id_text(continue_label)));
      }

      add_op(s, tprint("         % = OpLabel", id_text(continue_label)));
      compact_step := compact_text(stmt.for_step);
      step_op: string;
      if compact_step == "+=1" {
        step_op = "+";
      } else if compact_step == "-=1" {
        step_op = "-";
      } else {
        return_err("SPIR-V backend: unsupported for-loop step '%'.", stmt.for_step);
      }
      step_id: s64;
      if start_type == .INT step_id = get_i32_const(s, 1);
      else if start_type == .UINT step_id = get_u32_const(s, 1);
      else if start_type == .INT64 step_id = get_i64_const(s, 1);
      else if start_type == .UINT64 step_id = get_u64_const(s, 1);
      else return_err("SPIR-V backend: unsupported for-loop induction type %.", start_type);
      it_current := new_id(s);
      add_op(s, tprint("         % = OpLoad % %", id_text(it_current), id_text(start_type_id), id_text(loop_ptr)));
      next_it, next_type, next_ok, next_diag := emit_int_binary_op(s, step_op, start_type, it_current, step_id);
      if !next_ok return false, false, next_diag;
      if next_type != start_type return_err("SPIR-V backend: for-loop step must preserve induction type.");
      add_op(s, tprint("               OpStore % %", id_text(loop_ptr), id_text(next_it)));
      add_op(s, tprint("               OpBranch %", id_text(header_label)));

      add_op(s, tprint("         % = OpLabel", id_text(merge_label)));
      s.locals.count = local_count_before;
      return true, false, diag;
    }

    case .WHILE; {
      if !stmt.while_body return_err("SPIR-V backend: while-loop body is missing.");

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, tprint("               OpBranch %", id_text(header_label)));
      add_op(s, tprint("         % = OpLabel", id_text(header_label)));

      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.while_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .BOOL return_err("SPIR-V backend: while condition must be bool.");
      add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
      add_op(s, tprint("               OpBranchConditional % % %",
                                  id_text(cond_id),
                                  id_text(body_label),
                                  id_text(merge_label)));

      add_op(s, tprint("         % = OpLabel", id_text(body_label)));
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.while_body);
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, tprint("               OpBranch %", id_text(continue_label)));
      }

      add_op(s, tprint("         % = OpLabel", id_text(continue_label)));
      add_op(s, tprint("               OpBranch %", id_text(header_label)));

      add_op(s, tprint("         % = OpLabel", id_text(merge_label)));
      return true, false, diag;
    }

    case .BREAK; {
      break_target, found := get_current_break_target(s);
      if !found return_err("SPIR-V backend: break used outside loop.");
      add_op(s, tprint("               OpBranch %", id_text(break_target)));
      return true, true, diag;
    }

    case .CONTINUE; {
      loop_target, found := get_current_loop_target(s);
      if !found return_err("SPIR-V backend: continue used outside loop.");
      add_op(s, tprint("               OpBranch %", id_text(loop_target.continue_label)));
      return true, true, diag;
    }

    case .RETURN; {
      if s.stage == .COMPUTE {
        if stmt.return_expr {
          return_err("SPIR-V backend: return with value is not supported yet for compute.");
        }
        add_op(s, "               OpReturn");
        return true, true, diag;
      }

      if !stmt.return_expr {
        out_struct := find_local_struct(s, "o");
        ret_ok, ret_diag := emit_output_return_from_struct(s, out_struct);
        if !ret_ok return false, false, ret_diag;
        return true, true, diag;
      }
      if stmt.return_expr.kind != .IDENT {
        return_err("SPIR-V backend: graphics return value must be a local struct identifier.");
      }
      out_struct := find_local_struct(s, stmt.return_expr.text);
      ret_ok, ret_diag := emit_output_return_from_struct(s, out_struct);
      if !ret_ok return false, false, ret_diag;
      return true, true, diag;
    }
  }

  return_err("SPIR-V backend: unsupported statement kind %.", stmt.kind);
}

emit_stmt_block :: (s: *IR_SPV_Gen_State, block: *IR_Block) -> (ok: bool, terminated: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, { message = sprint(msg, ..args) }; }

  assert(s != null);
  diag: IR_Diagnostic;
  if !block return_err("SPIR-V backend: null statement block.");
  local_count_before := s.locals.count;
  local_array_count_before := s.local_arrays.count;
  local_struct_count_before := s.local_structs.count;
  for block.statements {
    ok, terminated, step_diag := emit_stmt(s, *it);
    if !ok {
      s.locals.count = local_count_before;
      s.local_arrays.count = local_array_count_before;
      s.local_structs.count = local_struct_count_before;
      return false, false, step_diag;
    }
    if terminated {
      s.locals.count = local_count_before;
      s.local_arrays.count = local_array_count_before;
      s.local_structs.count = local_struct_count_before;
      return true, true, diag;
    }
  }
  s.locals.count = local_count_before;
  s.local_arrays.count = local_array_count_before;
  s.local_structs.count = local_struct_count_before;
  return true, false, diag;
}

interface_builtin_from_semantic :: (stage: IR_SPV_Gen_Stage, field_name: string, semantic: string) -> IR_SPV_Gen_Interface_Builtin {
  sem := to_upper_copy(semantic);
  if stage == .VERTEX {
    if sem == "SV_VERTEXID" || sem == "VERTEX_ID" return .VERTEX_INDEX;
    if sem == "SV_INSTANCEID" || sem == "INSTANCE_ID" return .INSTANCE_INDEX;
    if sem == "SV_POSITION" || sem == "GL_POSITION" || sem == "POSITION" return .POSITION;
    if sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return .NONE;
  } else if stage == .FRAGMENT {
    if field_name == "gl_FragCoord" return .FRAG_COORD;
    if sem == "SV_POSITION" || sem == "POSITION" || sem == "FRAG_COORD" || sem == "GL_FRAGCOORD" return .FRAG_COORD;
  }
  return .NONE;
}

append_interface_var_decorations :: (sb: *String_Builder, vars: [] IR_SPV_Gen_Interface_Var) {
  location: s64 = 0;
  for vars {
    if it.builtin == .POSITION {
      append(sb, tprint("               OpDecorate % BuiltIn Position\n", id_text(it.var_id)));
      continue;
    }
    if it.builtin == .FRAG_COORD {
      append(sb, tprint("               OpDecorate % BuiltIn FragCoord\n", id_text(it.var_id)));
      continue;
    }
    if it.builtin == .VERTEX_INDEX {
      append(sb, tprint("               OpDecorate % BuiltIn VertexIndex\n", id_text(it.var_id)));
      continue;
    }
    if it.builtin == .INSTANCE_INDEX {
      append(sb, tprint("               OpDecorate % BuiltIn InstanceIndex\n", id_text(it.var_id)));
      continue;
    }
    append(sb, tprint("               OpDecorate % Location %\n", id_text(it.var_id), location));
    location += 1;
  }
}

emit_output_return_from_struct :: (s: *IR_SPV_Gen_State, local_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !local_struct {
    diag.message = "SPIR-V backend: missing local output struct for return.";
    return false, diag;
  }
  for s.output_vars {
    src := find_local_struct_field(local_struct, it.name);
    if !src {
      diag.message = tprint("SPIR-V backend: output struct is missing field '%'.", it.name);
      return false, diag;
    }
    if src.type != it.type {
      diag.message = tprint("SPIR-V backend: output field '%' type mismatch.", it.name);
      return false, diag;
    }
    value_id := new_id(s);
    type_id := type_id_from_kind(s, it.type);
    add_op(s, tprint("         % = OpLoad % %", id_text(value_id), id_text(type_id), id_text(src.ptr_id)));
    add_op(s, tprint("               OpStore % %", id_text(it.var_id), id_text(value_id)));
  }
  add_op(s, "               OpReturn");
  return true, diag;
}

spv_append_buffer_array_type :: (sb: *String_Builder, buffer: IR_SPV_Gen_Buffer) {
  if buffer.fixed_array_count > 0 {
    append(sb, tprint("% = OpTypeArray % %\n",
                      id_text(buffer.runtimearr_type_id),
                      id_text(buffer.element_type_id),
                      id_text(buffer.fixed_array_count_const_id)));
    return;
  }
  append(sb, tprint("% = OpTypeRuntimeArray %\n", id_text(buffer.runtimearr_type_id), id_text(buffer.element_type_id)));
}

parse_parameter_block_struct_name :: (type_name: string) -> (string, bool) {
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

find_pointer_root_arg :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> (*IR_Function_Arg, bool) {
  candidate: *IR_Function_Arg = null;
  for *args {
    if !it.is_pointer continue;
    if !it.pointer_pointee_is_struct continue;
    if it.pointer_pointee_type_name.count == 0 continue;
    if !struct_has_pointer_fields_recursive(extra_structs, it.pointer_pointee_type_name) continue;
    if candidate return null, false;
    candidate = it;
  }
  if !candidate return null, false;
  return candidate, true;
}

ps_assign_struct_info :: (s: *IR_SPV_Gen_State, infos: *[..] IR_SPV_PS_Struct_Info, struct_name: string, prefix: string, depth := 0) -> bool {
  assert(s != null);
  assert(infos != null);
  if depth > 24 return false;
  existing := find_ps_struct_info(infos, struct_name);
  if existing {
    return existing.prefix == prefix;
  }
  st := find_struct(s, struct_name);
  if !st return false;
  array_add(infos, .{
    name = struct_name,
    prefix = prefix,
    type_id = new_id(s),
    ptr_type_id = new_id(s),
  });
  for st.fields {
    field := it;
    if !field.is_pointer continue;
    if !field.pointer_pointee_is_struct continue;
    if field.pointer_pointee_type_name.count == 0 continue;
    if !struct_has_pointer_fields_recursive(s.extra_structs, field.pointer_pointee_type_name, depth + 1) continue;
    next_prefix := tprint("%.%", prefix, field.name);
    if !ps_assign_struct_info(s, infos, field.pointer_pointee_type_name, next_prefix, depth + 1) return false;
  }
  return true;
}

ps_get_ptr_to_ptr_type :: (s: *IR_SPV_Gen_State, ptr_to_ptr_types: *[..] IR_SPV_PS_Ptr_To_Ptr, ptr_type_id: s64) -> s64 {
  assert(s != null);
  assert(ptr_to_ptr_types != null);
  for ptr_to_ptr_types.* if it.ptr_type_id == ptr_type_id return it.ptr_to_ptr_type_id;
  new_ptr := new_id(s);
  array_add(ptr_to_ptr_types, .{
    ptr_type_id = ptr_type_id,
    ptr_to_ptr_type_id = new_ptr,
  });
  return new_ptr;
}

emit_graphics_physical_pointer_abi :: (stage: IR_SPV_Gen_Stage,
                                       source_name: string,
                                       input: IR_Struct,
                                       output: IR_Struct,
                                       args: [] IR_Function_Arg,
                                       body: *IR_Block,
                                       functions: [] IR_Function,
                                       extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, { message = sprint(msg, ..args) }; }

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
  append(*sb, "; SPIR-V\n");
  append(*sb, "; Version: 1.5\n");
  append(*sb, "; Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1\n");
  append(*sb, tprint("; Bound: %\n", state.next_id));
  append(*sb, "; Schema: 0\n");
  spv_append_capabilities(*sb, *state, use_physical_storage=true);
  append(*sb, tprint("          % = OpExtInstImport \"GLSL.std.450\"\n", id_text(state.id_extinst)));
  append(*sb, "               OpMemoryModel PhysicalStorageBuffer64 GLSL450\n");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint % % \"%\"", entry_model, id_text(state.id_main), entry_name));
  for state.input_vars append(*entry_point_sb, " ", id_text(it.var_id));
  for state.output_vars append(*entry_point_sb, " ", id_text(it.var_id));
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
  append(*sb, tprint("               OpDecorate % ArrayStride 4\n", id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("               OpDecorate % Block\n", id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(state.id_buffer_struct)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(buffer.runtimearr_type_id), buffer.array_stride));
    if buffer.element_kind == .STRUCT {
      for buffer.fields append(*sb, tprint("               OpMemberDecorate % % Offset %\n", id_text(buffer.element_type_id), it.index, it.offset));
    }
    append(*sb, tprint("               OpDecorate % Block\n", id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(buffer.wrapper_struct_type_id)));
  }
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

  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    if buffer.element_kind == .STRUCT {
      struct_type_line_sb: String_Builder;
      append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
      for buffer.fields append(*struct_type_line_sb, " ", id_text(type_id_from_kind(*state, it.type)));
      append(*struct_type_line_sb, "\n");
      append(*sb, builder_to_string(*struct_type_line_sb));
    }
    spv_append_buffer_array_type(*sb, buffer);
    append(*sb, tprint("% = OpTypeStruct %\n", id_text(buffer.wrapper_struct_type_id), id_text(buffer.runtimearr_type_id)));
    append(*sb, tprint("% = OpTypePointer % %\n", id_text(buffer.ptr_wrapper_type_id), storage_class, id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("% = OpTypePointer % %\n", id_text(buffer.ptr_storage_element_type_id), storage_class, id_text(buffer.element_type_id)));
  }

  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(root_var_id), id_text(root_var_ptr_type_id)));
  for state.local_array_types {
    append(*sb, tprint("% = OpTypeArray % %\n",
                       id_text(it.array_type_id),
                       id_text(type_id_from_kind(*state, it.element_type)),
                       id_text(it.count_const_id)));
    append(*sb, tprint("% = OpTypePointer Function %\n",
                       id_text(it.ptr_func_array_type_id),
                       id_text(it.array_type_id)));
  }

  append(*sb, tprint("     % = OpFunction % None %\n", id_text(state.id_main), id_text(state.id_void), id_text(state.id_fn_void)));
  append(*sb, tprint("      % = OpLabel\n", id_text(entry_label)));
  for state.local_var_lines append(*sb, it, "\n");
  for state.op_lines append(*sb, it, "\n");
  append(*sb, "               OpFunctionEnd\n");
  return builder_to_string(*sb), true, diag;
}

emit_graphics_generic :: (stage: IR_SPV_Gen_Stage, source_name: string, input: IR_Struct, output: IR_Struct, args: [] IR_Function_Arg, body: *IR_Block, functions: [] IR_Function, extra_structs: [] IR_Struct) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, { message = sprint(msg, ..args) }; }
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
  append(*sb, "; SPIR-V\n");
  append(*sb, "; Version: 1.5\n");
  append(*sb, "; Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1\n");
  append(*sb, tprint("; Bound: %\n", state.next_id));
  append(*sb, "; Schema: 0\n");
  spv_append_capabilities(*sb, *state);
  append(*sb, tprint("          % = OpExtInstImport \"GLSL.std.450\"\n", id_text(state.id_extinst)));
  append(*sb, "               OpMemoryModel Logical GLSL450\n");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint % % \"%\"", entry_model, id_text(state.id_main), entry_name));
  for state.input_vars append(*entry_point_sb, " ", id_text(it.var_id));
  for state.output_vars append(*entry_point_sb, " ", id_text(it.var_id));
  for state.buffers append(*entry_point_sb, " ", id_text(it.var_id));
  for state.uniform_blocks append(*entry_point_sb, " ", id_text(it.var_id));
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
  append(*sb, tprint("               OpDecorate % ArrayStride 4\n", id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("               OpDecorate % Block\n", id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(state.id_buffer_struct)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(buffer.runtimearr_type_id), buffer.array_stride));
    if buffer.element_kind == .STRUCT {
      for buffer.fields {
        append(*sb, tprint("               OpMemberDecorate % % Offset %\n",
                           id_text(buffer.element_type_id), it.index, it.offset));
      }
    }
    append(*sb, tprint("               OpDecorate % Block\n", id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(buffer.wrapper_struct_type_id)));
  }
  for state.buffers {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(it.var_id), it.binding_index));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(it.var_id)));
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
  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    if buffer.element_kind == .STRUCT {
      struct_type_line_sb: String_Builder;
      append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
      for buffer.fields append(*struct_type_line_sb, " ", id_text(type_id_from_kind(*state, it.type)));
      append(*struct_type_line_sb, "\n");
      append(*sb, builder_to_string(*struct_type_line_sb));
    }
    spv_append_buffer_array_type(*sb, buffer);
    append(*sb, tprint("% = OpTypeStruct %\n", id_text(buffer.wrapper_struct_type_id), id_text(buffer.runtimearr_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_wrapper_type_id), id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_storage_element_type_id), id_text(buffer.element_type_id)));
  }
  for state.input_vars append(*sb, tprint("% = OpVariable % Input\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.output_vars append(*sb, tprint("% = OpVariable % Output\n", id_text(it.var_id), id_text(it.ptr_id)));
  for state.buffers append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(it.var_id), id_text(it.ptr_wrapper_type_id)));
  for state.uniform_blocks append(*sb, tprint("% = OpVariable % Uniform\n", id_text(it.var_id), id_text(it.ptr_uniform_struct_type_id)));
  for state.local_array_types {
    append(*sb, tprint("% = OpTypeArray % %\n",
                       id_text(it.array_type_id),
                       id_text(type_id_from_kind(*state, it.element_type)),
                       id_text(it.count_const_id)));
    append(*sb, tprint("% = OpTypePointer Function %\n",
                       id_text(it.ptr_func_array_type_id),
                       id_text(it.array_type_id)));
  }

  append(*sb, tprint("     % = OpFunction % None %\n", id_text(state.id_main), id_text(state.id_void), id_text(state.id_fn_void)));
  append(*sb, tprint("      % = OpLabel\n", id_text(entry_label)));
  for state.local_var_lines append(*sb, it, "\n");
  for state.op_lines append(*sb, it, "\n");
  append(*sb, "               OpFunctionEnd\n");
  return builder_to_string(*sb), true, diag;
}

// -----------------------------------------------------------------------------
// Module Assembly
// -----------------------------------------------------------------------------

emit_compute_generic_uint_buffer :: (shader: IR_Compute_Shader) -> (spvasm: string, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return "", false, { message = sprint(msg, ..args) }; }

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
  append(*sb, "; SPIR-V\n");
  append(*sb, "; Version: 1.5\n");
  append(*sb, "; Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1\n");
  append(*sb, tprint("; Bound: %\n", state.next_id));
  append(*sb, "; Schema: 0\n");
  spv_append_capabilities(*sb, *state);
  append(*sb, tprint("          % = OpExtInstImport \"GLSL.std.450\"\n", id_text(state.id_extinst)));
  append(*sb, "               OpMemoryModel Logical GLSL450\n");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint GLCompute % \"%\" %", id_text(state.id_main), shader.entry_name, id_text(state.id_gl_global_invocation_id)));
  for state.buffers append(*entry_point_sb, " ", id_text(it.var_id));
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
  append(*sb, tprint("               OpDecorate % ArrayStride 4\n", id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("               OpDecorate % Block\n", id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(state.id_buffer_struct)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(buffer.runtimearr_type_id), buffer.array_stride));
    if buffer.element_kind == .STRUCT {
      for buffer.fields {
        append(*sb, tprint("               OpMemberDecorate % % Offset %\n",
                           id_text(buffer.element_type_id),
                           it.index,
                           it.offset));
      }
    }
    append(*sb, tprint("               OpDecorate % Block\n", id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(buffer.wrapper_struct_type_id)));
  }
  for state.buffers {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(it.var_id), it.binding_index));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(it.var_id)));
  }

  spv_append_common_type_decls(*sb, *state, "StorageBuffer");
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_global_invocation_id), id_text(state.id_ptr_input_v3uint)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind == .UINT continue;
    if buffer.element_kind == .STRUCT {
      struct_type_line_sb: String_Builder;
      append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
      for buffer.fields {
        field_type_id := type_id_from_kind(*state, it.type);
        append(*struct_type_line_sb, tprint(" %", id_text(field_type_id)));
      }
      append(*struct_type_line_sb, "\n");
      append(*sb, builder_to_string(*struct_type_line_sb));
    }
    spv_append_buffer_array_type(*sb, buffer);
    append(*sb, tprint("% = OpTypeStruct %\n", id_text(buffer.wrapper_struct_type_id), id_text(buffer.runtimearr_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_wrapper_type_id), id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_storage_element_type_id), id_text(buffer.element_type_id)));
  }
  for state.buffers append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(it.var_id), id_text(it.ptr_wrapper_type_id)));
  // Constants are emitted after types and before function body.
  spv_append_numeric_constants(*sb, *state);
  for state.local_array_types {
    append(*sb, tprint("% = OpTypeArray % %\n",
                       id_text(it.array_type_id),
                       id_text(type_id_from_kind(*state, it.element_type)),
                       id_text(it.count_const_id)));
    append(*sb, tprint("% = OpTypePointer Function %\n",
                       id_text(it.ptr_func_array_type_id),
                       id_text(it.array_type_id)));
  }

  append(*sb, tprint("       % = OpFunction % None %\n",
                     id_text(state.id_main),
                     id_text(state.id_void),
                     id_text(state.id_fn_void)));
  append(*sb, tprint("          % = OpLabel\n", id_text(entry_label)));
  for state.local_var_lines append(*sb, it, "\n");
  for state.op_lines append(*sb, it, "\n");
  if !body_terminated append(*sb, "               OpReturn\n");
  append(*sb, "               OpFunctionEnd\n");

  out := builder_to_string(*sb);
  return out, true, diag;
}
