//
// Jai IR -> SPIR-V text
// 

to_spvasm :: (shader: *IR_Shader) -> IR_Result(string) {
    if #complete shader.kind == {
    case .Vertex;
        using cast(*IR_Vertex_Shader)shader;
        spvasm, ok, diag := emit_graphics_generic(.VERTEX, source_name, input, output, args, *body, functions, extra_structs);
        return {spvasm, ok, diag};
    case .Fragment;
        using cast(*IR_Fragment_Shader)shader;
        spvasm, ok, diag := emit_graphics_generic(.FRAGMENT, source_name, input, output, args, *body, functions, extra_structs);
        return {spvasm, ok, diag};
    case .Compute;
        generic_out, generic_ok, generic_diag := emit_compute_generic_uint_buffer(cast(*IR_Compute_Shader)shader);
        if generic_ok return {generic_out, true, {}};
        if generic_diag.message.count == 0 {
            generic_diag.message = tprint("SPIR-V generic backend: unsupported compute shader '%'.", shader.source_name);
        }
        return {"", false, generic_diag};
    }
} @jdll_export


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
    end2: string = { 2, compact.data + compact.count - 2 };
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
  is_readonly: bool;
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
  uses_sample_2d: bool;
  
  using const_ids: struct {
    id_uint_0: s64;
    id_int_0: s64;
    id_int64_0: s64;
    id_uint64_0: s64;
    id_sample_2d_array_len_const: s64;
  }
  
  id_bound_const: s64;

  using unique_ids: struct {
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
    id_image2d: s64;
    id_sampler: s64;
    id_sampled_image2d: s64;
    id_image2d_array: s64;
    id_sampler_array: s64;
    id_ptr_uniformconst_image2d_array: s64;
    id_ptr_uniformconst_sampler_array: s64;
    id_ptr_uniformconst_image2d: s64;
    id_ptr_uniformconst_sampler: s64;
    id_sample_2d_textures_var: s64;
    id_sample_2d_samplers_var: s64;
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
  };

  bound_value: u32;
}

// -----------------------------------------------------------------------------
// Core State Helpers
// -----------------------------------------------------------------------------

id_text :: inline (id: s64) -> string {
  return tprint("%%", "%", id);
}

new_id :: (s: *IR_SPV_Gen_State) -> s64 {
  assert(s != null);
  id := s.next_id;
  s.next_id += 1;
  return id;
}

// Emits forms like "OpStore id_1 id2"
add_op :: (s: *IR_SPV_Gen_State, name: string, args: ..s64) {
  assert(name[0] == #char "O"); // sanity check for OpXXX
  auto_release_temp();
  sb: String_Builder;
  sb.allocator = temp;
  append_many(*sb, "               ", name);
  if args.count > 0 append(*sb, " ");
  for args {
    append(*sb, id_text(it));
    if it_index != args.count - 1 append(*sb, " ");
  }
  array_add(*s.op_lines, builder_to_string(*sb));
}

// Emits forms like "dest = OpLoad id_1"
add_op :: (s: *IR_SPV_Gen_State, dest: s64, name: string, args: ..s64) -> s64 {
  assert(name[0] == #char "O"); // sanity check for OpXXX
  auto_release_temp();
  sb: String_Builder;
  sb.allocator = temp;
  append_many(*sb, "         ", id_text(dest), " = ", name);
  if args.count > 0 append(*sb, " ");
  for args {
    append(*sb, id_text(it));
    if it_index != args.count - 1 append(*sb, " ");
  }
  array_add(*s.op_lines, builder_to_string(*sb));
  return dest;
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

parse_structured_buffer_type_info :: (type_name: string) -> (element_type_name: string, is_resource: bool, is_readonly: bool) {
  ro_prefix :: "StructuredBuffer<";
  rw_prefix :: "RWStructuredBuffer<";
  prefix := "";
  is_readonly := false;
  if begins_with(type_name, ro_prefix) {
    prefix = ro_prefix;
    is_readonly = true;
  } else if begins_with(type_name, rw_prefix) {
    prefix = rw_prefix;
  } else return "", false, false;
  if type_name.count < prefix.count + 2 return "", false, false;
  if type_name[type_name.count-1] != #char ">" return "", false, false;
  out: string;
  out.data = type_name.data + prefix.count;
  out.count = type_name.count - prefix.count - 1;
  if out.count == 0 return "", false, false;
  return out, true, is_readonly;
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

IR_SPV_Buffer_Element_Info :: struct {
  element_type_name: string;
  elem_kind: IR_SPV_Gen_Type;
  parsed_fixed_array: bool;
  parsed_array_count: s64;
}

parse_buffer_element_info :: (buffer: IR_Compute_Buffer) -> IR_SPV_Buffer_Element_Info {
  using info: IR_SPV_Buffer_Element_Info;
  element_type_name = buffer.element_type_name;
  elem_kind = spv_kind_from_ir_type_kind(buffer.element_type.kind);

  if buffer.element_type.kind == .FIXED_ARRAY {
    parsed_fixed_array = true;
    parsed_array_count = buffer.element_type.array_count;
    element_type_name = buffer.element_type.element_display_name;
    if element_type_name.count == 0 element_type_name = buffer.element_type_name;
    elem_kind = spv_kind_from_ir_type_kind(buffer.element_type.element_kind);
  } else {
    parsed_elem_type_name, parsed_count, parsed_array := parse_fixed_array_type_name(element_type_name);
    if parsed_array {
      parsed_fixed_array = true;
      parsed_array_count = parsed_count;
      element_type_name = parsed_elem_type_name;
    }
  }

  if parsed_fixed_array {
    parsed_elem_type_name, _, parsed_elem_array := parse_fixed_array_type_name(element_type_name);
    if parsed_elem_array element_type_name = parsed_elem_type_name;
  }

  return info;
}

struct_has_pointer_fields :: (st: *IR_Struct) -> bool {
  assert(st != null);
  for st.fields if it.is_pointer return true;
  return false;
}

resource_element_type_from_field :: (s: *IR_SPV_Gen_State, field: *IR_Field) -> (element_type_name: string, is_resource: bool, is_readonly: bool) {
  assert(s != null);
  assert(field != null);

  if field.is_pointer {
    pointee_name := field.pointer_pointee_type_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_struct_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_display_name;
    if pointee_name.count == 0 return "", false, false;
    if field.pointer_pointee_is_struct {
      nested_struct := find_struct(s, pointee_name);
      if nested_struct && struct_has_pointer_fields(nested_struct) return "", false, false;
    }
    return pointee_name, true, false;
  }

  if field.type.kind == .POINTER {
    pointee_name := field.type.pointee_struct_name;
    if pointee_name.count == 0 pointee_name = field.type.pointee_display_name;
    if pointee_name.count == 0 return "", false, false;
    if field.type.pointee_kind == .STRUCT {
      nested_struct := find_struct(s, pointee_name);
      if nested_struct && struct_has_pointer_fields(nested_struct) return "", false, false;
    }
    return pointee_name, true, false;
  }

  elem_type_name, is_resource, is_readonly := parse_structured_buffer_type_info(field.type_name);
  return elem_type_name, is_resource, is_readonly;
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
        array_add(out_buffers, .{
          name = field_path,
          element_type = .{display_name = elem_type_name},
          element_type_name = elem_type_name,
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
    struct_def := find_struct(s, buf.element_type_name);
    if !struct_def {
      array_add(out_buffers, buf);
      continue;
    }

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

make_diag :: (message: string, args: ..Any) -> IR_Diagnostic {
  return { message = sprint("SPIR-V backend: %", tprint(message, ..args)) };
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
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  assert(s != null);
  s.next_id = 1;
  s.bound_value = bound_value;
  s.use_physical_storage = use_physical_storage;
  
  s.id_uint_0      = get_u32_const(s, 0);
  s.id_int_0       = get_i32_const(s, 0);
  s.id_int64_0     = get_i64_const(s, 0);
  s.id_uint64_0    = get_u64_const(s, 0);
  s.id_sample_2d_array_len_const = get_u32_const(s, 16);
  
  s.id_bound_const = get_u32_const(s, bound_value);
  
  #insert -> string {
    sb: String_Builder;
    sb.allocator = temp;
    for type_info(type_of(IR_SPV_Gen_State.unique_ids)).members {
      a(*sb, "s.% = new_id(s);", it.name);
    }
    return builder_to_string(*sb,, temp);
  };

  for buffers {
    var_id := new_id(s);
    buffer_info: IR_SPV_Gen_Buffer = {
      name = it.name,
      var_id = var_id,
      binding_index = it_index,
      is_readonly = it.is_readonly,
    };

    element_info := parse_buffer_element_info(it);
    element_type_name := element_info.element_type_name;
    parsed_array_count := element_info.parsed_array_count;
    parsed_fixed_array := element_info.parsed_fixed_array;
    elem_kind := element_info.elem_kind;

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

      if elem_kind == .UINT && !parsed_fixed_array && !it.is_readonly {
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
  add_op(s, thread_id_ptr, "OpAccessChain", s.id_ptr_input_uint, s.id_gl_global_invocation_id, get_u32_const(s, cast(u32) component_index));
  return add_op(s, new_id(s), "OpLoad", s.id_uint, thread_id_ptr);
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
  if suffix.count == 0 {
    add_op(s, result_id, "OpLoad", type_id, ptr_id);
  } else {
    add_op(s, tprint("         % = OpLoad % %%", id_text(result_id), id_text(type_id), id_text(ptr_id), suffix));
  }
}

emit_store :: (s: *IR_SPV_Gen_State, ptr_id: s64, value_id: s64, kind: IR_SPV_Gen_Type, needs_physical_align := false) {
  assert(s != null);
  suffix := "";
  if needs_physical_align suffix = physical_aligned_suffix(s, kind);
  if suffix.count == 0 {
    add_op(s, "OpStore", ptr_id, value_id);
  } else {
    add_op(s, tprint("               OpStore % %%", id_text(ptr_id), id_text(value_id), suffix));
  }
}

spv_line_is_terminator :: (line: string) -> bool {
  auto_release_temp();
  trimmed := compact_text(line,, temp);
  if trimmed[0] != #char "O" return false;
  if trimmed[1] != #char "p" return false;
  advance(*trimmed, 2);
  if trimmed == {
  case "Return"; #through;
  case "Kill"; #through;
  case "Unreachable"; #through;
  case "BranchConditional"; #through;
  case "Branch"; #through;
  case "Switch";
    return true;
  }
  return false;
}

spv_last_op_is_terminator :: (op_lines: [] string) -> bool {
  idx := op_lines.count;
  while idx > 0 {
    idx -= 1;
    line := compact_text(op_lines[idx],, temp);
    if line.count == 0 continue;
    return spv_line_is_terminator(line);
  }
  return false;
}

spv_append_module_preamble :: (sb: *String_Builder, s: *IR_SPV_Gen_State, memory_model: string, use_physical_storage := false) {
  assert(sb != null);
  assert(s != null);
  a(sb, "; SPIR-V");
  a(sb, "; Version: 1.5");
  a(sb, "; Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1");
  a(sb, "; Bound: %", s.next_id);
  a(sb, "; Schema: 0");
  spv_append_capabilities(sb, s, use_physical_storage);
  a(sb, "          % = OpExtInstImport \"GLSL.std.450\"", id_text(s.id_extinst));
  a(sb, "               OpMemoryModel %", memory_model);
}

spv_append_function_and_body :: (sb: *String_Builder, s: *IR_SPV_Gen_State, entry_label: s64, function_indent: string, label_indent: string) {
  assert(sb != null && s != null);
  a(sb, "% % = OpFunction % None %", function_indent, id_text(s.id_main), id_text(s.id_void), id_text(s.id_fn_void));
  a(sb, "% % = OpLabel\n", label_indent, id_text(entry_label));
  for s.local_var_lines a(sb, it);
  for s.op_lines a(sb, it);
  if !spv_last_op_is_terminator(s.op_lines) a(sb, "               OpReturn");
  a(sb, "               OpFunctionEnd");
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

make_unique_local_struct_name :: (s: *IR_SPV_Gen_State, requested: string) -> string {
  assert(s != null);
  if !find_local_struct(s, requested) return requested;
  return tprint("%__%", requested, new_id(s));
}

alloc_local_struct :: (s: *IR_SPV_Gen_State, name: string, type_name: string) -> (local_struct: *IR_SPV_Gen_Local_Struct, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  struct_def := find_struct(s, type_name);
  if !struct_def return null, false, make_diag("unknown local struct type '%'.", type_name);

  local_struct: IR_SPV_Gen_Local_Struct;
  local_struct.name = name;
  local_struct.type_name = type_name;
  for struct_def.fields {
    field_type := spv_kind_from_ir_type_kind(it.type.kind);
    if field_type == .UNKNOWN field_type = expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN || field_type == .STRUCT {
      nested_def := find_struct(s, it.type_name);
      if !nested_def return null, false, make_diag("local struct '%' field '%' has unsupported type '%'.", type_name, it.name, it.type_name);
      
      nested_name := make_unique_local_struct_name(s, tprint("%.%", name, it.name));
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
      return null, false, make_diag("local struct '%' field '%' type '%' has no function pointer type.", type_name, it.name, it.type_name);
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
    return null, false, make_diag("failed to register local struct '%'.", name);
  }
  return out_struct, true, {};
}

copy_local_struct_fields :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, src: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !dst || !src return false, make_diag("null struct while copying fields.");
  
  if dst.type_name != src.type_name return false, make_diag("struct copy type mismatch ('%' vs '%').", dst.type_name, src.type_name);
  
  for dst.fields {
    src_field := find_local_struct_field(src, it.name);
    if !src_field  return false, make_diag("source struct '%' missing field '%'.", src.type_name, it.name);
    if it.type == .STRUCT {
      if src_field.type != .STRUCT {
        return false, make_diag("struct field '%' type mismatch.", it.name);
      }
      dst_nested := find_local_struct(s, it.nested_struct_name);
      src_nested := find_local_struct(s, src_field.nested_struct_name);
      if !dst_nested || !src_nested {
        return false, make_diag("nested struct field '%' could not be resolved.", it.name);
      }
      nested_ok, nested_diag := copy_local_struct_fields(s, dst_nested, src_nested);
      if !nested_ok return false, nested_diag;
      continue;
    }
    if src_field.type != it.type {
      return false, make_diag("struct field '%' type mismatch.", it.name);
    }
    type_id := type_id_from_kind(s, it.type);
    value_id := add_op(s, new_id(s), "OpLoad", type_id, src_field.ptr_id);
    add_op(s, "OpStore", it.ptr_id, value_id);
  }
  return true, diag;
}

init_local_struct_from_expr :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !dst || !expr return false, make_diag("null struct init inputs.");

  if expr.kind == .IDENT {
    src := find_local_struct(s, expr.text);
    if src == dst {
      i := s.local_structs.count - 1;
      while i >= 0 {
        candidate := s.local_structs.data + i;
        if candidate != dst && candidate.name == expr.text {
          src = candidate;
          break;
        }
        if i == 0 break;
        i -= 1;
      }
    }
    if !src                           return false, make_diag("struct init source '%' is not a local struct.", expr.text);
    if src == dst                     return false, make_diag("struct init source '%' resolves to destination itself.", expr.text);
    if src.type_name != dst.type_name return false, make_diag("struct init type mismatch ('%' vs '%').", dst.type_name, src.type_name);
    
    copy_ok, copy_diag := copy_local_struct_fields(s, dst, src);
    return copy_ok, copy_diag;
  }

  if expr.kind != .CONSTRUCTOR || expr.text != dst.type_name {
    return false, make_diag("unsupported struct init expression for type '%'.", dst.type_name);
  }
  if expr.args.count > dst.fields.count {
    return false, make_diag("struct constructor for '%' has too many arguments.", dst.type_name);
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
        return false, make_diag("constructor for '%' has unknown named field '%'.", dst.type_name, field_name);
      }
      if resolved_args[named_index] {
        return false, make_diag("constructor for '%' sets field '%' more than once.", dst.type_name, field_name);
      }
      resolved_args[named_index] = arg_expr.right;
      continue;
    }

    while positional_index < resolved_args.count && resolved_args[positional_index] positional_index += 1;
    if positional_index >= resolved_args.count {
      return false, make_diag("constructor for '%' has too many positional arguments.", dst.type_name);
    }
    resolved_args[positional_index] = arg_expr;
    positional_index += 1;
  }

  for 0..resolved_args.count-1 {
    if !resolved_args[it] {
      return false, make_diag("constructor for '%' is missing field '%'.", dst.type_name, dst.fields[it].name);
    }
  }

  for dst.fields {
    arg_expr := resolved_args[it_index];
    if it.type == .STRUCT {
      nested_dst := find_local_struct(s, it.nested_struct_name);
      if !nested_dst {
        return false, make_diag("nested struct destination missing for field '%'.", it.name);
      }
      nested_ok, nested_diag := init_local_struct_from_expr(s, nested_dst, arg_expr);
      if !nested_ok return false, nested_diag;
      continue;
    }

    value_id, value_type, value_ok, value_diag := emit_expr(s, arg_expr);
    if !value_ok return false, value_diag;
    if value_type != it.type {
      return false, make_diag("struct constructor field '%' type mismatch.", it.name);
    }
    add_op(s, "OpStore", it.ptr_id, value_id);
  }

  return true, diag;
}

emit_buffer_struct_field_ptr :: (s: *IR_SPV_Gen_State, subscript: *IR_Expr, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }
  
  assert(s != null);
  diag: IR_Diagnostic;
  if !subscript || subscript.kind != .SUBSCRIPT return_err("expected subscript expression for buffer struct field access.");

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
    return_err("subscript base must resolve to a buffer identifier/member.");
  }

  buffer := find_buffer(s, buffer_name);
  if !buffer return_err("unknown subscript base '%'.", buffer_name);
  
  if buffer.element_kind != .STRUCT return_err("buffer '%' is not a struct buffer.", buffer.name);
  field := find_buffer_field(buffer, field_name);
  if !field {
    diag.message = tprint("unknown field '%.%'.", buffer.name, field_name);
    return 0, .UNKNOWN, false, diag;
  }

  idx_id, idx_type, idx_ok, idx_diag := emit_expr(s, subscript.right);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;
  idx_id, idx_ok, idx_diag = coerce_to_kind(s, idx_id, idx_type, .UINT);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;

  field_ptr_type_id := storage_ptr_type_id_from_kind(s, field.type);
  if field_ptr_type_id == 0 return_err("unsupported struct buffer field type for '%.%'.", buffer.name, field.name);

  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain", 
    field_ptr_type_id,
    buffer.var_id,
    s.id_int_0,
    idx_id,
    field_index_id);
  return ptr, field.type, true, diag;
}

emit_uniform_field_ptr :: (s: *IR_SPV_Gen_State, uniform_name: string, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  assert(s != null);
  diag: IR_Diagnostic;
  uniform := find_uniform_block(s, uniform_name);
  if !uniform return_err("unknown uniform block '%'.", uniform_name);
  field := find_uniform_field(uniform, field_name);
  if !field return_err("unknown uniform field '%.%'.", uniform_name, field_name);
  if field.is_array return_err("uniform field '%.%' is an array; index it first.", uniform_name, field_name);
  ptr_type_id := uniform_ptr_type_id_from_kind(s, field.type);
  if ptr_type_id == 0 return_err("unsupported uniform field type for '%.%'.", uniform_name, field_name);
  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain",
    ptr_type_id,
    uniform.var_id,
    field_index_id);
  return ptr, field.type, true, diag;
}

emit_uniform_array_element_ptr :: (s: *IR_SPV_Gen_State, uniform_name: string, field_name: string, index_id: s64, index_type: IR_SPV_Gen_Type) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  assert(s != null);
  diag: IR_Diagnostic;
  index_id, index_ok, index_diag := coerce_to_kind(s, index_id, index_type, .UINT);
  if !index_ok return 0, .UNKNOWN, false, index_diag;
  uniform := find_uniform_block(s, uniform_name);
  if !uniform return_err("unknown uniform block '%'.", uniform_name);
  field := find_uniform_field(uniform, field_name);
  if !field return_err("unknown uniform field '%.%'.", uniform_name, field_name);
  if !field.is_array return_err("uniform field '%.%' is not an array.", uniform_name, field_name);
  elem_ptr_type_id := uniform_ptr_type_id_from_kind(s, field.type);
  if elem_ptr_type_id == 0 return_err("unsupported uniform array element type for '%.%'.", uniform_name, field_name);
  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain",
    elem_ptr_type_id,
    uniform.var_id,
    field_index_id,
    index_id);
  return ptr, field.type, true, diag;
}

