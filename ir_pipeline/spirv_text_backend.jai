//
// Jai IR -> SPIR-V text
// 

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
  diag.message = tprint("SPIR-V text backend: graphics pair emission is not implemented yet ('%' + '%').",
                       vertex.source_name, fragment.source_name);
  return "", "", false, diag;
}

#scope_file
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
  UINT;
  FLOAT;
  FLOAT2;
  FLOAT2X2;
  BOOL;
}

IR_SPV_Gen_Local :: struct {
  name: string;
  ptr_id: s64;
  type: IR_SPV_Gen_Type;
}

IR_SPV_Gen_Local_Struct_Field :: struct {
  name: string;
  ptr_id: s64;
  type: IR_SPV_Gen_Type;
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

IR_SPV_Gen_Const_U32 :: struct {
  value: u32;
  id: s64;
}

IR_SPV_Gen_Const_I32 :: struct {
  value: s32;
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

IR_SPV_Gen_State :: struct {
  next_id: s64;
  locals: [..] IR_SPV_Gen_Local;
  local_structs: [..] IR_SPV_Gen_Local_Struct;
  const_u32: [..] IR_SPV_Gen_Const_U32;
  const_i32: [..] IR_SPV_Gen_Const_I32;
  const_f32: [..] IR_SPV_Gen_Const_F32;
  buffers: [..] IR_SPV_Gen_Buffer;
  loop_targets: [..] IR_SPV_Gen_Loop_Target;
  break_targets: [..] s64;
  helpers: [] IR_Helper_Function;
  extra_structs: [] IR_Struct;
  local_var_lines: [..] string;
  op_lines: [..] string;

  id_extinst: s64;
  id_void: s64;
  id_fn_void: s64;
  id_uint: s64;
  id_float: s64;
  id_float2: s64;
  id_float2x2: s64;
  id_bool: s64;
  id_bool_true: s64;
  id_bool_false: s64;
  id_v3uint: s64;
  id_ptr_input_v3uint: s64;
  id_gl_global_invocation_id: s64;
  id_ptr_input_uint: s64;
  id_int: s64;
  id_int_0: s64;
  id_uint_0: s64;
  id_runtimearr_uint: s64;
  id_buffer_struct: s64;
  id_ptr_storage_buffer_struct: s64;
  id_ptr_storage_uint: s64;
  id_ptr_storage_float: s64;
  id_ptr_storage_float2: s64;
  id_ptr_func_float: s64;
  id_ptr_func_float2: s64;
  id_ptr_func_float2x2: s64;
  id_ptr_func_bool: s64;
  id_ptr_func_uint: s64;
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

find_by_name :: (arr: *[]$T, name: string) -> *T {
  assert(arr != null);
  for * arr.* if it.name == name return it;
  return null;
}

find_local  :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Local  { return find_by_name(*s.locals, name); }
find_buffer :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Buffer { return find_by_name(*s.buffers, name); }
find_helper :: (s: *IR_SPV_Gen_State, name: string) -> *IR_Helper_Function { return find_by_name(*s.helpers, name); }
find_struct :: (s: *IR_SPV_Gen_State, name: string) -> *IR_Struct { return find_by_name(*s.extra_structs, name); }
find_local_struct :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Local_Struct { return find_by_name(*s.local_structs, name); }
find_local_struct_field :: (s: *IR_SPV_Gen_Local_Struct, name: string) -> *IR_SPV_Gen_Local_Struct_Field { return find_by_name(*s.fields, name); }

is_uint_type_name :: (name: string) -> bool {
  return name == "uint" || name == "u32";
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

init_base :: (s: *IR_SPV_Gen_State, buffers: [] IR_Compute_Buffer, bound_value: u32) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, { message = sprint(msg, ..args) }; }

  diag: IR_Diagnostic;
  assert(s != null);
  assert(buffers.count > 0);
  s.next_id = 1;
  s.bound_value = bound_value;

  s.id_extinst = new_id(s);
  s.id_void = new_id(s);
  s.id_fn_void = new_id(s);
  s.id_uint = new_id(s);
  s.id_float = new_id(s);
  s.id_float2 = new_id(s);
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
  s.id_int_0 = get_i32_const(s, 0);
  s.id_ptr_storage_uint = new_id(s);
  s.id_ptr_storage_float = new_id(s);
  s.id_ptr_storage_float2 = new_id(s);
  s.id_ptr_func_float = new_id(s);
  s.id_ptr_func_float2 = new_id(s);
  s.id_ptr_func_float2x2 = new_id(s);
  s.id_ptr_func_bool = new_id(s);
  s.id_ptr_func_uint = new_id(s);
  s.id_main = new_id(s);

  for buffers {
    var_id := new_id(s);
    buffer_info: IR_SPV_Gen_Buffer;
    buffer_info.name = it.name;
    buffer_info.var_id = var_id;
    buffer_info.binding_index = it_index;
    buffer_info.element_type_name = it.element_type_name;
    if is_uint_type_name(it.element_type_name) {
      buffer_info.element_kind = .UINT;
      buffer_info.element_type_id = s.id_uint;
      buffer_info.runtimearr_type_id = s.id_runtimearr_uint;
      buffer_info.wrapper_struct_type_id = s.id_buffer_struct;
      buffer_info.ptr_wrapper_type_id = s.id_ptr_storage_buffer_struct;
      buffer_info.ptr_storage_element_type_id = s.id_ptr_storage_uint;
      buffer_info.array_stride = 4;
      array_add(*s.buffers, buffer_info);
      continue;
    }

    struct_def := find_struct(s, it.element_type_name);
    if !struct_def {
      return_err("SPIR-V generic backend: buffer '%' has unsupported element type '%'.", it.name, it.element_type_name);
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
      field_type := expr_type_from_decl(it.type_name);
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
      offset += field_size;
    }
    buffer_info.array_stride = offset;
    array_add(*s.buffers, buffer_info);
  }

  return true, diag;
}

load_thread_x :: (s: *IR_SPV_Gen_State) -> s64 {
  assert(s != null);
  thread_id_ptr := new_id(s);
  add_op(s, tprint("         % = OpAccessChain % % %",
                              id_text(thread_id_ptr),
                              id_text(s.id_ptr_input_uint),
                              id_text(s.id_gl_global_invocation_id),
                              id_text(s.id_uint_0)));
  thread_id := new_id(s);
  add_op(s, tprint("         % = OpLoad % %",
                              id_text(thread_id),
                              id_text(s.id_uint),
                              id_text(thread_id_ptr)));
  return thread_id;
}

expr_type_from_decl :: (name: string) -> IR_SPV_Gen_Type {
  if name == "uint" return .UINT;
  if name == "u32" return .UINT;
  if name == "float" return .FLOAT;
  if name == "float2" return .FLOAT2;
  if name == "float2x2" return .FLOAT2X2;
  if name == "Vector2" return .FLOAT2;
  if name == "Matrix2" return .FLOAT2X2;
  if name == "bool" return .BOOL;
  return .UNKNOWN;
}

type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  assert(s != null);
  if kind == .UINT return s.id_uint;
  if kind == .FLOAT return s.id_float;
  if kind == .FLOAT2 return s.id_float2;
  if kind == .FLOAT2X2 return s.id_float2x2;
  if kind == .BOOL return s.id_bool;
  return 0;
}

storage_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  assert(s != null);
  if kind == .UINT return s.id_ptr_storage_uint;
  if kind == .FLOAT return s.id_ptr_storage_float;
  if kind == .FLOAT2 return s.id_ptr_storage_float2;
  return 0;
}