emit_int_binary_op :: (s: *IR_SPV_Gen_State, op: string, kind: IR_SPV_Gen_Type, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  assert(is_integral_kind(kind));
  diag: IR_Diagnostic;
  type_id := type_id_from_kind(s, kind);
  if type_id == 0 {
    diag.message = tprint("missing SPIR-V type for integer kind %.", kind);
    return 0, .UNKNOWN, false, diag;
  }
  is_signed := is_signed_integral_kind(kind);
  result_id := new_id(s);
  if op == "+"  { add_op(s, result_id, "OpIAdd", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "-"  { add_op(s, result_id, "OpISub", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "*"  { add_op(s, result_id, "OpIMul", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "/"  { add_op(s, result_id, ifx is_signed then "OpSDiv" else "OpUDiv", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "%"  { add_op(s, result_id, ifx is_signed then "OpSMod" else "OpUMod", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "|"  { add_op(s, result_id, "OpBitwiseOr",        type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "&"  { add_op(s, result_id, "OpBitwiseAnd",       type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "^"  { add_op(s, result_id, "OpBitwiseXor",       type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "<<" { add_op(s, result_id, "OpShiftLeftLogical", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == ">>" { add_op(s, result_id, ifx is_signed then "OpShiftRightArithmetic" else "OpShiftRightLogical", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "<"  { add_op(s, result_id, ifx is_signed then "OpSLessThan" else "OpULessThan", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  if op == ">"  { add_op(s, result_id, ifx is_signed then "OpSGreaterThan" else "OpUGreaterThan", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  if op == "<=" { add_op(s, result_id, ifx is_signed then "OpSLessThanEqual" else "OpULessThanEqual", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  if op == ">=" { add_op(s, result_id, ifx is_signed then "OpSGreaterThanEqual" else "OpUGreaterThanEqual", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  if op == "==" { add_op(s, result_id, "OpIEqual", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  if op == "!=" { add_op(s, result_id, "OpINotEqual", s.id_bool, left_id, right_id); return result_id, .BOOL, true, diag; }
  return 0, .UNKNOWN, false, make_diag("unsupported integer binary op '%' for kind %.", op, kind);
}

coerce_to_float :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT return value_id, true, diag;
  if value_type == .UINT || value_type == .UINT64 {
    converted := new_id(s);
    add_op(s, converted, "OpConvertUToF", s.id_float, value_id);
    return converted, true, diag;
  }
  if value_type == .INT || value_type == .INT64 {
    converted := new_id(s);
    add_op(s, converted, "OpConvertSToF", s.id_float, value_id);
    return converted, true, diag;
  }
  diag.message = "cannot coerce value to float.";
  return 0, false, diag;
}

coerce_to_float2 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float2_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT2 return value_id, true, diag;
  if value_type == .FLOAT return splat_float2(s, value_id), true, diag;
  diag.message = "cannot coerce value to float2.";
  return 0, false, diag;
}

coerce_to_float3 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float3_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if value_type == .FLOAT3 return value_id, true, {};
  if value_type == .FLOAT  return splat_float3(s, value_id), true, {};
  return 0, false, make_diag("cannot coerce value to float3.");
}

coerce_to_float4 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float4_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if value_type == .FLOAT4 return value_id, true, {};
  if value_type == .FLOAT return splat_float4(s, value_id), true, {};
  return 0, false, make_diag("cannot coerce value to float4.");
}

coerce_to_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if src_type == dst_type return value_id, true, {};
  dst_type_id := type_id_from_kind(s, dst_type);
  if dst_type_id == 0 {
    return 0, false, make_diag("unsupported coercion destination type %.", dst_type);
  }

  out := new_id(s);
  if dst_type == .FLOAT {
    if src_type == .UINT || src_type == .UINT64 {
      add_op(s, out, "OpConvertUToF", s.id_float, value_id);
      return out, true, {};
    }
    if src_type == .INT || src_type == .INT64 {
      add_op(s, out, "OpConvertSToF", s.id_float, value_id);
      return out, true, {};
    }
  }

  if dst_type == .BOOL && src_type == .BOOL return value_id, true, {};

  if is_integral_kind(dst_type) {
    if src_type == .FLOAT {
      add_op(s, out, ifx is_signed_integral_kind(dst_type) then "OpConvertFToS" else "OpConvertFToU", dst_type_id, value_id);
      return out, true, {};
    }
    if is_integral_kind(src_type) {
      src_bytes := byte_size_of_kind(src_type);
      dst_bytes := byte_size_of_kind(dst_type);
      if src_bytes != 0 && src_bytes == dst_bytes {
        add_op(s, out, "OpBitcast", dst_type_id, value_id);
        return out, true, {};
      }
      if is_signed_integral_kind(dst_type) {
        add_op(s, out, "OpSConvert", dst_type_id, value_id);
      } else {
        add_op(s, out, "OpUConvert", dst_type_id, value_id);
      }
      return out, true, {};
    }
  }
  return 0, false, make_diag("unsupported coercion from % to %.", src_type, dst_type);
}

coerce_to_exact_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, out_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if src_type == dst_type return value_id, src_type, true, {};
  if dst_type == .FLOAT2 {
    coerced, coerced_ok, coerced_diag := coerce_to_float2(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT2, true, {};
  }
  if dst_type == .FLOAT3 {
    coerced, coerced_ok, coerced_diag := coerce_to_float3(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT3, true, {};
  }
  if dst_type == .FLOAT4 {
    coerced, coerced_ok, coerced_diag := coerce_to_float4(s, value_id, src_type);
    if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
    return coerced, .FLOAT4, true, {};
  }
  coerced, coerced_ok, coerced_diag := coerce_to_kind(s, value_id, src_type, dst_type);
  if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
  return coerced, dst_type, true, {};
}

emit_float_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float, left_id, right_id); return result, .FLOAT, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float, left_id, right_id); return result, .FLOAT, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float, left_id, right_id); return result, .FLOAT, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float, left_id, right_id); return result, .FLOAT, true, {}; }
  if op == "<"  { add_op(s, result, "OpFOrdLessThan", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  if op == ">"  { add_op(s, result, "OpFOrdGreaterThan", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  if op == "<=" { add_op(s, result, "OpFOrdLessThanEqual", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  if op == ">=" { add_op(s, result, "OpFOrdGreaterThanEqual", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  if op == "==" { add_op(s, result, "OpFOrdEqual", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  if op == "!=" { add_op(s, result, "OpFOrdNotEqual", s.id_bool, left_id, right_id); return result, .BOOL, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float binary op '%'.", op);
}

composite_construct :: (s: *IR_SPV_Gen_State, type_id_and_values: ..s64) -> s64 {
  assert(s != null);
  return add_op(s, new_id(s), "OpCompositeConstruct", ..type_id_and_values);
}

splat_float2 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float2, scalar_id, scalar_id); }
splat_float3 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float3, scalar_id, scalar_id, scalar_id); }
splat_float4 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float4, scalar_id, scalar_id, scalar_id, scalar_id); }

emit_float2_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float2 binary op '%'.", op);
}

emit_float3_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float3 binary op '%'.", op);
}

emit_float4_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float4 binary op '%'.", op);
}

emit_float_builtin_call :: (s: *IR_SPV_Gen_State, builtin_name: string, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if builtin_name == "min" || builtin_name == "max" {
    if args.count != 2 {
      return 0, .UNKNOWN, false, make_diag("builtin '%' expects 2 arguments.", builtin_name);
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
    return 0, .UNKNOWN, false, make_diag("builtin '%' expects 1 argument.", builtin_name);
  }
  value_id, value_type, value_ok, value_diag := emit_expr(s, args[0]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  op_name: string;
  if      builtin_name == "floor" op_name = "Floor";
  else if builtin_name == "abs" op_name = "FAbs";
  else if builtin_name == "sqrt" op_name = "Sqrt";
  else if builtin_name == "sin" op_name = "Sin";
  else if builtin_name == "cos" op_name = "Cos";
  else if builtin_name == "fract" op_name = "Fract";
  else return 0, .UNKNOWN, false, make_diag("unsupported float builtin '%'.", builtin_name);

  if value_type == .FLOAT2 {
    if builtin_name == "sin" || builtin_name == "cos" || builtin_name == "sqrt" {
      return 0, .UNKNOWN, false, make_diag("builtin '%' on float2 is not supported yet.", builtin_name);
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

emit_sample_2d_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if s.stage != .FRAGMENT return 0, .UNKNOWN, false, make_diag("sample_2d is currently fragment-stage only.");
  if args.count != 3      return 0, .UNKNOWN, false, make_diag("sample_2d expects 3 args (texture_index, sampler_index, uv).");

  texture_index_id, texture_index_type, texture_index_ok, texture_index_diag := emit_expr(s, args[0]);
  if !texture_index_ok return 0, .UNKNOWN, false, texture_index_diag;
  texture_index_id, texture_index_ok, texture_index_diag = coerce_to_kind(s, texture_index_id, texture_index_type, .UINT);
  if !texture_index_ok return 0, .UNKNOWN, false, texture_index_diag;

  sampler_index_id, sampler_index_type, sampler_index_ok, sampler_index_diag := emit_expr(s, args[1]);
  if !sampler_index_ok return 0, .UNKNOWN, false, sampler_index_diag;
  sampler_index_id, sampler_index_ok, sampler_index_diag = coerce_to_kind(s, sampler_index_id, sampler_index_type, .UINT);
  if !sampler_index_ok return 0, .UNKNOWN, false, sampler_index_diag;

  // Clamp resource indices to the declared bindless array range [0, 15] to make
  // out-of-range shader behavior explicit and deterministic across backends.
  sample_2d_max_index := get_u32_const(s, 15);
  clamped_texture_index := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % UMin % %",
                   id_text(clamped_texture_index),
                   id_text(s.id_uint),
                   id_text(s.id_extinst),
                   id_text(texture_index_id),
                   id_text(sample_2d_max_index)));
  clamped_sampler_index := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % UMin % %",
                   id_text(clamped_sampler_index),
                   id_text(s.id_uint),
                   id_text(s.id_extinst),
                   id_text(sampler_index_id),
                   id_text(sample_2d_max_index)));

  uv_id, uv_type, uv_ok, uv_diag := emit_expr(s, args[2]);
  if !uv_ok return 0, .UNKNOWN, false, uv_diag;
  uv_id, uv_ok, uv_diag = coerce_to_float2(s, uv_id, uv_type);
  if !uv_ok return 0, .UNKNOWN, false, uv_diag;

  tex_ptr       := add_op(s, new_id(s), "OpAccessChain", s.id_ptr_uniformconst_image2d, s.id_sample_2d_textures_var, clamped_texture_index);
  tex_id        := add_op(s, new_id(s), "OpLoad", s.id_image2d, tex_ptr);
  sampler_ptr   := add_op(s, new_id(s), "OpAccessChain", s.id_ptr_uniformconst_sampler, s.id_sample_2d_samplers_var, clamped_sampler_index);
  sampler_id    := add_op(s, new_id(s), "OpLoad", s.id_sampler, sampler_ptr);
  sampled_image := add_op(s, new_id(s), "OpSampledImage", s.id_sampled_image2d, tex_id, sampler_id);
  result        := add_op(s, new_id(s), "OpImageSampleImplicitLod", s.id_float4, sampled_image, uv_id);

  s.uses_sample_2d = true;
  return result, .FLOAT4, true, diag;
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
        return 0, .UNKNOWN, false, true, make_diag("helper '%' has unsupported early control-flow termination in return prelude.", helper.name);
      }
    }

    stmt := *block.statements[block.statements.count-1];

    if stmt.kind == .RETURN {
      if !stmt.return_expr {
        return 0, .UNKNOWN, false, true, make_diag("helper '%' must return a value.", helper.name);
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
        return 0, .UNKNOWN, false, true, make_diag("helper '%' if-condition must lower to bool.", helper.name);
      }

      then_id, then_type, then_ok, then_handled, then_diag := eval_return_block_value(s, helper, return_kind, stmt.if_then);
      if !then_handled return 0, .UNKNOWN, false, false, diag;
      if !then_ok return 0, .UNKNOWN, false, true, then_diag;

      else_id, else_type, else_ok, else_handled, else_diag := eval_return_block_value(s, helper, return_kind, stmt.if_else);
      if !else_handled return 0, .UNKNOWN, false, false, diag;
      if !else_ok return 0, .UNKNOWN, false, true, else_diag;
      if then_type != else_type {
        return 0, .UNKNOWN, false, true, make_diag("helper '%' if-return branches must resolve to same type.", helper.name);
      }
      result_type_id := type_id_from_kind(s, then_type);
      if result_type_id == 0 {
        return 0, .UNKNOWN, false, true, make_diag("helper '%' return type % is unsupported for OpSelect.", helper.name, then_type);
      }
      selected := new_id(s);
      add_op(s, selected, "OpSelect", result_type_id, cond_id, then_id, else_id);
      return selected, then_type, true, true, diag;
    }

    return 0, .UNKNOWN, false, false, diag;
  }

  // Canonical helper bodies:
  //   <prelude...>; return X;
  //   <prelude...>; if (...) ...return... else ...return...
  value_id, value_type, ok, handled, chain_diag := eval_return_block_value(s, helper, return_kind, *helper.body);
  if handled return value_id, value_type, ok, true, chain_diag;
  return 0, .UNKNOWN, false, true, make_diag("helper '%' body is not in canonical return form (normalize pass required).", helper.name);
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
    return true, false, make_diag("helper '%' pointer arg '%' must be a buffer identifier.", helper_name, arg.name);
  }
  source_buffer := find_buffer(s, arg_expr.text);
  if !source_buffer {
    return true, false, make_diag("helper '%' pointer arg '%' expected storage buffer identifier, got '%'.", helper_name, arg.name, arg_expr.text);
  }

  expected_kind := spv_kind_from_ir_type_kind(arg.type.pointee_kind);
  if arg.type.pointee_kind == .STRUCT || expected_kind == .STRUCT {
    if source_buffer.element_kind != .STRUCT {
      return true, false, make_diag("helper '%' pointer arg '%' expected struct buffer pointee '%'.", helper_name, arg.name, arg.type.pointee_struct_name);
    }
    if arg.type.pointee_struct_name.count != 0 && source_buffer.element_type_name != arg.type.pointee_struct_name {
      return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected '%', got '%').", helper_name, arg.name, arg.type.pointee_struct_name, source_buffer.element_type_name);
    }
  } else {
    if expected_kind == .UNKNOWN {
      return true, false, make_diag("helper '%' pointer arg '%' has unsupported pointee kind %.", helper_name, arg.name, arg.type.pointee_kind);
    }
    if source_buffer.element_kind != expected_kind {
      return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected %, got %).", helper_name, arg.name, expected_kind, source_buffer.element_kind);
    }
  }

  if arg.name != arg_expr.text {
    alias := source_buffer.*;
    alias.name = arg.name;
    array_add(*s.buffers, alias);
  }
  return true, true, diag;
}

bind_inline_function_scalar_arg :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  arg_type := spv_kind_from_ir_type_kind(arg.type.kind);
  if arg_type == .UNKNOWN arg_type = expr_type_from_decl(arg.type_name);
  if arg_type == .UNKNOWN || arg_type == .STRUCT return true, false, diag;

  arg_value, value_type, value_ok, value_diag := emit_expr(s, arg_expr);
  if !value_ok return false, true, value_diag;

  final_value := arg_value;
  final_type := value_type;
  if arg_type == .FLOAT || is_integral_kind(arg_type) || arg_type == .BOOL {
    coerced, coerced_ok, coerced_diag := coerce_to_kind(s, arg_value, value_type, arg_type);
    if !coerced_ok return false, true, coerced_diag;
    final_value = coerced;
    final_type = arg_type;
  } else if arg_type == .FLOAT2 && value_type != .FLOAT2 {
    coerced, coerced_ok, coerced_diag := coerce_to_float2(s, arg_value, value_type);
    if !coerced_ok return false, true, coerced_diag;
    final_value = coerced;
    final_type = .FLOAT2;
  } else if arg_type == .FLOAT3 && value_type != .FLOAT3 {
    coerced, coerced_ok, coerced_diag := coerce_to_float3(s, arg_value, value_type);
    if !coerced_ok return false, true, coerced_diag;
    final_value = coerced;
    final_type = .FLOAT3;
  } else if arg_type == .FLOAT4 && value_type != .FLOAT4 {
    coerced, coerced_ok, coerced_diag := coerce_to_float4(s, arg_value, value_type);
    if !coerced_ok return false, true, coerced_diag;
    final_value = coerced;
    final_type = .FLOAT4;
  }

  if final_type != arg_type {
    return false, true, make_diag("helper '%' arg '%' type mismatch (expected %, got %).", function_name, arg.name, arg_type, final_type);
  }

  arg_ptr_type := func_ptr_type_id_from_kind(s, arg_type);
  if arg_ptr_type == 0 {
    return false, true, make_diag("helper '%' arg '%' type '%' has no function pointer representation.", function_name, arg.name, arg_type);
  }
  arg_ptr := new_id(s);
  add_local_decl(s, tprint("         % = OpVariable % Function",
                           id_text(arg_ptr),
                           id_text(arg_ptr_type)));
  add_debug_name(s, arg_ptr, arg.name);
  add_op(s, "OpStore", arg_ptr, final_value);
  array_add(*s.locals, .{name=arg.name, ptr_id=arg_ptr, type=arg_type});
  return true, true, diag;
}

bind_inline_function_struct_arg :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  arg_struct_name := arg.type.struct_name;
  if arg_struct_name.count == 0 arg_struct_name = arg.type_name;
  arg_struct, arg_struct_ok, arg_struct_diag := alloc_local_struct(s, arg.name, arg_struct_name);
  if !arg_struct_ok return false, arg_struct_diag;

  if arg_expr && arg_expr.kind == .SUBSCRIPT && arg_expr.left && arg_expr.left.kind == .IDENT {
    src_buffer := find_buffer(s, arg_expr.left.text);
    if src_buffer && src_buffer.element_kind == .STRUCT && src_buffer.element_type_name == arg_struct_name {
      for arg_struct.fields {
        src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, arg_expr, it.name);
        if !src_ok return false, src_diag;
        if src_type != it.type {
          return false, make_diag("helper '%' struct arg field '%' type mismatch.", function_name, it.name);
        }
        value_id := new_id(s);
        type_id := type_id_from_kind(s, src_type);
        emit_load(s, value_id, type_id, src_ptr, src_type, needs_physical_align=true);
        add_op(s, "OpStore", it.ptr_id, value_id);
      }
      return true, diag;
    }
  }

  init_ok, init_diag := init_local_struct_from_expr(s, arg_struct, arg_expr);
  if !init_ok return false, make_diag("helper '%' struct arg '%' could not be initialized: %", function_name, arg.name, init_diag.message);
  
  return true, diag;
}

bind_inline_function_args :: (s: *IR_SPV_Gen_State, ir_function: *IR_Function, call_args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if !ir_function return false, make_diag("missing function metadata for inline call.");
  
  if ir_function.args.count != call_args.count {
    return false, make_diag("helper '%' expected % args but got %.", ir_function.name, ir_function.args.count, call_args.count);
  }

  for ir_function.args {
    arg_expr := call_args[it_index];
    pointer_handled, pointer_ok, pointer_diag := bind_inline_helper_pointer_arg(s, ir_function.name, it, arg_expr);
    if pointer_handled {
      if !pointer_ok return false, pointer_diag;
      continue;
    }

    scalar_ok, scalar_handled, scalar_diag := bind_inline_function_scalar_arg(s, ir_function.name, it, arg_expr);
    if scalar_handled {
      if !scalar_ok return false, scalar_diag;
      continue;
    }

    struct_ok, struct_diag := bind_inline_function_struct_arg(s, ir_function.name, it, arg_expr);
    if !struct_ok return false, struct_diag;
  }

  return true, {};
}

eval_inline_function :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if !helper return 0, .UNKNOWN, false, make_diag("missing helper metadata for inline call.");
  
  return_kind := spv_kind_from_ir_type_kind(helper.return_type.kind);
  if return_kind == .UNKNOWN return_kind = expr_type_from_decl(helper.return_type_name);
  if return_kind == .UNKNOWN || return_kind == .STRUCT {
    return 0, .UNKNOWN, false, make_diag("helper '%' has unsupported return type '%'.", helper.name, helper.return_type_name);
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }
  bind_ok, bind_diag := bind_inline_function_args(s, helper, call_args);
  if !bind_ok return 0, .UNKNOWN, false, bind_diag;

  return_id, return_type, return_ok, return_handled, return_diag := eval_inline_function_return_chain(s, helper, return_kind);
  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  if !return_handled {
    return 0, .UNKNOWN, false, make_diag("helper '%' body shape is unsupported for inline value return.", helper.name);
  }
  if !return_ok return 0, .UNKNOWN, false, return_diag;
  return return_id, return_type, true, {};
}

eval_inline_function_to_struct :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr, out_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !helper {
    return false, make_diag("missing helper metadata for inline struct call.");
  }
  if !out_struct {
    return false, make_diag("null destination struct for inline helper call.");
  }
  out_struct_name := out_struct.name;
  out_struct_type := out_struct.type_name;
  helper_return_struct_name := helper.return_type.struct_name;
  if helper_return_struct_name.count == 0 helper_return_struct_name = helper.return_type_name;
  if helper_return_struct_name != out_struct_type {
    return false, make_diag("helper '%' return type '%' does not match destination struct '%'.", helper.name, helper.return_type_name, out_struct_type);
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }

  bind_ok, bind_diag := bind_inline_function_args(s, helper, call_args);
  if !bind_ok return false, bind_diag;

  apply_return_expr_to_out :: (s: *IR_SPV_Gen_State, helper_name: string, out_struct: *IR_SPV_Gen_Local_Struct, out_struct_type: string, dst_name: string, expr: *IR_Expr) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !expr {
      return false, true, make_diag("helper '%' must return a struct value.", helper_name);
    }
    if expr.kind != .IDENT return false, false, diag;
    dst_struct := find_local_struct(s, dst_name);
    if !dst_struct dst_struct = out_struct;
    src_struct := find_local_struct(s, expr.text);
    if !src_struct {
      return false, true, make_diag("helper '%' return identifier '%' is not a local struct value.", helper_name, expr.text);
    }
    if src_struct.type_name != out_struct_type {
      diag.message = tprint("helper '%' return struct type mismatch ('%' vs '%').", helper_name, src_struct.type_name, out_struct_type);
      return false, true, diag;
    }
    copy_ok, copy_diag := copy_local_struct_fields(s, dst_struct, src_struct);
    if !copy_ok return false, true, copy_diag;
    return true, true, diag;
  }

  select_struct_fields :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, then_src: *IR_SPV_Gen_Local_Struct, else_src: *IR_SPV_Gen_Local_Struct, cond_id: s64) -> (ok: bool, diag: IR_Diagnostic) {
    diag: IR_Diagnostic;
    if !dst || !then_src || !else_src {
      return false, make_diag("null struct while selecting return fields.");
    }
    if dst.type_name != then_src.type_name || dst.type_name != else_src.type_name {
      return false, make_diag("struct select type mismatch ('%', '%', '%').", dst.type_name, then_src.type_name, else_src.type_name);
    }

    for dst.fields {
      then_field := find_local_struct_field(then_src, it.name);
      else_field := find_local_struct_field(else_src, it.name);
      if !then_field || !else_field {
        return false, make_diag("selected struct '%' missing field '%'.", dst.type_name, it.name);
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
        return false, make_diag("selected struct field '%' type mismatch.", it.name);
      }

      type_id := type_id_from_kind(s, it.type);
      if type_id == 0 {
        return false, make_diag("selected struct field '%' has unsupported type %.", it.name, it.type);
      }
      then_val := new_id(s);
      else_val := new_id(s);
      emit_load(s, then_val, type_id, then_field.ptr_id, then_field.type);
      emit_load(s, else_val, type_id, else_field.ptr_id, else_field.type);
      selected := new_id(s);
      add_op(s, selected, "OpSelect", type_id, cond_id, then_val, else_val);
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
        return false, true, make_diag("helper '%' has unsupported early control-flow termination in struct-return prelude.", helper_name);
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
        return false, true, make_diag("helper '%' if-condition must lower to bool.", helper_name);
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
  return false, make_diag("helper '%' body is not in canonical struct-return form (normalize pass required).", helper.name);
}

ensure_select_result_storage :: (s: *IR_SPV_Gen_State, result_type: IR_SPV_Gen_Type, result_ptr_id: *s64, result_ptr_type_id: *s64, result_type_id: *s64) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  assert(result_ptr_id != null);
  assert(result_ptr_type_id != null);
  assert(result_type_id != null);
  diag: IR_Diagnostic;
  if result_ptr_id.* != 0 return true, diag;

  result_type_id.* = type_id_from_kind(s, result_type);
  if result_type_id.* == 0 {
    return false, make_diag("select expression type % is unsupported.", result_type);
  }
  result_ptr_type_id.* = func_ptr_type_id_from_kind(s, result_type);
  if result_ptr_type_id.* == 0 {
    return false, make_diag("select expression pointer type % is unsupported.", result_type);
  }
  result_ptr_id.* = new_id(s);
  add_local_decl(s, tprint("         % = OpVariable % Function",
                           id_text(result_ptr_id.*),
                           id_text(result_ptr_type_id.*)));
  return true, diag;
}

// -----------------------------------------------------------------------------
// Expression Emission
// -----------------------------------------------------------------------------

emit_expr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(msg, ..args); }

  assert(s != null);
  diag: IR_Diagnostic;
  if !expr return_err("null IR expression.");

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
      return_err("unsupported literal '%'.", expr.text);
    }

    case .IDENT; {
      local := find_local(s, expr.text);
      if !local return_err("unknown identifier '%'.", expr.text);
      value_id := new_id(s);
      result_type_id := type_id_from_kind(s, local.type);
      assert(result_type_id != 0);
      add_op(s, value_id, "OpLoad", result_type_id, local.ptr_id);
      return value_id, local.type, true, diag;
    }

    case .MEMBER; {
      path := expr_text(expr);
      if path == "thread_id.x" || path == "input.thread_id.x" return load_thread_component(s, 0), .UINT, true, diag;
      if path == "thread_id.y" || path == "input.thread_id.y" return load_thread_component(s, 1), .UINT, true, diag;
      if path == "thread_id.z" || path == "input.thread_id.z" return load_thread_component(s, 2), .UINT, true, diag;
      if expr.left && expr.left.kind == .CALL && expr.left.left && expr.left.left.kind == .IDENT {
        helper := find_function(s, expr.left.left.text);
        if !helper return_err("unknown helper '%'.", expr.left.left.text);
        helper_ret_kind := spv_kind_from_ir_type_kind(helper.return_type.kind);
        if helper_ret_kind == .UNKNOWN helper_ret_kind = expr_type_from_decl(helper.return_type_name);
        if helper_ret_kind != .STRUCT return_err("member access on non-struct call return '%'.", helper.return_type_name);
        temp_name := tprint("__call_ret_%", new_id(s));
        helper_ret_struct_name := helper.return_type.struct_name;
        if helper_ret_struct_name.count == 0 helper_ret_struct_name = helper.return_type_name;
        temp_struct, temp_ok, temp_diag := alloc_local_struct(s, temp_name, helper_ret_struct_name);
        if !temp_ok return 0, .UNKNOWN, false, temp_diag;
        call_ok, call_diag := eval_inline_function_to_struct(s, helper, expr.left.args, temp_struct);
        if !call_ok return 0, .UNKNOWN, false, call_diag;
        temp_struct = find_local_struct(s, temp_name);
        if !temp_struct return_err("inline helper result struct '%' went missing.", temp_name);
        field := find_local_struct_field(temp_struct, expr.text);
        if !field return_err("helper call return type '%' has no field '%'.", helper.return_type_name, expr.text);
        value_id := new_id(s);
        type_id := type_id_from_kind(s, field.type);
        add_op(s, value_id, "OpLoad", type_id, field.ptr_id);
        return value_id, field.type, true, diag;
      }
      if expr.left && expr.left.kind == .SUBSCRIPT {
        field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left, expr.text);
        if field_ok {
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, field_type);
          if value_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
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
              if left_type == .FLOAT2 && comp_index > 1 return_err("component '%' out of range for float2.", expr.text);
              if left_type == .FLOAT3 && comp_index > 2 return_err("component '%' out of range for float3.", expr.text);
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
          add_op(s, value_id, "OpLoad", value_type_id, field_ptr);
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
          add_op(s, vec_value, "OpLoad", vec_type_id, local.ptr_id);
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
            if local.type == .FLOAT2 && comp_index > 1 return_err("component '%' out of range for float2.", expr.text);
            if local.type == .FLOAT3 && comp_index > 2 return_err("component '%' out of range for float3.", expr.text);
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
          if !field return_err("unknown struct field '%.%'.", expr.left.text, expr.text);
          if field.type == .STRUCT return_err("struct field '%.%' must be accessed through a member.", expr.left.text, expr.text);
          value_id := new_id(s);
          result_type_id := type_id_from_kind(s, field.type);
          assert(result_type_id != 0);
          add_op(s, value_id, "OpLoad", result_type_id, field.ptr_id);
          return value_id, field.type, true, diag;
        }
      }
      if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
        local_struct := find_local_struct(s, expr.left.left.text);
        if local_struct {
          parent_field := find_local_struct_field(local_struct, expr.left.text);
          if !parent_field return_err("unknown struct field '%.%'.", expr.left.left.text, expr.left.text);
          if parent_field.type != .STRUCT return_err("unsupported member expression '%'.", path);
          nested_struct := find_local_struct(s, parent_field.nested_struct_name);
          if !nested_struct return_err("nested struct '%.%' is missing.", expr.left.left.text, expr.left.text);
          nested_field := find_local_struct_field(nested_struct, expr.text);
          if !nested_field return_err("unknown nested struct field '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          if nested_field.type == .STRUCT return_err("nested struct field '%.%.%' must be accessed through a member.", expr.left.left.text, expr.left.text, expr.text);
          value_id := new_id(s);
          result_type_id := type_id_from_kind(s, nested_field.type);
          if result_type_id == 0 return_err("unsupported nested struct field type for '%.%.%'.", expr.left.left.text, expr.left.text, expr.text);
          add_op(s, value_id, "OpLoad", result_type_id, nested_field.ptr_id);
          return value_id, nested_field.type, true, diag;
        }
      }
      return_err("unsupported member expression '%'.", path);
    }

    case .SUBSCRIPT; {
      if expr.left && expr.left.kind == .MEMBER {
        uniform_name, uniform_field, uniform_ok := resolve_member_root_and_field(expr.left);
        if uniform_ok {
          idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
          if !idx_ok return 0, .UNKNOWN, false, idx_diag;
          ptr, elem_type, ptr_ok, ptr_diag := emit_uniform_array_element_ptr(s, uniform_name, uniform_field, idx, idx_type);
          if ptr_ok {
            value_type_id := type_id_from_kind(s, elem_type);
            value_id := add_op(s, new_id(s), "OpLoad", value_type_id, ptr);
            return value_id, elem_type, true, diag;
          }
        }
      }

      if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
        idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
        if !idx_ok return 0, .UNKNOWN, false, idx_diag;
        ptr, elem_type, ptr_ok, ptr_diag := emit_uniform_array_element_ptr(s, expr.left.left.text, expr.left.text, idx, idx_type);
        if ptr_ok {
          value_type_id := type_id_from_kind(s, elem_type);
          value_id := add_op(s, new_id(s), "OpLoad", value_type_id, ptr);
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
          add_op(s, elem_ptr, "OpAccessChain", elem_ptr_type_id, local_array.var_id, idx);
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, local_array.element_type);
          add_op(s, value_id, "OpLoad", value_type_id, elem_ptr);
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
        return_err("subscript base must resolve to an identifier/member.");
      }
      buffer := find_buffer(s, buffer_name);
      if !buffer return_err("unknown subscript base '%'.", buffer_name);
      idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      if buffer.element_kind != .STRUCT {
        value_ptr_id := new_id(s);
        add_op(s, value_ptr_id, "OpAccessChain", buffer.ptr_storage_element_type_id, buffer.var_id, s.id_int_0, idx);
        value_id := new_id(s);
        value_type_id := type_id_from_kind(s, buffer.element_kind);
        assert(value_type_id != 0);
        emit_load(s, value_id, value_type_id, value_ptr_id, buffer.element_kind, needs_physical_align=true);
        return value_id, buffer.element_kind, true, diag;
      }
      return_err("subscript value access for struct buffer '%' is unsupported; access a field instead.", buffer.name);
    }

    case .BINARY; {
      left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
      if !left_ok return 0, .UNKNOWN, false, left_diag;

      op := expr.text;
      if op == "&&" || op == "||" {
        left_bool, left_bool_ok, left_bool_diag := coerce_to_kind(s, left_id, left_type, .BOOL);
        if !left_bool_ok return 0, .UNKNOWN, false, left_bool_diag;

        result_ptr_id: s64 = 0;
        result_ptr_type_id: s64 = 0;
        result_type_id: s64 = 0;
        storage_ok, storage_diag := ensure_select_result_storage(s, .BOOL, *result_ptr_id, *result_ptr_type_id, *result_type_id);
        if !storage_ok return 0, .UNKNOWN, false, storage_diag;

        rhs_label := new_id(s);
        short_label := new_id(s);
        merge_label := new_id(s);
        add_op(s, tprint("               OpSelectionMerge % None", id_text(merge_label)));
        if op == "&&" {
          add_op(s, "OpBranchConditional", left_bool, rhs_label, short_label);
        } else {
          add_op(s, "OpBranchConditional", left_bool, short_label, rhs_label);
        }

        add_op(s, short_label, "OpLabel");
        short_value := s.id_bool_false;
        if op == "||" short_value = s.id_bool_true;
        emit_store(s, result_ptr_id, short_value, .BOOL);
        add_op(s, "OpBranch", merge_label);

        add_op(s, rhs_label, "OpLabel");
        right_id, right_type, right_ok, right_diag := emit_expr(s, expr.right);
        if !right_ok return 0, .UNKNOWN, false, right_diag;
        right_bool, right_bool_ok, right_bool_diag := coerce_to_kind(s, right_id, right_type, .BOOL);
        if !right_bool_ok return 0, .UNKNOWN, false, right_bool_diag;
        emit_store(s, result_ptr_id, right_bool, .BOOL);
        add_op(s, "OpBranch", merge_label);

        add_op(s, merge_label, "OpLabel");
        out := new_id(s);
        emit_load(s, out, result_type_id, result_ptr_id, .BOOL);
        return out, .BOOL, true, diag;
      }

      right_id, right_type, right_ok, right_diag := emit_expr(s, expr.right);
      if !right_ok return 0, .UNKNOWN, false, right_diag;

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
        if op == "&&" || op == "||" {
          return_err("internal error lowering short-circuit operator '%'.", op);
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
        add_op(s, result_id, "OpMatrixTimesVector", s.id_float2, left_id, right_id);
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

      return_err("unsupported binary op '%' for emitted types (% and %).", op, left_type, right_type);
    }

    case .SELECT; {
      if !expr.left || !expr.right || expr.args.count != 1 {
        return_err("select expression is malformed.");
      }

      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, expr.left);
      if !cond_ok return 0, .UNKNOWN, false, cond_diag;
      cond_id, cond_ok, cond_diag = coerce_to_kind(s, cond_id, cond_type, .BOOL);
      if !cond_ok return 0, .UNKNOWN, false, cond_diag;

      result_type := expr_type_from_decl(expr.text);
      result_ptr_id: s64 = 0;
      result_ptr_type_id: s64 = 0;
      result_type_id: s64 = 0;

      then_label := new_id(s);
      else_label := new_id(s);
      merge_label := new_id(s);
      add_op(s, tprint("               OpSelectionMerge % None", id_text(merge_label)));
      add_op(s, "OpBranchConditional", cond_id, then_label, else_label);

      add_op(s, then_label, "OpLabel");
      then_id, then_type, then_ok, then_diag := emit_expr(s, expr.right);
      if !then_ok return 0, .UNKNOWN, false, then_diag;
      if result_type == .UNKNOWN result_type = then_type;
      storage_ok, storage_diag := ensure_select_result_storage(s, result_type, *result_ptr_id, *result_ptr_type_id, *result_type_id);
      if !storage_ok return 0, .UNKNOWN, false, storage_diag;
      then_id, then_type, then_ok, then_diag = coerce_to_exact_kind(s, then_id, then_type, result_type);
      if !then_ok return 0, .UNKNOWN, false, then_diag;
      emit_store(s, result_ptr_id, then_id, result_type);
      add_op(s, "OpBranch", merge_label);

      add_op(s, else_label, "OpLabel");
      else_id, else_type, else_ok, else_diag := emit_expr(s, expr.args[0]);
      if !else_ok return 0, .UNKNOWN, false, else_diag;
      else_id, else_type, else_ok, else_diag = coerce_to_exact_kind(s, else_id, else_type, result_type);
      if !else_ok {
        return_err("select branches must resolve to a common type (then=% else=% target=%).", then_type, else_type, result_type);
      }
      emit_store(s, result_ptr_id, else_id, result_type);
      add_op(s, "OpBranch", merge_label);

      add_op(s, merge_label, "OpLabel");
      out := new_id(s);
      emit_load(s, out, result_type_id, result_ptr_id, result_type);
      return out, result_type, true, diag;
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
      if target_kind == .UNKNOWN return_err("unsupported cast target '%'.", expr.text);
      converted_id, converted_ok, converted_diag := coerce_to_kind(s, inner_id, inner_type, target_kind);
      if !converted_ok return 0, .UNKNOWN, false, converted_diag;
      return converted_id, target_kind, true, diag;
    }

    case .UNARY; {
      if !expr.left return_err("unary expression missing operand.");
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;
      if expr.text == "+" return inner_id, inner_type, true, diag;
      if expr.text == "-" {
        if inner_type == .FLOAT {
          out := new_id(s);
          add_op(s, out, "OpFNegate", s.id_float, inner_id);
          return out, .FLOAT, true, diag;
        }
        if inner_type == .FLOAT2 {
          out := new_id(s);
          add_op(s, out, "OpFNegate", s.id_float2, inner_id);
          return out, .FLOAT2, true, diag;
        }
        if inner_type == .FLOAT3 {
          out := new_id(s);
          add_op(s, out, "OpFNegate", s.id_float3, inner_id);
          return out, .FLOAT3, true, diag;
        }
        if inner_type == .FLOAT4 {
          out := new_id(s);
          add_op(s, out, "OpFNegate", s.id_float4, inner_id);
          return out, .FLOAT4, true, diag;
        }
        if is_integral_kind(inner_type) {
          out := new_id(s);
          type_id := type_id_from_kind(s, inner_type);
          add_op(s, out, "OpSNegate", type_id, inner_id);
          return out, inner_type, true, diag;
        }
        return_err("unary '-' unsupported for type %.", inner_type);
      }
      if expr.text == "!" {
        if inner_type != .BOOL return_err("unary '!' requires bool.");
        out := new_id(s);
        add_op(s, out, "OpLogicalNot", s.id_bool, inner_id);
        return out, .BOOL, true, diag;
      }
      if expr.text == "~" {
        if !is_integral_kind(inner_type) return_err("unary '~' requires integer.");
        out := new_id(s);
        type_id := type_id_from_kind(s, inner_type);
        add_op(s, out, "OpNot", type_id, inner_id);
        return out, inner_type, true, diag;
      }
      return_err("unsupported unary op '%'.", expr.text);
    }

    case .CALL; {
      if !expr.left return_err("unsupported call target expression.");
      callee := "";
      if expr.left.kind == .IDENT callee = expr.left.text;
      else if expr.left.kind == .MEMBER callee = expr.left.text;
      if callee.count == 0 return_err("unsupported call target expression.");
      if callee == "sample_2d" {
        sampled_id, sampled_type, sampled_ok, sampled_diag := emit_sample_2d_call(s, expr.args);
        return sampled_id, sampled_type, sampled_ok, sampled_diag;
      }
      if callee == "radians" {
        if expr.args.count != 1 return_err("radians expects 1 arg.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        k := get_f32_const(s, "0.017453292519943295");
        out := new_id(s);
        add_op(s, out, "OpFMul", s.id_float, af, k);
        return out, .FLOAT, true, diag;
      }
      if callee == "degrees" {
        if expr.args.count != 1 return_err("d: degrees expects 1 arg.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        k := get_f32_const(s, "57.29577951308232");
        out := new_id(s);
        add_op(s, out, "OpFMul", s.id_float, af, k);
        return out, .FLOAT, true, diag;
      }
      if callee == "mod" || callee == "fmod_cycling" {
        if expr.args.count != 2 return_err("mod expects 2 args.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        if a_type == .FLOAT2 || b_type == .FLOAT2 {
          av, av_ok, av_diag := coerce_to_float2(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          bv, bv_ok, bv_diag := coerce_to_float2(s, b_id, b_type);
          if !bv_ok return 0, .UNKNOWN, false, bv_diag;
          out := new_id(s);
          add_op(s, out, "OpFRem", s.id_float2, av, bv);
          return out, .FLOAT2, true, diag;
        }
        if a_type == .FLOAT3 || b_type == .FLOAT3 {
          av, av_ok, av_diag := coerce_to_float3(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          bv, bv_ok, bv_diag := coerce_to_float3(s, b_id, b_type);
          if !bv_ok return 0, .UNKNOWN, false, bv_diag;
          out := new_id(s);
          add_op(s, out, "OpFRem", s.id_float3, av, bv);
          return out, .FLOAT3, true, diag;
        }
        if a_type == .FLOAT4 || b_type == .FLOAT4 {
          av, av_ok, av_diag := coerce_to_float4(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          bv, bv_ok, bv_diag := coerce_to_float4(s, b_id, b_type);
          if !bv_ok return 0, .UNKNOWN, false, bv_diag;
          out := new_id(s);
          add_op(s, out, "OpFRem", s.id_float4, av, bv);
          return out, .FLOAT4, true, diag;
        }
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
        if !bf_ok return 0, .UNKNOWN, false, bf_diag;
        out := new_id(s);
        add_op(s, out, "OpFRem", s.id_float, af, bf);
        return out, .FLOAT, true, diag;
      }
      if callee == "saturate" {
        if expr.args.count != 1 return_err("saturate expects 1 arg.");
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
      if callee == "clamp" {
        if expr.args.count != 3 return_err("clamp expects 3 args.");
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[0]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        lo_id, lo_type, lo_ok, lo_diag := emit_expr(s, expr.args[1]);
        if !lo_ok return 0, .UNKNOWN, false, lo_diag;
        hi_id, hi_type, hi_ok, hi_diag := emit_expr(s, expr.args[2]);
        if !hi_ok return 0, .UNKNOWN, false, hi_diag;

        if x_type == .FLOAT2 {
          x2, x2_ok, x2_diag := coerce_to_float2(s, x_id, x_type);
          if !x2_ok return 0, .UNKNOWN, false, x2_diag;
          lo2, lo2_ok, lo2_diag := coerce_to_float2(s, lo_id, lo_type);
          if !lo2_ok return 0, .UNKNOWN, false, lo2_diag;
          hi2, hi2_ok, hi2_diag := coerce_to_float2(s, hi_id, hi_type);
          if !hi2_ok return 0, .UNKNOWN, false, hi2_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "FClamp",
                           id_text(x2), id_text(lo2), id_text(hi2)));
          return out, .FLOAT2, true, diag;
        }
        if x_type == .FLOAT3 {
          x3, x3_ok, x3_diag := coerce_to_float3(s, x_id, x_type);
          if !x3_ok return 0, .UNKNOWN, false, x3_diag;
          lo3, lo3_ok, lo3_diag := coerce_to_float3(s, lo_id, lo_type);
          if !lo3_ok return 0, .UNKNOWN, false, lo3_diag;
          hi3, hi3_ok, hi3_diag := coerce_to_float3(s, hi_id, hi_type);
          if !hi3_ok return 0, .UNKNOWN, false, hi3_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "FClamp",
                           id_text(x3), id_text(lo3), id_text(hi3)));
          return out, .FLOAT3, true, diag;
        }
        if x_type == .FLOAT4 {
          x4, x4_ok, x4_diag := coerce_to_float4(s, x_id, x_type);
          if !x4_ok return 0, .UNKNOWN, false, x4_diag;
          lo4, lo4_ok, lo4_diag := coerce_to_float4(s, lo_id, lo_type);
          if !lo4_ok return 0, .UNKNOWN, false, lo4_diag;
          hi4, hi4_ok, hi4_diag := coerce_to_float4(s, hi_id, hi_type);
          if !hi4_ok return 0, .UNKNOWN, false, hi4_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "FClamp",
                           id_text(x4), id_text(lo4), id_text(hi4)));
          return out, .FLOAT4, true, diag;
        }

        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        lof, lof_ok, lof_diag := coerce_to_float(s, lo_id, lo_type);
        if !lof_ok return 0, .UNKNOWN, false, lof_diag;
        hif, hif_ok, hif_diag := coerce_to_float(s, hi_id, hi_type);
        if !hif_ok return 0, .UNKNOWN, false, hif_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float), id_text(s.id_extinst), "FClamp", id_text(xf), id_text(lof), id_text(hif)));
        return out, .FLOAT, true, diag;
      }
      if callee == "step" {
        if expr.args.count != 2 return_err("step expects 2 args.");
        edge_id, edge_type, edge_ok, edge_diag := emit_expr(s, expr.args[0]);
        if !edge_ok return 0, .UNKNOWN, false, edge_diag;
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[1]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        if x_type == .FLOAT2 || edge_type == .FLOAT2 {
          edge2, edge2_ok, edge2_diag := coerce_to_float2(s, edge_id, edge_type);
          if !edge2_ok return 0, .UNKNOWN, false, edge2_diag;
          x2, x2_ok, x2_diag := coerce_to_float2(s, x_id, x_type);
          if !x2_ok return 0, .UNKNOWN, false, x2_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %", id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "Step", id_text(edge2), id_text(x2)));
          return out, .FLOAT2, true, diag;
        }
        if x_type == .FLOAT3 || edge_type == .FLOAT3 {
          edge3, edge3_ok, edge3_diag := coerce_to_float3(s, edge_id, edge_type);
          if !edge3_ok return 0, .UNKNOWN, false, edge3_diag;
          x3, x3_ok, x3_diag := coerce_to_float3(s, x_id, x_type);
          if !x3_ok return 0, .UNKNOWN, false, x3_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %", id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "Step", id_text(edge3), id_text(x3)));
          return out, .FLOAT3, true, diag;
        }
        if x_type == .FLOAT4 || edge_type == .FLOAT4 {
          edge4, edge4_ok, edge4_diag := coerce_to_float4(s, edge_id, edge_type);
          if !edge4_ok return 0, .UNKNOWN, false, edge4_diag;
          x4, x4_ok, x4_diag := coerce_to_float4(s, x_id, x_type);
          if !x4_ok return 0, .UNKNOWN, false, x4_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %", id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "Step", id_text(edge4), id_text(x4)));
          return out, .FLOAT4, true, diag;
        }
        edgef, edgef_ok, edgef_diag := coerce_to_float(s, edge_id, edge_type);
        if !edgef_ok return 0, .UNKNOWN, false, edgef_diag;
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        cond := new_id(s);
        add_op(s, cond, "OpFOrdLessThan", s.id_bool, xf, edgef);
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        out := new_id(s);
        add_op(s, out, "OpSelect", s.id_float, cond, zero, one);
        return out, .FLOAT, true, diag;
      }
      if callee == "mix" {
        if expr.args.count != 3 return_err("mix expects 3 args.");
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[0]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        y_id, y_type, y_ok, y_diag := emit_expr(s, expr.args[1]);
        if !y_ok return 0, .UNKNOWN, false, y_diag;
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[2]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        if x_type == .FLOAT2 || y_type == .FLOAT2 || a_type == .FLOAT2 {
          xv, xv_ok, xv_diag := coerce_to_float2(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          yv, yv_ok, yv_diag := coerce_to_float2(s, y_id, y_type);
          if !yv_ok return 0, .UNKNOWN, false, yv_diag;
          av, av_ok, av_diag := coerce_to_float2(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "FMix", id_text(xv), id_text(yv), id_text(av)));
          return out, .FLOAT2, true, diag;
        }
        if x_type == .FLOAT3 || y_type == .FLOAT3 || a_type == .FLOAT3 {
          xv, xv_ok, xv_diag := coerce_to_float3(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          yv, yv_ok, yv_diag := coerce_to_float3(s, y_id, y_type);
          if !yv_ok return 0, .UNKNOWN, false, yv_diag;
          av, av_ok, av_diag := coerce_to_float3(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "FMix", id_text(xv), id_text(yv), id_text(av)));
          return out, .FLOAT3, true, diag;
        }
        if x_type == .FLOAT4 || y_type == .FLOAT4 || a_type == .FLOAT4 {
          xv, xv_ok, xv_diag := coerce_to_float4(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          yv, yv_ok, yv_diag := coerce_to_float4(s, y_id, y_type);
          if !yv_ok return 0, .UNKNOWN, false, yv_diag;
          av, av_ok, av_diag := coerce_to_float4(s, a_id, a_type);
          if !av_ok return 0, .UNKNOWN, false, av_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "FMix", id_text(xv), id_text(yv), id_text(av)));
          return out, .FLOAT4, true, diag;
        }
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        yf, yf_ok, yf_diag := coerce_to_float(s, y_id, y_type);
        if !yf_ok return 0, .UNKNOWN, false, yf_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        y_minus_x := new_id(s);
        add_op(s, y_minus_x, "OpFSub", s.id_float, yf, xf);
        scaled := new_id(s);
        add_op(s, scaled, "OpFMul", s.id_float, af, y_minus_x);
        out := new_id(s);
        add_op(s, out, "OpFAdd", s.id_float, xf, scaled);
        return out, .FLOAT, true, diag;
      }
      if callee == "pow" {
        if expr.args.count != 2 return_err("pow expects 2 args.");
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
        if expr.args.count != 3 return_err("smoothstep expects 3 args.");
        e0_id, e0_type, e0_ok, e0_diag := emit_expr(s, expr.args[0]);
        if !e0_ok return 0, .UNKNOWN, false, e0_diag;
        e1_id, e1_type, e1_ok, e1_diag := emit_expr(s, expr.args[1]);
        if !e1_ok return 0, .UNKNOWN, false, e1_diag;
        x_id, x_type, x_ok, x_diag := emit_expr(s, expr.args[2]);
        if !x_ok return 0, .UNKNOWN, false, x_diag;
        if x_type == .FLOAT2 || e0_type == .FLOAT2 || e1_type == .FLOAT2 {
          e0v, e0v_ok, e0v_diag := coerce_to_float2(s, e0_id, e0_type);
          if !e0v_ok return 0, .UNKNOWN, false, e0v_diag;
          e1v, e1v_ok, e1v_diag := coerce_to_float2(s, e1_id, e1_type);
          if !e1v_ok return 0, .UNKNOWN, false, e1v_diag;
          xv, xv_ok, xv_diag := coerce_to_float2(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "SmoothStep", id_text(e0v), id_text(e1v), id_text(xv)));
          return out, .FLOAT2, true, diag;
        }
        if x_type == .FLOAT3 || e0_type == .FLOAT3 || e1_type == .FLOAT3 {
          e0v, e0v_ok, e0v_diag := coerce_to_float3(s, e0_id, e0_type);
          if !e0v_ok return 0, .UNKNOWN, false, e0v_diag;
          e1v, e1v_ok, e1v_diag := coerce_to_float3(s, e1_id, e1_type);
          if !e1v_ok return 0, .UNKNOWN, false, e1v_diag;
          xv, xv_ok, xv_diag := coerce_to_float3(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "SmoothStep", id_text(e0v), id_text(e1v), id_text(xv)));
          return out, .FLOAT3, true, diag;
        }
        if x_type == .FLOAT4 || e0_type == .FLOAT4 || e1_type == .FLOAT4 {
          e0v, e0v_ok, e0v_diag := coerce_to_float4(s, e0_id, e0_type);
          if !e0v_ok return 0, .UNKNOWN, false, e0v_diag;
          e1v, e1v_ok, e1v_diag := coerce_to_float4(s, e1_id, e1_type);
          if !e1v_ok return 0, .UNKNOWN, false, e1v_diag;
          xv, xv_ok, xv_diag := coerce_to_float4(s, x_id, x_type);
          if !xv_ok return 0, .UNKNOWN, false, xv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "SmoothStep", id_text(e0v), id_text(e1v), id_text(xv)));
          return out, .FLOAT4, true, diag;
        }
        e0f, e0f_ok, e0f_diag := coerce_to_float(s, e0_id, e0_type);
        if !e0f_ok return 0, .UNKNOWN, false, e0f_diag;
        e1f, e1f_ok, e1f_diag := coerce_to_float(s, e1_id, e1_type);
        if !e1f_ok return 0, .UNKNOWN, false, e1f_diag;
        xf, xf_ok, xf_diag := coerce_to_float(s, x_id, x_type);
        if !xf_ok return 0, .UNKNOWN, false, xf_diag;
        num := new_id(s);
        add_op(s, num, "OpFSub", s.id_float, xf, e0f);
        den := new_id(s);
        add_op(s, den, "OpFSub", s.id_float, e1f, e0f);
        t_raw := new_id(s);
        add_op(s, t_raw, "OpFDiv", s.id_float, num, den);
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        t := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %", id_text(t), id_text(s.id_float), id_text(s.id_extinst), "FClamp", id_text(t_raw), id_text(zero), id_text(one)));
        t2 := new_id(s);
        add_op(s, t2, "OpFMul", s.id_float, t, t);
        two := get_f32_const(s, "2.0");
        three := get_f32_const(s, "3.0");
        two_t := new_id(s);
        add_op(s, two_t, "OpFMul", s.id_float, two, t);
        three_minus_two_t := new_id(s);
        add_op(s, three_minus_two_t, "OpFSub", s.id_float, three, two_t);
        out := new_id(s);
        add_op(s, out, "OpFMul", s.id_float, t2, three_minus_two_t);
        return out, .FLOAT, true, diag;
      }
      if callee == "mul" {
        if expr.args.count != 2 return_err("mul expects 2 args.");
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        out := new_id(s);
        if a_type == .FLOAT2 && b_type == .FLOAT2X2 {
          // IR normalizes Jai's `m * v` into `mul(v, m)` for shader backends.
          // Preserve Jai semantics by evaluating as matrix-times-vector here.
          add_op(s, out, "OpMatrixTimesVector", s.id_float2, b_id, a_id);
          return out, .FLOAT2, true, diag;
        }
        if a_type == .FLOAT2X2 && b_type == .FLOAT2 {
          add_op(s, out, "OpMatrixTimesVector", s.id_float2, a_id, b_id);
          return out, .FLOAT2, true, diag;
        }
        return_err("unsupported mul argument types (%, %).", a_type, b_type);
      }
      if callee == "floor" || callee == "min" || callee == "max" ||
         callee == "abs" || callee == "sqrt" || callee == "sin" || callee == "cos" || callee == "fract" || callee == "length" || callee == "normalize" {
        if callee == "length" {
          if expr.args.count != 1 return_err("length expects 1 arg.");
          v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
          if !v_ok return 0, .UNKNOWN, false, v_diag;
          v2, v2_ok, v2_diag := coerce_to_float2(s, v_id, v_type);
          if !v2_ok return 0, .UNKNOWN, false, v2_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float), id_text(s.id_extinst), "Length", id_text(v2)));
          return out, .FLOAT, true, diag;
        }
        if callee == "normalize" {
          if expr.args.count != 1 return_err("normalize expects 1 arg.");
          v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
          if !v_ok return 0, .UNKNOWN, false, v_diag;

          if v_type == .FLOAT2 {
            v2, v2_ok, v2_diag := coerce_to_float2(s, v_id, v_type);
            if !v2_ok return 0, .UNKNOWN, false, v2_diag;
            out := new_id(s);
            add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "Normalize", id_text(v2)));
            return out, .FLOAT2, true, diag;
          }
          if v_type == .FLOAT3 {
            v3, v3_ok, v3_diag := coerce_to_float3(s, v_id, v_type);
            if !v3_ok return 0, .UNKNOWN, false, v3_diag;
            out := new_id(s);
            add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "Normalize", id_text(v3)));
            return out, .FLOAT3, true, diag;
          }
          if v_type == .FLOAT4 {
            v4, v4_ok, v4_diag := coerce_to_float4(s, v_id, v_type);
            if !v4_ok return 0, .UNKNOWN, false, v4_diag;
            out := new_id(s);
            add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "Normalize", id_text(v4)));
            return out, .FLOAT4, true, diag;
          }
          return_err("normalize requires float2/float3/float4, got %.", v_type);
        }
        builtin_id, builtin_type, builtin_ok, builtin_diag := emit_float_builtin_call(s, callee, expr.args);
        if !builtin_ok return 0, .UNKNOWN, false, builtin_diag;
        return builtin_id, builtin_type, true, diag;
      }
      helper := find_function(s, callee);
      if !helper return_err("unsupported call target '%'.", callee);
      helper_id, helper_type, helper_ok, helper_diag := eval_inline_function(s, helper, expr.args);
      return helper_id, helper_type, helper_ok, helper_diag;
    }

    case .CONSTRUCTOR; {
      ctor_type := expr_type_from_decl(expr.text);
      if ctor_type == .FLOAT2 {
        if expr.args.count != 2 return_err("float2 constructor expects 2 args, got %.", expr.args.count);
        a_id, a_type, a_ok, a_diag := emit_expr(s, expr.args[0]);
        if !a_ok return 0, .UNKNOWN, false, a_diag;
        b_id, b_type, b_ok, b_diag := emit_expr(s, expr.args[1]);
        if !b_ok return 0, .UNKNOWN, false, b_diag;
        af, af_ok, af_diag := coerce_to_float(s, a_id, a_type);
        if !af_ok return 0, .UNKNOWN, false, af_diag;
        bf, bf_ok, bf_diag := coerce_to_float(s, b_id, b_type);
        if !bf_ok return 0, .UNKNOWN, false, bf_diag;
        out := new_id(s);
        add_op(s, out, "OpCompositeConstruct", s.id_float2, af, bf);
        return out, .FLOAT2, true, diag;
      }
      if ctor_type == .FLOAT3 {
        if expr.args.count != 3 return_err("float3 constructor expects 3 args, got %.", expr.args.count);
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
        add_op(s, out, "OpCompositeConstruct", s.id_float3, f0, f1, f2);
        return out, .FLOAT3, true, diag;
      }
      if ctor_type == .FLOAT4 {
        if expr.args.count != 4 return_err("float4 constructor expects 4 args, got %.", expr.args.count);
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
        add_op(s, out, "OpCompositeConstruct", s.id_float4, f0, f1, f2, f3);
        return out, .FLOAT4, true, diag;
      }
      if ctor_type == .FLOAT2X2 {
        if expr.args.count != 4 return_err("float2x2 constructor expects 4 scalar args, got %.", expr.args.count);
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
        add_op(s, col0, "OpCompositeConstruct", s.id_float2, f0, f2);
        col1 := new_id(s);
        add_op(s, col1, "OpCompositeConstruct", s.id_float2, f1, f3);
        out := new_id(s);
        add_op(s, out, "OpCompositeConstruct", s.id_float2x2, col0, col1);
        return out, .FLOAT2X2, true, diag;
      }
      return_err("unsupported constructor type '%'.", expr.text);
    }
  }

  return_err("unsupported expression kind %.", expr.kind);
}

emit_lvalue_ptr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(msg, ..args); }

  assert(s != null);
  diag: IR_Diagnostic;
  if !expr return_err("null lvalue expression.");
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
      return_err("unsupported lvalue subscript base.");
    }
    buffer := find_buffer(s, buffer_name);
    if !buffer return_err("unknown lvalue subscript base '%'.", buffer_name);
    idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
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
      return ptr_id, ptr_type, ptr_ok, ptr_diag;
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .SUBSCRIPT {
      field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left.left, expr.left.text);
      if !field_ok return 0, .UNKNOWN, false, field_diag;
      if field_type != .FLOAT2 && field_type != .FLOAT3 && field_type != .FLOAT4 return_err("lvalue component access requires float2/float3/float4 field, got %.", field_type);
      comp_index: u32 = 0;
      if expr.text == "x" comp_index = 0;
      else if expr.text == "y" comp_index = 1;
      else if expr.text == "z" comp_index = 2;
      else if expr.text == "w" comp_index = 3;
      else return_err("unsupported vector component '%' for lvalue.", expr.text);
      if field_type == .FLOAT2 && comp_index > 1 return_err("vector component '%' out of range for float2 lvalue.", expr.text);
      if field_type == .FLOAT3 && comp_index > 2 return_err("vector component '%' out of range for float3 lvalue.", expr.text);
      comp_index_id := get_u32_const(s, comp_index);
      ptr := new_id(s);
      add_op(s, ptr, "OpAccessChain", s.id_ptr_storage_float, field_ptr, comp_index_id);
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
        else return_err("unsupported vector component '%' for lvalue.", expr.text);
        if local_vec.type == .FLOAT2 && comp_index > 1 return_err("vector component '%' out of range for float2 lvalue.", expr.text);
        if local_vec.type == .FLOAT3 && comp_index > 2 return_err("vector component '%' out of range for float3 lvalue.", expr.text);
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
        comp_index: u32 = 0;
        if      expr.text == "x" comp_index = 0;
        else if expr.text == "y" comp_index = 1;
        else if expr.text == "z" comp_index = 2;
        else if expr.text == "w" comp_index = 3;
        else return_err("unsupported vector component '%' for lvalue.", expr.text);
        if field.type == .FLOAT2 && comp_index > 1 return_err("vector component '%' out of range for float2 lvalue.", expr.text);
        if field.type == .FLOAT3 && comp_index > 2 return_err("vector component '%' out of range for float3 lvalue.", expr.text);
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
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, make_diag(msg, ..args); }
  
  assert(s != null);
  diag: IR_Diagnostic;
  if !stmt return_err("null statement.");
  
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
          add_op(s, "OpStore", ptr_id, init_id);
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
          return_err("unsupported local array element type '%'.", array_elem_type_name);
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
            return_err("local array '%' initializer must be an array literal.", stmt.decl_name);
          }
          if stmt.decl_init.args.count != array_count {
            return_err("local array '%' initializer count mismatch (expected %, got %).",
                       stmt.decl_name, array_count, stmt.decl_init.args.count);
          }
          elem_ptr_type_id := func_ptr_type_id_from_kind(s, elem_type);
          for stmt.decl_init.args {
            value_id, value_type, value_ok, value_diag := emit_expr(s, it);
            if !value_ok return false, false, value_diag;
            if value_type != elem_type {
              return_err("local array '%' initializer type mismatch at index %.", stmt.decl_name, it_index);
            }
            idx_const := get_u32_const(s, cast(u32) it_index);
            elem_ptr := new_id(s);
            add_op(s, elem_ptr, "OpAccessChain", elem_ptr_type_id, ptr_id, idx_const);
            add_op(s, "OpStore", elem_ptr, value_id);
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
        return_err("unsupported declaration type '%'.", stmt.decl_type_name);
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
            return_err("struct declaration '%': unsupported initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            src_field := find_local_struct_field(src_struct, it.name);
            if !src_field {
              return_err("missing struct field '%' on initializer '%'.", it.name, stmt.decl_init.text);
            }
            if dst_field.type == .STRUCT {
              if src_field.type != .STRUCT {
                return_err("nested struct field '%' type mismatch.", it.name);
              }
              dst_nested := find_local_struct(s, dst_field.nested_struct_name);
              src_nested := find_local_struct(s, src_field.nested_struct_name);
              if !dst_nested || !src_nested {
                return_err("nested struct field '%' could not be resolved.", it.name);
              }
              copy_ok, copy_diag := copy_local_struct_fields(s, dst_nested, src_nested);
              if !copy_ok return false, false, copy_diag;
              continue;
            }
            src_value := new_id(s);
            src_type_id := type_id_from_kind(s, src_field.type);
            if src_type_id == 0 {
              return_err("unsupported struct field type while copying '%'.", it.name);
            }
            add_op(s, src_value, "OpLoad", src_type_id, src_field.ptr_id);
            add_op(s, "OpStore", dst_field.ptr_id, src_value);
          }
        } else if stmt.decl_init.kind == .SUBSCRIPT {
          buffer_name: string;
          base_ok := false;
          resolved_name, resolved_ok := resolve_ident_or_zero_deref(stmt.decl_init.left);
          if resolved_ok {
            buffer_name = resolved_name;
            base_ok = true;
          } else if stmt.decl_init.left && stmt.decl_init.left.kind == .MEMBER {
            member_root, member_field, member_ok := resolve_member_root_and_field(stmt.decl_init.left);
            if member_ok {
              buffer_name = tprint("%.%", member_root, member_field);
              base_ok = true;
            }
          }
          if !base_ok {
            return_err("struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          buffer := find_buffer(s, buffer_name);
          if !buffer || buffer.element_kind != .STRUCT || buffer.element_type_name != struct_type_name {
            return_err("struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            if dst_field.type == .STRUCT {
              return_err("struct declaration '%': nested struct buffer initializers are unsupported for field '%'.", stmt.decl_name, it.name);
            }
            src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, stmt.decl_init, it.name);
            if !src_ok return false, false, src_diag;
            if src_type != dst_field.type {
              return_err("struct declaration '%': field '%' type mismatch in buffer initializer.", stmt.decl_name, it.name);
            }
            src_value := new_id(s);
            src_type_id := type_id_from_kind(s, src_type);
            emit_load(s, src_value, src_type_id, src_ptr, src_type, needs_physical_align=true);
            add_op(s, "OpStore", dst_field.ptr_id, src_value);
          }
        } else if stmt.decl_init.kind == .CALL && stmt.decl_init.left && stmt.decl_init.left.kind == .IDENT {
          helper := find_function(s, stmt.decl_init.left.text);
          helper_return_struct_name := "";
          if helper {
            helper_return_struct_name = helper.return_type.struct_name;
            if helper_return_struct_name.count == 0 helper_return_struct_name = helper.return_type_name;
          }
          if !helper || helper_return_struct_name != struct_type_name {
            return_err("struct declaration '%': unsupported call initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          call_ok, call_diag := eval_inline_function_to_struct(s, helper, stmt.decl_init.args, local_struct);
          if !call_ok return false, false, call_diag;
        } else {
          return_err("struct declaration '%': unsupported initializer expression kind %.", stmt.decl_name, stmt.decl_init.kind);
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
              return_err("assignment source '%' is not a local struct.", stmt.binary_right.text);
            }
            if src_struct.type_name != dst_buffer.element_type_name {
              return_err("struct buffer assignment type mismatch ('%' vs '%').",
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
              return_err("struct buffer assignment call '%' has incompatible return type.", expr_text(stmt.binary_right));
            }
            tmp_name := tprint("__assign_src_%", new_id(s));
            tmp_struct, tmp_ok, tmp_diag := alloc_local_struct(s, tmp_name, helper_return_struct_name);
            if !tmp_ok return false, false, tmp_diag;
            call_ok, call_diag := eval_inline_function_to_struct(s, helper, stmt.binary_right.args, tmp_struct);
            if !call_ok return false, false, call_diag;
            src_struct = find_local_struct(s, tmp_name);
            if !src_struct {
              return_err("inline helper assignment source struct '%' went missing.", tmp_name);
            }
          } else {
            return_err("unsupported struct buffer assignment rhs '%'.", expr_text(stmt.binary_right));
          }

          for dst_buffer.fields {
            dst_ptr, dst_type, dst_ok, dst_diag := emit_buffer_struct_field_ptr(s, stmt.binary_left, it.name);
            if !dst_ok return false, false, dst_diag;
            if dst_type != it.type {
              return_err("struct buffer field '%' type mismatch on destination.", it.name);
            }
            src_field := find_local_struct_field(src_struct, it.name);
            if !src_field {
              return_err("struct assignment source missing field '%'.", it.name);
            }
            if src_field.type != it.type {
              return_err("struct assignment field '%' type mismatch.", it.name);
            }
            value_id := add_op(s, new_id(s), "OpLoad", type_id_from_kind(s, it.type), src_field.ptr_id);
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
        if base_op.count == 0 return_err("unsupported float compound assignment op '%'.", op);

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
            return_err("float2 compound assignment rhs must be float or float2.");
          }
          result_id, result_type, result_ok, result_diag = emit_float2_binary_op(s, base_op, lhs_vec, rhs_vec);
        } else if lhs_type == .FLOAT3 {
          lhs_vec := lhs_value;
          rhs_vec := rhs_id;
          if rhs_type == .FLOAT rhs_vec = splat_float3(s, rhs_id);
          if rhs_type == .FLOAT3 {
            // keep
          } else if rhs_type != .FLOAT {
            return_err("float3 compound assignment rhs must be float or float3.");
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
            return_err("float4 compound assignment rhs must be float or float4.");
          }
          result_id, result_type, result_ok, result_diag = emit_float4_binary_op(s, base_op, lhs_vec, rhs_vec);
        }
        if !result_ok return false, false, result_diag;
        if result_type != lhs_type return_err("float compound assignment produced wrong type.");
        emit_store(s, ptr_id, result_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
        return true, false, diag;
      }

      if !is_integral_kind(lhs_type) return_err("non-integer compound assignment is not supported yet.");

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
        return_err("unsupported statement binary op '%'.", stmt.binary_op);
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
        return_err("compound assignment operator must produce matching integer type.");
      }

      emit_store(s, ptr_id, result_id, lhs_type, needs_physical_align=lhs_is_storage_buffer);
      return true, false, diag;
    }

    case .IF; {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.if_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .BOOL return_err("if condition must be bool.");

      then_label := new_id(s);
      merge_label := new_id(s);
      else_label := merge_label;
      if stmt.if_else else_label = new_id(s);

      add_op(s, tprint("OpSelectionMerge % None", id_text(merge_label)));
      add_op(s, "OpBranchConditional", cond_id, then_label, else_label);

      add_op(s, then_label, "OpLabel");
      then_ok, then_terminated, then_diag := emit_stmt_block(s, stmt.if_then);
      if !then_ok return false, false, then_diag;
      if !then_terminated {
        add_op(s, "OpBranch", merge_label);
      }

      else_terminated := false;
      if stmt.if_else {
        add_op(s, else_label, "OpLabel");
        else_ok, local_else_terminated, else_diag := emit_stmt_block(s, stmt.if_else);
        else_terminated = local_else_terminated;
        if !else_ok return false, false, else_diag;
        if !else_terminated {
          add_op(s, "OpBranch", merge_label);
        }
      }

      add_op(s, merge_label, "OpLabel");
      all_terminated := false;
      if stmt.if_else {
        all_terminated = then_terminated && else_terminated;
      }
      return true, all_terminated, diag;
    }

    case .SWITCH; {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.switch_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .UINT return_err("switch condition must be uint.");

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
      a(*switch_line_sb, "               OpSwitch % %", id_text(cond_id), id_text(default_label));
      for stmt.switch_cases {
        if !it.condition continue;
        value, value_ok := parse_u32_literal_expr(it.condition);
        if !value_ok return_err("switch case values must be uint literals.");
        a(*switch_line_sb, " % %", value, id_text(case_labels[it_index]));
      }
      add_op(s, builder_to_string(*switch_line_sb));

      array_add(*s.break_targets, merge_label);
      for stmt.switch_cases {
        case_block := it.body;
        if !case_block {
          if s.break_targets.count > 0 s.break_targets.count -= 1;
          return_err("switch case body is missing.");
        }
        add_op(s, case_labels[it_index], "OpLabel");
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
          add_op(s, "OpBranch", target_label);
        }
      }
      if s.break_targets.count > 0 s.break_targets.count -= 1;

      add_op(s, merge_label, "OpLabel");
      return true, false, diag;
    }

    case .FOR; {
      if !stmt.for_body return_err("for-loop body is missing.");

      loop_name := stmt.for_loop_name;
      if loop_name.count == 0 loop_name = "__for_it";

      local_count_before := s.locals.count;

      start_id, start_type, start_ok, start_diag := emit_expr(s, stmt.for_start);
      if !start_ok return false, false, start_diag;
      if !is_integral_kind(start_type) return_err("for-loop start expression must be integer.");

      loop_ptr := new_id(s);
      loop_ptr_type_id := func_ptr_type_id_from_kind(s, start_type);
      if loop_ptr_type_id == 0 return_err("for-loop start type is unsupported (%).", start_type);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                                          id_text(loop_ptr),
                                          id_text(loop_ptr_type_id)));
      add_debug_name(s, loop_ptr, loop_name);
      array_add(*s.locals, .{name=loop_name, ptr_id=loop_ptr, type=start_type});
      add_op(s, "OpStore", loop_ptr, start_id);

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, "OpBranch", header_label);
      add_op(s, header_label, "OpLabel");

      it_value := new_id(s);
      start_type_id := type_id_from_kind(s, start_type);
      add_op(s, it_value, "OpLoad", start_type_id, loop_ptr);
      end_id, end_type, end_ok, end_diag := emit_expr(s, stmt.for_end);
      if !end_ok return false, false, end_diag;
      end_id, end_ok, end_diag = coerce_to_kind(s, end_id, end_type, start_type);
      if !end_ok return false, false, end_diag;
      cmp_id, cmp_type, cmp_ok, cmp_diag := emit_int_binary_op(s, stmt.for_cmp, start_type, it_value, end_id);
      if !cmp_ok return false, false, cmp_diag;
      if cmp_type != .BOOL return_err("for-loop comparison '%' must produce bool.", stmt.for_cmp);
      add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
      add_op(s, "OpBranchConditional", cmp_id, body_label, merge_label);

      add_op(s, body_label, "OpLabel");
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.for_body);
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, "OpBranch", continue_label);
      }

      add_op(s, continue_label, "OpLabel");
      compact_step := compact_text(stmt.for_step);
      step_op: string;
      if compact_step == "+=1" {
        step_op = "+";
      } else if compact_step == "-=1" {
        step_op = "-";
      } else {
        return_err("unsupported for-loop step '%'.", stmt.for_step);
      }
      step_id: s64;
      if      start_type == .INT step_id    = get_i32_const(s, 1);
      else if start_type == .UINT step_id   = get_u32_const(s, 1);
      else if start_type == .INT64 step_id  = get_i64_const(s, 1);
      else if start_type == .UINT64 step_id = get_u64_const(s, 1);
      else return_err("unsupported for-loop induction type %.", start_type);
      it_current := new_id(s);
      add_op(s, it_current, "OpLoad", start_type_id, loop_ptr);
      next_it, next_type, next_ok, next_diag := emit_int_binary_op(s, step_op, start_type, it_current, step_id);
      if !next_ok return false, false, next_diag;
      if next_type != start_type return_err("for-loop step must preserve induction type.");
      add_op(s, "OpStore", loop_ptr, next_it);
      add_op(s, "OpBranch", header_label);

      add_op(s, merge_label, "OpLabel");
      s.locals.count = local_count_before;
      return true, false, diag;
    }

    case .WHILE; {
      if !stmt.while_body return_err("while-loop body is missing.");

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, "OpBranch", header_label);
      add_op(s, header_label, "OpLabel");

      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.while_condition);
      if !cond_ok return false, false, cond_diag;
      if cond_type != .BOOL return_err("while condition must be bool.");
      add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
      add_op(s, "OpBranchConditional", cond_id, body_label, merge_label);

      add_op(s, body_label, "OpLabel");
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.while_body);
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, "OpBranch", continue_label);
      }

      add_op(s, continue_label, "OpLabel");
      add_op(s, "OpBranch", header_label);

      add_op(s, merge_label, "OpLabel");
      return true, false, diag;
    }

    case .BREAK; {
      break_target, found := get_current_break_target(s);
      if !found return_err("break used outside loop.");
      add_op(s, "OpBranch", break_target);
      return true, true, diag;
    }

    case .CONTINUE; {
      loop_target, found := get_current_loop_target(s);
      if !found return_err("continue used outside loop.");
      add_op(s, "OpBranch", loop_target.continue_label);
      return true, true, diag;
    }

    case .RETURN; {
      if s.stage == .COMPUTE {
        if stmt.return_expr {
          return_err("return with value is not supported yet for compute.");
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
      if stmt.return_expr.kind == .IDENT {
        out_struct := find_local_struct(s, stmt.return_expr.text);
        if out_struct {
          ret_ok, ret_diag := emit_output_return_from_struct(s, out_struct);
          if !ret_ok return false, false, ret_diag;
          return true, true, diag;
        }
      }

      if s.output_vars.count != 1 {
        return_err("non-struct graphics return values require exactly one output.");
      }
      output_var := s.output_vars[0];
      raw_id, raw_type, raw_ok, raw_diag := emit_expr(s, stmt.return_expr);
      if !raw_ok return false, false, raw_diag;
      coerced_id, coerced_type, coerced_ok, coerced_diag := coerce_to_exact_kind(s, raw_id, raw_type, output_var.type);
      if !coerced_ok {
        if coerced_diag.message.count == 0 {
          coerced_diag.message = "could not coerce return expression to fragment output type.";
        }
        return false, false, coerced_diag;
      }
      if coerced_type != output_var.type {
        return_err("return expression type does not match output type.");
      }
      add_op(s, "OpStore", output_var.var_id, coerced_id);
      add_op(s, "               OpReturn");
      return true, true, diag;
    }
  }

  return_err("unsupported statement kind %.", stmt.kind);
}