func_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  assert(s != null);
  if kind == .UINT return s.id_ptr_func_uint;
  if kind == .FLOAT return s.id_ptr_func_float;
  if kind == .FLOAT2 return s.id_ptr_func_float2;
  if kind == .FLOAT2X2 return s.id_ptr_func_float2x2;
  if kind == .BOOL return s.id_ptr_func_bool;
  return 0;
}

byte_size_of_kind :: (kind: IR_SPV_Gen_Type) -> s64 {
  if kind == .UINT return 4;
  if kind == .FLOAT return 4;
  if kind == .FLOAT2 return 8;
  return 0;
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
    field_type := expr_type_from_decl(it.type_name);
    if field_type == .UNKNOWN || field_type == .STRUCT {
      diag.message = tprint("SPIR-V backend: local struct '%' field '%' has unsupported type '%'.", type_name, it.name, it.type_name);
      return null, false, diag;
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

emit_buffer_struct_field_ptr :: (s: *IR_SPV_Gen_State, subscript: *IR_Expr, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, { message = sprint(message, ..args) }; }
  
  assert(s != null);
  diag: IR_Diagnostic;
  if !subscript || subscript.kind != .SUBSCRIPT       return_err("SPIR-V backend: expected subscript expression for buffer struct field access.");
  if !subscript.left || subscript.left.kind != .IDENT return_err("SPIR-V backend: subscript base must be an identifier.");
  
  buffer := find_buffer(s, subscript.left.text);
  if !buffer return_err("SPIR-V backend: unknown subscript base '%'.", subscript.left.text);
  
  if buffer.element_kind != .STRUCT return_err("SPIR-V backend: buffer '%' is not a struct buffer.", buffer.name);
  field := find_buffer_field(buffer, field_name);
  if !field {
    diag.message = tprint("SPIR-V backend: unknown field '%.%'.", buffer.name, field_name);
    return 0, .UNKNOWN, false, diag;
  }

  idx_id, idx_type, idx_ok, idx_diag := emit_expr(s, subscript.right);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;
  if idx_type != .UINT {
    return_err("SPIR-V backend: subscript index must be uint.");
  }

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

emit_uint_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  result_id := new_id(s);
  if op == "+" { add_op(s, tprint("         % = OpIAdd % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "-" { add_op(s, tprint("         % = OpISub % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "*" { add_op(s, tprint("         % = OpIMul % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "%" { add_op(s, tprint("         % = OpUMod % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "|" { add_op(s, tprint("         % = OpBitwiseOr % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "&" { add_op(s, tprint("         % = OpBitwiseAnd % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "^" { add_op(s, tprint("         % = OpBitwiseXor % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "<<" { add_op(s, tprint("         % = OpShiftLeftLogical % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == ">>" { add_op(s, tprint("         % = OpShiftRightLogical % % %", id_text(result_id), id_text(s.id_uint), id_text(left_id), id_text(right_id))); return result_id, .UINT, true, diag; }
  if op == "<"  { add_op(s, tprint("         % = OpULessThan % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == ">"  { add_op(s, tprint("         % = OpUGreaterThan % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == "<=" { add_op(s, tprint("         % = OpULessThanEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == ">=" { add_op(s, tprint("         % = OpUGreaterThanEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == "==" { add_op(s, tprint("         % = OpIEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  if op == "!=" { add_op(s, tprint("         % = OpINotEqual % % %", id_text(result_id), id_text(s.id_bool), id_text(left_id), id_text(right_id))); return result_id, .BOOL, true, diag; }
  diag.message = tprint("SPIR-V backend: unsupported uint binary op '%'.", op);
  return 0, .UNKNOWN, false, diag;
}

coerce_to_float :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float_id: s64, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if value_type == .FLOAT return value_id, true, diag;
  if value_type == .UINT {
    converted := new_id(s);
    add_op(s, tprint("         % = OpConvertUToF % %",
                     id_text(converted),
                     id_text(s.id_float),
                     id_text(value_id)));
    return converted, true, diag;
  }
  diag.message = "SPIR-V backend: cannot coerce value to float.";
  return 0, false, diag;
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
  vf, vf_ok, vf_diag := coerce_to_float(s, value_id, value_type);
  if !vf_ok return 0, .UNKNOWN, false, vf_diag;

  op_name: string;
  if builtin_name == "floor" op_name = "Floor";
  else if builtin_name == "abs" op_name = "FAbs";
  else if builtin_name == "sqrt" op_name = "Sqrt";
  else if builtin_name == "sin" op_name = "Sin";
  else if builtin_name == "cos" op_name = "Cos";
  else {
    diag.message = tprint("SPIR-V backend: unsupported float builtin '%'.", builtin_name);
    return 0, .UNKNOWN, false, diag;
  }

  result := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % % %",
                   id_text(result), id_text(s.id_float), id_text(s.id_extinst), op_name, id_text(vf)));
  return result, .FLOAT, true, diag;
}

eval_inline_helper :: (s: *IR_SPV_Gen_State, helper: *IR_Helper_Function, call_args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  assert(s != null);
  diag: IR_Diagnostic;
  if !helper {
    diag.message = "SPIR-V backend: missing helper metadata for inline call.";
    return 0, .UNKNOWN, false, diag;
  }
  if !is_uint_type_name(helper.return_type_name) {
    diag.message = tprint("SPIR-V backend: helper '%' has unsupported return type '%'.", helper.name, helper.return_type_name);
    return 0, .UNKNOWN, false, diag;
  }
  if helper.args.count != call_args.count {
    diag.message = tprint("SPIR-V backend: helper '%' expected % args but got %.", helper.name, helper.args.count, call_args.count);
    return 0, .UNKNOWN, false, diag;
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;
  for helper.args {
    if is_uint_type_name(it.type_name) {
      arg_value, arg_type, arg_ok, arg_diag := emit_expr(s, call_args[it_index]);
      if !arg_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return 0, .UNKNOWN, false, arg_diag;
      }
      if arg_type != .UINT {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' arg '%' must lower to uint.", helper.name, it.name);
        return 0, .UNKNOWN, false, diag;
      }
      arg_ptr := new_id(s);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                               id_text(arg_ptr),
                               id_text(s.id_ptr_func_uint)));
      add_op(s, tprint("               OpStore % %", id_text(arg_ptr), id_text(arg_value)));
      array_add(*s.locals, .{name=it.name, ptr_id=arg_ptr, type=.UINT});
      continue;
    }

    arg_struct_def := find_struct(s, it.type_name);
    if !arg_struct_def {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' arg '%' has unsupported type '%'.", helper.name, it.name, it.type_name);
      return 0, .UNKNOWN, false, diag;
    }

    struct_arg := call_args[it_index];
    arg_local_struct: IR_SPV_Gen_Local_Struct;
    arg_local_struct.name = it.name;
    arg_local_struct.type_name = it.type_name;

    if struct_arg && struct_arg.kind == .IDENT {
      source_struct := find_local_struct(s, struct_arg.text);
      if !source_struct {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' struct arg '%' expects local struct value '%'.", helper.name, it.name, struct_arg.text);
        return 0, .UNKNOWN, false, diag;
      }
      if source_struct.type_name != it.type_name {
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

    if !struct_arg || struct_arg.kind != .CONSTRUCTOR || struct_arg.text != it.type_name {
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
      if !is_uint_type_name(it.type_name) {
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
      add_op(s, tprint("               OpStore % %", id_text(field_ptr), id_text(field_value)));
      array_add(*arg_local_struct.fields, .{name=it.name, ptr_id=field_ptr, type=.UINT});
    }
    array_add(*s.local_structs, arg_local_struct);
  }

  return_id: s64 = 0;
  return_type := IR_SPV_Gen_Type.UNKNOWN;
  got_return := false;
  for *helper.body.statements {
    stmt := it;
    if stmt.kind == .RETURN {
      if !stmt.return_expr {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' must return a value.", helper.name);
        return 0, .UNKNOWN, false, diag;
      }
      value_id, value_type, value_ok, value_diag := emit_expr(s, stmt.return_expr);
      if !value_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return 0, .UNKNOWN, false, value_diag;
      }
      return_id = value_id;
      return_type = value_type;
      got_return = true;
      break;
    }
    stmt_ok, stmt_terminated, stmt_diag := emit_stmt(s, stmt);
    if !stmt_ok {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      return 0, .UNKNOWN, false, stmt_diag;
    }
    if stmt_terminated {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' has unsupported early control-flow termination.", helper.name);
      return 0, .UNKNOWN, false, diag;
    }
  }

  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  if !got_return {
    diag.message = tprint("SPIR-V backend: helper '%' has no return statement.", helper.name);
    return 0, .UNKNOWN, false, diag;
  }
  if return_type != .UINT {
    diag.message = tprint("SPIR-V backend: helper '%' return expression must lower to uint.", helper.name);
    return 0, .UNKNOWN, false, diag;
  }
  return return_id, return_type, true, diag;
}

eval_inline_helper_to_struct :: (s: *IR_SPV_Gen_State, helper: *IR_Helper_Function, call_args: [] *IR_Expr, out_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
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
  if helper.return_type_name != out_struct_type {
    diag.message = tprint("SPIR-V backend: helper '%' return type '%' does not match destination struct '%'.", helper.name, helper.return_type_name, out_struct_type);
    return false, diag;
  }
  if helper.args.count != call_args.count {
    diag.message = tprint("SPIR-V backend: helper '%' expected % args but got %.", helper.name, helper.args.count, call_args.count);
    return false, diag;
  }

  local_count_before := s.locals.count;
  local_struct_count_before := s.local_structs.count;

  for helper.args {
    arg_type := expr_type_from_decl(it.type_name);
    if arg_type != .UNKNOWN && arg_type != .STRUCT {
      arg_value, value_type, value_ok, value_diag := emit_expr(s, call_args[it_index]);
      if !value_ok {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        return false, value_diag;
      }

      final_value := arg_value;
      final_type := value_type;
      if arg_type == .FLOAT && value_type != .FLOAT {
        coerced, coerced_ok, coerced_diag := coerce_to_float(s, arg_value, value_type);
        if !coerced_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, coerced_diag;
        }
        final_value = coerced;
        final_type = .FLOAT;
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
      add_op(s, tprint("               OpStore % %", id_text(arg_ptr), id_text(final_value)));
      array_add(*s.locals, .{name=it.name, ptr_id=arg_ptr, type=arg_type});
      continue;
    }

    arg_struct, arg_struct_ok, arg_struct_diag := alloc_local_struct(s, it.name, it.type_name);
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
      if src_buffer && src_buffer.element_kind == .STRUCT && src_buffer.element_type_name == it.type_name {
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
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(value_id),
                           id_text(type_id),
                           id_text(src_ptr)));
          add_op(s, tprint("               OpStore % %",
                           id_text(it.ptr_id),
                           id_text(value_id)));
        }
        continue;
      }
    }

    if arg_expr && arg_expr.kind == .CONSTRUCTOR && arg_expr.text == it.type_name {
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

  got_return := false;
  for *helper.body.statements {
    stmt := it;
    if stmt.kind == .RETURN {
      if !stmt.return_expr {
        s.locals.count = local_count_before;
        s.local_structs.count = local_struct_count_before;
        diag.message = tprint("SPIR-V backend: helper '%' must return a struct value.", helper.name);
        return false, diag;
      }

      if stmt.return_expr.kind == .IDENT {
        ret_struct := find_local_struct(s, stmt.return_expr.text);
        if !ret_struct {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          diag.message = tprint("SPIR-V backend: helper '%' return identifier '%' is not a struct.", helper.name, stmt.return_expr.text);
          return false, diag;
        }
        dst_struct := find_local_struct(s, out_struct_name);
        if !dst_struct dst_struct = out_struct;
        copy_ok, copy_diag := copy_local_struct_fields(s, dst_struct, ret_struct);
        if !copy_ok {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          return false, copy_diag;
        }
        got_return = true;
        break;
      }

      if stmt.return_expr.kind == .CONSTRUCTOR && stmt.return_expr.text == out_struct_type {
        dst_struct := find_local_struct(s, out_struct_name);
        if !dst_struct dst_struct = out_struct;
        if stmt.return_expr.args.count != dst_struct.fields.count {
          s.locals.count = local_count_before;
          s.local_structs.count = local_struct_count_before;
          diag.message = tprint("SPIR-V backend: helper '%' return constructor field count mismatch.", helper.name);
          return false, diag;
        }
        for dst_struct.fields {
          value_id, value_type, value_ok, value_diag := emit_expr(s, stmt.return_expr.args[it_index]);
          if !value_ok {
            s.locals.count = local_count_before;
            s.local_structs.count = local_struct_count_before;
            return false, value_diag;
          }
          if value_type != it.type {
            s.locals.count = local_count_before;
            s.local_structs.count = local_struct_count_before;
            diag.message = tprint("SPIR-V backend: helper '%' return constructor field '%' type mismatch.", helper.name, it.name);
            return false, diag;
          }
          add_op(s, tprint("               OpStore % %",
                           id_text(it.ptr_id),
                           id_text(value_id)));
        }
        got_return = true;
        break;
      }

      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' return expression kind % is unsupported for struct return.", helper.name, stmt.return_expr.kind);
      return false, diag;
    }

    stmt_ok, stmt_terminated, stmt_diag := emit_stmt(s, stmt);
    if !stmt_ok {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      return false, stmt_diag;
    }
    if stmt_terminated {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      diag.message = tprint("SPIR-V backend: helper '%' has unsupported early control-flow termination.", helper.name);
      return false, diag;
    }
  }

  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  if !got_return {
    diag.message = tprint("SPIR-V backend: helper '%' has no return statement.", helper.name);
    return false, diag;
  }
  return true, diag;
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
      if path == "thread_id.x" || path == "input.thread_id.x" {
        return load_thread_x(s), .UINT, true, diag;
      }
      if expr.left && expr.left.kind == .CALL && expr.left.left && expr.left.left.kind == .IDENT {
        helper := find_helper(s, expr.left.left.text);
        if !helper return_err("SPIR-V backend: unknown helper '%'.", expr.left.left.text);
        if expr_type_from_decl(helper.return_type_name) != .UNKNOWN return_err("SPIR-V backend: member access on non-struct call return '%'.", helper.return_type_name);
        temp_name := tprint("__call_ret_%", new_id(s));
        temp_struct, temp_ok, temp_diag := alloc_local_struct(s, temp_name, helper.return_type_name);
        if !temp_ok return 0, .UNKNOWN, false, temp_diag;
        call_ok, call_diag := eval_inline_helper_to_struct(s, helper, expr.left.args, temp_struct);
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
          add_op(s, tprint("         % = OpLoad % %",
                           id_text(value_id),
                           id_text(value_type_id),
                           id_text(field_ptr)));
          return value_id, field_type, true, diag;
        }
        return 0, .UNKNOWN, false, field_diag;
      }
      if expr.left {
        left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
        if left_ok && left_type == .FLOAT2 {
          comp_index: s64 = -1;
          if expr.text == "x" comp_index = 0;
          if expr.text == "y" comp_index = 1;
          if comp_index >= 0 {
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
      if expr.left && expr.left.kind == .IDENT {
        local := find_local(s, expr.left.text);
        if local && local.type == .FLOAT2 {
          comp_index: s64 = -1;
          if expr.text == "x" comp_index = 0;
          if expr.text == "y" comp_index = 1;
          if comp_index >= 0 {
            vec_value := new_id(s);
            add_op(s, tprint("         % = OpLoad % %",
                             id_text(vec_value),
                             id_text(s.id_float2),
                             id_text(local.ptr_id)));
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
      return_err("SPIR-V backend: unsupported member expression '%'.", path);
    }

    case .SUBSCRIPT; {
      if !expr.left || expr.left.kind != .IDENT return_err("SPIR-V backend: subscript base must be an identifier.");
      buffer := find_buffer(s, expr.left.text);
      if !buffer return_err("SPIR-V backend: unknown subscript base '%'.", expr.left.text);
      idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      if idx_type != .UINT return_err("SPIR-V backend: subscript index must be uint.");
      if buffer.element_kind == .UINT {
        value_ptr_id := new_id(s);
        add_op(s, tprint("         % = OpAccessChain % % % %",
                                    id_text(value_ptr_id),
                                    id_text(buffer.ptr_storage_element_type_id),
                                    id_text(buffer.var_id),
                                    id_text(s.id_int_0),
                                    id_text(idx)));
        value_id := new_id(s);
        add_op(s, tprint("         % = OpLoad % %",
                                    id_text(value_id),
                                    id_text(s.id_uint),
                                    id_text(value_ptr_id)));
        return value_id, .UINT, true, diag;
      }
      return_err("SPIR-V backend: subscript value access for struct buffer '%' is unsupported; access a field instead.", buffer.name);
    }

    case .BINARY; {
      left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
      if !left_ok return 0, .UNKNOWN, false, left_diag;
      right_id, right_type, right_ok, right_diag := emit_expr(s, expr.right);
      if !right_ok return 0, .UNKNOWN, false, right_diag;

      op := expr.text;
      if left_type == .UINT && right_type == .UINT {
        result_id, result_type, result_ok, result_diag := emit_uint_binary_op(s, op, left_id, right_id);
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
      if left_type == .FLOAT || right_type == .FLOAT {
        left_float, left_float_ok, left_float_diag := coerce_to_float(s, left_id, left_type);
        if !left_float_ok return 0, .UNKNOWN, false, left_float_diag;
        right_float, right_float_ok, right_float_diag := coerce_to_float(s, right_id, right_type);
        if !right_float_ok return 0, .UNKNOWN, false, right_float_diag;
        result_id, result_type, result_ok, result_diag := emit_float_binary_op(s, op, left_float, right_float);
        return result_id, result_type, result_ok, result_diag;
      }

      return_err("SPIR-V backend: unsupported binary op '%' for emitted types.", op);
    }

    case .CAST; {
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;

      target := compact_text(expr.text);
      if target == "uint" || target == "u32" {
        if inner_type == .UINT return inner_id, .UINT, true, diag;
        if inner_type == .FLOAT {
          converted := new_id(s);
          add_op(s, tprint("         % = OpConvertFToU % %",
                           id_text(converted),
                           id_text(s.id_uint),
                           id_text(inner_id)));
          return converted, .UINT, true, diag;
        }
      }
      if target == "bool" {
        if inner_type == .BOOL return inner_id, .BOOL, true, diag;
      }
      if target == "float" {
        if inner_type == .FLOAT return inner_id, .FLOAT, true, diag;
        if inner_type == .UINT {
          converted := new_id(s);
          add_op(s, tprint("         % = OpConvertUToF % %",
                           id_text(converted),
                           id_text(s.id_float),
                           id_text(inner_id)));
          return converted, .FLOAT, true, diag;
        }
      }

      return_err("SPIR-V backend: unsupported cast to '%' from emitted type %.", expr.text, inner_type);
    }

    case .CALL; {
      if !expr.left || expr.left.kind != .IDENT return_err("SPIR-V backend: unsupported call target expression.");
      callee := expr.left.text;
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
         callee == "abs" || callee == "sqrt" || callee == "sin" || callee == "cos" {
        builtin_id, builtin_type, builtin_ok, builtin_diag := emit_float_builtin_call(s, callee, expr.args);
        if !builtin_ok return 0, .UNKNOWN, false, builtin_diag;
        return builtin_id, builtin_type, true, diag;
      }
      helper := find_helper(s, callee);
      if !helper return_err("SPIR-V backend: unsupported call target '%'.", callee);
      helper_id, helper_type, helper_ok, helper_diag := eval_inline_helper(s, helper, expr.args);
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
    if !expr.left || expr.left.kind != .IDENT return_err("SPIR-V backend: unsupported lvalue subscript base.");
    buffer := find_buffer(s, expr.left.text);
    if !buffer return_err("SPIR-V backend: unknown lvalue subscript base '%'.", expr.left.text);
    idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    if idx_type != .UINT return_err("SPIR-V backend: lvalue subscript index must be uint.");
    if buffer.element_kind == .UINT {
      ptr := new_id(s);
      add_op(s, tprint("         % = OpAccessChain % % % %",
                                  id_text(ptr),
                                  id_text(buffer.ptr_storage_element_type_id),
                                  id_text(buffer.var_id),
                                  id_text(s.id_int_0),
                                  id_text(idx)));
      return ptr, .UINT, true, diag;
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
      if field_type != .FLOAT2 return_err("SPIR-V backend: lvalue component access requires float2 field, got %.", field_type);
      comp_index: u32 = 0;
      if expr.text == "x" comp_index = 0;
      else if expr.text == "y" comp_index = 1;
      else return_err("SPIR-V backend: unsupported vector component '%' for lvalue.", expr.text);
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
      local_struct := find_local_struct(s, expr.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.text);
        if !field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.text, expr.text);
        return field.ptr_id, field.type, true, diag;
      }
    }
    if expr.left && expr.left.kind == .MEMBER && expr.left.left && expr.left.left.kind == .IDENT {
      local_struct := find_local_struct(s, expr.left.left.text);
      if local_struct {
        field := find_local_struct_field(local_struct, expr.left.text);
        if !field return_err("SPIR-V backend: unknown struct field '%.%'.", expr.left.left.text, expr.left.text);
        if field.type != .FLOAT2 return_err("SPIR-V backend: component lvalue requires float2 field, got %.", field.type);
        comp_index: u32 = 0;
        if expr.text == "x" comp_index = 0;
        else if expr.text == "y" comp_index = 1;
        else return_err("SPIR-V backend: unsupported vector component '%' for lvalue.", expr.text);
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
      decl_type := expr_type_from_decl(stmt.decl_type_name);
      if decl_type == .UINT || decl_type == .BOOL || decl_type == .FLOAT || decl_type == .FLOAT2 || decl_type == .FLOAT2X2 {
        ptr_id := new_id(s);
        ptr_type_id := func_ptr_type_id_from_kind(s, decl_type);
        assert(ptr_type_id != 0);
        add_local_decl(s, tprint("         % = OpVariable % Function",
                                 id_text(ptr_id),
                                 id_text(ptr_type_id)));
        array_add(*s.locals, .{name=stmt.decl_name, ptr_id=ptr_id, type=decl_type});
        if stmt.decl_init {
          init_id, init_type, init_ok, init_diag := emit_expr(s, stmt.decl_init);
          if !init_ok return false, false, init_diag;
          if init_type != decl_type {
            return_err("SPIR-V backend: declaration type mismatch for '%'.", stmt.decl_name);
          }
          add_op(s, tprint("               OpStore % %",
                           id_text(ptr_id),
                           id_text(init_id)));
        }
        return true, false, diag;
      }

      struct_def := find_struct(s, stmt.decl_type_name);
      if !struct_def {
        return_err("SPIR-V backend: unsupported declaration type '%'.", stmt.decl_type_name);
      }
      local_struct: IR_SPV_Gen_Local_Struct;
      local_struct.name = stmt.decl_name;
      local_struct.type_name = stmt.decl_type_name;
      for struct_def.fields {
        field_type := expr_type_from_decl(it.type_name);
        if field_type == .UNKNOWN || field_type == .STRUCT {
          return_err("SPIR-V backend: struct '%' field '%' type '%' is unsupported in generic path.", struct_def.name, it.name, it.type_name);
        }
        field_ptr := new_id(s);
        field_ptr_type := func_ptr_type_id_from_kind(s, field_type);
        if field_ptr_type == 0 {
          return_err("SPIR-V backend: struct '%' field '%' type '%' has no function pointer type.", struct_def.name, it.name, it.type_name);
        }
        add_local_decl(s, tprint("         % = OpVariable % Function",
                                 id_text(field_ptr),
                                 id_text(field_ptr_type)));
        array_add(*local_struct.fields, .{name=it.name, ptr_id=field_ptr, type=field_type});
      }

      if stmt.decl_init {
        if stmt.decl_init.kind == .CONSTRUCTOR && stmt.decl_init.text == stmt.decl_type_name {
          if stmt.decl_init.args.count != struct_def.fields.count {
            return_err("SPIR-V backend: struct constructor for '%' has wrong argument count.", stmt.decl_name);
          }
          for struct_def.fields {
            field := local_struct.fields[it_index];
            init_id, init_type, init_ok, init_diag := emit_expr(s, stmt.decl_init.args[it_index]);
            if !init_ok return false, false, init_diag;
            if init_type != field.type {
              return_err("SPIR-V backend: struct constructor field '%' type mismatch for '%'.", it.name, stmt.decl_name);
            }
            add_op(s, tprint("               OpStore % %",
                             id_text(field.ptr_id),
                             id_text(init_id)));
          }
        } else if stmt.decl_init.kind == .IDENT {
          src_struct := find_local_struct(s, stmt.decl_init.text);
          if !src_struct || src_struct.type_name != stmt.decl_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            src_field := find_local_struct_field(src_struct, it.name);
            if !src_field {
              return_err("SPIR-V backend: missing struct field '%' on initializer '%'.", it.name, stmt.decl_init.text);
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
          if !buffer || buffer.element_kind != .STRUCT || buffer.element_type_name != stmt.decl_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          for struct_def.fields {
            dst_field := local_struct.fields[it_index];
            src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, stmt.decl_init, it.name);
            if !src_ok return false, false, src_diag;
            if src_type != dst_field.type {
              return_err("SPIR-V backend: struct declaration '%': field '%' type mismatch in buffer initializer.", stmt.decl_name, it.name);
            }
            src_value := new_id(s);
            src_type_id := type_id_from_kind(s, src_type);
            add_op(s, tprint("         % = OpLoad % %",
                             id_text(src_value),
                             id_text(src_type_id),
                             id_text(src_ptr)));
            add_op(s, tprint("               OpStore % %",
                             id_text(dst_field.ptr_id),
                             id_text(src_value)));
          }
        } else if stmt.decl_init.kind == .CALL && stmt.decl_init.left && stmt.decl_init.left.kind == .IDENT {
          helper := find_helper(s, stmt.decl_init.left.text);
          if !helper || helper.return_type_name != stmt.decl_type_name {
            return_err("SPIR-V backend: struct declaration '%': unsupported call initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          call_ok, call_diag := eval_inline_helper_to_struct(s, helper, stmt.decl_init.args, *local_struct);
          if !call_ok return false, false, call_diag;
        } else {
          return_err("SPIR-V backend: struct declaration '%': unsupported initializer expression kind %.", stmt.decl_name, stmt.decl_init.kind);
        }
      }

      array_add(*s.local_structs, local_struct);
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
            helper := find_helper(s, stmt.binary_right.left.text);
            if !helper || helper.return_type_name != dst_buffer.element_type_name {
              return_err("SPIR-V backend: struct buffer assignment call '%' has incompatible return type.", expr_text(stmt.binary_right));
            }
            tmp_name := tprint("__assign_src_%", new_id(s));
            tmp_struct, tmp_ok, tmp_diag := alloc_local_struct(s, tmp_name, helper.return_type_name);
            if !tmp_ok return false, false, tmp_diag;
            call_ok, call_diag := eval_inline_helper_to_struct(s, helper, stmt.binary_right.args, tmp_struct);
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
            add_op(s, tprint("               OpStore % %",
                             id_text(dst_ptr),
                             id_text(value_id)));
          }
          return true, false, diag;
        }
      }

      ptr_id, lhs_type, lhs_ok, lhs_diag := emit_lvalue_ptr(s, stmt.binary_left);
      if !lhs_ok return false, false, lhs_diag;

      if op == "=" {
        rhs_id, rhs_type, rhs_ok, rhs_diag := emit_expr(s, stmt.binary_right);
        if !rhs_ok return false, false, rhs_diag;
        if lhs_type != rhs_type {
          return_err("SPIR-V backend: assignment type mismatch.");
        }
        add_op(s, tprint("               OpStore % %",
                                    id_text(ptr_id),
                                    id_text(rhs_id)));
        return true, false, diag;
      }

      if lhs_type != .UINT return_err("SPIR-V backend: non-uint compound assignment is not supported yet.");

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
      add_op(s, tprint("         % = OpLoad % %",
                                  id_text(lhs_value),
                                  id_text(s.id_uint),
                                  id_text(ptr_id)));
      rhs_id, rhs_type, rhs_ok, rhs_diag := emit_expr(s, stmt.binary_right);
      if !rhs_ok return false, false, rhs_diag;
      if rhs_type != .UINT {
        return_err("SPIR-V backend: compound assignment rhs must be uint.");
      }
      result_id, result_type, result_ok, result_diag := emit_uint_binary_op(s, base_op, lhs_value, rhs_id);
      if !result_ok return false, false, result_diag;
      if result_type != .UINT {
        return_err("SPIR-V backend: compound assignment operator must produce uint.");
      }

      add_op(s, tprint("               OpStore % %",
                                  id_text(ptr_id),
                                  id_text(result_id)));
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

      loop_ptr := new_id(s);
      add_local_decl(s, tprint("         % = OpVariable % Function",
                                          id_text(loop_ptr),
                                          id_text(s.id_ptr_func_uint)));
      array_add(*s.locals, .{name=loop_name, ptr_id=loop_ptr, type=.UINT});

      start_id, start_type, start_ok, start_diag := emit_expr(s, stmt.for_start);
      if !start_ok return false, false, start_diag;
      if start_type != .UINT return_err("SPIR-V backend: for-loop start expression must be uint.");
      add_op(s, tprint("               OpStore % %", id_text(loop_ptr), id_text(start_id)));

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, tprint("               OpBranch %", id_text(header_label)));
      add_op(s, tprint("         % = OpLabel", id_text(header_label)));

      it_value := new_id(s);
      add_op(s, tprint("         % = OpLoad % %", id_text(it_value), id_text(s.id_uint), id_text(loop_ptr)));
      end_id, end_type, end_ok, end_diag := emit_expr(s, stmt.for_end);
      if !end_ok return false, false, end_diag;
      if end_type != .UINT return_err("SPIR-V backend: for-loop end expression must be uint.");
      cmp_id, cmp_type, cmp_ok, cmp_diag := emit_uint_binary_op(s, stmt.for_cmp, it_value, end_id);
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
      step_id := get_u32_const(s, 1);
      it_current := new_id(s);
      add_op(s, tprint("         % = OpLoad % %", id_text(it_current), id_text(s.id_uint), id_text(loop_ptr)));
      next_it, next_type, next_ok, next_diag := emit_uint_binary_op(s, step_op, it_current, step_id);
      if !next_ok return false, false, next_diag;
      if next_type != .UINT return_err("SPIR-V backend: for-loop step must produce uint.");
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
      if stmt.return_expr {
        return_err("SPIR-V backend: return with value is not supported yet for compute.");
      }
      add_op(s, "               OpReturn");
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
  local_struct_count_before := s.local_structs.count;
  for block.statements {
    ok, terminated, step_diag := emit_stmt(s, *it);
    if !ok {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      return false, false, step_diag;
    }
    if terminated {
      s.locals.count = local_count_before;
      s.local_structs.count = local_struct_count_before;
      return true, true, diag;
    }
  }
  s.locals.count = local_count_before;
  s.local_structs.count = local_struct_count_before;
  return true, false, diag;
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
  state.helpers = shader.helpers;
  state.extra_structs = shader.extra_structs;
  init_ok, init_diag := init_base(*state, shader.buffers, bound_value);
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
  append(*sb, "               OpCapability Shader\n");
  append(*sb, tprint("          % = OpExtInstImport \"GLSL.std.450\"\n", id_text(state.id_extinst)));
  append(*sb, "               OpMemoryModel Logical GLSL450\n");
  entry_point_sb: String_Builder;
  append(*entry_point_sb, tprint("               OpEntryPoint GLCompute % \"main\" %", id_text(state.id_main), id_text(state.id_gl_global_invocation_id)));
  for state.buffers append(*entry_point_sb, " ", id_text(it.var_id));
  append(*entry_point_sb, "\n");
  append(*sb, builder_to_string(*entry_point_sb));
  append(*sb, tprint("               OpExecutionMode % LocalSize 1 1 1\n", id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"ComputeMain\"\n", id_text(state.id_main)));
  append(*sb, tprint("               OpName % \"gl_GlobalInvocationID\"\n", id_text(state.id_gl_global_invocation_id)));
  for state.buffers append(*sb, tprint("               OpName % \"%\"\n", id_text(it.var_id), it.name));
  append(*sb, tprint("               OpDecorate % BuiltIn GlobalInvocationId\n", id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("               OpDecorate % ArrayStride 4\n", id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("               OpDecorate % Block\n", id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(state.id_buffer_struct)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind != .STRUCT continue;
    append(*sb, tprint("               OpDecorate % ArrayStride %\n", id_text(buffer.runtimearr_type_id), buffer.array_stride));
    for buffer.fields {
      append(*sb, tprint("               OpMemberDecorate % % Offset %\n",
                         id_text(buffer.element_type_id),
                         it.index,
                         it.offset));
    }
    append(*sb, tprint("               OpDecorate % Block\n", id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", id_text(buffer.wrapper_struct_type_id)));
  }
  for state.buffers {
    append(*sb, tprint("               OpDecorate % Binding %\n", id_text(it.var_id), it.binding_index));
    append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", id_text(it.var_id)));
  }

  append(*sb, tprint("       % = OpTypeVoid\n", id_text(state.id_void)));
  append(*sb, tprint("          % = OpTypeFunction %\n", id_text(state.id_fn_void), id_text(state.id_void)));
  append(*sb, tprint("       % = OpTypeInt 32 0\n", id_text(state.id_uint)));
  append(*sb, tprint("      % = OpTypeFloat 32\n", id_text(state.id_float)));
  append(*sb, tprint("     % = OpTypeVector % 2\n", id_text(state.id_float2), id_text(state.id_float)));
  append(*sb, tprint("   % = OpTypeMatrix % 2\n", id_text(state.id_float2x2), id_text(state.id_float2)));
  append(*sb, tprint("       % = OpTypeBool\n", id_text(state.id_bool)));
  append(*sb, tprint("       % = OpConstantTrue %\n", id_text(state.id_bool_true), id_text(state.id_bool)));
  append(*sb, tprint("       % = OpConstantFalse %\n", id_text(state.id_bool_false), id_text(state.id_bool)));
  append(*sb, tprint("     % = OpTypeVector % 3\n", id_text(state.id_v3uint), id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_v3uint), id_text(state.id_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", id_text(state.id_gl_global_invocation_id), id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_uint), id_text(state.id_uint)));
  append(*sb, tprint("        % = OpTypeInt 32 1\n", id_text(state.id_int)));
  append(*sb, tprint("% = OpTypeRuntimeArray %\n", id_text(state.id_runtimearr_uint), id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypeStruct %\n", id_text(state.id_buffer_struct), id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(state.id_ptr_storage_buffer_struct), id_text(state.id_buffer_struct)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(state.id_ptr_storage_uint), id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(state.id_ptr_storage_float), id_text(state.id_float)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(state.id_ptr_storage_float2), id_text(state.id_float2)));
  for state.buffers {
    buffer := it;
    if buffer.element_kind != .STRUCT continue;
    struct_type_line_sb: String_Builder;
    append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
    for buffer.fields {
      field_type_id := type_id_from_kind(*state, it.type);
      append(*struct_type_line_sb, tprint(" %", id_text(field_type_id)));
    }
    append(*struct_type_line_sb, "\n");
    append(*sb, builder_to_string(*struct_type_line_sb));
    append(*sb, tprint("% = OpTypeRuntimeArray %\n", id_text(buffer.runtimearr_type_id), id_text(buffer.element_type_id)));
    append(*sb, tprint("% = OpTypeStruct %\n", id_text(buffer.wrapper_struct_type_id), id_text(buffer.runtimearr_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_wrapper_type_id), id_text(buffer.wrapper_struct_type_id)));
    append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", id_text(buffer.ptr_storage_element_type_id), id_text(buffer.element_type_id)));
  }
  for state.buffers append(*sb, tprint("% = OpVariable % StorageBuffer\n", id_text(it.var_id), id_text(it.ptr_wrapper_type_id)));
  append(*sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float), id_text(state.id_float)));
  append(*sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2), id_text(state.id_float2)));
  append(*sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2x2), id_text(state.id_float2x2)));
  append(*sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_bool), id_text(state.id_bool)));
  append(*sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint), id_text(state.id_uint)));

  // Constants are emitted after types and before function body.
  for state.const_u32 {
    append(*sb, tprint("      % = OpConstant % %\n",
                       id_text(it.id),
                       id_text(state.id_uint),
                       it.value));
  }
  for state.const_i32 {
    append(*sb, tprint("      % = OpConstant % %\n",
                       id_text(it.id),
                       id_text(state.id_int),
                       it.value));
  }
  for state.const_f32 {
    append(*sb, tprint("      % = OpConstant % %\n",
                       id_text(it.id),
                       id_text(state.id_float),
                       it.text));
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