emit_stmt_block :: (using s: *IR_SPV_Gen_State, block: *IR_Block) -> (ok: bool, terminated: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, make_diag(msg, ..args); }

  assert(s != null);
  if !block return_err("null statement block.");
  local_count_before := s.locals.count;
  local_array_count_before := s.local_arrays.count;
  local_struct_count_before := s.local_structs.count;
  defer {
    locals.count = local_count_before;
    local_arrays.count = local_array_count_before;
    local_structs.count = local_struct_count_before;
  }
  for block.statements {
    ok, terminated, step_diag := emit_stmt(s, *it);
    if !ok return false, false, step_diag;
    if terminated return true, true, {};
  }
  return true, false, {};
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
      a(sb, "               OpDecorate % BuiltIn Position", id_text(it.var_id));
      continue;
    }
    if it.builtin == .FRAG_COORD {
      a(sb, "               OpDecorate % BuiltIn FragCoord", id_text(it.var_id));
      continue;
    }
    if it.builtin == .VERTEX_INDEX {
      a(sb, "               OpDecorate % BuiltIn VertexIndex", id_text(it.var_id));
      continue;
    }
    if it.builtin == .INSTANCE_INDEX {
      a(sb, "               OpDecorate % BuiltIn InstanceIndex", id_text(it.var_id));
      continue;
    }
    a(sb, "               OpDecorate % Location %", id_text(it.var_id), location);
    location += 1;
  }
}

emit_output_return_from_struct :: (s: *IR_SPV_Gen_State, local_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  if !local_struct return false, make_diag("missing local output struct for return.");
  for s.output_vars {
    src := find_local_struct_field(local_struct, it.name);
    if !src return false, make_diag("output struct is missing field '%'.", it.name);
    
    if src.type != it.type  return false, make_diag("output field '%' type mismatch.", it.name);
    
    value_id := new_id(s);
    type_id  := type_id_from_kind(s, it.type);
    add_op(s, value_id, "OpLoad", type_id, src.ptr_id);
    add_op(s, "OpStore", it.var_id, value_id);
  }
  add_op(s, "               OpReturn");
  return true, {};
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

spv_append_base_buffer_decorations :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  append(sb, tprint("               OpDecorate % ArrayStride 4\n", id_text(s.id_runtimearr_uint)));
  append(sb, tprint("               OpDecorate % Block\n", id_text(s.id_buffer_struct)));
  append(sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(s.id_buffer_struct)));
}

spv_append_buffer_layout_decorations :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  for s.buffers {
    buffer := it;
    if buffer.element_kind == .UINT && buffer.wrapper_struct_type_id == s.id_buffer_struct continue;
    a(sb, "               OpDecorate % ArrayStride %", id_text(buffer.runtimearr_type_id), buffer.array_stride);
    if buffer.element_kind == .STRUCT {
      for buffer.fields {
        a(sb, "               OpMemberDecorate % % Offset %", id_text(buffer.element_type_id), it.index, it.offset);
      }
    }
    a(sb, "               OpDecorate % Block", id_text(buffer.wrapper_struct_type_id));
    a(sb, "               OpMemberDecorate % 0 Offset 0", id_text(buffer.wrapper_struct_type_id));
    if buffer.is_readonly a(sb, "               OpMemberDecorate % 0 NonWritable", id_text(buffer.wrapper_struct_type_id));
  }
}

spv_append_buffer_binding_decorations :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  for s.buffers {
    a(sb, "               OpDecorate % Binding %", id_text(it.var_id), it.binding_index);
    a(sb, "               OpDecorate % DescriptorSet 0", id_text(it.var_id));
  }
}

spv_append_buffer_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State, storage_class: string) {
  for s.buffers {
    buffer := it;
    if buffer.element_kind == .UINT && buffer.wrapper_struct_type_id == s.id_buffer_struct continue;
    if buffer.element_kind == .STRUCT {
      struct_type_line_sb: String_Builder;
      append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
      for buffer.fields append(*struct_type_line_sb, " ", id_text(type_id_from_kind(s, it.type)));
      append(*struct_type_line_sb, "\n");
      append(sb, builder_to_string(*struct_type_line_sb));
    }
    spv_append_buffer_array_type(sb, buffer);
    a(sb, "% = OpTypeStruct %", id_text(buffer.wrapper_struct_type_id), id_text(buffer.runtimearr_type_id));
    a(sb, "% = OpTypePointer % %", id_text(buffer.ptr_wrapper_type_id), storage_class, id_text(buffer.wrapper_struct_type_id));
    a(sb, "% = OpTypePointer % %", id_text(buffer.ptr_storage_element_type_id), storage_class, id_text(buffer.element_type_id));
  }
}

spv_append_buffer_vars :: (sb: *String_Builder, s: *IR_SPV_Gen_State, storage_class: string) {
  for s.buffers a(sb, "% = OpVariable % %", id_text(it.var_id), id_text(it.ptr_wrapper_type_id), storage_class);
}

spv_append_var_ids :: (sb: *String_Builder, items: [] $T) #expand {
  for items append(sb, " ", id_text(it.var_id));
}

spv_append_local_array_type_decls :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  for s.local_array_types {
    a(sb, "% = OpTypeArray % %",
      id_text(it.array_type_id),
      id_text(type_id_from_kind(s, it.element_type)),
      id_text(it.count_const_id));
    a(sb, "% = OpTypePointer Function %",
      id_text(it.ptr_func_array_type_id),
      id_text(it.array_type_id));
  }
}

parse_parameter_block_struct_name :: (type_name: string) -> (string, bool) {
  prefix :: "ParameterBlock<";
  if !begins_with(type_name, prefix) return "", false;
  if type_name.count < prefix.count + 1 return "", false;
  if type_name[type_name.count-1] != #char ">" return "", false;
  out: string = { type_name.count - prefix.count - 1, type_name.data + prefix.count };
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
    using it;
    if !is_pointer continue;
    if !pointer_pointee_is_struct continue;
    if pointer_pointee_type_name.count == 0 continue;
    if !struct_has_pointer_fields_recursive(s.extra_structs, pointer_pointee_type_name, depth + 1) continue;
    next_prefix := tprint("%.%", prefix, name);
    if !ps_assign_struct_info(s, infos, pointer_pointee_type_name, next_prefix, depth + 1) return false;
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

#load "spirv_text_backend_emitters.jai";
#load "../string_builder_util.jai";
