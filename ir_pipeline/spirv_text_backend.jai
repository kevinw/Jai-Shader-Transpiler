//
// Jai IR -> SPIR-V text
// 
to_spvasm :: (shader: *IR_Shader) -> IR_Result(string) {
    validate_ok, validate_diag := ir_validate_shader_invariants(shader);
    if !validate_ok return {"", false, validate_diag};
    if #complete shader.kind == {
    case .Vertex;
        using cast(*IR_Vertex_Shader)shader;
        spvasm, ok, diag := emit_graphics_generic(.VERTEX, source_name, input, output, args, *body, functions, function_constants, extra_structs);
        return {spvasm, ok, diag};
    case .Fragment;
        using cast(*IR_Fragment_Shader)shader;
        spvasm, ok, diag := emit_graphics_generic(.FRAGMENT, source_name, input, output, args, *body, functions, function_constants, extra_structs);
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
  normalize_ident_text :: (in: string) -> string {
    out := in;
    if out.count > 0 {
      start: s64 = 0;
      end := out.count - 1;
      while start <= end && (out[start] == #char " " || out[start] == #char "\t" || out[start] == #char "\n" || out[start] == #char "\r") start += 1;
      while end >= start && (out[end] == #char " " || out[end] == #char "\t" || out[end] == #char "\n" || out[end] == #char "\r") end -= 1;
      if start > 0 || end < out.count - 1 {
        trimmed: string;
        trimmed.data = out.data + start;
        trimmed.count = end - start + 1;
        out = trimmed;
      }
    }
    if out.count < 4 return out;
    if out[0] != #char "*" return out;
    if out[out.count - 1] != #char ")" return out;

    open: s64 = -1;
    for out {
      if it == #char "(" {
        open = it_index;
        break;
      }
    }
    if open <= 0 return out;
    if open + 1 >= out.count - 1 return out;

    inner: string;
    inner.data = out.data + open + 1;
    inner.count = out.count - open - 2;
    return normalize_ident_text(inner);
  }

  if !expr return "", false;
  if expr.kind == .IDENT return normalize_ident_text(expr.text), true;
  if expr.kind == .CAST && expr.left {
    name, ok := resolve_ident_or_zero_deref(expr.left);
    return name, ok;
  }
  if expr.kind == .UNARY && expr.left {
    if expr.unary_op == .ADDRESS_OF || expr.unary_op == .DEREF {
      name, ok := resolve_ident_or_zero_deref(expr.left);
      return name, ok;
    }
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

resolve_member_path :: (expr: *IR_Expr) -> (path: string, ok: bool) {
  if !expr return "", false;
  if expr.kind != .MEMBER {
    base_name, base_ok := resolve_ident_or_zero_deref(expr);
    if !base_ok return "", false;
    return base_name, true;
  }

  left_path, left_ok := resolve_member_path(expr.left);
  if !left_ok return "", false;
  if expr.text.count == 0 return "", false;
  return tprint("%.%", left_path, expr.text), true;
}

split_path_root :: (path: string) -> (root: string, tail: string, ok: bool) {
  if path.count == 0 return "", "", false;
  for path {
    if it == #char "." {
      if it_index <= 0 || it_index + 1 >= path.count return "", "", false;
      root: string;
      root.data = path.data;
      root.count = it_index;
      tail: string;
      tail.data = path.data + it_index + 1;
      tail.count = path.count - it_index - 1;
      return root, tail, true;
    }
  }
  return path, "", true;
}

split_path_last :: (path: string) -> (prefix: string, tail: string, ok: bool) {
  if path.count == 0 return "", "", false;
  i := path.count - 1;
  while i >= 0 {
    if path[i] == #char "." {
      if i <= 0 || i + 1 >= path.count return "", "", false;
      prefix: string = .{i, path.data};
      tail: string = .{path.count - i - 1, path.data + i + 1};
      return prefix, tail, true;
    }
    if i == 0 break;
    i -= 1;
  }
  return "", "", false;
}

resolve_buffer_root_and_field_path :: (expr: *IR_Expr) -> (buffer_name: string, field_path: string, ok: bool) {
  full_path, path_ok := resolve_member_path(expr);
  if !path_ok return "", "", false;
  root, tail, split_ok := split_path_root(full_path);
  if !split_ok return "", "", false;
  if tail.count == 0 return "", "", false;
  return root, tail, true;
}

resolve_buffer_prefix_and_field_path :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (buffer_name: string, field_path: string, ok: bool) {
  if !expr return "", "", false;

  full_path, path_ok := resolve_member_path(expr);
  if !path_ok {
    base_name, base_ok := resolve_buffer_name_from_expr(expr);
    if !base_ok return "", "", false;
    full_path = base_name;
  }

  if find_buffer(s, full_path) return full_path, "", true;

  prefix := full_path;
  suffix := "";
  while true {
    next_prefix, tail, split_ok := split_path_last(prefix);
    if !split_ok break;
    suffix = ifx suffix.count == 0 then tail else tprint("%.%", tail, suffix);
    prefix = next_prefix;
    if find_buffer(s, prefix) return prefix, suffix, true;
  }

  return "", "", false;
}

expr_text :: (expr: *IR_Expr) -> string {
  text, ok := ir_expr_to_slang_from_ir(expr);
  if !ok return "";
  return text;
}

canonical_callee_name :: (name: string) -> string {
  if name.count == 0 return name;
  i := name.count - 1;
  while i >= 0 {
    if name[i] == #char "." {
      out: string;
      out.data = name.data + i + 1;
      out.count = name.count - i - 1;
      return out;
    }
    if i == 0 break;
    i -= 1;
  }
  return name;
}

callee_matches_builtin :: (callee: string, builtin: string) -> bool {
  if callee == builtin return true;
  if callee.count <= builtin.count return false;
  if !begins_with(callee, builtin) return false;
  next := callee[builtin.count];
  is_digit := next >= #char "0" && next <= #char "9";
  is_alpha := (next >= #char "a" && next <= #char "z") || (next >= #char "A" && next <= #char "Z");
  return !is_alpha || is_digit;
}

call_builtin_kind_from_callee_name :: (callee: string) -> IR_Call_Builtin_Kind {
  if callee_matches_builtin(callee, "sample_2d") return .SAMPLE_2D;
  if callee_matches_builtin(callee, "sample_3d") return .SAMPLE_3D;
  if callee_matches_builtin(callee, "write_2d") return .WRITE_2D;
  if callee_matches_builtin(callee, "write_3d") return .WRITE_3D;
  if callee_matches_builtin(callee, "discard") return .DISCARD;
  if callee_matches_builtin(callee, "saturate") return .SATURATE;
  if callee_matches_builtin(callee, "mix") return .MIX;
  if callee_matches_builtin(callee, "lerp") return .LERP;
  if callee_matches_builtin(callee, "reflect") return .REFLECT;
  if callee == "clamp" return .CLAMP;
  if callee == "step" return .STEP;
  if callee == "pow" return .POW;
  if callee == "smoothstep" return .SMOOTHSTEP;
  if callee == "mod" return .MOD;
  if callee == "fmod_cycling" return .FMOD_CYCLING;
  if callee == "mul" return .MUL;
  if callee == "floor" return .FLOOR;
  if callee == "min" return .MIN;
  if callee == "max" return .MAX;
  if callee == "abs" return .ABS;
  if callee == "sqrt" return .SQRT;
  if callee == "exp" return .EXP;
  if callee == "sin" return .SIN;
  if callee == "cos" return .COS;
  if callee == "fract" return .FRACT;
  if callee == "length" return .LENGTH;
  if callee == "normalize" return .NORMALIZE;
  if callee == "radians" return .RADIANS;
  if callee == "degrees" return .DEGREES;
  if callee == "atomic_add_u32" return .ATOMIC_ADD_U32;
  if callee == "atomic_sub_u32" return .ATOMIC_SUB_U32;
  if callee == "atomic_exchange_u32" return .ATOMIC_EXCHANGE_U32;
  if callee == "atomic_compare_exchange_u32" return .ATOMIC_COMPARE_EXCHANGE_U32;
  if callee == "atomic_min_u32" return .ATOMIC_MIN_U32;
  if callee == "atomic_max_u32" return .ATOMIC_MAX_U32;
  return .NONE;
}

call_builtin_kind_for_expr :: (expr: *IR_Expr) -> IR_Call_Builtin_Kind {
  if !expr return .NONE;
  if expr.call_builtin_kind != .NONE return expr.call_builtin_kind;
  if expr.call_resolved_name.count != 0 return call_builtin_kind_from_callee_name(canonical_callee_name(expr.call_resolved_name));
  if !expr.left return .NONE;
  callee := "";
  if expr.left.kind == .IDENT || expr.left.kind == .MEMBER callee = expr.left.text;
  if callee.count == 0 return .NONE;
  return call_builtin_kind_from_callee_name(canonical_callee_name(callee));
}

call_helper_name_for_expr :: (expr: *IR_Expr) -> (string, bool) {
  if !expr return "", false;
  if expr.call_resolved_name.count != 0 return canonical_callee_name(expr.call_resolved_name), true;
  if !expr.left return "", false;
  if expr.call_target_kind == .HELPER && (expr.left.kind == .IDENT || expr.left.kind == .MEMBER) {
    return canonical_callee_name(expr.left.text), true;
  }
  if expr.left.kind == .IDENT || expr.left.kind == .MEMBER {
    return canonical_callee_name(expr.left.text), true;
  }
  return "", false;
}

call_builtin_kind_to_name :: (kind: IR_Call_Builtin_Kind) -> string {
  if kind == .SAMPLE_2D return "sample_2d";
  if kind == .SAMPLE_3D return "sample_3d";
  if kind == .WRITE_2D return "write_2d";
  if kind == .WRITE_3D return "write_3d";
  if kind == .ATOMIC_ADD_U32 return "atomic_add_u32";
  if kind == .ATOMIC_SUB_U32 return "atomic_sub_u32";
  if kind == .ATOMIC_EXCHANGE_U32 return "atomic_exchange_u32";
  if kind == .ATOMIC_COMPARE_EXCHANGE_U32 return "atomic_compare_exchange_u32";
  if kind == .ATOMIC_MIN_U32 return "atomic_min_u32";
  if kind == .ATOMIC_MAX_U32 return "atomic_max_u32";
  if kind == .FLOOR return "floor";
  if kind == .MIN return "min";
  if kind == .MAX return "max";
  if kind == .ABS return "abs";
  if kind == .SQRT return "sqrt";
  if kind == .EXP return "exp";
  if kind == .SIN return "sin";
  if kind == .COS return "cos";
  if kind == .FRACT return "fract";
  return "";
}

compact_text :: (in: string) -> string {
  need_compact := false;
  for in {
    if it == #char " " || it == #char "\t" || it == #char "\n" || it == #char "\r" {
        need_compact = true;
    }
  }
  if !need_compact return in;
    
  out: [..] u8;
  for in {
    if it == #char " " || it == #char "\t" || it == #char "\n" || it == #char "\r" continue;
    array_add(*out, it);
  }
  return string.{data=out.data, count=out.count};
}

thread_x_expr :: (expr: *IR_Expr) -> bool {
  if !expr return false;
  return expr.builtin_ref.kind == .DISPATCH_THREAD_ID && expr.builtin_ref.component == 0;
}

match_branch_condition_outer :: (expr: *IR_Expr) -> (u32, bool) {
  if !expr || expr.kind != .BINARY return 0, false;
  op, op_ok := ir_expr_binary_op_text(expr);
  if !op_ok || op != "<" return 0, false;
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
  FLOAT16;
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
  struct_name: string;
  type_id: s64;
  ptr_storage_type_id: s64;
  is_array: bool;
  array_count: s64;
  array_stride: s64;
  array_type_id: s64;
  array_length_const_id: s64;
  array_element_struct_name: string;
  array_element_type_id: s64;
  offset: s64;
}

IR_SPV_Gen_Buffer_Layout_Struct :: struct {
  name: string;
  type_id: s64;
  max_align: s64;
  stride: s64;
  fields: [..] IR_SPV_Gen_Buffer_Field;
}

IR_SPV_Gen_Uniform_Field :: struct {
  name: string;
  index: s64;
  type: IR_SPV_Gen_Type;
  field_type_id: s64;
  is_array: bool;
  array_count: s64;
  array_stride: s64;
  array_type_id: Id;
  array_length_const_id: Id;
  offset: s64;
}

IR_SPV_Gen_Uniform_Block :: struct {
  name: string;
  type_name: string;
  binding_index: s64;
  var_id: Id;
  struct_type_id: s64;
  ptr_uniform_struct_type_id: s64;
  fields: [..] IR_SPV_Gen_Uniform_Field;
}

IR_SPV_Gen_Const_U32 :: struct {
  value: u32;
  id: Id;
}

Id :: s64;

IR_SPV_Gen_Const_I32 :: struct {
  value: s32;
  id: Id;
}

IR_SPV_Gen_Const_I64 :: struct {
  value: s64;
  id: Id;
}

IR_SPV_Gen_Const_U64 :: struct {
  value: u64;
  id: Id;
}

IR_SPV_Gen_Const_F32 :: struct {
  text: string;
  id: Id;
}

IR_SPV_Gen_Const_F16 :: struct {
  text: string;
  id: Id;
}

IR_SPV_Gen_Function_Constant :: struct {
  name: string;
  declaration: *Code_Declaration;
  type: IR_Function_Constant_Type;
  default_value_text: string;
  spec_id: u32;
  id: Id;
  component_count: s64;
  component_ids: [4] s64;
}

IR_SPV_Gen_Const_Null :: struct {
  type_id: s64;
  id: s64;
}

IR_SPV_Gen_Buffer :: struct {
  name: string;
  var_id: s64;
  binding_index: s64;
  is_readonly: bool;
  element_type_name: string;
  element_struct_name: string;
  element_kind: IR_SPV_Gen_Type;
  element_type_id: s64;
  runtimearr_type_id: s64;
  fixed_array_count: s64;
  fixed_array_count_const_id: s64;
  wrapper_struct_type_id: s64;
  ptr_wrapper_type_id: s64;
  ptr_storage_element_type_id: s64;
  has_base_index: bool;
  base_index_id: s64;
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

IR_SPV_Inline_Helper_Context :: struct {
  exit_label: s64;
  return_flag_ptr: s64;
  has_return_value: bool;
  return_value_ptr: s64;
  return_value_type: IR_SPV_Gen_Type;
  break_targets_base_count: s64;
  control_merge_targets_base_count: s64;
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
  const_f16: [..] IR_SPV_Gen_Const_F16;
  function_constants: [..] IR_SPV_Gen_Function_Constant;
  const_null: [..] IR_SPV_Gen_Const_Null;
  buffers: [..] IR_SPV_Gen_Buffer;
  buffer_layout_structs: [..] IR_SPV_Gen_Buffer_Layout_Struct;
  uniform_blocks: [..] IR_SPV_Gen_Uniform_Block;
  loop_targets: [..] IR_SPV_Gen_Loop_Target;
  break_targets: [..] s64;
  control_merge_targets: [..] s64;
  inline_return_targets: [..] s64;
  inline_helper_contexts: [..] IR_SPV_Inline_Helper_Context;
  functions: [] IR_Function;
  extra_structs: [..] IR_Struct;
  local_var_lines: String_Builder;
  op_lines: String_Builder;
  last_op_is_terminator: bool;
  debug_names: [..] IR_SPV_Gen_Debug_Name;
  debug_member_names: [..] IR_SPV_Gen_Debug_Member_Name;
  stage: IR_SPV_Gen_Stage;
  debug_type_prefix: string;
  output_struct_type_name: string;
  input_vars: [..] IR_SPV_Gen_Interface_Var;
  output_vars: [..] IR_SPV_Gen_Interface_Var;
  physical_root_name: string;
  physical_root_struct_name: string;
  physical_root_var_id: s64;
  physical_ps_infos: [..] IR_SPV_PS_Struct_Info;
  physical_storage_struct_ptr_types: [..] IR_SPV_PS_Ptr_To_Ptr;
  use_physical_storage: bool;
  uses_sample_2d: bool;
  uses_sample_3d: bool;
  uses_write_2d: bool;
  uses_write_3d: bool;
  
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
    id_half: s64;
    id_float: s64;
    id_float2: s64;
    id_float3: s64;
    id_float4: s64;
    id_float2x2: s64;
    id_bool: s64;
    id_bool_true: s64;
    id_bool_false: s64;
    id_v3uint: s64;
    id_v2uint: s64;
    id_ptr_input_v3uint: s64;
    id_gl_global_invocation_id: s64;
    id_gl_local_invocation_id: s64;
    id_gl_workgroup_id: s64;
    id_gl_local_invocation_index: s64;
    id_ptr_input_uint: s64;
    id_ptr_input_half: s64;
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
    id_ptr_storage_half: s64;
    id_ptr_storage_float: s64;
    id_ptr_storage_float2: s64;
    id_ptr_storage_float3: s64;
    id_ptr_storage_float4: s64;
    id_ptr_input_float: s64;
    id_ptr_input_float2: s64;
    id_ptr_input_float3: s64;
    id_ptr_input_float4: s64;
    id_ptr_output_float: s64;
    id_ptr_output_float2: s64;
    id_ptr_output_float3: s64;
    id_ptr_output_float4: s64;
    id_ptr_uniform_half: s64;
    id_ptr_uniform_float: s64;
    id_ptr_uniform_float2: s64;
    id_ptr_uniform_float3: s64;
    id_ptr_uniform_float4: s64;
    id_ptr_uniform_int: s64;
    id_ptr_uniform_uint: s64;
    id_ptr_uniform_int64: s64;
    id_ptr_uniform_uint64: s64;
    id_image2d: s64;
    id_image3d: s64;
    id_sampler: s64;
    id_sampled_image2d: s64;
    id_sampled_image3d: s64;
    id_image2d_array: s64;
    id_image3d_array: s64;
    id_sampler_array: s64;
    id_ptr_uniformconst_image2d_array: s64;
    id_ptr_uniformconst_image3d_array: s64;
    id_ptr_uniformconst_sampler_array: s64;
    id_ptr_uniformconst_image2d: s64;
    id_ptr_uniformconst_image3d: s64;
    id_ptr_uniformconst_sampler: s64;
    id_sample_2d_textures_var: s64;
    id_sample_2d_samplers_var: s64;
    id_sample_3d_textures_var: s64;
    id_sample_3d_samplers_var: s64;
    id_storage_image2d: s64;
    id_storage_image3d: s64;
    id_storage_image2d_array: s64;
    id_storage_image3d_array: s64;
    id_ptr_uniformconst_storage_image2d_array: s64;
    id_ptr_uniformconst_storage_image3d_array: s64;
    id_ptr_uniformconst_storage_image2d: s64;
    id_ptr_uniformconst_storage_image3d: s64;
    id_write_2d_textures_var: s64;
    id_write_3d_textures_var: s64;
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
    id_ptr_func_half: s64;
    id_main: s64;
  };

  bound_value: u32;
}

// -----------------------------------------------------------------------------
// Core State Helpers
// -----------------------------------------------------------------------------

id_text :: (id: s64) -> string {
    assert(id >= 0);
    assert(id <= 0xFFFF);
    value := cast,no_check(u16) id;
    
    if value == 0 return "%0";
    
    buffer := cast(*u8)talloc(6);

    n := cast(u32) value;
    p := buffer + 6;   // write from end

    while n > 0 {
        p -= 1;
        p.* = #char "0" + cast,no_check(u8)(n % 10);
        n /= 10;
    }

    count := cast,no_check(s64)((buffer + 6) - p);
    p -= 1;
    p.* = #char "%";
    
    return string.{count + 1, p};
}

new_id :: (s: *IR_SPV_Gen_State) -> s64 {
  id := s.next_id;
  s.next_id += 1;
  return id;
}

spv_function_constant_kind_from_ir_type :: (type: IR_Type) -> (IR_Function_Constant_Type, bool) {
  if type.kind == {
    case .BOOL; return .BOOL, true;
    case .U32;  return .U32, true;
    case .I32;  return .S32, true;
    case .F32;  return .FLOAT, true;
    case .F32x2; return .FLOAT2, true;
    case .F32x3; return .FLOAT3, true;
    case .F32x4; return .FLOAT4, true;
  }
  return .BOOL, false;
}

spv_slice_text :: (text: string, start: s64, end_exclusive: s64) -> string {
  if start < 0 start = 0;
  if end_exclusive < start end_exclusive = start;
  if end_exclusive > text.count end_exclusive = text.count;
  return string.{count = end_exclusive - start, data = text.data + start};
}

spv_parse_function_constant_float_vector_literal :: (text: string, expected_count: s64) -> ([4] string, bool) {
  values: [4] string;
  if expected_count < 2 || expected_count > 4 return values, false;

  inner := trim(text);
  if starts_with(inner, ".{") && ends_with(inner, "}") {
    inner = spv_slice_text(inner, 2, inner.count - 1);
  } else if starts_with(inner, "{") && ends_with(inner, "}") {
    inner = spv_slice_text(inner, 1, inner.count - 1);
  } else {
    return values, false;
  }

  index: s64 = 0;
  start: s64 = 0;
  for i: 0..inner.count-1 {
    if inner[i] != #char "," continue;
    if index >= expected_count return values, false;
    values[index] = trim(spv_slice_text(inner, start, i));
    index += 1;
    start = i + 1;
  }

  if index != expected_count - 1 return values, false;
  values[index] = trim(spv_slice_text(inner, start, inner.count));

  for i: 0..expected_count-1 if values[i].count == 0 return values, false;
  return values, true;
}

emit_vector_function_constant_def :: (sb: *String_Builder, s: *IR_SPV_Gen_State, fc: IR_SPV_Gen_Function_Constant, expected_count: s64, vector_type_id: s64) -> bool {
  component_texts, components_ok := spv_parse_function_constant_float_vector_literal(fc.default_value_text, expected_count);
  if !components_ok return false;

  for i: 0..expected_count-1 {
    value_text, value_ok := parse_f32_literal_text(component_texts[i]);
    if !value_ok return false;
    append(sb, tprint("% = OpSpecConstant % %\n", id_text(fc.component_ids[i]), id_text(s.id_float), value_text));
  }

  append(sb, tprint("% = OpSpecConstantComposite %", id_text(fc.id), id_text(vector_type_id)));
  for i: 0..expected_count-1 append(sb, tprint(" %", id_text(fc.component_ids[i])));
  append(sb, "\n");
  return true;
}

spv_function_constant_declaration_from_expr :: (expr: *IR_Expr) -> *Code_Declaration {
  if !expr || !expr.origin_node return null;
  node := expr.origin_node;
  if node.kind != .IDENT return null;
  ident := cast(*Code_Ident) node;
  return ident.resolved_declaration;
}

find_function_constant_by_decl :: (s: *IR_SPV_Gen_State, decl: *Code_Declaration) -> *IR_SPV_Gen_Function_Constant {
  if !decl return null;
  for *s.function_constants if it.declaration == decl return it;
  return null;
}

find_function_constant_by_name :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Function_Constant {
  if name.count == 0 return null;
  for *s.function_constants if it.name == name return it;
  return null;
}

register_function_constants :: (s: *IR_SPV_Gen_State, shader_constants: [] IR_Function_Constant) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  for shader_constants {
    if find_function_constant_by_decl(s, it.declaration) != null continue;
    source_kind: IR_Type_Kind;
    if it.type == {
      case .BOOL;   source_kind = .BOOL;
      case .U32;    source_kind = .U32;
      case .S32;    source_kind = .I32;
      case .FLOAT;  source_kind = .F32;
      case .FLOAT2; source_kind = .F32x2;
      case .FLOAT3; source_kind = .F32x3;
      case .FLOAT4; source_kind = .F32x4;
    }
    type_kind, type_ok := spv_function_constant_kind_from_ir_type(.{kind = source_kind});
    if !type_ok return_err("unsupported function constant type for '%'.", it.name);
    component_count: s64 = 1;
    if type_kind == {
      case .FLOAT2; component_count = 2;
      case .FLOAT3; component_count = 3;
      case .FLOAT4; component_count = 4;
    }
    component_ids: [4] s64;
    if component_count > 1 {
      for i: 0..component_count-1 component_ids[i] = new_id(s);
    }
    array_add(*s.function_constants, .{
      name = it.name,
      declaration = it.declaration,
      type = type_kind,
      default_value_text = it.default_value_text,
      spec_id = it.spec_id,
      id = new_id(s),
      component_count = component_count,
      component_ids = component_ids,
    });
  }
  return true, {};
}

spv_append_function_constant_names :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  for s.function_constants {
    append(sb, tprint("               OpName % \"%\"\n", id_text(it.id), it.name));
    if it.component_count <= 1 continue;

    suffixes := string.["x", "y", "z", "w"];
    for i: 0..it.component_count-1 {
      append(sb, tprint("               OpName % \"%_%\"\n",
                        id_text(it.component_ids[i]),
                        it.name,
                        suffixes[i]));
    }
  }
}

spv_append_function_constant_decorations :: (sb: *String_Builder, s: *IR_SPV_Gen_State) {
  for s.function_constants {
    if it.component_count <= 1 {
      append(sb, tprint("               OpDecorate % SpecId %\n", id_text(it.id), it.spec_id));
      continue;
    }
    for i: 0..it.component_count-1 append(sb, tprint("               OpDecorate % SpecId %\n", id_text(it.component_ids[i]), it.spec_id + cast(u32) i));
  }
}

spv_append_function_constant_defs :: (sb: *String_Builder, s: *IR_SPV_Gen_State) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  for s.function_constants {
    if it.type == {
      case .BOOL;
        if it.default_value_text == "true" {
          append(sb, tprint("% = OpSpecConstantTrue %\n", id_text(it.id), id_text(s.id_bool)));
        } else if it.default_value_text == "false" {
          append(sb, tprint("% = OpSpecConstantFalse %\n", id_text(it.id), id_text(s.id_bool)));
        } else {
          return_err("function constant '%' expected bool literal, got '%'.", it.name, it.default_value_text);
        }
      case .U32;
        value, value_ok := parse_u32_literal_text(it.default_value_text);
        if !value_ok return_err("function constant '%' expected u32 literal, got '%'.", it.name, it.default_value_text);
        append(sb, tprint("% = OpSpecConstant % %\n", id_text(it.id), id_text(s.id_uint), value));
      case .S32;
        value64, value_ok := parse_i64_literal_text(it.default_value_text);
        if !value_ok return_err("function constant '%' expected s32 literal, got '%'.", it.name, it.default_value_text);
        append(sb, tprint("% = OpSpecConstant % %\n", id_text(it.id), id_text(s.id_int), cast(s32) value64));
      case .FLOAT;
        value_text, value_ok := parse_f32_literal_text(it.default_value_text);
        if !value_ok return_err("function constant '%' expected float literal, got '%'.", it.name, it.default_value_text);
        append(sb, tprint("% = OpSpecConstant % %\n", id_text(it.id), id_text(s.id_float), value_text));
      case .FLOAT2;
        if !emit_vector_function_constant_def(sb, s, it, 2, s.id_float2) {
          return_err("function constant '%' expected float2 literal, got '%'.", it.name, it.default_value_text);
        }
      case .FLOAT3;
        if !emit_vector_function_constant_def(sb, s, it, 3, s.id_float3) {
          return_err("function constant '%' expected float3 literal, got '%'.", it.name, it.default_value_text);
        }
      case .FLOAT4;
        if !emit_vector_function_constant_def(sb, s, it, 4, s.id_float4) {
          return_err("function constant '%' expected float4 literal, got '%'.", it.name, it.default_value_text);
        }
    }
  }

  return true, {};
}

// Emits forms like "OpStore id_1 id2"
add_op :: (using s: *IR_SPV_Gen_State, name: string, args: ..s64, is_terminator := false) {
  append(*op_lines, name);
  if args.count > 0 append(*op_lines, " ");
  for args {
    append(*op_lines, id_text(it));
    if it_index != args.count - 1 append(*op_lines, " ");
  }
  append(*s.op_lines, "\n");
  s.last_op_is_terminator = is_terminator;
}

// Emits forms like "dest = OpLoad id_1"
add_op :: (using s: *IR_SPV_Gen_State, dest: s64, name: string, args: ..s64, is_terminator := false) -> s64 {
  append_many(*op_lines, id_text(dest), " = ", name);
  if args.count > 0 append(*op_lines, " ");
  for args {
    append(*op_lines, id_text(it));
    if it_index != args.count - 1 append(*op_lines, " ");
  }
  append(*op_lines, "\n");
  s.last_op_is_terminator = is_terminator;
  return dest;
}

add_op :: (s: *IR_SPV_Gen_State, line: string, is_terminator := false) {
  append(*s.op_lines, line);
  append(*s.op_lines, "\n");
  s.last_op_is_terminator = is_terminator;
}

add_local_decl :: (s: *IR_SPV_Gen_State, line: string, args: ..Any) {
  print_to_builder(*s.local_var_lines, line, ..args);
  append(*s.local_var_lines, "\n");
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
  base_name := sanitize_identifier_name(base);
  prefix := sanitize_identifier_name(s.debug_type_prefix);
  if prefix.count == 0 return base_name;
  if base_name.count == 0 return prefix;
  return tprint("%_%", prefix, base_name);
}

add_debug_name :: (s: *IR_SPV_Gen_State, id: s64, name: string) {
  if id == 0 || name.count == 0 return;
  safe_name := sanitize_debug_name(name);
  if safe_name.count == 0 return;
  for *s.debug_names if it.id == id return;
  array_add(*s.debug_names, .{id=id, name=safe_name});
}

add_debug_member_name :: (s: *IR_SPV_Gen_State, type_id: s64, member_index: s64, name: string) {
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

resolve_buffer_name_from_expr :: (expr: *IR_Expr) -> (buffer_name: string, ok: bool) {
  if !expr return "", false;
  if expr.kind == .CAST && expr.left {
    name, ok := resolve_buffer_name_from_expr(expr.left);
    return name, ok;
  }
  if expr.kind == .UNARY && expr.left {
    if expr.unary_op == .ADDRESS_OF || expr.unary_op == .DEREF {
      name, ok := resolve_buffer_name_from_expr(expr.left);
      return name, ok;
    }
  }
  if expr.kind == .SUBSCRIPT && expr.left {
    name, ok := resolve_buffer_name_from_expr(expr.left);
    return name, ok;
  }
  buffer_name, base_ok := resolve_ident_or_zero_deref(expr);
  if base_ok return buffer_name, true;
  if expr.kind == .MEMBER {
    member_root, member_field, member_ok := resolve_member_root_and_field(expr);
    if member_ok return tprint("%.%", member_root, member_field), true;
    member_path, path_ok := resolve_member_path(expr);
    if path_ok return member_path, true;
  }
  return "", false;
}

spv_member_component_index :: inline (access: IR_Member_Access_Kind) -> (s64, bool) {
  if access == .COMPONENT_X return 0, true;
  if access == .COMPONENT_Y return 1, true;
  if access == .COMPONENT_Z return 2, true;
  if access == .COMPONENT_W return 3, true;
  return -1, false;
}

spv_member_component_index_u32 :: inline (access: IR_Member_Access_Kind) -> (u32, bool) {
  idx, ok := spv_member_component_index(access);
  if !ok return 0, false;
  return cast(u32) idx, true;
}

spv_vector_component_in_range :: (vec_type: IR_SPV_Gen_Type, comp_index: s64) -> bool {
  if comp_index < 0 return false;
  if vec_type == .FLOAT2 return comp_index <= 1;
  if vec_type == .FLOAT3 return comp_index <= 2;
  if vec_type == .FLOAT4 return comp_index <= 3;
  return false;
}

spv_extract_vector_member :: (s: *IR_SPV_Gen_State, vec_id: s64, vec_type: IR_SPV_Gen_Type, access: IR_Member_Access_Kind, field_text: string) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(msg, ..args); }

  if access == .SWIZZLE_XY {
    if vec_type == .FLOAT2 return vec_id, .FLOAT2, true, {};
    swz := new_id(s);
    add_op(s, tprint("         % = OpVectorShuffle % % % 0 1",
                     id_text(swz),
                     id_text(s.id_float2),
                     id_text(vec_id),
                     id_text(vec_id)));
    return swz, .FLOAT2, true, {};
  }

  if access == .SWIZZLE_XYZ {
    if vec_type == .FLOAT3 return vec_id, .FLOAT3, true, {};
    if vec_type != .FLOAT4 return_err("swizzle '%': expected float3/float4, got %.", field_text, vec_type);
    swz := new_id(s);
    add_op(s, tprint("         % = OpVectorShuffle % % % 0 1 2",
                     id_text(swz),
                     id_text(s.id_float3),
                     id_text(vec_id),
                     id_text(vec_id)));
    return swz, .FLOAT3, true, {};
  }

  comp_index, comp_ok := spv_member_component_index(access);
  if !comp_ok return_err("unsupported vector member access '%'.", field_text);
  if !spv_vector_component_in_range(vec_type, comp_index) return_err("component '%' out of range for type %.", field_text, vec_type);
  scalar_value := new_id(s);
  add_op(s, tprint("         % = OpCompositeExtract % % %",
                   id_text(scalar_value),
                   id_text(s.id_float),
                   id_text(vec_id),
                   comp_index));
  return scalar_value, .FLOAT, true, {};
}

apply_buffer_base_index :: (s: *IR_SPV_Gen_State, buffer: *IR_SPV_Gen_Buffer, idx: s64) -> s64 {
  if !buffer || !buffer.has_base_index return idx;
  out := new_id(s);
  add_op(s, out, "OpIAdd", s.id_uint, buffer.base_index_id, idx);
  return out;
}
find_uniform_block :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Uniform_Block { return find_by_name(*s.uniform_blocks, name); }
find_function :: (s: *IR_SPV_Gen_State, name: string) -> *IR_Function {
  if !s return null;
  found := find_by_name(*s.functions, name);
  if found return found;

  target := canonical_callee_name(name);
  for 0..s.functions.count-1 {
    candidate := s.functions.data + it;
    if canonical_callee_name(candidate.name) == target return candidate;
  }
  return null;
}
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

get_f16_const :: (s: *IR_SPV_Gen_State, text: string) -> s64 {
  for s.const_f16 if it.text == text return it.id;
  id := new_id(s);
  array_add(*s.const_f16, .{text=text, id=id});
  return id;
}

get_null_const :: (s: *IR_SPV_Gen_State, type_id: s64) -> s64 {
  if type_id == 0 return 0;
  for s.const_null if it.type_id == type_id return it.id;
  id := new_id(s);
  array_add(*s.const_null, .{type_id=type_id, id=id});
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

get_current_inline_return_target :: (s: *IR_SPV_Gen_State) -> (s64, bool) {
  if s.inline_return_targets.count == 0 return 0, false;
  return s.inline_return_targets[s.inline_return_targets.count-1], true;
}

get_current_control_merge_target :: (s: *IR_SPV_Gen_State) -> (s64, bool) {
  if s.control_merge_targets.count == 0 return 0, false;
  return s.control_merge_targets[s.control_merge_targets.count-1], true;
}

get_current_inline_helper_context :: (s: *IR_SPV_Gen_State) -> (IR_SPV_Inline_Helper_Context, bool) {
  if s.inline_helper_contexts.count == 0 return .{}, false;
  return s.inline_helper_contexts[s.inline_helper_contexts.count-1], true;
}

// -----------------------------------------------------------------------------
// Type Mapping / Layout
// -----------------------------------------------------------------------------

init_base :: (s: *IR_SPV_Gen_State, buffers: [] IR_Compute_Buffer, bound_value: u32, use_physical_storage := false) -> (ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, make_diag(msg, ..args); }

  diag: IR_Diagnostic;
  if s.next_id < 1 s.next_id = 1;
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

    struct_type_name := "";
    if it.element_type.kind == .STRUCT {
      struct_type_name = it.element_type.struct_name;
    } else if it.element_type.kind == .FIXED_ARRAY && it.element_type.element_kind == .STRUCT {
      struct_type_name = it.element_type.element_struct_name;
    }
    if struct_type_name.count == 0 {
      return_err("SPIR-V generic backend: buffer '%' struct element is missing typed struct metadata.", it.name);
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
    buffer_info.element_struct_name = struct_type_name;
    buffer_info.element_type_id = element_struct_type_id;
    buffer_info.runtimearr_type_id = runtimearr_type_id;
    buffer_info.wrapper_struct_type_id = wrapper_struct_type_id;
    buffer_info.ptr_wrapper_type_id = ptr_wrapper_type_id;
    buffer_info.ptr_storage_element_type_id = ptr_storage_element_type_id;

    offset: s64 = 0;
    max_align: s64 = 1;
    cpu_offset: s64 = 0;
    cpu_max_align: s64 = 1;
    for struct_def.fields {
      if it.type.kind == .STRUCT && spv_kind_from_ir_type_for_layout(s, it.type) == .STRUCT {
        outer_field_name := it.name;
        nested_struct_name := it.type.struct_name;
        nested_struct := find_struct(s, nested_struct_name);
        if !nested_struct {
          return_err("SPIR-V generic backend: buffer struct '%' field '%' references unknown nested struct '%'.", struct_def.name, outer_field_name, nested_struct_name);
        }

        nested_offset := offset;
        nested_cpu_offset := cpu_offset;
        nested_max_align: s64 = 1;
        nested_cpu_max_align: s64 = 1;

        for nested_struct.fields {
          nested_field := it;
          if nested_field.type.kind == .STRUCT && spv_kind_from_ir_type_for_layout(s, nested_field.type) == .STRUCT {
            return_err("SPIR-V generic backend: buffer struct '%' field '%' nested struct field '%' has unsupported nested struct type '%'.", struct_def.name, outer_field_name, nested_field.name, nested_field.type.struct_name);
          }

          field_type := IR_SPV_Gen_Type.UNKNOWN;
          field_type_name := ir_string_first_non_empty(nested_field.type.display_name, nested_field.type.struct_name);
          field_struct_name := "";
          field_type_id: s64 = 0;
          field_ptr_storage_type_id: s64 = 0;
          field_size: s64 = 0;
          field_align: s64 = 1;
          is_array := false;
          array_count: s64 = 0;
          array_stride: s64 = 0;
          array_type_id: s64 = 0;
          array_length_const_id: s64 = 0;
          array_element_struct_name := "";
          array_element_type_id: s64 = 0;

          if nested_field.type.kind == .FIXED_ARRAY {
            field_type_name = ir_string_first_non_empty(nested_field.type.element_display_name, nested_field.type.element_struct_name);
            if nested_field.type.array_count <= 0 || nested_field.type.array_count > 0xFFFF_FFFF {
              return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' has invalid fixed array count %.", struct_def.name, outer_field_name, nested_field.name, nested_field.type.array_count);
            }

            if nested_field.type.element_kind == .STRUCT {
              nested_layout, nested_layout_ok, nested_layout_diag := register_buffer_layout_struct(s, nested_field.type.element_struct_name);
              if !nested_layout_ok return false, nested_layout_diag;
              field_type = .STRUCT;
              field_struct_name = nested_layout.name;
              field_type_id = nested_layout.type_id;
              field_align = nested_layout.max_align;
              field_size = nested_layout.stride;
              array_element_struct_name = nested_layout.name;
              array_element_type_id = nested_layout.type_id;
            } else {
              field_type = spv_kind_from_ir_type_kind(nested_field.type.element_kind);
              if field_type == .UNKNOWN || field_type == .STRUCT {
                return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' array element type '%' is unsupported.", struct_def.name, outer_field_name, nested_field.name, field_type_name);
              }
              field_type_id = type_id_from_kind(s, field_type);
              field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
              field_align = host_blit_align_for_kind(field_type);
              field_size = byte_size_of_kind(field_type);
            }
            if field_size <= 0 {
              return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' array element type '%' has unsupported layout.", struct_def.name, outer_field_name, nested_field.name, field_type_name);
            }
            array_count = nested_field.type.array_count;
            array_stride = align_up(field_size, field_align);
            field_size = array_stride * array_count;
            array_length_const_id = get_u32_const(s, cast(u32) array_count);
            array_type_id = new_id(s);
            add_debug_name(s, array_type_id, debug_type_name(s, tprint("%_%_%_array", struct_def.name, outer_field_name, nested_field.name)));
            is_array = true;
          } else {
            field_type = spv_kind_from_ir_type_for_layout(s, nested_field.type);
            if field_type == .UNKNOWN {
              return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' type '%' is unsupported.", struct_def.name, outer_field_name, nested_field.name, field_type_name);
            }
            field_type_id = type_id_from_kind(s, field_type);
            field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
            field_size = byte_size_of_kind(field_type);
            if field_size <= 0 {
              return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' has unsupported layout type '%'.", struct_def.name, outer_field_name, nested_field.name, field_type_name);
            }
            field_align = host_blit_align_for_kind(field_type);
          }

          nested_offset = align_up(nested_offset, field_align);
          if field_align > nested_max_align nested_max_align = field_align;

          cpu_field_align := host_blit_align_for_kind(field_type);
          nested_cpu_offset = align_up(nested_cpu_offset, cpu_field_align);
          if cpu_field_align > nested_cpu_max_align nested_cpu_max_align = cpu_field_align;

          if nested_cpu_offset != nested_offset {
            return_err("SPIR-V generic backend: buffer struct '%' nested field '%.%' is not CPU-blittable (cpu offset %, gpu offset %).", struct_def.name, outer_field_name, nested_field.name, nested_cpu_offset, nested_offset);
          }

          nested_field_name := tprint("%.%", outer_field_name, nested_field.name);
          field_index := buffer_info.fields.count;
          array_add(*buffer_info.fields, .{
            name = nested_field_name,
            index = field_index,
            type = field_type,
            struct_name = field_struct_name,
            type_id = field_type_id,
            ptr_storage_type_id = field_ptr_storage_type_id,
            is_array = is_array,
            array_count = array_count,
            array_stride = array_stride,
            array_type_id = array_type_id,
            array_length_const_id = array_length_const_id,
            array_element_struct_name = array_element_struct_name,
            array_element_type_id = array_element_type_id,
            offset = nested_offset,
          });
          add_debug_member_name(s, buffer_info.element_type_id, field_index, nested_field_name);
          nested_offset += field_size;
          nested_cpu_offset += field_size;
        }

        nested_stride := align_up(nested_offset, nested_max_align);
        nested_cpu_stride := align_up(nested_cpu_offset, nested_cpu_max_align);
        if nested_cpu_stride != nested_stride {
          return_err("SPIR-V generic backend: buffer struct '%' nested field '%' is not CPU-blittable (cpu stride %, gpu stride %).", struct_def.name, outer_field_name, nested_cpu_stride, nested_stride);
        }
        if nested_max_align > max_align max_align = nested_max_align;
        if nested_cpu_max_align > cpu_max_align cpu_max_align = nested_cpu_max_align;
        offset = nested_stride;
        cpu_offset = nested_cpu_stride;
        continue;
      }

      field_type := IR_SPV_Gen_Type.UNKNOWN;
      field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
      field_struct_name := "";
      field_type_id: s64 = 0;
      field_ptr_storage_type_id: s64 = 0;
      field_size: s64 = 0;
      field_align: s64 = 1;
      is_array := false;
      array_count: s64 = 0;
      array_stride: s64 = 0;
      array_type_id: s64 = 0;
      array_length_const_id: s64 = 0;
      array_element_struct_name := "";
      array_element_type_id: s64 = 0;

      if it.type.kind == .FIXED_ARRAY {
        field_type_name = ir_string_first_non_empty(it.type.element_display_name, it.type.element_struct_name);
        if it.type.array_count <= 0 || it.type.array_count > 0xFFFF_FFFF {
          return_err("SPIR-V generic backend: buffer struct '%' field '%' has invalid fixed array count %.", struct_def.name, it.name, it.type.array_count);
        }

        if it.type.element_kind == .STRUCT {
          nested_layout, nested_layout_ok, nested_layout_diag := register_buffer_layout_struct(s, it.type.element_struct_name);
          if !nested_layout_ok return false, nested_layout_diag;
          field_type = .STRUCT;
          field_struct_name = nested_layout.name;
          field_type_id = nested_layout.type_id;
          field_align = nested_layout.max_align;
          field_size = nested_layout.stride;
          array_element_struct_name = nested_layout.name;
          array_element_type_id = nested_layout.type_id;
        } else {
          field_type = spv_kind_from_ir_type_kind(it.type.element_kind);
          if field_type == .UNKNOWN || field_type == .STRUCT {
            return_err("SPIR-V generic backend: buffer struct '%' field '%' array element type '%' is unsupported.", struct_def.name, it.name, field_type_name);
          }
          field_type_id = type_id_from_kind(s, field_type);
          field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
          field_align = host_blit_align_for_kind(field_type);
          field_size = byte_size_of_kind(field_type);
        }
        if field_size <= 0 {
          return_err("SPIR-V generic backend: buffer struct '%' field '%' array element type '%' has unsupported layout.", struct_def.name, it.name, field_type_name);
        }
        array_count = it.type.array_count;
        array_stride = align_up(field_size, field_align);
        field_size = array_stride * array_count;
        array_length_const_id = get_u32_const(s, cast(u32) array_count);
        array_type_id = new_id(s);
        add_debug_name(s, array_type_id, debug_type_name(s, tprint("%_%_array", struct_def.name, it.name)));
        is_array = true;
      } else {
        field_type = spv_kind_from_ir_type_for_layout(s, it.type);
        if field_type == .UNKNOWN {
          return_err("SPIR-V generic backend: buffer struct '%' field '%' type '%' is unsupported.", struct_def.name, it.name, field_type_name);
        }
        field_type_id = type_id_from_kind(s, field_type);
        field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
        field_size = byte_size_of_kind(field_type);
        if field_size <= 0 {
          return_err("SPIR-V generic backend: buffer struct '%' field '%' has unsupported layout type '%'.", struct_def.name, it.name, field_type_name);
        }
        field_align = host_blit_align_for_kind(field_type);
      }

      offset = align_up(offset, field_align);
      if field_align > max_align max_align = field_align;

      cpu_field_align := host_blit_align_for_kind(field_type);
      cpu_offset = align_up(cpu_offset, cpu_field_align);
      if cpu_field_align > cpu_max_align cpu_max_align = cpu_field_align;

      if cpu_offset != offset {
        return_err("SPIR-V generic backend: buffer struct '%' field '%' is not CPU-blittable (cpu offset %, gpu offset %).", struct_def.name, it.name, cpu_offset, offset);
      }

      field_index := buffer_info.fields.count;
      array_add(*buffer_info.fields, .{
        name = it.name,
        index = field_index,
        type = field_type,
        struct_name = field_struct_name,
        type_id = field_type_id,
        ptr_storage_type_id = field_ptr_storage_type_id,
        is_array = is_array,
        array_count = array_count,
        array_stride = array_stride,
        array_type_id = array_type_id,
        array_length_const_id = array_length_const_id,
        array_element_struct_name = array_element_struct_name,
        array_element_type_id = array_element_type_id,
        offset = offset,
      });
      add_debug_member_name(s, buffer_info.element_type_id, field_index, it.name);
      offset += field_size;
      cpu_offset += field_size;
    }
    buffer_info.array_stride = align_up(offset, max_align);
    cpu_stride := align_up(cpu_offset, cpu_max_align);
    if cpu_stride != buffer_info.array_stride {
      return_err("SPIR-V generic backend: buffer struct '%' is not CPU-blittable (cpu stride %, gpu stride %).", struct_def.name, cpu_stride, buffer_info.array_stride);
    }
    debug_element_type_name := element_type_name;
    if buffer_info.element_kind == .STRUCT && buffer_info.element_struct_name.count != 0 {
      debug_element_type_name = buffer_info.element_struct_name;
    }
    add_debug_name(s, buffer_info.element_type_id, debug_type_name(s, debug_element_type_name));
    add_debug_name(s, buffer_info.runtimearr_type_id, debug_type_name(s, tprint("%_data_array", buffer_info.name)));
    add_debug_name(s, buffer_info.wrapper_struct_type_id, debug_type_name(s, tprint("%_buffer", buffer_info.name)));
    add_debug_member_name(s, buffer_info.wrapper_struct_type_id, 0, "data");
    array_add(*s.buffers, buffer_info);
  }

  return true, diag;
}


load_builtin_vec3_component :: (s: *IR_SPV_Gen_State, builtin_var_id: s64, component_index: s64) -> s64 {
  assert(component_index >= 0 && component_index <= 2);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain", s.id_ptr_input_uint, builtin_var_id, get_u32_const(s, cast(u32) component_index));
  return add_op(s, new_id(s), "OpLoad", s.id_uint, ptr);
}

load_builtin_u32 :: (s: *IR_SPV_Gen_State, builtin_var_id: s64) -> s64 {
  return add_op(s, new_id(s), "OpLoad", s.id_uint, builtin_var_id);
}


physical_aligned_suffix :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> string {
  if !s.use_physical_storage return "";
  align := host_blit_align_for_kind(kind);
  if align <= 0 align = 4;
  assert((align & (align - 1)) == 0);
  return tprint(" Aligned %", align);
}

emit_load :: (s: *IR_SPV_Gen_State, result_id: s64, type_id: s64, ptr_id: s64, kind: IR_SPV_Gen_Type, needs_physical_align := false) {
  suffix := "";
  if needs_physical_align suffix = physical_aligned_suffix(s, kind);
  if suffix.count == 0 {
    add_op(s, result_id, "OpLoad", type_id, ptr_id);
  } else {
    add_op(s, tprint("         % = OpLoad % %%", id_text(result_id), id_text(type_id), id_text(ptr_id), suffix));
  }
}

emit_store :: (s: *IR_SPV_Gen_State, ptr_id: s64, value_id: s64, kind: IR_SPV_Gen_Type, needs_physical_align := false) {
  suffix := "";
  if needs_physical_align suffix = physical_aligned_suffix(s, kind);
  if suffix.count == 0 {
    add_op(s, "OpStore", ptr_id, value_id);
  } else {
    add_op(s, tprint("               OpStore % %%", id_text(ptr_id), id_text(value_id), suffix));
  }
}

spv_access_chain1 :: inline (s: *IR_SPV_Gen_State, ptr_type_id: s64, base_id: s64, index0_id: s64) -> s64 {
  return add_op(s, new_id(s), "OpAccessChain", ptr_type_id, base_id, index0_id);
}

spv_access_chain2 :: inline (s: *IR_SPV_Gen_State, ptr_type_id: s64, base_id: s64, index0_id: s64, index1_id: s64) -> s64 {
  return add_op(s, new_id(s), "OpAccessChain", ptr_type_id, base_id, index0_id, index1_id);
}

spv_load :: inline (s: *IR_SPV_Gen_State, type_id: s64, ptr_id: s64) -> s64 {
  return add_op(s, new_id(s), "OpLoad", type_id, ptr_id);
}

spv_extinst1 :: inline (s: *IR_SPV_Gen_State, type_id: s64, op_name: string, a_id: s64) -> s64 {
  out := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % % %",
                   id_text(out), id_text(type_id), id_text(s.id_extinst), op_name, id_text(a_id)));
  return out;
}

spv_extinst2 :: inline (s: *IR_SPV_Gen_State, type_id: s64, op_name: string, a_id: s64, b_id: s64) -> s64 {
  out := new_id(s);
  add_op(s, tprint("         % = OpExtInst % % % % %",
                   id_text(out), id_text(type_id), id_text(s.id_extinst), op_name, id_text(a_id), id_text(b_id)));
  return out;
}

spv_append_module_preamble :: (sb: *String_Builder, s: *IR_SPV_Gen_State, memory_model: string, use_physical_storage := false) {
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
  a(sb, "% % = OpFunction % None %\n", function_indent, id_text(s.id_main), id_text(s.id_void), id_text(s.id_fn_void));
  a(sb, "% % = OpLabel\n", label_indent, id_text(entry_label));
  append_and_steal_buffers(sb, *s.local_var_lines);
  append_and_steal_buffers(sb, *s.op_lines);
  if !s.last_op_is_terminator a(sb, "OpReturn");
  a(sb, "OpFunctionEnd");
}

align_up :: (value: s64, alignment: s64) -> s64 {
  if alignment <= 1 return value;
  mask := alignment - 1;
  return (value + mask) & ~mask;
}

host_blit_align_for_kind :: (kind: IR_SPV_Gen_Type) -> s64 {
  if kind == .FLOAT16 return 2;
  if kind == .INT64 || kind == .UINT64 return 8;
  if kind == .INT || kind == .UINT || kind == .FLOAT || kind == .FLOAT2 ||
     kind == .FLOAT3 || kind == .FLOAT4 || kind == .FLOAT2X2 || kind == .BOOL return 4;
  return 4;
}

find_buffer_field :: (buffer: *IR_SPV_Gen_Buffer, name: string) -> *IR_SPV_Gen_Buffer_Field {
  assert(buffer != null);
  return find_by_name(*buffer.fields, name);
}

find_buffer_layout_struct :: (s: *IR_SPV_Gen_State, name: string) -> *IR_SPV_Gen_Buffer_Layout_Struct {
  return find_by_name(*s.buffer_layout_structs, name);
}

find_buffer_layout_field :: (layout: *IR_SPV_Gen_Buffer_Layout_Struct, name: string) -> *IR_SPV_Gen_Buffer_Field {
  assert(layout != null);
  return find_by_name(*layout.fields, name);
}

register_buffer_layout_struct :: (s: *IR_SPV_Gen_State, struct_name: string) -> (layout: *IR_SPV_Gen_Buffer_Layout_Struct, ok: bool, diag: IR_Diagnostic) {
  if struct_name.count == 0 return null, false, make_diag("buffer layout struct is missing a name.");

  existing := find_buffer_layout_struct(s, struct_name);
  if existing return existing, true, {};

  struct_def := find_struct(s, struct_name);
  if !struct_def return null, false, make_diag("buffer layout struct '%' is missing.", struct_name);

  array_add(*s.buffer_layout_structs, .{
    name = struct_name,
    type_id = new_id(s),
  });
  layout := find_buffer_layout_struct(s, struct_name);
  assert(layout != null);

  offset: s64 = 0;
  max_align: s64 = 1;
  cpu_offset: s64 = 0;
  cpu_max_align: s64 = 1;

  for struct_def.fields {
    field_type := IR_SPV_Gen_Type.UNKNOWN;
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    field_struct_name := "";
    field_type_id: s64 = 0;
    field_ptr_storage_type_id: s64 = 0;
    field_size: s64 = 0;
    field_align: s64 = 1;
    is_array := false;
    array_count: s64 = 0;
    array_stride: s64 = 0;
    array_type_id: s64 = 0;
    array_length_const_id: s64 = 0;
    array_element_struct_name := "";
    array_element_type_id: s64 = 0;

    if it.type.kind == .STRUCT {
      return null, false, make_diag("buffer layout struct '%' field '%' nested struct type '%' is unsupported.", struct_name, it.name, it.type.struct_name);
    }

    if it.type.kind == .FIXED_ARRAY {
      if it.type.array_count <= 0 || it.type.array_count > 0xFFFF_FFFF {
        return null, false, make_diag("buffer layout struct '%' field '%' has invalid fixed array count %.", struct_name, it.name, it.type.array_count);
      }

      if it.type.element_kind == .STRUCT {
        nested_layout, nested_ok, nested_diag := register_buffer_layout_struct(s, it.type.element_struct_name);
        if !nested_ok return null, false, nested_diag;
        field_type = .STRUCT;
        field_struct_name = nested_layout.name;
        field_type_id = nested_layout.type_id;
        field_align = nested_layout.max_align;
        field_size = nested_layout.stride;
        array_element_struct_name = nested_layout.name;
        array_element_type_id = nested_layout.type_id;
      } else {
        field_type = spv_kind_from_ir_type_kind(it.type.element_kind);
        field_type_name = ir_string_first_non_empty(it.type.element_display_name, it.type.element_struct_name);
        if field_type == .UNKNOWN || field_type == .STRUCT {
          return null, false, make_diag("buffer layout struct '%' field '%' array element type '%' is unsupported.", struct_name, it.name, field_type_name);
        }
        field_type_id = type_id_from_kind(s, field_type);
        field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
        field_align = host_blit_align_for_kind(field_type);
        field_size = byte_size_of_kind(field_type);
      }

      if field_size <= 0 {
        return null, false, make_diag("buffer layout struct '%' field '%' array element type '%' has unsupported layout.", struct_name, it.name, field_type_name);
      }
      array_count = it.type.array_count;
      array_stride = align_up(field_size, field_align);
      field_size = array_stride * array_count;
      array_length_const_id = get_u32_const(s, cast(u32) array_count);
      array_type_id = new_id(s);
      add_debug_name(s, array_type_id, debug_type_name(s, tprint("%_%_array", struct_name, it.name)));
      is_array = true;
    } else {
      field_type = spv_kind_from_ir_type_for_layout(s, it.type);
      if field_type == .UNKNOWN {
        return null, false, make_diag("buffer layout struct '%' field '%' type '%' is unsupported.", struct_name, it.name, field_type_name);
      }
      field_type_id = type_id_from_kind(s, field_type);
      field_ptr_storage_type_id = storage_ptr_type_id_from_kind(s, field_type);
      field_size = byte_size_of_kind(field_type);
      if field_size <= 0 {
        return null, false, make_diag("buffer layout struct '%' field '%' type '%' has unsupported layout.", struct_name, it.name, field_type_name);
      }
      field_align = host_blit_align_for_kind(field_type);
    }

    offset = align_up(offset, field_align);
    if field_align > max_align max_align = field_align;

    cpu_field_align := ifx field_type == .STRUCT then field_align else host_blit_align_for_kind(field_type);
    cpu_offset = align_up(cpu_offset, cpu_field_align);
    if cpu_field_align > cpu_max_align cpu_max_align = cpu_field_align;

    if cpu_offset != offset {
      return null, false, make_diag("buffer layout struct '%' field '%' is not CPU-blittable (cpu offset %, gpu offset %).", struct_name, it.name, cpu_offset, offset);
    }

    field_index := layout.fields.count;
    array_add(*layout.fields, .{
      name = it.name,
      index = field_index,
      type = field_type,
      struct_name = field_struct_name,
      type_id = field_type_id,
      ptr_storage_type_id = field_ptr_storage_type_id,
      is_array = is_array,
      array_count = array_count,
      array_stride = array_stride,
      array_type_id = array_type_id,
      array_length_const_id = array_length_const_id,
      array_element_struct_name = array_element_struct_name,
      array_element_type_id = array_element_type_id,
      offset = offset,
    });
    add_debug_member_name(s, layout.type_id, field_index, it.name);
    offset += field_size;
    cpu_offset += field_size;
  }

  layout.max_align = max_align;
  layout.stride = align_up(offset, max_align);
  cpu_stride := align_up(cpu_offset, cpu_max_align);
  if cpu_stride != layout.stride {
    return null, false, make_diag("buffer layout struct '%' is not CPU-blittable (cpu stride %, gpu stride %).", struct_name, cpu_stride, layout.stride);
  }

  return layout, true, {};
}

make_unique_local_struct_name :: (s: *IR_SPV_Gen_State, requested: string) -> string {
  if !find_local_struct(s, requested) return requested;
  return tprint("%__%", requested, new_id(s));
}

alloc_local_struct :: (s: *IR_SPV_Gen_State, name: string, type_name: string) -> (local_struct: *IR_SPV_Gen_Local_Struct, ok: bool, diag: IR_Diagnostic) {
  struct_def := find_struct(s, type_name);
  if !struct_def return null, false, make_diag("unknown local struct type '%'.", type_name);

  local_struct: IR_SPV_Gen_Local_Struct;
  local_struct.name = name;
  local_struct.type_name = type_name;
  for struct_def.fields {
    field_type := spv_kind_from_ir_type(it.type);
    field_type_name := ir_string_first_non_empty(it.type.display_name, it.type.struct_name);
    if field_type == .UNKNOWN || field_type == .STRUCT {
      nested_type_name := spv_struct_name_from_ir_type(it.type);
      nested_def := find_struct(s, nested_type_name);
      if !nested_def return null, false, make_diag("local struct '%' field '%' has unsupported type '%'.", type_name, it.name, field_type_name);
      
      nested_name := make_unique_local_struct_name(s, tprint("%.%", name, it.name));
      _, nested_ok, nested_diag := alloc_local_struct(s, nested_name, nested_type_name);
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
      return null, false, make_diag("local struct '%' field '%' type '%' has no function pointer type.", type_name, it.name, field_type_name);
    }
    field_ptr := new_id(s);
    field_zero := get_null_const(s, type_id_from_kind(s, field_type));
    add_local_decl(s, "% = OpVariable % Function %", id_text(field_ptr), id_text(field_ptr_type), id_text(field_zero));
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

store_value_in_local_struct_alias :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, value_id: s64, value_type: IR_SPV_Gen_Type) -> (ok: bool, diag: IR_Diagnostic) {
  if !dst return false, make_diag("null destination struct for alias store.");

  if dst.fields.count == 1 {
    field := dst.fields[0];
    if field.type == value_type {
      type_id := type_id_from_kind(s, value_type);
      if type_id == 0 return false, make_diag("unsupported alias store type % for '%'.", value_type, dst.type_name);
      add_op(s, "OpStore", field.ptr_id, value_id);
      return true, {};
    }
  }

  expected_count: s64 = 0;
  vector_type_id: s64 = 0;
  if value_type == .FLOAT2 { expected_count = 2; vector_type_id = s.id_float2; }
  if value_type == .FLOAT3 { expected_count = 3; vector_type_id = s.id_float3; }
  if value_type == .FLOAT4 { expected_count = 4; vector_type_id = s.id_float4; }
  if expected_count != dst.fields.count || expected_count == 0 {
    return false, make_diag("cannot map alias value type % into struct '%'.", value_type, dst.type_name);
  }

  for dst.fields {
    if it.type != .FLOAT || it.nested_struct_name.count != 0 {
      return false, make_diag("struct '%' is not a flat float alias.", dst.type_name);
    }
    component_value := new_id(s);
    add_op(s, tprint("         % = OpCompositeExtract % % %",
                     id_text(component_value),
                     id_text(s.id_float),
                     id_text(value_id),
                     it_index));
    add_op(s, "OpStore", it.ptr_id, component_value);
  }
  _ = vector_type_id;
  return true, {};
}

pack_local_struct_alias_to_value :: (s: *IR_SPV_Gen_State, src: *IR_SPV_Gen_Local_Struct, dst_type: IR_SPV_Gen_Type) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  if !src return 0, .UNKNOWN, false, make_diag("null source struct for alias pack.");

  if src.fields.count == 1 {
    field := src.fields[0];
    if field.type == dst_type {
      type_id := type_id_from_kind(s, dst_type);
      if type_id == 0 return 0, .UNKNOWN, false, make_diag("unsupported alias pack type % from '%'.", dst_type, src.type_name);
      value := new_id(s);
      add_op(s, value, "OpLoad", type_id, field.ptr_id);
      return value, dst_type, true, {};
    }
  }

  expected_count: s64 = 0;
  vector_type_id: s64 = 0;
  if dst_type == .FLOAT2 { expected_count = 2; vector_type_id = s.id_float2; }
  if dst_type == .FLOAT3 { expected_count = 3; vector_type_id = s.id_float3; }
  if dst_type == .FLOAT4 { expected_count = 4; vector_type_id = s.id_float4; }
  if expected_count != src.fields.count || expected_count == 0 {
    return 0, .UNKNOWN, false, make_diag("cannot map struct '%' into alias type %.", src.type_name, dst_type);
  }

  component_values: [4]s64;
  for src.fields {
    if it.type != .FLOAT || it.nested_struct_name.count != 0 {
      return 0, .UNKNOWN, false, make_diag("struct '%' is not a flat float alias.", src.type_name);
    }
    component_values[it_index] = new_id(s);
    add_op(s, component_values[it_index], "OpLoad", s.id_float, it.ptr_id);
  }

  out := new_id(s);
  if dst_type == .FLOAT2 {
    add_op(s, tprint("         % = OpCompositeConstruct % % %",
                     id_text(out),
                     id_text(vector_type_id),
                     id_text(component_values[0]),
                     id_text(component_values[1])));
    return out, dst_type, true, {};
  }
  if dst_type == .FLOAT3 {
    add_op(s, tprint("         % = OpCompositeConstruct % % % %",
                     id_text(out),
                     id_text(vector_type_id),
                     id_text(component_values[0]),
                     id_text(component_values[1]),
                     id_text(component_values[2])));
    return out, dst_type, true, {};
  }
  if dst_type == .FLOAT4 {
    add_op(s, tprint("         % = OpCompositeConstruct % % % % %",
                     id_text(out),
                     id_text(vector_type_id),
                     id_text(component_values[0]),
                     id_text(component_values[1]),
                     id_text(component_values[2]),
                     id_text(component_values[3])));
    return out, dst_type, true, {};
  }

  return 0, .UNKNOWN, false, make_diag("cannot pack struct '%' into alias type %.", src.type_name, dst_type);
}

init_local_struct_from_expr :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
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

  expr_struct_name := spv_struct_name_from_ir_expr_result(expr);
  if expr.kind != .CONSTRUCTOR || expr_struct_name != dst.type_name {
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
    if arg_expr && arg_expr.kind == .BINARY &&
       arg_expr.left && arg_expr.left.kind == .IDENT {
      op, op_ok := ir_expr_binary_op_text(arg_expr);
      if op_ok && op == "=" {
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
    }

    while positional_index < resolved_args.count && resolved_args[positional_index] positional_index += 1;
    if positional_index >= resolved_args.count {
      return false, make_diag("constructor for '%' has too many positional arguments.", dst.type_name);
    }
    resolved_args[positional_index] = arg_expr;
    positional_index += 1;
  }

  for dst.fields {
    arg_expr := resolved_args[it_index];
    if !arg_expr {
      // Local struct fields are zero-initialized at allocation time; omitted constructor
      // members keep that default value.
      continue;
    }
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
  
  diag: IR_Diagnostic;
  if !subscript || subscript.kind != .SUBSCRIPT return_err("expected subscript expression for buffer struct field access.");

  buffer_name: string;
  field_path := field_name;
  if subscript.left && subscript.left.kind == .MEMBER {
    resolved_buffer_name, resolved_field_path, resolved_ok := resolve_buffer_prefix_and_field_path(s, subscript.left);
    if resolved_ok {
      buffer_name = resolved_buffer_name;
      if resolved_field_path.count > 0 {
        field_path = tprint("%.%", resolved_field_path, field_name);
      }
    }
  }
  if buffer_name.count == 0 {
    base_name, base_ok := resolve_buffer_name_from_expr(subscript.left);
    if !base_ok return_err("subscript base must resolve to a buffer identifier/member.");
    buffer_name = base_name;
  }

  buffer := find_buffer(s, buffer_name);
  if !buffer return_err("unknown subscript base '%'.", buffer_name);
  
  if buffer.element_kind != .STRUCT return_err("buffer '%' is not a struct buffer.", buffer.name);
  field := find_buffer_field(buffer, field_path);
  if !field {
    diag.message = tprint("unknown field '%.%'.", buffer.name, field_path);
    return 0, .UNKNOWN, false, diag;
  }
  if field.is_array return_err("buffer struct field '%.%' is an array; index it first.", buffer.name, field_name);

  idx_id, idx_type, idx_ok, idx_diag := emit_expr(s, subscript.right);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;
  idx_id, idx_ok, idx_diag = coerce_to_kind(s, idx_id, idx_type, .UINT);
  if !idx_ok return 0, .UNKNOWN, false, idx_diag;
  idx_id = apply_buffer_base_index(s, buffer, idx_id);

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

emit_buffer_struct_field_ptr_from_member_expr :: (s: *IR_SPV_Gen_State, member_expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  diag: IR_Diagnostic;
  if !member_expr || member_expr.kind != .MEMBER return_err("expected member expression for struct-buffer field access.");

  buffer_name, field_path, path_ok := resolve_buffer_prefix_and_field_path(s, member_expr);
  if !path_ok return_err("member root must resolve to a buffer identifier.");
  buffer := find_buffer(s, buffer_name);
  if !buffer return_err("unknown buffer '%'.", buffer_name);
  if buffer.element_kind != .STRUCT return_err("buffer '%' is not a struct buffer.", buffer.name);
  if field_path.count == 0 return_err("buffer '%' must be accessed through a field.", buffer.name);
  field := find_buffer_field(buffer, field_path);
  if !field return_err("unknown field '%.%'.", buffer.name, field_path);
  if field.is_array return_err("buffer struct field '%.%' is an array; index it first.", buffer.name, field_path);

  struct_idx := ifx buffer.has_base_index then buffer.base_index_id else s.id_uint_0;
  field_ptr_type_id := storage_ptr_type_id_from_kind(s, field.type);
  if field_ptr_type_id == 0 return_err("unsupported struct buffer field type for '%.%'.", buffer.name, field.name);

  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain",
    field_ptr_type_id,
    buffer.var_id,
    s.id_int_0,
    struct_idx,
    field_index_id);
  return ptr, field.type, true, diag;
}

emit_buffer_struct_array_element_ptr :: (s: *IR_SPV_Gen_State, member_expr: *IR_Expr, index_expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  diag: IR_Diagnostic;
  if !member_expr || member_expr.kind != .MEMBER return_err("expected member expression for struct-buffer array element access.");

  buffer_name, field_path, path_ok := resolve_buffer_prefix_and_field_path(s, member_expr);
  if !path_ok return_err("struct-buffer array base must resolve to a buffer identifier/member.");
  buffer := find_buffer(s, buffer_name);

  if !buffer return_err("unknown struct-buffer array base '%'.", buffer_name);
  if buffer.element_kind != .STRUCT return_err("buffer '%' is not a struct buffer.", buffer.name);
  if field_path.count == 0 return_err("buffer '%' array access requires a field path.", buffer.name);

  field := find_buffer_field(buffer, field_path);
  if !field return_err("unknown field '%.%'.", buffer.name, field_path);
  if !field.is_array return_err("buffer struct field '%.%' is not an array.", buffer.name, field.name);

  struct_idx := ifx buffer.has_base_index then buffer.base_index_id else s.id_uint_0;
  elem_idx, elem_type, elem_ok, elem_diag := emit_expr(s, index_expr);
  if !elem_ok return 0, .UNKNOWN, false, elem_diag;
  elem_idx, elem_ok, elem_diag = coerce_to_kind(s, elem_idx, elem_type, .UINT);
  if !elem_ok return 0, .UNKNOWN, false, elem_diag;

  elem_ptr_type_id := storage_ptr_type_id_from_kind(s, field.type);
  if elem_ptr_type_id == 0 return_err("unsupported struct-buffer array element type for '%.%'.", buffer.name, field.name);

  field_index_id := get_i32_const(s, cast(s32) field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain",
    elem_ptr_type_id,
    buffer.var_id,
    s.id_int_0,
    struct_idx,
    field_index_id,
    elem_idx);
  return ptr, field.type, true, diag;
}

emit_buffer_struct_array_element_field_ptr :: (s: *IR_SPV_Gen_State, subscript_expr: *IR_Expr, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  diag: IR_Diagnostic;
  if !subscript_expr || subscript_expr.kind != .SUBSCRIPT return_err("expected subscript expression for struct-buffer array field access.");
  if !subscript_expr.left || subscript_expr.left.kind != .MEMBER return_err("struct-buffer array field access requires a member array base.");

  buffer_name, field_path, path_ok := resolve_buffer_prefix_and_field_path(s, subscript_expr.left);
  if !path_ok return_err("struct-buffer array field access requires a resolvable buffer member base.");

  buffer := find_buffer(s, buffer_name);
  if field_path.count == 0 {
    direct_ptr, direct_type, direct_ok, direct_diag := emit_buffer_struct_field_ptr(s, subscript_expr, field_name);
    return direct_ptr, direct_type, direct_ok, direct_diag;
  }

  if !buffer return_err("unknown buffer '%'.", buffer_name);
  if buffer.element_kind != .STRUCT return_err("buffer '%' is not a struct buffer.", buffer.name);

  field := find_buffer_field(buffer, field_path);
  if !field return_err("unknown field '%.%'.", buffer.name, field_path);
  if !field.is_array return_err("buffer struct field '%.%' is not an array.", buffer.name, field.name);
  if field.array_element_struct_name.count == 0 return_err("buffer struct field '%.%' does not contain struct elements.", buffer.name, field.name);

  layout := find_buffer_layout_struct(s, field.array_element_struct_name);
  if !layout return_err("buffer struct field '%.%' references unknown element struct '%'.", buffer.name, field.name, field.array_element_struct_name);
  nested_field := find_buffer_layout_field(layout, field_name);
  if !nested_field return_err("unknown struct-buffer array element field '%.%[%].%'.", buffer.name, field.name, "*", field_name);
  if nested_field.is_array return_err("struct-buffer array element field '%.%[%].%' is an array; index it first.", buffer.name, field.name, "*", field_name);
  if nested_field.ptr_storage_type_id == 0 return_err("unsupported struct-buffer array element field type for '%.%[%].%'.", buffer.name, field.name, "*", field_name);

  struct_idx := ifx buffer.has_base_index then buffer.base_index_id else s.id_uint_0;
  elem_idx, elem_type, elem_ok, elem_diag := emit_expr(s, subscript_expr.right);
  _ = elem_type;
  if !elem_ok return 0, .UNKNOWN, false, elem_diag;
  elem_idx, elem_ok, elem_diag = coerce_to_kind(s, elem_idx, elem_type, .UINT);
  if !elem_ok return 0, .UNKNOWN, false, elem_diag;

  field_index_id := get_i32_const(s, cast(s32) field.index);
  nested_field_index_id := get_i32_const(s, cast(s32) nested_field.index);
  ptr := new_id(s);
  add_op(s, ptr, "OpAccessChain",
    nested_field.ptr_storage_type_id,
    buffer.var_id,
    s.id_int_0,
    struct_idx,
    field_index_id,
    elem_idx,
    nested_field_index_id);
  return ptr, nested_field.type, true, diag;
}

emit_physical_root_pod_field_ptr_from_member_expr :: (s: *IR_SPV_Gen_State, member_expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  diag: IR_Diagnostic;
  if !s.use_physical_storage || s.physical_root_name.count == 0 || s.physical_root_struct_name.count == 0 || s.physical_root_var_id == 0 {
    return_err("physical-root POD field access is unavailable.");
  }
  if !member_expr || member_expr.kind != .MEMBER return_err("expected member expression for physical-root POD access.");

  full_path, path_ok := resolve_member_path(member_expr);
  if !path_ok return_err("physical-root POD access requires a resolvable member path.");
  segments: [..] string;
  split_dotted_path(full_path, *segments);
  if segments.count < 2 || segments[0] != s.physical_root_name return_err("member expression '%' is not rooted at '%'.", full_path, s.physical_root_name);

  current_ptr := s.physical_root_var_id;
  current_struct_name := s.physical_root_struct_name;
  for i: 1..segments.count-1 {
    current_struct := find_struct(s, current_struct_name);
    if !current_struct return_err("missing physical-root struct '%' while resolving '%'.", current_struct_name, full_path);
    field_index := find_field_index_by_name(current_struct, segments[i]);
    if field_index < 0 return_err("field '%' not found in '%' while resolving '%'.", segments[i], current_struct_name, full_path);
    field := current_struct.fields[field_index];
    is_last := i == segments.count-1;
    field_index_id := get_i32_const(s, cast(s32) field_index);

    if !is_last {
      if field.type.kind != .STRUCT || field.type.struct_name.count == 0 {
        return_err("physical-root POD access reached unsupported intermediate field '%.%'.", current_struct_name, field.name);
      }
      next_ptr_type_id := ps_get_storage_struct_ptr_type(s, *s.physical_ps_infos, *s.physical_storage_struct_ptr_types, field.type.struct_name);
      next_ptr_access := new_id(s);
      add_op(s, tprint("         % = OpAccessChain % % %",
                        id_text(next_ptr_access),
                        id_text(next_ptr_type_id),
                        id_text(current_ptr),
                        id_text(field_index_id)));
      current_ptr = next_ptr_access;
      current_struct_name = field.type.struct_name;
      continue;
    }

    if field.type.kind == .STRUCT return_err("physical-root POD field '%.%' must be accessed through a member.", current_struct_name, field.name);
    if field.type.kind == .POINTER return_err("physical-root POD access does not apply to resource pointer field '%.%'.", current_struct_name, field.name);
    if field.type.kind == .FIXED_ARRAY return_err("physical-root POD array field '%.%' must be indexed first.", current_struct_name, field.name);

    field_type := spv_kind_from_ir_type(field.type);
    field_ptr_type_id := storage_ptr_type_id_from_kind(s, field_type);
    if field_ptr_type_id == 0 return_err("unsupported physical-root POD field type for '%.%'.", current_struct_name, field.name);
    ptr := new_id(s);
    add_op(s, tprint("         % = OpAccessChain % % %",
                      id_text(ptr),
                      id_text(field_ptr_type_id),
                      id_text(current_ptr),
                      id_text(field_index_id)));
    return ptr, field_type, true, diag;
  }

  return_err("physical-root POD field access path '%' is incomplete.", full_path);
}

emit_physical_root_pod_field_value_from_member_expr :: (s: *IR_SPV_Gen_State, member_expr: *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  diag: IR_Diagnostic;
  if !s.use_physical_storage || s.physical_root_name.count == 0 || s.physical_root_struct_name.count == 0 || s.physical_root_var_id == 0 {
    return_err("physical-root POD field access is unavailable.");
  }
  if !member_expr || member_expr.kind != .MEMBER return_err("expected member expression for physical-root POD access.");

  full_path, path_ok := resolve_member_path(member_expr);
  if !path_ok return_err("physical-root POD access requires a resolvable member path.");
  segments: [..] string;
  split_dotted_path(full_path, *segments);
  if segments.count < 2 || segments[0] != s.physical_root_name return_err("member expression '%' is not rooted at '%'.", full_path, s.physical_root_name);

  current_ptr := s.physical_root_var_id;
  current_struct_name := s.physical_root_struct_name;
  for i: 1..segments.count-1 {
    current_struct := find_struct(s, current_struct_name);
    if !current_struct return_err("missing physical-root struct '%' while resolving '%'.", current_struct_name, full_path);
    field_index := find_field_index_by_name(current_struct, segments[i]);
    if field_index < 0 return_err("field '%' not found in '%' while resolving '%'.", segments[i], current_struct_name, full_path);
    field := current_struct.fields[field_index];
    is_last := i == segments.count-1;
    field_index_id := get_i32_const(s, cast(s32) field_index);

    if !is_last {
      if field.type.kind != .STRUCT || field.type.struct_name.count == 0 {
        return_err("physical-root POD access reached unsupported intermediate field '%.%'.", current_struct_name, field.name);
      }
      next_ptr_type_id := ps_get_storage_struct_ptr_type(s, *s.physical_ps_infos, *s.physical_storage_struct_ptr_types, field.type.struct_name);
      next_ptr_access := new_id(s);
      add_op(s, tprint("         % = OpAccessChain % % %",
                        id_text(next_ptr_access),
                        id_text(next_ptr_type_id),
                        id_text(current_ptr),
                        id_text(field_index_id)));
      current_ptr = next_ptr_access;
      current_struct_name = field.type.struct_name;
      continue;
    }

    if field.type.kind == .STRUCT return_err("physical-root POD field '%.%' must be accessed through a member.", current_struct_name, field.name);
    if field.type.kind == .POINTER return_err("physical-root POD access does not apply to resource pointer field '%.%'.", current_struct_name, field.name);
    if field.type.kind == .FIXED_ARRAY return_err("physical-root POD array field '%.%' must be indexed first.", current_struct_name, field.name);

    ps_info := find_ps_struct_info(*s.physical_ps_infos, current_struct_name);
    if !ps_info return_err("missing pointer-struct type info for '%'.", current_struct_name);
    current_value_id := new_id(s);
    add_op(s, tprint("         % = OpLoad % %", id_text(current_value_id), id_text(ps_info.type_id), id_text(current_ptr)));

    field_type := spv_kind_from_ir_type(field.type);
    field_type_id := type_id_from_kind(s, field_type);
    if field_type_id == 0 return_err("unsupported physical-root POD field type for '%.%'.", current_struct_name, field.name);
    value_id := new_id(s);
    add_op(s, tprint("         % = OpCompositeExtract % % %", id_text(value_id), id_text(field_type_id), id_text(current_value_id), field_index));
    return value_id, field_type, true, diag;
  }

  return_err("physical-root POD field access path '%' is incomplete.", full_path);
}

emit_buffer_struct_reinterpret_const_subscript_ptr :: (s: *IR_SPV_Gen_State, buffer: *IR_SPV_Gen_Buffer, subscript_expr: *IR_Expr) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

  assert(buffer != null);
  if !subscript_expr || subscript_expr.kind != .SUBSCRIPT return_err("expected subscript expression for struct-buffer reinterpret access.");

  is_cast_reinterpret_base :: (expr: *IR_Expr) -> bool {
    if !expr return false;
    if expr.kind == .CAST return true;
    if expr.kind == .UNARY && expr.left && expr.unary_op == .DEREF return is_cast_reinterpret_base(expr.left);
    return false;
  }

  allow_non_base_root := is_cast_reinterpret_base(subscript_expr.left);
  if !buffer.has_base_index && !allow_non_base_root return_err("struct-buffer reinterpret access requires a pointer-root buffer.");

  idx_i64, idx_i64_ok := parse_i64_literal_expr(subscript_expr.right);
  if !idx_i64_ok {
    idx_u32, idx_u32_ok := parse_u32_literal_expr(subscript_expr.right);
    if !idx_u32_ok return_err("struct-buffer reinterpret access currently requires a constant integer index.");
    idx_i64 = cast(s64) idx_u32;
  }
  if idx_i64 < 0 return_err("struct-buffer reinterpret access index must be non-negative.");

  expected_type := spv_kind_from_ir_expr_result(subscript_expr);
  if expected_type == .UNKNOWN {
    base_type := subscript_expr.left.result_type;
    if base_type.kind == .FIXED_ARRAY {
      expected_type = spv_kind_from_ir_type_kind(base_type.element_kind);
    } else if base_type.kind == .POINTER {
      if base_type.pointee_kind == .FIXED_ARRAY {
        expected_type = spv_kind_from_ir_type_kind(base_type.pointee_element_kind);
      } else {
        expected_type = spv_kind_from_ir_type_kind(base_type.pointee_kind);
      }
    }
  }
  if expected_type == .UNKNOWN {
    cast_text := expr_text(subscript_expr.left);
    if cast_text.count != 0 {
      has_match, _ := contains(cast_text, "float4");
      if has_match expected_type = .FLOAT4;
      has_match, _ = contains(cast_text, "float3");
      if has_match expected_type = .FLOAT3;
      has_match, _ = contains(cast_text, "float2");
      if has_match expected_type = .FLOAT2;
      has_match, _ = contains(cast_text, "float16");
      if has_match expected_type = .FLOAT16;
      has_match, _ = contains(cast_text, "float");
      if has_match && expected_type == .UNKNOWN expected_type = .FLOAT;
      has_match, _ = contains(cast_text, "uint64");
      if has_match expected_type = .UINT64;
      has_match, _ = contains(cast_text, "int64");
      if has_match && expected_type == .UNKNOWN expected_type = .INT64;
      has_match, _ = contains(cast_text, "uint");
      if has_match && expected_type == .UNKNOWN expected_type = .UINT;
      has_match, _ = contains(cast_text, "int");
      if has_match && expected_type == .UNKNOWN expected_type = .INT;
    }
  }
  if expected_type == .UNKNOWN return_err("struct-buffer reinterpret access has unknown expected result type.");

  slot_base: s64 = 0;
  for buffer.fields {
    slot_count := ifx it.is_array then it.array_count else 1;
    if idx_i64 < slot_base || idx_i64 >= slot_base + slot_count {
      slot_base += slot_count;
      continue;
    }

    if it.type != expected_type {
      return_err("struct-buffer reinterpret access type mismatch at slot % (expected %, got %).", idx_i64, expected_type, it.type);
    }

    struct_idx := ifx buffer.has_base_index then buffer.base_index_id else s.id_uint_0;
    elem_ptr_type_id := storage_ptr_type_id_from_kind(s, it.type);
    if elem_ptr_type_id == 0 return_err("unsupported struct-buffer reinterpret element type %.", it.type);

    field_index_id := get_i32_const(s, cast(s32) it.index);
    ptr := new_id(s);
    if it.is_array {
      local_index := idx_i64 - slot_base;
      add_op(s, ptr, "OpAccessChain",
        elem_ptr_type_id,
        buffer.var_id,
        s.id_int_0,
        struct_idx,
        field_index_id,
        get_u32_const(s, cast(u32) local_index));
    } else {
      add_op(s, ptr, "OpAccessChain",
        elem_ptr_type_id,
        buffer.var_id,
        s.id_int_0,
        struct_idx,
        field_index_id);
    }
    return ptr, it.type, true, {};
  }

  return_err("struct-buffer reinterpret access index % is out of range.", idx_i64);
}

load_buffer_struct_into_local_struct :: (s: *IR_SPV_Gen_State, dst: *IR_SPV_Gen_Local_Struct, subscript_expr: *IR_Expr, field_prefix: string = "") -> (ok: bool, diag: IR_Diagnostic) {
  if !dst || !subscript_expr return false, make_diag("null input while loading struct buffer into local struct.");

  for dst.fields {
    full_name := it.name;
    if field_prefix.count != 0 full_name = tprint("%.%", field_prefix, it.name);
    if it.type == .STRUCT {
      nested := find_local_struct(s, it.nested_struct_name);
      if !nested return false, make_diag("nested struct destination missing for field '%'.", full_name);
      nested_ok, nested_diag := load_buffer_struct_into_local_struct(s, nested, subscript_expr, full_name);
      if !nested_ok return false, nested_diag;
      continue;
    }

    src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, subscript_expr, full_name);
    if !src_ok return false, src_diag;
    if src_type != it.type return false, make_diag("struct field '%' type mismatch in buffer initializer.", full_name);
    src_type_id := type_id_from_kind(s, src_type);
    if src_type_id == 0 return false, make_diag("unsupported struct field type while loading '%'.", full_name);
    src_value := new_id(s);
    emit_load(s, src_value, src_type_id, src_ptr, src_type, needs_physical_align=true);
    add_op(s, "OpStore", it.ptr_id, src_value);
  }

  return true, {};
}

emit_uniform_field_ptr :: (s: *IR_SPV_Gen_State, uniform_name: string, field_name: string) -> (ptr_id: s64, ptr_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (message: string, args: ..Any) #expand { `return 0, .UNKNOWN, false, make_diag(message, ..args); }

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
  if op == "^"  { add_op(s, result_id, "OpBitwiseXor", type_id, left_id, right_id); return result_id, kind, true, diag; }
  if op == "~"  {
    // Jai binary '~' is a boolean equivalence comparison on scalar integers.
    add_op(s, result_id, "OpIEqual", s.id_bool, left_id, right_id);
    return result_id, .BOOL, true, diag;
  }
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

spv_emit_scalar_conversion :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, ok: bool, diag: IR_Diagnostic) {
  if src_type == dst_type return value_id, true, {};
  dst_type_id := type_id_from_kind(s, dst_type);
  if dst_type_id == 0 return 0, false, make_diag("unsupported conversion destination type %.", dst_type);

  out := new_id(s);
  if dst_type == .FLOAT {
    if src_type == .FLOAT16 {
      add_op(s, out, "OpFConvert", s.id_float, value_id);
      return out, true, {};
    }
    if src_type == .UINT || src_type == .UINT64 {
      add_op(s, out, "OpConvertUToF", s.id_float, value_id);
      return out, true, {};
    }
    if src_type == .INT || src_type == .INT64 {
      add_op(s, out, "OpConvertSToF", s.id_float, value_id);
      return out, true, {};
    }
  }

  if dst_type == .FLOAT16 {
    if src_type == .FLOAT {
      add_op(s, out, "OpFConvert", s.id_half, value_id);
      return out, true, {};
    }
    if src_type == .UINT || src_type == .UINT64 {
      add_op(s, out, "OpConvertUToF", s.id_half, value_id);
      return out, true, {};
    }
    if src_type == .INT || src_type == .INT64 {
      add_op(s, out, "OpConvertSToF", s.id_half, value_id);
      return out, true, {};
    }
  }

  if is_integral_kind(dst_type) {
    if src_type == .BOOL {
      one_id: s64 = 0;
      zero_id: s64 = 0;
      if dst_type == .INT {
        one_id = get_i32_const(s, 1);
        zero_id = get_i32_const(s, 0);
      } else if dst_type == .UINT {
        one_id = get_u32_const(s, 1);
        zero_id = get_u32_const(s, 0);
      } else if dst_type == .INT64 {
        one_id = get_i64_const(s, 1);
        zero_id = get_i64_const(s, 0);
      } else if dst_type == .UINT64 {
        one_id = get_u64_const(s, 1);
        zero_id = get_u64_const(s, 0);
      }
      if one_id == 0 || zero_id == 0 {
        return 0, false, make_diag("unsupported bool-to-integer conversion destination type %.", dst_type);
      }
      add_op(s, out, "OpSelect", dst_type_id, value_id, one_id, zero_id);
      return out, true, {};
    }
    if src_type == .FLOAT || src_type == .FLOAT16 {
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

  if dst_type == .BOOL {
    if src_type == .BOOL return value_id, true, {};
    if is_integral_kind(src_type) {
      src_type_id := type_id_from_kind(s, src_type);
      if src_type_id == 0 return 0, false, make_diag("unsupported integer-to-bool conversion source type %.", src_type);
      zero_id: s64 = 0;
      if src_type == .INT {
        zero_id = get_i32_const(s, 0);
      } else if src_type == .UINT {
        zero_id = get_u32_const(s, 0);
      } else if src_type == .INT64 {
        zero_id = get_i64_const(s, 0);
      } else if src_type == .UINT64 {
        zero_id = get_u64_const(s, 0);
      }
      if zero_id == 0 return 0, false, make_diag("unsupported integer-to-bool conversion source type %.", src_type);
      add_op(s, out, "OpINotEqual", s.id_bool, value_id, zero_id);
      return out, true, {};
    }
    if src_type == .FLOAT || src_type == .FLOAT16 {
      src_type_id := type_id_from_kind(s, src_type);
      if src_type_id == 0 return 0, false, make_diag("unsupported float-to-bool conversion source type %.", src_type);
      zero_const := get_null_const(s, src_type_id);
      add_op(s, out, "OpFOrdNotEqual", s.id_bool, value_id, zero_const);
      return out, true, {};
    }
  }

  return 0, false, make_diag("unsupported conversion from % to %.", src_type, dst_type);
}

coerce_to_float :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float_id: s64, ok: bool, diag: IR_Diagnostic) {
  out_id, ok, diag := spv_emit_scalar_conversion(s, value_id, value_type, .FLOAT);
  if !ok return 0, false, diag;
  return out_id, true, {};
}

coerce_to_float2 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float2_id: s64, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if value_type == .FLOAT2 return value_id, true, diag;
  scalar_id, scalar_ok, scalar_diag := coerce_to_float(s, value_id, value_type);
  if scalar_ok return splat_float2(s, scalar_id), true, diag;
  diag.message = tprint("cannot coerce value type % to float2.", value_type);
  if scalar_diag.message.count != 0 diag.message = tprint("% (detail: %)", diag.message, scalar_diag.message);
  return 0, false, diag;
}

coerce_to_float3 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float3_id: s64, ok: bool, diag: IR_Diagnostic) {
  if value_type == .FLOAT3 return value_id, true, {};
  scalar_id, scalar_ok, scalar_diag := coerce_to_float(s, value_id, value_type);
  if scalar_ok return splat_float3(s, scalar_id), true, {};
  message := tprint("cannot coerce value type % to float3.", value_type);
  if scalar_diag.message.count != 0 message = tprint("% (detail: %)", message, scalar_diag.message);
  return 0, false, make_diag(message);
}

coerce_to_float4 :: (s: *IR_SPV_Gen_State, value_id: s64, value_type: IR_SPV_Gen_Type) -> (float4_id: s64, ok: bool, diag: IR_Diagnostic) {
  if value_type == .FLOAT4 return value_id, true, {};
  scalar_id, scalar_ok, scalar_diag := coerce_to_float(s, value_id, value_type);
  if scalar_ok return splat_float4(s, scalar_id), true, {};
  message := tprint("cannot coerce value type % to float4.", value_type);
  if scalar_diag.message.count != 0 message = tprint("% (detail: %)", message, scalar_diag.message);
  return 0, false, make_diag(message);
}

coerce_to_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, ok: bool, diag: IR_Diagnostic) {
  if src_type == dst_type return value_id, true, {};
  out_id, ok, diag := spv_emit_scalar_conversion(s, value_id, src_type, dst_type);
  return out_id, ok, diag;
}

coerce_to_exact_kind :: (s: *IR_SPV_Gen_State, value_id: s64, src_type: IR_SPV_Gen_Type, dst_type: IR_SPV_Gen_Type) -> (out_id: s64, out_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
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

coerce_to_expr_result_kind :: (s: *IR_SPV_Gen_State, expr: *IR_Expr, value_id: s64, value_type: IR_SPV_Gen_Type) -> (out_id: s64, out_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  target_kind := spv_kind_from_ir_expr_result(expr);
  if target_kind == .UNKNOWN || target_kind == .STRUCT || target_kind == value_type {
    return value_id, value_type, true, {};
  }
  coerced, coerced_ok, coerced_diag := coerce_to_kind(s, value_id, value_type, target_kind);
  if !coerced_ok return 0, .UNKNOWN, false, coerced_diag;
  return coerced, target_kind, true, {};
}

emit_float_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
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
  return add_op(s, new_id(s), "OpCompositeConstruct", ..type_id_and_values);
}

splat_float2 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float2, scalar_id, scalar_id); }
splat_float3 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float3, scalar_id, scalar_id, scalar_id); }
splat_float4 :: inline (s: *IR_SPV_Gen_State, scalar_id: s64) -> s64 { return composite_construct(s, s.id_float4, scalar_id, scalar_id, scalar_id, scalar_id); }

emit_float2_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float2, left_id, right_id); return result, .FLOAT2, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float2 binary op '%'.", op);
}

emit_float3_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float3, left_id, right_id); return result, .FLOAT3, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float3 binary op '%'.", op);
}

emit_float4_binary_op :: (s: *IR_SPV_Gen_State, op: string, left_id: s64, right_id: s64) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  result := new_id(s);
  if op == "+" { add_op(s, result, "OpFAdd", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "-" { add_op(s, result, "OpFSub", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "*" { add_op(s, result, "OpFMul", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  if op == "/" { add_op(s, result, "OpFDiv", s.id_float4, left_id, right_id); return result, .FLOAT4, true, {}; }
  return 0, .UNKNOWN, false, make_diag("unsupported float4 binary op '%'.", op);
}

emit_float_builtin_call :: (s: *IR_SPV_Gen_State, builtin_name: string, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
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
    result := spv_extinst2(s, s.id_float, op_name, af, bf);
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
  else if builtin_name == "exp" op_name = "Exp";
  else if builtin_name == "sin" op_name = "Sin";
  else if builtin_name == "cos" op_name = "Cos";
  else if builtin_name == "fract" op_name = "Fract";
  else return 0, .UNKNOWN, false, make_diag("unsupported float builtin '%'.", builtin_name);

  if value_type == .FLOAT2 {
    if builtin_name == "sin" || builtin_name == "cos" || builtin_name == "sqrt" || builtin_name == "exp" {
      return 0, .UNKNOWN, false, make_diag("builtin '%' on float2 is not supported yet.", builtin_name);
    }
    out_v2 := spv_extinst1(s, s.id_float2, op_name, value_id);
    return out_v2, .FLOAT2, true, diag;
  }

  vf, vf_ok, vf_diag := coerce_to_float(s, value_id, value_type);
  if !vf_ok return 0, .UNKNOWN, false, vf_diag;
  result := spv_extinst1(s, s.id_float, op_name, vf);
  return result, .FLOAT, true, diag;
}

emit_sample_2d_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
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
  clamped_texture_index := spv_extinst2(s, s.id_uint, "UMin", texture_index_id, sample_2d_max_index);
  clamped_sampler_index := spv_extinst2(s, s.id_uint, "UMin", sampler_index_id, sample_2d_max_index);

  uv_id, uv_type, uv_ok, uv_diag := emit_expr(s, args[2]);
  if !uv_ok return 0, .UNKNOWN, false, uv_diag;
  uv_id, uv_ok, uv_diag = coerce_to_float2(s, uv_id, uv_type);
  if !uv_ok return 0, .UNKNOWN, false, uv_diag;

  tex_ptr       := spv_access_chain1(s, s.id_ptr_uniformconst_image2d, s.id_sample_2d_textures_var, clamped_texture_index);
  tex_id        := spv_load(s, s.id_image2d, tex_ptr);
  sampler_ptr   := spv_access_chain1(s, s.id_ptr_uniformconst_sampler, s.id_sample_2d_samplers_var, clamped_sampler_index);
  sampler_id    := spv_load(s, s.id_sampler, sampler_ptr);
  sampled_image := add_op(s, new_id(s), "OpSampledImage", s.id_sampled_image2d, tex_id, sampler_id);
  result        := add_op(s, new_id(s), "OpImageSampleImplicitLod", s.id_float4, sampled_image, uv_id);

  s.uses_sample_2d = true;
  return result, .FLOAT4, true, diag;
}

emit_sample_3d_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .FRAGMENT return 0, .UNKNOWN, false, make_diag("sample_3d is currently fragment-stage only.");
  if args.count != 3      return 0, .UNKNOWN, false, make_diag("sample_3d expects 3 args (texture_index, sampler_index, uvw).");

  texture_index_id, texture_index_type, texture_index_ok, texture_index_diag := emit_expr(s, args[0]);
  if !texture_index_ok return 0, .UNKNOWN, false, texture_index_diag;
  texture_index_id, texture_index_ok, texture_index_diag = coerce_to_kind(s, texture_index_id, texture_index_type, .UINT);
  if !texture_index_ok return 0, .UNKNOWN, false, texture_index_diag;

  sampler_index_id, sampler_index_type, sampler_index_ok, sampler_index_diag := emit_expr(s, args[1]);
  if !sampler_index_ok return 0, .UNKNOWN, false, sampler_index_diag;
  sampler_index_id, sampler_index_ok, sampler_index_diag = coerce_to_kind(s, sampler_index_id, sampler_index_type, .UINT);
  if !sampler_index_ok return 0, .UNKNOWN, false, sampler_index_diag;

  sample_3d_max_index := get_u32_const(s, 15);
  clamped_texture_index := spv_extinst2(s, s.id_uint, "UMin", texture_index_id, sample_3d_max_index);
  clamped_sampler_index := spv_extinst2(s, s.id_uint, "UMin", sampler_index_id, sample_3d_max_index);

  uvw_id, uvw_type, uvw_ok, uvw_diag := emit_expr(s, args[2]);
  if !uvw_ok return 0, .UNKNOWN, false, uvw_diag;
  uvw_id, uvw_ok, uvw_diag = coerce_to_kind(s, uvw_id, uvw_type, .FLOAT3);
  if !uvw_ok return 0, .UNKNOWN, false, uvw_diag;

  tex_ptr       := spv_access_chain1(s, s.id_ptr_uniformconst_image3d, s.id_sample_3d_textures_var, clamped_texture_index);
  tex_id        := spv_load(s, s.id_image3d, tex_ptr);
  sampler_ptr   := spv_access_chain1(s, s.id_ptr_uniformconst_sampler, s.id_sample_3d_samplers_var, clamped_sampler_index);
  sampler_id    := spv_load(s, s.id_sampler, sampler_ptr);
  sampled_image := add_op(s, new_id(s), "OpSampledImage", s.id_sampled_image3d, tex_id, sampler_id);
  result        := add_op(s, new_id(s), "OpImageSampleImplicitLod", s.id_float4, sampled_image, uvw_id);

  s.uses_sample_3d = true;
  return result, .FLOAT4, true, diag;
}

emit_write_2d_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return false, make_diag("write_2d is currently compute-stage only.");
  if !s.uses_write_2d return false, make_diag("internal backend error: write_2d call was not pre-analyzed before compute emission.");
  if args.count != 4      return false, make_diag("write_2d expects 4 args (texture_index, x, y, value).");

  texture_index_id, texture_index_type, texture_index_ok, texture_index_diag := emit_expr(s, args[0]);
  if !texture_index_ok return false, texture_index_diag;
  texture_index_id, texture_index_ok, texture_index_diag = coerce_to_kind(s, texture_index_id, texture_index_type, .UINT);
  if !texture_index_ok return false, texture_index_diag;

  x_id, x_type, x_ok, x_diag := emit_expr(s, args[1]);
  if !x_ok return false, x_diag;
  x_id, x_ok, x_diag = coerce_to_kind(s, x_id, x_type, .UINT);
  if !x_ok return false, x_diag;

  y_id, y_type, y_ok, y_diag := emit_expr(s, args[2]);
  if !y_ok return false, y_diag;
  y_id, y_ok, y_diag = coerce_to_kind(s, y_id, y_type, .UINT);
  if !y_ok return false, y_diag;

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[3]);
  if !value_ok return false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .FLOAT4);
  if !value_ok return false, value_diag;

  // Clamp resource indices to the declared bindless array range [0, 15] to make
  // out-of-range shader behavior explicit and deterministic across backends.
  write_2d_max_index := get_u32_const(s, 15);
  clamped_texture_index := spv_extinst2(s, s.id_uint, "UMin", texture_index_id, write_2d_max_index);

  tex_ptr := spv_access_chain1(s, s.id_ptr_uniformconst_storage_image2d, s.id_write_2d_textures_var, clamped_texture_index);
  tex_id := spv_load(s, s.id_storage_image2d, tex_ptr);
  coord_id := add_op(s, new_id(s), "OpCompositeConstruct", s.id_v2uint, x_id, y_id);
  add_op(s, "OpImageWrite", tex_id, coord_id, value_id);
  return true, diag;
}

emit_write_3d_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return false, make_diag("write_3d is currently compute-stage only.");
  if !s.uses_write_3d return false, make_diag("internal backend error: write_3d call was not pre-analyzed before compute emission.");
  if args.count != 5      return false, make_diag("write_3d expects 5 args (texture_index, x, y, z, value).");

  texture_index_id, texture_index_type, texture_index_ok, texture_index_diag := emit_expr(s, args[0]);
  if !texture_index_ok return false, texture_index_diag;
  texture_index_id, texture_index_ok, texture_index_diag = coerce_to_kind(s, texture_index_id, texture_index_type, .UINT);
  if !texture_index_ok return false, texture_index_diag;

  x_id, x_type, x_ok, x_diag := emit_expr(s, args[1]);
  if !x_ok return false, x_diag;
  x_id, x_ok, x_diag = coerce_to_kind(s, x_id, x_type, .UINT);
  if !x_ok return false, x_diag;

  y_id, y_type, y_ok, y_diag := emit_expr(s, args[2]);
  if !y_ok return false, y_diag;
  y_id, y_ok, y_diag = coerce_to_kind(s, y_id, y_type, .UINT);
  if !y_ok return false, y_diag;

  z_id, z_type, z_ok, z_diag := emit_expr(s, args[3]);
  if !z_ok return false, z_diag;
  z_id, z_ok, z_diag = coerce_to_kind(s, z_id, z_type, .UINT);
  if !z_ok return false, z_diag;

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[4]);
  if !value_ok return false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .FLOAT4);
  if !value_ok return false, value_diag;

  write_3d_max_index := get_u32_const(s, 15);
  clamped_texture_index := spv_extinst2(s, s.id_uint, "UMin", texture_index_id, write_3d_max_index);

  tex_ptr := spv_access_chain1(s, s.id_ptr_uniformconst_storage_image3d, s.id_write_3d_textures_var, clamped_texture_index);
  tex_id := spv_load(s, s.id_storage_image3d, tex_ptr);
  coord_id := add_op(s, new_id(s), "OpCompositeConstruct", s.id_v3uint, x_id, y_id, z_id);
  add_op(s, "OpImageWrite", tex_id, coord_id, value_id);
  return true, diag;
}

emit_atomic_u32_call :: (s: *IR_SPV_Gen_State, op_name: string, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return 0, .UNKNOWN, false, make_diag("% is currently compute-stage only.", op_name);
  if args.count != 2 return 0, .UNKNOWN, false, make_diag("% expects 2 args (*dst, value).", op_name);

  dst_ptr, dst_type, dst_ok, dst_diag := emit_lvalue_ptr(s, args[0]);
  if !dst_ok return 0, .UNKNOWN, false, dst_diag;
  if dst_type != .UINT return 0, .UNKNOWN, false, make_diag("% first arg must point to u32.", op_name);

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[1]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .UINT);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  scope_device := get_u32_const(s, 1);
  semantics_relaxed := get_u32_const(s, 0);
  out := new_id(s);
  add_op(s, out, op_name, s.id_uint, dst_ptr, scope_device, semantics_relaxed, value_id);
  return out, .UINT, true, diag;
}

emit_atomic_sub_u32_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return 0, .UNKNOWN, false, make_diag("atomic_sub_u32 is currently compute-stage only.");
  if args.count != 2 return 0, .UNKNOWN, false, make_diag("atomic_sub_u32 expects 2 args (*dst, value).");

  dst_ptr, dst_type, dst_ok, dst_diag := emit_lvalue_ptr(s, args[0]);
  if !dst_ok return 0, .UNKNOWN, false, dst_diag;
  if dst_type != .UINT return 0, .UNKNOWN, false, make_diag("atomic_sub_u32 first arg must point to u32.");

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[1]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .UINT);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  zero := get_u32_const(s, 0);
  neg_value := new_id(s);
  add_op(s, neg_value, "OpISub", s.id_uint, zero, value_id);

  scope_device := get_u32_const(s, 1);
  semantics_relaxed := get_u32_const(s, 0);
  out := new_id(s);
  add_op(s, out, "OpAtomicIAdd", s.id_uint, dst_ptr, scope_device, semantics_relaxed, neg_value);
  return out, .UINT, true, diag;
}

emit_atomic_compare_exchange_u32_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return 0, .UNKNOWN, false, make_diag("OpAtomicCompareExchange is currently compute-stage only.");
  if args.count != 3 return 0, .UNKNOWN, false, make_diag("atomic_compare_exchange_u32 expects 3 args (*dst, compare, value).");

  dst_ptr, dst_type, dst_ok, dst_diag := emit_lvalue_ptr(s, args[0]);
  if !dst_ok return 0, .UNKNOWN, false, dst_diag;
  if dst_type != .UINT return 0, .UNKNOWN, false, make_diag("atomic_compare_exchange_u32 first arg must point to u32.");

  compare_id, compare_type, compare_ok, compare_diag := emit_expr(s, args[1]);
  if !compare_ok return 0, .UNKNOWN, false, compare_diag;
  compare_id, compare_ok, compare_diag = coerce_to_kind(s, compare_id, compare_type, .UINT);
  if !compare_ok return 0, .UNKNOWN, false, compare_diag;

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[2]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .UINT);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  scope_device := get_u32_const(s, 1);
  semantics_relaxed := get_u32_const(s, 0);
  out := new_id(s);
  add_op(s, out, "OpAtomicCompareExchange", s.id_uint, dst_ptr, scope_device, semantics_relaxed, semantics_relaxed, value_id, compare_id);
  return out, .UINT, true, diag;
}

emit_atomic_reduce_u32_call :: (s: *IR_SPV_Gen_State, args: [] *IR_Expr, reduce_kind: string) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if s.stage != .COMPUTE return 0, .UNKNOWN, false, make_diag("atomic_%_u32 is currently compute-stage only.", reduce_kind);
  if args.count != 2 return 0, .UNKNOWN, false, make_diag("atomic_%_u32 expects 2 args (*dst, value).", reduce_kind);

  dst_ptr, dst_type, dst_ok, dst_diag := emit_lvalue_ptr(s, args[0]);
  if !dst_ok return 0, .UNKNOWN, false, dst_diag;
  if dst_type != .UINT return 0, .UNKNOWN, false, make_diag("atomic_%_u32 first arg must point to u32.", reduce_kind);

  value_id, value_type, value_ok, value_diag := emit_expr(s, args[1]);
  if !value_ok return 0, .UNKNOWN, false, value_diag;
  value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, .UINT);
  if !value_ok return 0, .UNKNOWN, false, value_diag;

  prev_ptr := new_id(s);
  prev_zero := get_null_const(s, s.id_uint);
  add_local_decl(s, "% = OpVariable % Function %", id_text(prev_ptr), id_text(s.id_ptr_func_uint), id_text(prev_zero));
  add_debug_name(s, prev_ptr, tprint("__atomic_%_prev", reduce_kind));

  header_label := new_id(s);
  body_label := new_id(s);
  continue_label := new_id(s);
  merge_label := new_id(s);

  add_op(s, "OpBranch", header_label, is_terminator=true);
  add_op(s, header_label, "OpLabel");
  add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
  add_op(s, "OpBranch", body_label, is_terminator=true);

  add_op(s, body_label, "OpLabel");
  old_value := new_id(s);
  add_op(s, old_value, "OpLoad", s.id_uint, dst_ptr);

  use_new_value := new_id(s);
  if reduce_kind == "min" {
    add_op(s, use_new_value, "OpULessThan", s.id_bool, value_id, old_value);
  } else {
    add_op(s, use_new_value, "OpUGreaterThan", s.id_bool, value_id, old_value);
  }

  desired_value := new_id(s);
  add_op(s, desired_value, "OpSelect", s.id_uint, use_new_value, value_id, old_value);

  scope_device := get_u32_const(s, 1);
  semantics_relaxed := get_u32_const(s, 0);
  prev_value := new_id(s);
  add_op(s, prev_value, "OpAtomicCompareExchange", s.id_uint, dst_ptr, scope_device, semantics_relaxed, semantics_relaxed, desired_value, old_value);
  add_op(s, "OpStore", prev_ptr, prev_value);

  success := new_id(s);
  add_op(s, success, "OpIEqual", s.id_bool, prev_value, old_value);
  add_op(s, "OpBranchConditional", success, merge_label, continue_label, is_terminator=true);

  add_op(s, continue_label, "OpLabel");
  add_op(s, "OpBranch", header_label, is_terminator=true);

  add_op(s, merge_label, "OpLabel");
  out := new_id(s);
  add_op(s, out, "OpLoad", s.id_uint, prev_ptr);
  return out, .UINT, true, diag;
}

spv_kind_from_ir_type_kind :: (kind: IR_Type_Kind) -> IR_SPV_Gen_Type {
  if kind == .BOOL return .BOOL;
  if kind == .I32 return .INT;
  if kind == .U32 return .UINT;
  if kind == .I64 return .INT64;
  if kind == .U64 return .UINT64;
  if kind == .F16 return .FLOAT16;
  if kind == .F32 return .FLOAT;
  if kind == .F32x2 return .FLOAT2;
  if kind == .F32x3 return .FLOAT3;
  if kind == .F32x4 return .FLOAT4;
  if kind == .F32x2x2 return .FLOAT2X2;
  if kind == .STRUCT return .STRUCT;
  return .UNKNOWN;
}

spv_kind_from_ir_expr_result :: (expr: *IR_Expr) -> IR_SPV_Gen_Type {
  if !expr return .UNKNOWN;
  return spv_kind_from_ir_type_kind(expr.result_type.kind);
}

spv_struct_name_from_ir_expr_result :: (expr: *IR_Expr) -> string {
  if !expr return "";
  if expr.result_type.kind != .STRUCT return "";
  if expr.result_type.struct_name.count != 0 return expr.result_type.struct_name;
  return expr.result_type.display_name;
}

spv_kind_from_ir_type :: (type: IR_Type) -> IR_SPV_Gen_Type {
  kind := spv_kind_from_ir_type_kind(type.kind);
  if kind != .UNKNOWN return kind;
  return .UNKNOWN;
}

spv_kind_from_struct_alias :: (s: *IR_SPV_Gen_State, struct_name: string) -> IR_SPV_Gen_Type {
  if !s || struct_name.count == 0 return .UNKNOWN;
  st := find_struct(s, struct_name);
  if !st return .UNKNOWN;

  if st.fields.count == 1 {
    k := spv_kind_from_ir_type_kind(st.fields[0].type.kind);
    if k == .FLOAT || k == .FLOAT2 || k == .FLOAT3 || k == .FLOAT4 || k == .FLOAT2X2 return k;
  }

  if st.fields.count == 2 {
    a := spv_kind_from_ir_type_kind(st.fields[0].type.kind);
    b := spv_kind_from_ir_type_kind(st.fields[1].type.kind);
    if a == .FLOAT && b == .FLOAT return .FLOAT2;
  }
  if st.fields.count == 3 {
    a := spv_kind_from_ir_type_kind(st.fields[0].type.kind);
    b := spv_kind_from_ir_type_kind(st.fields[1].type.kind);
    c := spv_kind_from_ir_type_kind(st.fields[2].type.kind);
    if a == .FLOAT && b == .FLOAT && c == .FLOAT return .FLOAT3;
  }
  if st.fields.count == 4 {
    a := spv_kind_from_ir_type_kind(st.fields[0].type.kind);
    b := spv_kind_from_ir_type_kind(st.fields[1].type.kind);
    c := spv_kind_from_ir_type_kind(st.fields[2].type.kind);
    d := spv_kind_from_ir_type_kind(st.fields[3].type.kind);
    if a == .FLOAT && b == .FLOAT && c == .FLOAT && d == .FLOAT return .FLOAT4;
  }

  return .UNKNOWN;
}

spv_kind_from_ir_type_for_layout :: (s: *IR_SPV_Gen_State, type: IR_Type) -> IR_SPV_Gen_Type {
  kind := spv_kind_from_ir_type(type);
  // For host-visible buffer layouts we store bool as 32-bit uint.
  // This preserves CPU/GPU blittability while frontend semantics still coerce to bool at use sites.
  if kind == .BOOL return .UINT;
  if kind == .STRUCT {
    alias_kind := spv_kind_from_struct_alias(s, spv_struct_name_from_ir_type(type));
    if alias_kind != .UNKNOWN return alias_kind;
  }
  return kind;
}

spv_struct_name_from_ir_type :: (type: IR_Type) -> string {
  if type.kind != .STRUCT return "";
  return ir_string_first_non_empty(type.struct_name, type.display_name);
}

spv_fixed_array_info_from_ir_type :: (type: IR_Type) -> (element_type_name: string, array_count: s64, element_kind: IR_SPV_Gen_Type, ok: bool) {
  if type.kind != .FIXED_ARRAY return "", 0, .UNKNOWN, false;
  element_type_name := ir_string_first_non_empty(type.element_display_name, type.element_struct_name);
  array_count := type.array_count;
  element_kind := spv_kind_from_ir_type_kind(type.element_kind);
  return element_type_name, array_count, element_kind, true;
}

bind_inline_helper_pointer_arg :: (s: *IR_SPV_Gen_State, helper_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (handled: bool, ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if arg.type.kind != .POINTER return false, true, diag;

  expr := arg_expr;
  if expr && expr.kind == .CAST && expr.left expr = expr.left;
  if expr && expr.kind == .UNARY && expr.left &&
     (expr.unary_op == .ADDRESS_OF || expr.unary_op == .DEREF) expr = expr.left;

  expected_kind := spv_kind_from_ir_type_kind(arg.type.pointee_kind);

  // Local pointer args: allow lvalue addresses of locals/struct fields/components.
  if expr && !lvalue_hits_storage_buffer(s, expr) {
    ptr_id, ptr_type, ptr_ok, _ := emit_lvalue_ptr(s, expr);
    if ptr_ok {
      if arg.type.pointee_kind == .STRUCT || expected_kind == .STRUCT {
        return true, false, make_diag("helper '%' pointer arg '%' local struct pointees are not supported yet.", helper_name, arg.name);
      }
      if expected_kind == .UNKNOWN {
        return true, false, make_diag("helper '%' pointer arg '%' has unsupported pointee kind %.", helper_name, arg.name, arg.type.pointee_kind);
      }
      if ptr_type != expected_kind {
        return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected %, got %).", helper_name, arg.name, expected_kind, ptr_type);
      }

      array_add(*s.locals, .{
        name = arg.name,
        ptr_id = ptr_id,
        type = ptr_type,
      });
      return true, true, diag;
    }
  }

  buffer_name, buffer_name_ok := resolve_buffer_name_from_expr(expr);
  if !buffer_name_ok {
    return true, false, make_diag("helper '%' pointer arg '%' must be a buffer identifier/subscript or local lvalue.", helper_name, arg.name);
  }
  source_buffer := find_buffer(s, buffer_name);
  if !source_buffer {
    return true, false, make_diag("helper '%' pointer arg '%' expected storage buffer identifier, got '%'.", helper_name, arg.name, buffer_name);
  }
  if arg.type.pointee_kind == .FIXED_ARRAY {
    expected_elem := spv_kind_from_ir_type_kind(arg.type.pointee_element_kind);
    if expected_elem == .UNKNOWN {
      return true, false, make_diag("helper '%' pointer arg '%' fixed-array pointee has unsupported element kind %.", helper_name, arg.name, arg.type.pointee_element_kind);
    }
    if expected_elem == .STRUCT {
      if source_buffer.element_kind != .STRUCT {
        return true, false, make_diag("helper '%' pointer arg '%' expected struct-array buffer pointee '%'.", helper_name, arg.name, arg.type.pointee_element_struct_name);
      }
      if arg.type.pointee_element_struct_name.count != 0 && source_buffer.element_struct_name != arg.type.pointee_element_struct_name {
        return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected '%', got '%').", helper_name, arg.name, arg.type.pointee_element_struct_name, source_buffer.element_struct_name);
      }
    } else {
      if source_buffer.element_kind != expected_elem {
        return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected %, got %).", helper_name, arg.name, expected_elem, source_buffer.element_kind);
      }
    }
  } else if arg.type.pointee_kind == .STRUCT || expected_kind == .STRUCT {
    if source_buffer.element_kind != .STRUCT {
      return true, false, make_diag("helper '%' pointer arg '%' expected struct buffer pointee '%'.", helper_name, arg.name, arg.type.pointee_struct_name);
    }
    if arg.type.pointee_struct_name.count != 0 && source_buffer.element_struct_name != arg.type.pointee_struct_name {
      return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected '%', got '%').", helper_name, arg.name, arg.type.pointee_struct_name, source_buffer.element_struct_name);
    }
  } else {
    if expected_kind == .UNKNOWN {
      return true, false, make_diag("helper '%' pointer arg '%' has unsupported pointee kind %.", helper_name, arg.name, arg.type.pointee_kind);
    }
    if source_buffer.element_kind != expected_kind {
      return true, false, make_diag("helper '%' pointer arg '%' pointee mismatch (expected %, got %).", helper_name, arg.name, expected_kind, source_buffer.element_kind);
    }
  }

  alias := source_buffer.*;
  alias.name = arg.name;
  alias.has_base_index = false;
  alias.base_index_id = 0;

  if expr && expr.kind == .SUBSCRIPT {
    idx_id, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
    if !idx_ok return true, false, idx_diag;
    idx_id, idx_ok, idx_diag = coerce_to_kind(s, idx_id, idx_type, .UINT);
    if !idx_ok return true, false, idx_diag;
    alias.has_base_index = true;
    alias.base_index_id = apply_buffer_base_index(s, source_buffer, idx_id);
  }

  array_add(*s.buffers, alias);
  return true, true, diag;
}

bind_inline_function_scalar_arg_with_value :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, final_value: s64, final_type: IR_SPV_Gen_Type, arg_type: IR_SPV_Gen_Type) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if arg_type == .UNKNOWN || arg_type == .STRUCT return true, false, diag;

  if final_type != arg_type {
    return false, true, make_diag("helper '%' arg '%' type mismatch (expected %, got %).", function_name, arg.name, arg_type, final_type);
  }

  arg_ptr_type := func_ptr_type_id_from_kind(s, arg_type);
  if arg_ptr_type == 0 {
    return false, true, make_diag("helper '%' arg '%' type '%' has no function pointer representation.", function_name, arg.name, arg_type);
  }
  arg_ptr := new_id(s);
  arg_zero := get_null_const(s, type_id_from_kind(s, arg_type));
  add_local_decl(s, "% = OpVariable % Function %", id_text(arg_ptr), id_text(arg_ptr_type), id_text(arg_zero));
  add_debug_name(s, arg_ptr, arg.name);
  add_op(s, "OpStore", arg_ptr, final_value);
  array_add(*s.locals, .{name=arg.name, ptr_id=arg_ptr, type=arg_type});
  return true, true, diag;
}

bind_inline_function_scalar_arg :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  arg_type := spv_kind_from_ir_type(arg.type);
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

  bind_ok, bind_handled, bind_diag := bind_inline_function_scalar_arg_with_value(s, function_name, arg, final_value, final_type, arg_type);
  return bind_ok, bind_handled, bind_diag;
}

bind_inline_function_struct_arg :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  arg_struct_name := arg.type.struct_name;
  if arg_struct_name.count == 0 {
    return false, make_diag("helper '%' struct arg '%' is missing typed struct metadata.", function_name, arg.name);
  }
  arg_struct, arg_struct_ok, arg_struct_diag := alloc_local_struct(s, arg.name, arg_struct_name);
  if !arg_struct_ok return false, arg_struct_diag;

  if arg_expr && arg_expr.kind == .SUBSCRIPT {
    src_buffer_name, src_buffer_name_ok := resolve_buffer_name_from_expr(arg_expr.left);
    src_buffer := ifx src_buffer_name_ok then find_buffer(s, src_buffer_name) else null;
    if src_buffer && src_buffer.element_kind == .STRUCT && src_buffer.element_struct_name == arg_struct_name {
      for arg_struct.fields {
        src_ptr, src_type, src_ok, src_diag := emit_buffer_struct_field_ptr(s, arg_expr, it.name);
        if !src_ok return false, src_diag;
        value_id := new_id(s);
        type_id := type_id_from_kind(s, src_type);
        emit_load(s, value_id, type_id, src_ptr, src_type, needs_physical_align=true);
        if it.type == .STRUCT {
          nested_dst := find_local_struct(s, it.nested_struct_name);
          if !nested_dst return false, make_diag("helper '%' struct arg nested field '%' destination is missing.", function_name, it.name);
          nested_ok, nested_diag := store_value_in_local_struct_alias(s, nested_dst, value_id, src_type);
          if !nested_ok return false, make_diag("helper '%' struct arg nested field '%' alias init failed: %", function_name, it.name, nested_diag.message);
        } else {
          if src_type != it.type {
            return false, make_diag("helper '%' struct arg field '%' type mismatch.", function_name, it.name);
          }
          add_op(s, "OpStore", it.ptr_id, value_id);
        }
      }
      return true, diag;
    }
  }

  init_ok, init_diag := init_local_struct_from_expr(s, arg_struct, arg_expr);
  if !init_ok return false, make_diag("helper '%' struct arg '%' could not be initialized: %", function_name, arg.name, init_diag.message);
  
  return true, diag;
}

bind_inline_function_fixed_array_arg :: (s: *IR_SPV_Gen_State, function_name: string, arg: IR_Function_Arg, arg_expr: *IR_Expr) -> (ok: bool, handled: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !s return false, false, make_diag("null SPIR-V state while binding helper array arg.");

  array_elem_type_name, array_count, elem_type, is_fixed_array := spv_fixed_array_info_from_ir_type(arg.type);
  if !is_fixed_array return false, false, diag;

  if elem_type == .UNKNOWN || elem_type == .STRUCT {
    return false, true, make_diag("helper '%' fixed array arg '%' has unsupported element type '%'.", function_name, arg.name, array_elem_type_name);
  }
  if array_count <= 0 || array_count > 0xFFFF_FFFF {
    return false, true, make_diag("helper '%' fixed array arg '%' has invalid count %.", function_name, arg.name, array_count);
  }

  count_const_id := get_u32_const(s, cast(u32) array_count);
  array_type_id := new_id(s);
  ptr_func_array_type_id := new_id(s);
  ptr_id := new_id(s);
  add_debug_name(s, array_type_id, tprint("%_array", arg.name));
  add_debug_name(s, ptr_func_array_type_id, tprint("%_array_ptr", arg.name));
  array_zero := get_null_const(s, array_type_id);
  add_local_decl(s, "% = OpVariable % Function %", id_text(ptr_id), id_text(ptr_func_array_type_id), id_text(array_zero));
  add_debug_name(s, ptr_id, arg.name);
  array_add(*s.local_arrays, .{
    name = arg.name,
    element_type = elem_type,
    count = array_count,
    var_id = ptr_id,
    array_type_id = array_type_id,
    ptr_func_array_type_id = ptr_func_array_type_id,
    count_const_id = count_const_id,
  });
  array_add(*s.local_array_types, .{
    name = arg.name,
    element_type = elem_type,
    count = array_count,
    var_id = ptr_id,
    array_type_id = array_type_id,
    ptr_func_array_type_id = ptr_func_array_type_id,
    count_const_id = count_const_id,
  });

  elem_ptr_type_id := func_ptr_type_id_from_kind(s, elem_type);
  if elem_ptr_type_id == 0 {
    return false, true, make_diag("helper '%' fixed array arg '%' element type '%' has no function pointer type.", function_name, arg.name, elem_type);
  }

  if arg_expr && arg_expr.kind == .IDENT {
    src_array := find_local_array(s, arg_expr.text);
    if !src_array {
      return false, true, make_diag("helper '%' fixed array arg '%' source '%' is not a local array.", function_name, arg.name, arg_expr.text);
    }
    if src_array.count != array_count || src_array.element_type != elem_type {
      return false, true, make_diag("helper '%' fixed array arg '%' source '%' type mismatch.", function_name, arg.name, arg_expr.text);
    }
    type_id := type_id_from_kind(s, elem_type);
    for i: 0..array_count-1 {
      idx_const := get_u32_const(s, cast(u32) i);
      src_ptr := new_id(s);
      dst_ptr := new_id(s);
      add_op(s, src_ptr, "OpAccessChain", elem_ptr_type_id, src_array.var_id, idx_const);
      add_op(s, dst_ptr, "OpAccessChain", elem_ptr_type_id, ptr_id, idx_const);
      src_value := new_id(s);
      add_op(s, src_value, "OpLoad", type_id, src_ptr);
      add_op(s, "OpStore", dst_ptr, src_value);
    }
    return true, true, diag;
  }

  if arg_expr && arg_expr.kind == .ARRAY_LITERAL {
    if arg_expr.args.count != array_count {
      return false, true, make_diag("helper '%' fixed array arg '%' literal count mismatch (expected %, got %).", function_name, arg.name, array_count, arg_expr.args.count);
    }
    for arg_expr.args {
      value_id, value_type, value_ok, value_diag := emit_expr(s, it);
      if !value_ok return false, true, value_diag;
      value_id, value_ok, value_diag = coerce_to_kind(s, value_id, value_type, elem_type);
      if !value_ok return false, true, value_diag;
      idx_const := get_u32_const(s, cast(u32) it_index);
      dst_ptr := new_id(s);
      add_op(s, dst_ptr, "OpAccessChain", elem_ptr_type_id, ptr_id, idx_const);
      add_op(s, "OpStore", dst_ptr, value_id);
    }
    return true, true, diag;
  }

  return false, true, make_diag("helper '%' fixed array arg '%' must be passed as local array identifier or array literal.", function_name, arg.name);
}

bind_inline_function_args :: (s: *IR_SPV_Gen_State, ir_function: *IR_Function, call_args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if !ir_function return false, make_diag("missing function metadata for inline call.");
  
  if ir_function.args.count != call_args.count {
    return false, make_diag("helper '%' expected % args but got %.", ir_function.name, ir_function.args.count, call_args.count);
  }

  Inline_Scalar_Arg_Capture :: struct {
    captured: bool;
    arg_type: IR_SPV_Gen_Type;
    value_type: IR_SPV_Gen_Type;
    value_id: s64;
  }
  scalar_captures: [..] Inline_Scalar_Arg_Capture;
  for call_args array_add(*scalar_captures, .{});

  // Pre-evaluate scalar call args before introducing helper parameter locals.
  // This prevents accidental capture of earlier helper args when later call
  // args reference identifiers with matching names.
  for ir_function.args {
    arg_expr := call_args[it_index];
    arg_type := spv_kind_from_ir_type(it.type);
    if arg_type == .UNKNOWN || arg_type == .STRUCT continue;

    value_id, value_type, value_ok, value_diag := emit_expr(s, arg_expr);
    if !value_ok return false, value_diag;

    final_value := value_id;
    final_type := value_type;
    if arg_type == .FLOAT || is_integral_kind(arg_type) || arg_type == .BOOL {
      coerced, coerced_ok, coerced_diag := coerce_to_kind(s, value_id, value_type, arg_type);
      if !coerced_ok return false, coerced_diag;
      final_value = coerced;
      final_type = arg_type;
    } else if arg_type == .FLOAT2 && value_type != .FLOAT2 {
      coerced, coerced_ok, coerced_diag := coerce_to_float2(s, value_id, value_type);
      if !coerced_ok return false, coerced_diag;
      final_value = coerced;
      final_type = .FLOAT2;
    } else if arg_type == .FLOAT3 && value_type != .FLOAT3 {
      coerced, coerced_ok, coerced_diag := coerce_to_float3(s, value_id, value_type);
      if !coerced_ok return false, coerced_diag;
      final_value = coerced;
      final_type = .FLOAT3;
    } else if arg_type == .FLOAT4 && value_type != .FLOAT4 {
      coerced, coerced_ok, coerced_diag := coerce_to_float4(s, value_id, value_type);
      if !coerced_ok return false, coerced_diag;
      final_value = coerced;
      final_type = .FLOAT4;
    }

    scalar_captures[it_index] = .{
      captured = true,
      arg_type = arg_type,
      value_type = final_type,
      value_id = final_value,
    };
  }

  for ir_function.args {
    arg_expr := call_args[it_index];
    pointer_handled, pointer_ok, pointer_diag := bind_inline_helper_pointer_arg(s, ir_function.name, it, arg_expr);
    if pointer_handled {
      if !pointer_ok return false, pointer_diag;
      continue;
    }

    if scalar_captures[it_index].captured {
      capture := scalar_captures[it_index];
      scalar_ok, scalar_handled, scalar_diag := bind_inline_function_scalar_arg_with_value(s, ir_function.name, it, capture.value_id, capture.value_type, capture.arg_type);
      if scalar_handled {
        if !scalar_ok return false, scalar_diag;
        continue;
      }
    }

    scalar_ok, scalar_handled, scalar_diag := bind_inline_function_scalar_arg(s, ir_function.name, it, arg_expr);
    if scalar_handled {
      if !scalar_ok return false, scalar_diag;
      continue;
    }

    array_ok, array_handled, array_diag := bind_inline_function_fixed_array_arg(s, ir_function.name, it, arg_expr);
    if array_handled {
      if !array_ok return false, array_diag;
      continue;
    }

    struct_ok, struct_diag := bind_inline_function_struct_arg(s, ir_function.name, it, arg_expr);
    if !struct_ok return false, struct_diag;
  }

  return true, {};
}

eval_inline_function :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  if !helper return 0, .UNKNOWN, false, make_diag("missing helper metadata for inline call.");
  
  return_kind := spv_kind_from_ir_type(helper.return_type);
  if return_kind == .UNKNOWN || return_kind == .STRUCT {
    helper_return_text := helper.return_type.display_name;
    if helper_return_text.count == 0 helper_return_text = spv_struct_name_from_ir_type(helper.return_type);
    if helper_return_text.count == 0 helper_return_text = "<unknown>";
    return 0, .UNKNOWN, false, make_diag("helper '%' has unsupported return type '%'.", helper.name, helper_return_text);
  }

  value_id, value_type, ok, diag := eval_inline_function_value(s, helper, call_args, return_kind);
  return value_id, value_type, ok, diag;
}

eval_inline_function_value :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr, return_kind: IR_SPV_Gen_Type) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  result_type_id := type_id_from_kind(s, return_kind);
  if result_type_id == 0 {
    return 0, .UNKNOWN, false, make_diag("helper '%' return type % has no SPIR-V type id.", helper.name, return_kind);
  }
  result_ptr_type_id := func_ptr_type_id_from_kind(s, return_kind);
  if result_ptr_type_id == 0 {
    return 0, .UNKNOWN, false, make_diag("helper '%' return type % has no function pointer type.", helper.name, return_kind);
  }

  local_count_before := s.locals.count;
  local_array_count_before := s.local_arrays.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_arrays.count = local_array_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }

  bind_ok, bind_diag := bind_inline_function_args(s, helper, call_args);
  if !bind_ok return 0, .UNKNOWN, false, bind_diag;

  helper_exit_label := new_id(s);
  helper_return_flag_ptr := new_id(s);
  helper_return_flag_zero := get_null_const(s, s.id_bool);
  add_local_decl(s, "% = OpVariable % Function %", id_text(helper_return_flag_ptr), id_text(s.id_ptr_func_bool), id_text(helper_return_flag_zero));
  add_debug_name(s, helper_return_flag_ptr, tprint("__helper_returned_%", helper.name));
  add_op(s, "OpStore", helper_return_flag_ptr, s.id_bool_false);

  helper_return_value_ptr := new_id(s);
  helper_return_value_zero := get_null_const(s, result_type_id);
  add_local_decl(s, "% = OpVariable % Function %", id_text(helper_return_value_ptr), id_text(result_ptr_type_id), id_text(helper_return_value_zero));
  add_debug_name(s, helper_return_value_ptr, tprint("__helper_return_value_%", helper.name));

  array_add(*s.inline_return_targets, helper_exit_label);
  array_add(*s.inline_helper_contexts, .{
    exit_label = helper_exit_label,
    return_flag_ptr = helper_return_flag_ptr,
    has_return_value = true,
    return_value_ptr = helper_return_value_ptr,
    return_value_type = return_kind,
    break_targets_base_count = s.break_targets.count,
    control_merge_targets_base_count = s.control_merge_targets.count,
  });

  for helper.body.statements {
    guard_body_label := new_id(s);
    guard_merge_label := new_id(s);
    guard_flag_id := new_id(s);
    add_op(s, guard_flag_id, "OpLoad", s.id_bool, helper_return_flag_ptr);
    add_op(s, tprint("OpSelectionMerge % None", id_text(guard_merge_label)));
    add_op(s, "OpBranchConditional", guard_flag_id, guard_merge_label, guard_body_label, is_terminator=true);
    add_op(s, guard_body_label, "OpLabel");
    array_add(*s.control_merge_targets, guard_merge_label);

    stmt_ok, stmt_terminated, stmt_diag := emit_stmt(s, *it);
    if !stmt_ok {
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
      if s.inline_helper_contexts.count > 0 s.inline_helper_contexts.count -= 1;
      if s.inline_return_targets.count > 0 s.inline_return_targets.count -= 1;
      return 0, .UNKNOWN, false, stmt_diag;
    }
    if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
    if !stmt_terminated {
      add_op(s, "OpBranch", guard_merge_label, is_terminator=true);
    }
    add_op(s, guard_merge_label, "OpLabel");
  }

  if s.inline_helper_contexts.count > 0 s.inline_helper_contexts.count -= 1;
  if s.inline_return_targets.count > 0 s.inline_return_targets.count -= 1;

  add_op(s, "OpBranch", helper_exit_label, is_terminator=true);
  add_op(s, helper_exit_label, "OpLabel");

  helper_value := new_id(s);
  add_op(s, helper_value, "OpLoad", result_type_id, helper_return_value_ptr);
  return helper_value, return_kind, true, {};
}

helper_returns_void :: (helper: *IR_Function) -> bool {
  if !helper return false;
  return helper.return_type.display_name == "void";
}

eval_inline_function_void :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if !helper return false, make_diag("missing helper metadata for inline void call.");
  if !helper_returns_void(helper) {
    return false, make_diag("helper '%' is not a void helper.", helper.name);
  }

  local_count_before := s.locals.count;
  local_array_count_before := s.local_arrays.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_arrays.count = local_array_count_before;
    s.local_structs.count = local_struct_count_before;
    s.buffers.count = buffer_count_before;
  }

  bind_ok, bind_diag := bind_inline_function_args(s, helper, call_args);
  if !bind_ok return false, bind_diag;

  helper_exit_label := new_id(s);
  helper_return_flag_ptr := new_id(s);
  helper_return_flag_zero := get_null_const(s, s.id_bool);
  add_local_decl(s, "% = OpVariable % Function %", id_text(helper_return_flag_ptr), id_text(s.id_ptr_func_bool), id_text(helper_return_flag_zero));
  add_debug_name(s, helper_return_flag_ptr, tprint("__helper_returned_%", helper.name));
  add_op(s, "OpStore", helper_return_flag_ptr, s.id_bool_false);

  array_add(*s.inline_return_targets, helper_exit_label);
  array_add(*s.inline_helper_contexts, .{
    exit_label = helper_exit_label,
    return_flag_ptr = helper_return_flag_ptr,
    break_targets_base_count = s.break_targets.count,
    control_merge_targets_base_count = s.control_merge_targets.count,
  });
  for helper.body.statements {
    guard_body_label := new_id(s);
    guard_merge_label := new_id(s);
    guard_flag_id := new_id(s);
    add_op(s, guard_flag_id, "OpLoad", s.id_bool, helper_return_flag_ptr);
    add_op(s, tprint("OpSelectionMerge % None", id_text(guard_merge_label)));
    add_op(s, "OpBranchConditional", guard_flag_id, guard_merge_label, guard_body_label, is_terminator=true);
    add_op(s, guard_body_label, "OpLabel");
    array_add(*s.control_merge_targets, guard_merge_label);

    stmt_ok, stmt_terminated, stmt_diag := emit_stmt(s, *it);
    if !stmt_ok {
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
      if s.inline_helper_contexts.count > 0 s.inline_helper_contexts.count -= 1;
      if s.inline_return_targets.count > 0 s.inline_return_targets.count -= 1;
      return false, stmt_diag;
    }
    if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
    if !stmt_terminated {
      add_op(s, "OpBranch", guard_merge_label, is_terminator=true);
    }
    add_op(s, guard_merge_label, "OpLabel");
  }
  if s.inline_helper_contexts.count > 0 s.inline_helper_contexts.count -= 1;
  if s.inline_return_targets.count > 0 s.inline_return_targets.count -= 1;

  add_op(s, "OpBranch", helper_exit_label, is_terminator=true);
  add_op(s, helper_exit_label, "OpLabel");

  return true, {};
}

eval_inline_function_to_struct :: (s: *IR_SPV_Gen_State, helper: *IR_Function, call_args: [] *IR_Expr, out_struct: *IR_SPV_Gen_Local_Struct) -> (ok: bool, diag: IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !helper {
    return false, make_diag("missing helper metadata for inline struct call.");
  }
  if !out_struct {
    return false, make_diag("null destination struct for inline helper call.");
  }
  out_struct_name := out_struct.name;
  out_struct_type := out_struct.type_name;
  if helper.return_type.kind != .STRUCT {
    return false, make_diag("helper '%' return type is not a struct.", helper.name);
  }
  helper_return_struct_name := spv_struct_name_from_ir_type(helper.return_type);
  if helper_return_struct_name != out_struct_type {
    helper_return_text := helper.return_type.display_name;
    if helper_return_text.count == 0 helper_return_text = helper_return_struct_name;
    if helper_return_text.count == 0 helper_return_text = "<unknown>";
    return false, make_diag("helper '%' return type '%' does not match destination struct '%'.", helper.name, helper_return_text, out_struct_type);
  }

  local_count_before := s.locals.count;
  local_array_count_before := s.local_arrays.count;
  local_struct_count_before := s.local_structs.count;
  buffer_count_before := s.buffers.count;
  defer {
    s.locals.count = local_count_before;
    s.local_arrays.count = local_array_count_before;
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
  result_zero := get_null_const(s, result_type_id.*);
  add_local_decl(s, "% = OpVariable % Function %", id_text(result_ptr_id.*), id_text(result_ptr_type_id.*), id_text(result_zero));
  return true, diag;
}

// -----------------------------------------------------------------------------
// Expression Emission
// -----------------------------------------------------------------------------

emit_expr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (value_id: s64, value_type: IR_SPV_Gen_Type, ok: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any, code_node: *Code_Node = null) #expand { 
      diag := make_diag(msg, ..args);
      if code_node {
          diag.location = make_location(code_node);
          diag.has_location = true;
      }
      `return 0, .UNKNOWN, false, diag; 
  }

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
      if !local {
        function_constant_decl := spv_function_constant_declaration_from_expr(expr);
        function_constant := ifx function_constant_decl then find_function_constant_by_decl(s, function_constant_decl) else find_function_constant_by_name(s, expr.text);
        if function_constant {
          if function_constant.type == {
            case .BOOL;  return function_constant.id, .BOOL, true, diag;
            case .U32;   return function_constant.id, .UINT, true, diag;
            case .S32;   return function_constant.id, .INT, true, diag;
            case .FLOAT; return function_constant.id, .FLOAT, true, diag;
            case .FLOAT2; return function_constant.id, .FLOAT2, true, diag;
            case .FLOAT3; return function_constant.id, .FLOAT3, true, diag;
            case .FLOAT4; return function_constant.id, .FLOAT4, true, diag;
          }
        }
        return_err("unknown identifier '%'.", expr.text);
      }
      value_id := new_id(s);
      result_type_id := type_id_from_kind(s, local.type);
      assert(result_type_id != 0);
      add_op(s, value_id, "OpLoad", result_type_id, local.ptr_id);
      return value_id, local.type, true, diag;
    }

    case .MEMBER; {
      path := expr_text(expr);
      if expr.builtin_ref.component >= 0 && expr.builtin_ref.component <= 2 {
        if expr.builtin_ref.kind == .DISPATCH_THREAD_ID {
          return load_builtin_vec3_component(s, s.id_gl_global_invocation_id, expr.builtin_ref.component), .UINT, true, diag;
        }
        if expr.builtin_ref.kind == .GROUP_THREAD_ID {
          return load_builtin_vec3_component(s, s.id_gl_local_invocation_id, expr.builtin_ref.component), .UINT, true, diag;
        }
        if expr.builtin_ref.kind == .GROUP_ID {
          return load_builtin_vec3_component(s, s.id_gl_workgroup_id, expr.builtin_ref.component), .UINT, true, diag;
        }
      }
      if expr.builtin_ref.kind == .GROUP_INDEX && expr.builtin_ref.component == -1 {
        return load_builtin_u32(s, s.id_gl_local_invocation_index), .UINT, true, diag;
      }
      if expr.left && expr.left.kind == .CALL && expr.left.left && expr.left.left.kind == .IDENT {
        call_builtin := call_builtin_kind_for_expr(expr.left);
        if call_builtin == .NONE {
          call_builtin = call_builtin_kind_from_callee_name(expr.left.left.text);
          if call_builtin == .NONE {
            has_sample_3d, _ := contains(expr.left.left.text, "sample_3d");
            has_write_3d, _ := contains(expr.left.left.text, "write_3d");
            if has_sample_3d call_builtin = .SAMPLE_3D;
            if has_write_3d call_builtin = .WRITE_3D;
          }
        }
        if call_builtin != .NONE {
          call_value_id, call_value_type, call_ok, call_diag := emit_expr(s, expr.left);
          if !call_ok return 0, .UNKNOWN, false, call_diag;
          access_kind := ir_member_access_kind_from_name(expr.text);
          if access_kind != .NONE {
            member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, call_value_id, call_value_type, access_kind, expr.text);
            return member_id, member_type, member_ok, member_diag;
          }
        }
        helper := find_function(s, expr.left.left.text);
        if !helper return_err("unknown helper '%'.", expr.left.left.text);
        helper_ret_kind := spv_kind_from_ir_type(helper.return_type);
        helper_ret_text := helper.return_type.display_name;
        if helper_ret_text.count == 0 helper_ret_text = spv_struct_name_from_ir_type(helper.return_type);
        if helper_ret_text.count == 0 helper_ret_text = "<unknown>";
        if helper_ret_kind == .STRUCT {
          temp_name := tprint("__call_ret_%", new_id(s));
          helper_ret_struct_name := spv_struct_name_from_ir_type(helper.return_type);
          temp_struct, temp_ok, temp_diag := alloc_local_struct(s, temp_name, helper_ret_struct_name);
          if !temp_ok return 0, .UNKNOWN, false, temp_diag;
          call_ok, call_diag := eval_inline_function_to_struct(s, helper, expr.left.args, temp_struct);
          if !call_ok return 0, .UNKNOWN, false, call_diag;
          temp_struct = find_local_struct(s, temp_name);
          if !temp_struct return_err("inline helper result struct '%' went missing.", temp_name);
          field := find_local_struct_field(temp_struct, expr.text);
          if !field return_err("helper call return type '%' has no field '%'.", helper_ret_text, expr.text);
          value_id := new_id(s);
          type_id := type_id_from_kind(s, field.type);
          add_op(s, value_id, "OpLoad", type_id, field.ptr_id);
          return value_id, field.type, true, diag;
        }
        if helper_ret_kind == .FLOAT2 || helper_ret_kind == .FLOAT3 || helper_ret_kind == .FLOAT4 {
          helper_value_id, helper_value_type, helper_ok, helper_diag := eval_inline_function(s, helper, expr.left.args);
          if !helper_ok return 0, .UNKNOWN, false, helper_diag;
          member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, helper_value_id, helper_value_type, expr.member_access, expr.text);
          if !member_ok return 0, .UNKNOWN, false, member_diag;
          return member_id, member_type, true, diag;
        }
        return_err("member access on unsupported call return '%'.", helper_ret_text);
      }
      if expr.left && expr.left.kind == .SUBSCRIPT {
        field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr(s, expr.left, expr.text);
        if field_ok {
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, field_type);
          if value_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
          emit_load(s, value_id, value_type_id, field_ptr, field_type, needs_physical_align=true);
          out_id, out_type, out_ok, out_diag := coerce_to_expr_result_kind(s, expr, value_id, field_type);
          if !out_ok return 0, .UNKNOWN, false, out_diag;
          return out_id, out_type, true, diag;
        }
        // Non-buffer subscripts (for example uniform-array or local-array indexing) should
        // continue through the generic member-expression path below.
      }
      if expr.left {
        if expr.left.kind == .SUBSCRIPT {
          field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_array_element_field_ptr(s, expr.left, expr.text);
          if field_ok {
            value_type_id := type_id_from_kind(s, field_type);
            if value_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
            field_value := new_id(s);
            emit_load(s, field_value, value_type_id, field_ptr, field_type, needs_physical_align=true);
            if expr.member_access != .NONE {
              member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, field_value, field_type, expr.member_access, expr.text);
              if member_ok return member_id, member_type, true, diag;
              return 0, .UNKNOWN, false, member_diag;
            }
            out_id, out_type, out_ok, out_diag := coerce_to_expr_result_kind(s, expr, field_value, field_type);
            if !out_ok return 0, .UNKNOWN, false, out_diag;
            return out_id, out_type, true, diag;
          }
          _ = field_diag;
        }

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
            member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, left_id, left_type, expr.member_access, expr.text);
            if member_ok return member_id, member_type, true, diag;
            return 0, .UNKNOWN, false, member_diag;
          }
          if !left_ok && expr.left.kind != .IDENT && expr.left.kind != .MEMBER && expr.left.kind != .SUBSCRIPT {
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

        buffer_field_ptr, buffer_field_type, buffer_field_ok, _ := emit_buffer_struct_field_ptr_from_member_expr(s, expr);
        if buffer_field_ok {
          value_id := new_id(s);
          value_type_id := type_id_from_kind(s, buffer_field_type);
          if value_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
          emit_load(s, value_id, value_type_id, buffer_field_ptr, buffer_field_type, needs_physical_align=true);
          out_id, out_type, out_ok, out_diag := coerce_to_expr_result_kind(s, expr, value_id, buffer_field_type);
          if !out_ok return 0, .UNKNOWN, false, out_diag;
          return out_id, out_type, true, diag;
        }

        physical_value_id, physical_value_type, physical_value_ok, _ := emit_physical_root_pod_field_value_from_member_expr(s, expr);
        if physical_value_ok {
          out_id, out_type, out_ok, out_diag := coerce_to_expr_result_kind(s, expr, physical_value_id, physical_value_type);
          if !out_ok return 0, .UNKNOWN, false, out_diag;
          return out_id, out_type, true, diag;
        }

        local := find_local(s, expr.left.text);
        if local && (local.type == .FLOAT2 || local.type == .FLOAT3 || local.type == .FLOAT4) {
          vec_value := new_id(s);
          vec_type_id := s.id_float4;
          if local.type == .FLOAT2 vec_type_id = s.id_float2;
          if local.type == .FLOAT3 vec_type_id = s.id_float3;
          add_op(s, vec_value, "OpLoad", vec_type_id, local.ptr_id);
          member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, vec_value, local.type, expr.member_access, expr.text);
          if member_ok return member_id, member_type, true, diag;
          return 0, .UNKNOWN, false, member_diag;
        }
      }
      if expr.left && expr.left.kind == .MEMBER &&
         expr.left.left && expr.left.left.kind == .SUBSCRIPT {
        field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_array_element_field_ptr(s, expr.left.left, expr.left.text);
        if !field_ok {
          field_ptr, field_type, field_ok, field_diag = emit_buffer_struct_field_ptr(s, expr.left.left, expr.left.text);
        }
        if field_ok {
          if field_type != .FLOAT2 && field_type != .FLOAT3 && field_type != .FLOAT4 {
            return_err("unsupported member expression(1) '%'.", path);
          }
          field_type_id := type_id_from_kind(s, field_type);
          if field_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
          field_value := new_id(s);
          emit_load(s, field_value, field_type_id, field_ptr, field_type, needs_physical_align=true);
          member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, field_value, field_type, expr.member_access, expr.text);
          if !member_ok return 0, .UNKNOWN, false, member_diag;
          return member_id, member_type, true, diag;
        }
      }
      if expr.left && expr.left.kind == .MEMBER {
        field_ptr, field_type, field_ok, field_diag := emit_buffer_struct_field_ptr_from_member_expr(s, expr.left);
        _ = field_diag;
        if field_ok && (field_type == .FLOAT2 || field_type == .FLOAT3 || field_type == .FLOAT4) {
          field_type_id := type_id_from_kind(s, field_type);
          if field_type_id == 0 return_err("unsupported loaded field type for '%'.", path);
          field_value := new_id(s);
          emit_load(s, field_value, field_type_id, field_ptr, field_type, needs_physical_align=true);
          member_id, member_type, member_ok, member_diag := spv_extract_vector_member(s, field_value, field_type, expr.member_access, expr.text);
          if member_ok return member_id, member_type, true, diag;
          _ = member_diag;
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
          if parent_field.type != .STRUCT return_err("unsupported member expression(2) '%'.", path);
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
      if expr.left && expr.left.kind == .MEMBER {
        _, _, debug_field_ok, debug_field_diag := emit_buffer_struct_field_ptr_from_member_expr(s, expr.left);
        if !debug_field_ok && debug_field_diag.message.count != 0 {
          return_err("unsupported member expression(3) '%': %", path, debug_field_diag.message);
        }
      }
      return_err("unsupported member expression(4) '%'.", path, code_node=expr.origin_node);
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

      if expr.left && expr.left.kind == .MEMBER {
        ptr, elem_type, ptr_ok, ptr_diag := emit_buffer_struct_array_element_ptr(s, expr.left, expr.right);
        if ptr_ok {
          value_type_id := type_id_from_kind(s, elem_type);
          if value_type_id == 0 return_err("unsupported struct-buffer array element type for '%'.", expr_text(expr.left));
          value_id := new_id(s);
          emit_load(s, value_id, value_type_id, ptr, elem_type, needs_physical_align=true);
          out_id, out_type, out_ok, out_diag := coerce_to_expr_result_kind(s, expr, value_id, elem_type);
          if !out_ok return 0, .UNKNOWN, false, out_diag;
          return out_id, out_type, true, diag;
        }
        // Keep existing fallback paths for non-buffer member subscripts.
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

      buffer_name, base_ok := resolve_buffer_name_from_expr(expr.left);
      if !base_ok {
        return_err("subscript base must resolve to an identifier/member.");
      }
      buffer := find_buffer(s, buffer_name);
      if !buffer return_err("unknown subscript base '%'.", buffer_name);
      idx, idx_type, idx_ok, idx_diag := emit_expr(s, expr.right);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      idx, idx_ok, idx_diag = coerce_to_kind(s, idx, idx_type, .UINT);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      idx = apply_buffer_base_index(s, buffer, idx);
      if buffer.element_kind != .STRUCT {
        value_ptr_id := new_id(s);
        add_op(s, value_ptr_id, "OpAccessChain", buffer.ptr_storage_element_type_id, buffer.var_id, s.id_int_0, idx);
        value_id := new_id(s);
        value_type_id := type_id_from_kind(s, buffer.element_kind);
        assert(value_type_id != 0);
        emit_load(s, value_id, value_type_id, value_ptr_id, buffer.element_kind, needs_physical_align=true);
        return value_id, buffer.element_kind, true, diag;
      }
      reinterpret_ptr, reinterpret_type, reinterpret_ok, reinterpret_diag := emit_buffer_struct_reinterpret_const_subscript_ptr(s, buffer, expr);
      if reinterpret_ok {
        value_type_id := type_id_from_kind(s, reinterpret_type);
        if value_type_id == 0 return_err("unsupported struct-buffer reinterpret load type for '%'.", expr_text(expr));
        value_id := new_id(s);
        emit_load(s, value_id, value_type_id, reinterpret_ptr, reinterpret_type, needs_physical_align=true);
        return value_id, reinterpret_type, true, diag;
      }
      if reinterpret_diag.message.count != 0 return 0, .UNKNOWN, false, reinterpret_diag;
      return_err("subscript value access for struct buffer '%' is unsupported; access a field instead (expr='%').", buffer.name, expr_text(expr));
    }

    case .BINARY; {
      left_id, left_type, left_ok, left_diag := emit_expr(s, expr.left);
      if !left_ok return 0, .UNKNOWN, false, left_diag;

      op, op_ok := ir_expr_binary_op_text(expr);
      if !op_ok return_err("binary expression missing operator text.");
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
          add_op(s, "OpBranchConditional", left_bool, rhs_label, short_label, is_terminator=true);
        } else {
          add_op(s, "OpBranchConditional", left_bool, short_label, rhs_label, is_terminator=true);
        }

        add_op(s, short_label, "OpLabel");
        short_value := s.id_bool_false;
        if op == "||" short_value = s.id_bool_true;
        emit_store(s, result_ptr_id, short_value, .BOOL);
        add_op(s, "OpBranch", merge_label, is_terminator=true);

        add_op(s, rhs_label, "OpLabel");
        right_id, right_type, right_ok, right_diag := emit_expr(s, expr.right);
        if !right_ok return 0, .UNKNOWN, false, right_diag;
        right_bool, right_bool_ok, right_bool_diag := coerce_to_kind(s, right_id, right_type, .BOOL);
        if !right_bool_ok return 0, .UNKNOWN, false, right_bool_diag;
        emit_store(s, result_ptr_id, right_bool, .BOOL);
        add_op(s, "OpBranch", merge_label, is_terminator=true);

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
      if left_type == .FLOAT || left_type == .FLOAT16 || right_type == .FLOAT || right_type == .FLOAT16 {
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

      result_type := spv_kind_from_ir_expr_result(expr);
      result_ptr_id: s64 = 0;
      result_ptr_type_id: s64 = 0;
      result_type_id: s64 = 0;

      then_label := new_id(s);
      else_label := new_id(s);
      merge_label := new_id(s);
      add_op(s, tprint("               OpSelectionMerge % None", id_text(merge_label)));
      add_op(s, "OpBranchConditional", cond_id, then_label, else_label, is_terminator=true);

      add_op(s, then_label, "OpLabel");
      then_id, then_type, then_ok, then_diag := emit_expr(s, expr.right);
      if !then_ok return 0, .UNKNOWN, false, then_diag;
      if result_type == .UNKNOWN result_type = then_type;
      storage_ok, storage_diag := ensure_select_result_storage(s, result_type, *result_ptr_id, *result_ptr_type_id, *result_type_id);
      if !storage_ok return 0, .UNKNOWN, false, storage_diag;
      then_id, then_type, then_ok, then_diag = coerce_to_exact_kind(s, then_id, then_type, result_type);
      if !then_ok return 0, .UNKNOWN, false, then_diag;
      emit_store(s, result_ptr_id, then_id, result_type);
      add_op(s, "OpBranch", merge_label, is_terminator=true);

      add_op(s, else_label, "OpLabel");
      else_id, else_type, else_ok, else_diag := emit_expr(s, expr.args[0]);
      if !else_ok return 0, .UNKNOWN, false, else_diag;
      else_id, else_type, else_ok, else_diag = coerce_to_exact_kind(s, else_id, else_type, result_type);
      if !else_ok {
        return_err("select branches must resolve to a common type (then=% else=% target=%).", then_type, else_type, result_type);
      }
      emit_store(s, result_ptr_id, else_id, result_type);
      add_op(s, "OpBranch", merge_label, is_terminator=true);

      add_op(s, merge_label, "OpLabel");
      out := new_id(s);
      emit_load(s, out, result_type_id, result_ptr_id, result_type);
      return out, result_type, true, diag;
    }

    case .CAST; {
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;

      target_kind := spv_kind_from_ir_expr_result(expr);
      if target_kind == .UNKNOWN return_err("unsupported cast target '%'.", expr.text);
      converted_id, converted_ok, converted_diag := coerce_to_kind(s, inner_id, inner_type, target_kind);
      if !converted_ok return 0, .UNKNOWN, false, converted_diag;
      return converted_id, target_kind, true, diag;
    }

    case .UNARY; {
      if !expr.left return_err("unary expression missing operand.");
      if expr.unary_op == .DEREF {
        ptr_id, ptr_type, ptr_ok, ptr_diag := emit_lvalue_ptr(s, expr);
        if !ptr_ok return 0, .UNKNOWN, false, ptr_diag;
        value_type_id := type_id_from_kind(s, ptr_type);
        if value_type_id == 0 return_err("unary '*' unsupported for pointee type %.", ptr_type);
        out := new_id(s);
        emit_load(s, out, value_type_id, ptr_id, ptr_type, needs_physical_align=true);
        return out, ptr_type, true, diag;
      }
      if expr.unary_op == .ADDRESS_OF return_err("unary address-of is only supported as a helper pointer argument.");
      op, op_ok := ir_expr_unary_op_text(expr);
      if !op_ok return_err("unary expression missing operator text.");
      inner_id, inner_type, inner_ok, inner_diag := emit_expr(s, expr.left);
      if !inner_ok return 0, .UNKNOWN, false, inner_diag;
      if op == "+" return inner_id, inner_type, true, diag;
      if op == "-" {
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
      if op == "!" {
        if inner_type != .BOOL return_err("unary '!' requires bool.");
        out := new_id(s);
        add_op(s, out, "OpLogicalNot", s.id_bool, inner_id);
        return out, .BOOL, true, diag;
      }
      if op == "~" {
        if !is_integral_kind(inner_type) return_err("unary '~' requires integer.");
        out := new_id(s);
        type_id := type_id_from_kind(s, inner_type);
        add_op(s, out, "OpNot", type_id, inner_id);
        return out, inner_type, true, diag;
      }
      return_err("unsupported unary op '%'.", op);
    }

    case .CALL; {
      if !expr.left return_err("unsupported call target expression.");
      builtin_kind := call_builtin_kind_for_expr(expr);
      helper_name, helper_name_ok := call_helper_name_for_expr(expr);
      if builtin_kind == .NONE && helper_name_ok {
        builtin_kind = call_builtin_kind_from_callee_name(helper_name);
        if builtin_kind == .NONE {
          has_sample_3d, _ := contains(helper_name, "sample_3d");
          has_write_3d, _ := contains(helper_name, "write_3d");
          if has_sample_3d builtin_kind = .SAMPLE_3D;
          if has_write_3d builtin_kind = .WRITE_3D;
        }
      }
      if !helper_name_ok && builtin_kind == .NONE return_err("unsupported call target expression.");
      if builtin_kind == .SAMPLE_2D {
        sampled_id, sampled_type, sampled_ok, sampled_diag := emit_sample_2d_call(s, expr.args);
        return sampled_id, sampled_type, sampled_ok, sampled_diag;
      }
      if builtin_kind == .SAMPLE_3D {
        sampled_id, sampled_type, sampled_ok, sampled_diag := emit_sample_3d_call(s, expr.args);
        return sampled_id, sampled_type, sampled_ok, sampled_diag;
      }
      if builtin_kind == .WRITE_2D {
        return_err("write_2d has no return value and must be used as a statement.");
      }
      if builtin_kind == .WRITE_3D {
        return_err("write_3d has no return value and must be used as a statement.");
      }
      if builtin_kind == .DISCARD {
        return_err("discard has no return value and must be used as a statement.");
      }
      if builtin_kind == .ATOMIC_ADD_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_u32_call(s, "OpAtomicIAdd", expr.args);
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .ATOMIC_SUB_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_sub_u32_call(s, expr.args);
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .ATOMIC_EXCHANGE_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_u32_call(s, "OpAtomicExchange", expr.args);
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .ATOMIC_COMPARE_EXCHANGE_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_compare_exchange_u32_call(s, expr.args);
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .ATOMIC_MIN_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_reduce_u32_call(s, expr.args, "min");
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .ATOMIC_MAX_U32 {
        atomic_id, atomic_type, atomic_ok, atomic_diag := emit_atomic_reduce_u32_call(s, expr.args, "max");
        return atomic_id, atomic_type, atomic_ok, atomic_diag;
      }
      if builtin_kind == .RADIANS {
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
      if builtin_kind == .DEGREES {
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
      if builtin_kind == .MOD || builtin_kind == .FMOD_CYCLING {
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
      if builtin_kind == .SATURATE {
        if expr.args.count != 1 return_err("saturate expects 1 arg.");
        v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
        if !v_ok return 0, .UNKNOWN, false, v_diag;
        zero := get_f32_const(s, "0.0");
        one := get_f32_const(s, "1.0");
        if v_type == .FLOAT2 {
          v2, v2_ok, v2_diag := coerce_to_float2(s, v_id, v_type);
          if !v2_ok return 0, .UNKNOWN, false, v2_diag;
          lo2 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float2, zero, zero);
          hi2 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float2, one, one);
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "FClamp",
                           id_text(v2), id_text(lo2), id_text(hi2)));
          return out, .FLOAT2, true, diag;
        }
        if v_type == .FLOAT3 {
          v3, v3_ok, v3_diag := coerce_to_float3(s, v_id, v_type);
          if !v3_ok return 0, .UNKNOWN, false, v3_diag;
          lo3 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float3, zero, zero, zero);
          hi3 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float3, one, one, one);
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "FClamp",
                           id_text(v3), id_text(lo3), id_text(hi3)));
          return out, .FLOAT3, true, diag;
        }
        if v_type == .FLOAT4 {
          v4, v4_ok, v4_diag := coerce_to_float4(s, v_id, v_type);
          if !v4_ok return 0, .UNKNOWN, false, v4_diag;
          lo4 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float4, zero, zero, zero, zero);
          hi4 := add_op(s, new_id(s), "OpCompositeConstruct", s.id_float4, one, one, one, one);
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % % %",
                           id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "FClamp",
                           id_text(v4), id_text(lo4), id_text(hi4)));
          return out, .FLOAT4, true, diag;
        }
        vf, vf_ok, vf_diag := coerce_to_float(s, v_id, v_type);
        if !vf_ok return 0, .UNKNOWN, false, vf_diag;
        out := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %",
                         id_text(out), id_text(s.id_float), id_text(s.id_extinst), "FClamp",
                         id_text(vf), id_text(zero), id_text(one)));
        return out, .FLOAT, true, diag;
      }
      if builtin_kind == .CLAMP {
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
      if builtin_kind == .STEP {
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
      if builtin_kind == .MIX || builtin_kind == .LERP {
        if expr.args.count != 3 return_err("mix/lerp expects 3 args.");
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
        out := new_id(s);
        add_op(s, tprint("         % = OpExtInst % % % % % %",
                         id_text(out), id_text(s.id_float), id_text(s.id_extinst), "FMix",
                         id_text(xf), id_text(yf), id_text(af)));
        return out, .FLOAT, true, diag;
      }
      if builtin_kind == .REFLECT {
        if expr.args.count != 2 return_err("reflect expects 2 args.");
        i_id, i_type, i_ok, i_diag := emit_expr(s, expr.args[0]);
        if !i_ok return 0, .UNKNOWN, false, i_diag;
        n_id, n_type, n_ok, n_diag := emit_expr(s, expr.args[1]);
        if !n_ok return 0, .UNKNOWN, false, n_diag;
        if i_type == .FLOAT2 || n_type == .FLOAT2 {
          iv, iv_ok, iv_diag := coerce_to_float2(s, i_id, i_type);
          if !iv_ok return 0, .UNKNOWN, false, iv_diag;
          nv, nv_ok, nv_diag := coerce_to_float2(s, n_id, n_type);
          if !nv_ok return 0, .UNKNOWN, false, nv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %",
                           id_text(out), id_text(s.id_float2), id_text(s.id_extinst), "Reflect",
                           id_text(iv), id_text(nv)));
          return out, .FLOAT2, true, diag;
        }
        if i_type == .FLOAT3 || n_type == .FLOAT3 {
          iv, iv_ok, iv_diag := coerce_to_float3(s, i_id, i_type);
          if !iv_ok return 0, .UNKNOWN, false, iv_diag;
          nv, nv_ok, nv_diag := coerce_to_float3(s, n_id, n_type);
          if !nv_ok return 0, .UNKNOWN, false, nv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %",
                           id_text(out), id_text(s.id_float3), id_text(s.id_extinst), "Reflect",
                           id_text(iv), id_text(nv)));
          return out, .FLOAT3, true, diag;
        }
        if i_type == .FLOAT4 || n_type == .FLOAT4 {
          iv, iv_ok, iv_diag := coerce_to_float4(s, i_id, i_type);
          if !iv_ok return 0, .UNKNOWN, false, iv_diag;
          nv, nv_ok, nv_diag := coerce_to_float4(s, n_id, n_type);
          if !nv_ok return 0, .UNKNOWN, false, nv_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % % %",
                           id_text(out), id_text(s.id_float4), id_text(s.id_extinst), "Reflect",
                           id_text(iv), id_text(nv)));
          return out, .FLOAT4, true, diag;
        }
        return_err("reflect requires float2/float3/float4 args, got (%, %).", i_type, n_type);
      }
      if builtin_kind == .POW {
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
      if builtin_kind == .SMOOTHSTEP {
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
      if builtin_kind == .MUL {
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
      if builtin_kind == .FLOOR || builtin_kind == .MIN || builtin_kind == .MAX ||
         builtin_kind == .ABS || builtin_kind == .SQRT || builtin_kind == .EXP || builtin_kind == .SIN || builtin_kind == .COS || builtin_kind == .FRACT || builtin_kind == .LENGTH || builtin_kind == .NORMALIZE {
        if builtin_kind == .LENGTH {
          if expr.args.count != 1 return_err("length expects 1 arg.");
          v_id, v_type, v_ok, v_diag := emit_expr(s, expr.args[0]);
          if !v_ok return 0, .UNKNOWN, false, v_diag;
          v2, v2_ok, v2_diag := coerce_to_float2(s, v_id, v_type);
          if !v2_ok return 0, .UNKNOWN, false, v2_diag;
          out := new_id(s);
          add_op(s, tprint("         % = OpExtInst % % % %", id_text(out), id_text(s.id_float), id_text(s.id_extinst), "Length", id_text(v2)));
          return out, .FLOAT, true, diag;
        }
        if builtin_kind == .NORMALIZE {
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
        builtin_name := call_builtin_kind_to_name(builtin_kind);
        if builtin_name.count == 0 return_err("internal backend error: unsupported builtin enum %.", builtin_kind);
        builtin_id, builtin_type, builtin_ok, builtin_diag := emit_float_builtin_call(s, builtin_name, expr.args);
        if !builtin_ok return 0, .UNKNOWN, false, builtin_diag;
        return builtin_id, builtin_type, true, diag;
      }
      helper := find_function(s, helper_name);
      if !helper return_err("unsupported call target '%'.", helper_name);
      helper_id, helper_type, helper_ok, helper_diag := eval_inline_function(s, helper, expr.args);
      return helper_id, helper_type, helper_ok, helper_diag;
    }

    case .CONSTRUCTOR; {
      ctor_type := spv_kind_from_ir_expr_result(expr);
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

// -----------------------------------------------------------------------------
// Statement Emission
// -----------------------------------------------------------------------------

spv_local_decl_default_initializer :: (s: *IR_SPV_Gen_State, decl_type: IR_Type, scalar_kind: IR_SPV_Gen_Type, array_type_id: s64 = 0) -> (init_id: s64, ok: bool, diag: IR_Diagnostic) {
  if scalar_kind != .UNKNOWN {
    type_id := type_id_from_kind(s, scalar_kind);
    if type_id == 0 return 0, false, make_diag("missing SPIR-V type id for scalar declaration kind %.", scalar_kind);
    return get_null_const(s, type_id), true, {};
  }
  if decl_type.kind == .FIXED_ARRAY {
    if array_type_id == 0 return 0, false, make_diag("missing SPIR-V fixed-array type id for local declaration.");
    return get_null_const(s, array_type_id), true, {};
  }
  return 0, false, make_diag("unsupported local declaration kind for default initialization (%).", decl_type.kind);
}

emit_stmt :: (s: *IR_SPV_Gen_State, stmt: *IR_Stmt) -> (ok: bool, terminated: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, make_diag(msg, ..args); }
  
  diag: IR_Diagnostic;
  if !stmt return_err("null statement.");
  
  if stmt.kind == {
    case .DECL; {
      decl_type := spv_kind_from_ir_type(stmt.decl_type);
      if decl_type == .INT || decl_type == .UINT || decl_type == .INT64 || decl_type == .UINT64 ||
         decl_type == .BOOL || decl_type == .FLOAT16 || decl_type == .FLOAT || decl_type == .FLOAT2 || decl_type == .FLOAT3 || decl_type == .FLOAT4 || decl_type == .FLOAT2X2 {
        ptr_id := new_id(s);
        ptr_type_id := func_ptr_type_id_from_kind(s, decl_type);
        assert(ptr_type_id != 0);
        local_zero, local_zero_ok, local_zero_diag := spv_local_decl_default_initializer(s, stmt.decl_type, decl_type);
        if !local_zero_ok return false, false, local_zero_diag;
        add_local_decl(s, "% = OpVariable % Function %", id_text(ptr_id), id_text(ptr_type_id), id_text(local_zero));
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

      array_elem_type_name, array_count, elem_type, is_fixed_array := spv_fixed_array_info_from_ir_type(stmt.decl_type);
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
        array_zero, array_zero_ok, array_zero_diag := spv_local_decl_default_initializer(s, stmt.decl_type, .UNKNOWN, array_type_id);
        if !array_zero_ok return false, false, array_zero_diag;
        add_local_decl(s, "% = OpVariable % Function %", id_text(ptr_id), id_text(ptr_func_array_type_id), id_text(array_zero));
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

      struct_type_name := stmt.decl_type.struct_name;
      if struct_type_name.count == 0 {
        decl_type_name := ir_string_first_non_empty(stmt.decl_type.display_name, stmt.decl_type.struct_name, "<unknown>");
        return_err("unsupported declaration type '%': missing typed struct metadata.", decl_type_name);
      }
      struct_def := find_struct(s, struct_type_name);
      if !struct_def {
        return_err("unsupported declaration type '%'.", struct_type_name);
      }
      local_struct, local_struct_ok, local_struct_diag := alloc_local_struct(s, stmt.decl_name, struct_type_name);
      if !local_struct_ok return false, false, local_struct_diag;

      if stmt.decl_init {
        init_struct_name := spv_struct_name_from_ir_expr_result(stmt.decl_init);
        if stmt.decl_init.kind == .CONSTRUCTOR &&
           init_struct_name == struct_type_name {
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
          buffer_name, base_ok := resolve_buffer_name_from_expr(stmt.decl_init.left);
          if !base_ok {
            return_err("struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          buffer := find_buffer(s, buffer_name);
          if !buffer || buffer.element_kind != .STRUCT || buffer.element_struct_name != struct_type_name {
            return_err("struct declaration '%': unsupported subscript initializer '%'.", stmt.decl_name, expr_text(stmt.decl_init));
          }
          load_ok, load_diag := load_buffer_struct_into_local_struct(s, local_struct, stmt.decl_init);
          if !load_ok return false, false, make_diag("struct declaration '%': subscript initializer failed: %", stmt.decl_name, load_diag.message);
        } else if stmt.decl_init.kind == .CALL && stmt.decl_init.left && stmt.decl_init.left.kind == .IDENT {
          helper := find_function(s, stmt.decl_init.left.text);
          helper_return_struct_name := "";
          if helper {
            if helper.return_type.kind == .STRUCT {
              helper_return_struct_name = spv_struct_name_from_ir_type(helper.return_type);
            }
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
      op, op_ok := ir_stmt_binary_op_text(stmt);
      if !op_ok return_err("statement binary expression missing operator text.");

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
            if src_struct.type_name != dst_buffer.element_struct_name {
              return_err("struct buffer assignment type mismatch ('%' vs '%').",
                         dst_buffer.element_struct_name, src_struct.type_name);
            }
          } else if stmt.binary_right && stmt.binary_right.kind == .CALL &&
                    stmt.binary_right.left && stmt.binary_right.left.kind == .IDENT {
            helper := find_function(s, stmt.binary_right.left.text);
            helper_return_struct_name := "";
            if helper {
              if helper.return_type.kind == .STRUCT {
                helper_return_struct_name = spv_struct_name_from_ir_type(helper.return_type);
              }
            }
            if !helper || helper_return_struct_name != dst_buffer.element_struct_name {
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
          } else if stmt.binary_right && stmt.binary_right.kind == .CONSTRUCTOR &&
                    spv_struct_name_from_ir_expr_result(stmt.binary_right) == dst_buffer.element_struct_name {
            tmp_name := tprint("__assign_src_%", new_id(s));
            tmp_struct, tmp_ok, tmp_diag := alloc_local_struct(s, tmp_name, dst_buffer.element_struct_name);
            if !tmp_ok return false, false, tmp_diag;
            init_ok, init_diag := init_local_struct_from_expr(s, tmp_struct, stmt.binary_right);
            if !init_ok return false, false, init_diag;
            src_struct = find_local_struct(s, tmp_name);
            if !src_struct {
              return_err("constructor assignment source struct '%' went missing.", tmp_name);
            }
          } else if stmt.binary_right && stmt.binary_right.kind == .SUBSCRIPT {
            src_buffer_name, src_base_ok := resolve_buffer_name_from_expr(stmt.binary_right.left);
            src_buffer := ifx src_base_ok then find_buffer(s, src_buffer_name) else null;
            if !src_buffer || src_buffer.element_kind != .STRUCT || src_buffer.element_struct_name != dst_buffer.element_struct_name {
              return_err("struct buffer assignment subscript rhs '%' has incompatible source type.", expr_text(stmt.binary_right));
            }
            tmp_name := tprint("__assign_src_%", new_id(s));
            tmp_struct, tmp_ok, tmp_diag := alloc_local_struct(s, tmp_name, dst_buffer.element_struct_name);
            if !tmp_ok return false, false, tmp_diag;
            load_ok, load_diag := load_buffer_struct_into_local_struct(s, tmp_struct, stmt.binary_right);
            if !load_ok return false, false, make_diag("struct buffer assignment subscript rhs load failed: %", load_diag.message);
            src_struct = find_local_struct(s, tmp_name);
            if !src_struct {
              return_err("subscript assignment source struct '%' went missing.", tmp_name);
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
            if src_field.type == .STRUCT {
              src_nested := find_local_struct(s, src_field.nested_struct_name);
              if !src_nested {
                return_err("struct assignment source nested field '%' missing.", it.name);
              }
              packed_id, packed_type, packed_ok, packed_diag := pack_local_struct_alias_to_value(s, src_nested, it.type);
              if !packed_ok return false, false, make_diag("struct assignment nested field '%' pack failed: %", it.name, packed_diag.message);
              if packed_type != it.type {
                return_err("struct assignment nested field '%' type mismatch.", it.name);
              }
              emit_store(s, dst_ptr, packed_id, it.type, needs_physical_align=true);
              continue;
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
        return_err("unsupported statement binary op '%'.", op);
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
      cond_id, cond_ok, cond_diag = coerce_to_kind(s, cond_id, cond_type, .BOOL);
      if !cond_ok return false, false, cond_diag;

      then_label := new_id(s);
      merge_label := new_id(s);
      else_label := merge_label;
      if stmt.if_else else_label = new_id(s);

      add_op(s, tprint("OpSelectionMerge % None", id_text(merge_label)));
      add_op(s, "OpBranchConditional", cond_id, then_label, else_label, is_terminator=true);
      array_add(*s.control_merge_targets, merge_label);

      add_op(s, then_label, "OpLabel");
      then_ok, then_terminated, then_diag := emit_stmt_block(s, stmt.if_then);
      if !then_ok {
        if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
        return false, false, then_diag;
      }
      if !then_terminated {
        add_op(s, "OpBranch", merge_label, is_terminator=true);
      }

      else_terminated := false;
      if stmt.if_else {
        add_op(s, else_label, "OpLabel");
        else_ok, local_else_terminated, else_diag := emit_stmt_block(s, stmt.if_else);
        else_terminated = local_else_terminated;
        if !else_ok {
          if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
          return false, false, else_diag;
        }
        if !else_terminated {
          add_op(s, "OpBranch", merge_label, is_terminator=true);
        }
      }
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;

      add_op(s, merge_label, "OpLabel");
      all_terminated := false;
      if stmt.if_else {
        all_terminated = then_terminated && else_terminated;
      }
      if all_terminated {
        _, has_inline_helper_context := get_current_inline_helper_context(s);
        if has_inline_helper_context {
          parent_merge_label, has_parent_merge_label := get_current_control_merge_target(s);
          if has_parent_merge_label {
            add_op(s, "OpBranch", parent_merge_label, is_terminator=true);
          } else {
            add_op(s, "OpUnreachable", is_terminator=true);
          }
          return true, true, diag;
        }
        // Keep a concrete merge block for structured control flow, but terminate it
        // so the next emitted label starts a fresh basic block.
        add_op(s, "OpUnreachable", is_terminator=true);
        return true, true, diag;
      }
      return true, false, diag;
    }

    case .SWITCH; {
      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.switch_condition);
      if !cond_ok return false, false, cond_diag;
      switch_type := cond_type;
      if cond_type == .INT64 {
        cond_id, cond_ok, cond_diag = coerce_to_kind(s, cond_id, cond_type, .INT);
        if !cond_ok return false, false, cond_diag;
        switch_type = .INT;
      } else if cond_type == .UINT64 {
        cond_id, cond_ok, cond_diag = coerce_to_kind(s, cond_id, cond_type, .UINT);
        if !cond_ok return false, false, cond_diag;
        switch_type = .UINT;
      }
      if switch_type != .UINT && switch_type != .INT {
        return_err("switch condition must be integer.");
      }

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
        case_word: u32;
        case_ok := false;
        if switch_type == .UINT {
          case_word, case_ok = parse_u32_literal_expr(it.condition);
          if !case_ok return_err("switch case values must be uint literals.");
        } else {
          case_i64, case_i64_ok := parse_i64_literal_expr(it.condition);
          if case_i64_ok && case_i64 >= -2147483648 && case_i64 <= 2147483647 {
            case_word = cast(u32) cast(s32) case_i64;
            case_ok = true;
          }
          if !case_ok return_err("switch case values must be int literals.");
        }
        a(*switch_line_sb, " % %", case_word, id_text(case_labels[it_index]));
      }
      add_op(s, builder_to_string(*switch_line_sb), is_terminator=true);

      array_add(*s.break_targets, merge_label);
      array_add(*s.control_merge_targets, merge_label);
      for stmt.switch_cases {
        case_block := it.body;
        if !case_block {
          if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
          if s.break_targets.count > 0 s.break_targets.count -= 1;
          return_err("switch case body is missing.");
        }
        add_op(s, case_labels[it_index], "OpLabel");
        case_ok, case_terminated, case_diag := emit_stmt_block(s, case_block);
        if !case_ok {
          if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
          if s.break_targets.count > 0 s.break_targets.count -= 1;
          return false, false, case_diag;
        }
        if !case_terminated {
          target_label := merge_label;
          if it.falls_through && it_index + 1 < case_labels.count {
            target_label = case_labels[it_index+1];
          }
          add_op(s, "OpBranch", target_label, is_terminator=true);
        }
      }
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
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
      loop_zero := get_null_const(s, type_id_from_kind(s, start_type));
      add_local_decl(s, "% = OpVariable % Function %", id_text(loop_ptr), id_text(loop_ptr_type_id), id_text(loop_zero));
      add_debug_name(s, loop_ptr, loop_name);
      array_add(*s.locals, .{name=loop_name, ptr_id=loop_ptr, type=start_type});
      add_op(s, "OpStore", loop_ptr, start_id);

      header_label := new_id(s);
      body_label := new_id(s);
      continue_label := new_id(s);
      merge_label := new_id(s);

      add_op(s, "OpBranch", header_label, is_terminator=true);
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
      add_op(s, "OpBranchConditional", cmp_id, body_label, merge_label, is_terminator=true);

      add_op(s, body_label, "OpLabel");
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      array_add(*s.control_merge_targets, merge_label);
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.for_body);
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, "OpBranch", continue_label, is_terminator=true);
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
      add_op(s, "OpBranch", header_label, is_terminator=true);

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

      add_op(s, "OpBranch", header_label, is_terminator=true);
      add_op(s, header_label, "OpLabel");

      cond_id, cond_type, cond_ok, cond_diag := emit_expr(s, stmt.while_condition);
      if !cond_ok return false, false, cond_diag;
      cond_id, cond_ok, cond_diag = coerce_to_kind(s, cond_id, cond_type, .BOOL);
      if !cond_ok return false, false, cond_diag;
      add_op(s, tprint("               OpLoopMerge % % None", id_text(merge_label), id_text(continue_label)));
      add_op(s, "OpBranchConditional", cond_id, body_label, merge_label, is_terminator=true);

      add_op(s, body_label, "OpLabel");
      array_add(*s.break_targets, merge_label);
      array_add(*s.loop_targets, .{merge_label=merge_label, continue_label=continue_label});
      array_add(*s.control_merge_targets, merge_label);
      body_ok, body_terminated, body_diag := emit_stmt_block(s, stmt.while_body);
      if s.control_merge_targets.count > 0 s.control_merge_targets.count -= 1;
      if s.loop_targets.count > 0 s.loop_targets.count -= 1;
      if s.break_targets.count > 0 s.break_targets.count -= 1;
      if !body_ok return false, false, body_diag;
      if !body_terminated {
        add_op(s, "OpBranch", continue_label, is_terminator=true);
      }

      add_op(s, continue_label, "OpLabel");
      add_op(s, "OpBranch", header_label, is_terminator=true);

      add_op(s, merge_label, "OpLabel");
      return true, false, diag;
    }

    case .BREAK; {
      break_target, found := get_current_break_target(s);
      if !found return_err("break used outside loop.");
      add_op(s, "OpBranch", break_target, is_terminator=true);
      return true, true, diag;
    }

    case .CONTINUE; {
      loop_target, found := get_current_loop_target(s);
      if !found return_err("continue used outside loop.");
      add_op(s, "OpBranch", loop_target.continue_label, is_terminator=true);
      return true, true, diag;
    }

    case .CALL; {
      if !stmt.call_expr return_err("call statement is missing call expression.");
      if stmt.call_expr.kind != .CALL return_err("call statement has non-call expression.");
      if !stmt.call_expr.left return_err("unsupported call target expression.");

      builtin_kind := call_builtin_kind_for_expr(stmt.call_expr);
      helper_name, helper_name_ok := call_helper_name_for_expr(stmt.call_expr);
      if builtin_kind == .NONE && helper_name_ok {
        builtin_kind = call_builtin_kind_from_callee_name(helper_name);
        if builtin_kind == .NONE {
          has_sample_3d, _ := contains(helper_name, "sample_3d");
          has_write_3d, _ := contains(helper_name, "write_3d");
          if has_sample_3d builtin_kind = .SAMPLE_3D;
          if has_write_3d builtin_kind = .WRITE_3D;
        }
      }
      if !helper_name_ok && builtin_kind == .NONE return_err("unsupported call target expression.");

      if builtin_kind == .WRITE_2D {
        write_ok, write_diag := emit_write_2d_call(s, stmt.call_expr.args);
        if !write_ok return false, false, write_diag;
        return true, false, diag;
      }
      if builtin_kind == .WRITE_3D {
        write_ok, write_diag := emit_write_3d_call(s, stmt.call_expr.args);
        if !write_ok return false, false, write_diag;
        return true, false, diag;
      }
      if builtin_kind == .DISCARD {
        if s.stage != .FRAGMENT return_err("discard is currently fragment-stage only.");
        if stmt.call_expr.args.count != 0 return_err("discard expects 0 args.");
        add_op(s, "OpKill", is_terminator=true);
        return true, true, diag;
      }

      helper := find_function(s, helper_name);
      if helper && helper_returns_void(helper) {
        call_ok, call_diag := eval_inline_function_void(s, helper, stmt.call_expr.args);
        if !call_ok return false, false, call_diag;
        return true, false, diag;
      }

      _, _, call_ok, call_diag := emit_expr(s, stmt.call_expr);
      if !call_ok return false, false, call_diag;
      return true, false, diag;
    }

    case .RETURN; {
      inline_helper_context, has_inline_helper_context := get_current_inline_helper_context(s);
      if has_inline_helper_context {
        if stmt.return_expr {
          if !inline_helper_context.has_return_value {
            return_err("inline void helper return cannot return a value.");
          }
          raw_id, raw_type, raw_ok, raw_diag := emit_expr(s, stmt.return_expr);
          if !raw_ok return false, false, raw_diag;
          coerced_id, coerced_type, coerced_ok, coerced_diag := coerce_to_exact_kind(s, raw_id, raw_type, inline_helper_context.return_value_type);
          if !coerced_ok return false, false, coerced_diag;
          if coerced_type != inline_helper_context.return_value_type {
            return_err("inline helper return type does not match expected value type.");
          }
          add_op(s, "OpStore", inline_helper_context.return_value_ptr, coerced_id);
        } else if inline_helper_context.has_return_value {
          return_err("inline helper return must return a value.");
        }
        add_op(s, "OpStore", inline_helper_context.return_flag_ptr, s.id_bool_true);
        branch_target := inline_helper_context.exit_label;
        helper_has_break_target := s.break_targets.count > inline_helper_context.break_targets_base_count;
        if helper_has_break_target {
          branch_target = s.break_targets[s.break_targets.count-1];
        } else {
          helper_has_merge_target := s.control_merge_targets.count > inline_helper_context.control_merge_targets_base_count;
          if helper_has_merge_target {
            branch_target = s.control_merge_targets[s.control_merge_targets.count-1];
          }
        }
        add_op(s, "OpBranch", branch_target, is_terminator=true);
        return true, true, diag;
      }

      inline_return_target, has_inline_return_target := get_current_inline_return_target(s);
      if has_inline_return_target {
        if stmt.return_expr {
          return_err("inline helper return cannot return a value.");
        }
        add_op(s, "OpBranch", inline_return_target, is_terminator=true);
        return true, true, diag;
      }

      if s.stage == .COMPUTE {
        if stmt.return_expr {
          return_err("return with value is not supported yet for compute.");
        }
        add_op(s, "OpReturn", is_terminator=true);
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
      add_op(s, "OpReturn", is_terminator=true);
      return true, true, diag;
    }
  }

  return_err("unsupported statement kind %.", stmt.kind);
}

emit_stmt_block :: (using s: *IR_SPV_Gen_State, block: *IR_Block) -> (ok: bool, terminated: bool, diag: IR_Diagnostic) {
  return_err :: (msg: string, args: ..Any) #expand { `return false, false, make_diag(msg, ..args); }

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
  add_op(s, "OpReturn", is_terminator=true);
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
  for s.buffer_layout_structs {
    layout := it;
    for layout.fields {
      if it.is_array {
        a(sb, "               OpDecorate % ArrayStride %", id_text(it.array_type_id), it.array_stride);
      }
      a(sb, "               OpMemberDecorate % % Offset %", id_text(layout.type_id), it.index, it.offset);
    }
  }

  for s.buffers {
    buffer := it;
    if buffer.element_kind == .UINT && buffer.wrapper_struct_type_id == s.id_buffer_struct continue;
    a(sb, "               OpDecorate % ArrayStride %", id_text(buffer.runtimearr_type_id), buffer.array_stride);
    if buffer.element_kind == .STRUCT {
      for buffer.fields {
        if it.is_array {
          a(sb, "               OpDecorate % ArrayStride %", id_text(it.array_type_id), it.array_stride);
        }
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
  for s.buffer_layout_structs {
    layout := it;
    for layout.fields {
      if !it.is_array continue;
      elem_type_id := ifx it.array_element_type_id != 0 then it.array_element_type_id else it.type_id;
      a(sb, "% = OpTypeArray % %", id_text(it.array_type_id), id_text(elem_type_id), id_text(it.array_length_const_id));
    }
    struct_type_line_sb: String_Builder;
    append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(layout.type_id)));
    for layout.fields {
      field_type_id := ifx it.is_array then it.array_type_id else it.type_id;
      append(*struct_type_line_sb, " ", id_text(field_type_id));
    }
    append(*struct_type_line_sb, "\n");
    append_and_steal_buffers(sb, *struct_type_line_sb);
  }

  for s.buffers {
    buffer := it;
    if buffer.element_kind == .UINT && buffer.wrapper_struct_type_id == s.id_buffer_struct continue;
    if buffer.element_kind == .STRUCT {
      for buffer.fields {
        if !it.is_array continue;
        elem_type_id := ifx it.array_element_type_id != 0 then it.array_element_type_id else it.type_id;
        a(sb, "% = OpTypeArray % %", id_text(it.array_type_id), id_text(elem_type_id), id_text(it.array_length_const_id));
      }
      struct_type_line_sb: String_Builder;
      append(*struct_type_line_sb, tprint("% = OpTypeStruct", id_text(buffer.element_type_id)));
      for buffer.fields {
        field_type_id := ifx it.is_array then it.array_type_id else it.type_id;
        append(*struct_type_line_sb, " ", id_text(field_type_id));
      }
      append(*struct_type_line_sb, "\n");
      append_and_steal_buffers(sb, *struct_type_line_sb);
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

find_pointer_root_arg :: (args: [] IR_Function_Arg, extra_structs: [] IR_Struct) -> (*IR_Function_Arg, bool) {
  candidate: *IR_Function_Arg = null;
  for *args {
    if it.type.kind != .POINTER continue;
    if it.type.pointee_kind != .STRUCT continue;
    if it.type.pointee_struct_name.count == 0 continue;
    if !struct_has_pointer_fields_recursive(extra_structs, it.type.pointee_struct_name) continue;
    if candidate return null, false;
    candidate = it;
  }
  if !candidate return null, false;
  return candidate, true;
}

ps_assign_struct_info :: (s: *IR_SPV_Gen_State, infos: *[..] IR_SPV_PS_Struct_Info, struct_name: string, prefix: string, depth := 0) -> bool {
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
    if type.kind == .POINTER {
      if type.pointee_kind != .STRUCT continue;
      if type.pointee_struct_name.count == 0 continue;
      if !struct_has_pointer_fields_recursive(s.extra_structs, type.pointee_struct_name, depth + 1) continue;
      next_prefix := tprint("%.%", prefix, name);
      if !ps_assign_struct_info(s, infos, type.pointee_struct_name, next_prefix, depth + 1) return false;
      continue;
    }
    if type.kind == .STRUCT && type.struct_name.count != 0 &&
       struct_has_pointer_fields_recursive(s.extra_structs, type.struct_name, depth + 1) {
      next_prefix := tprint("%.%", prefix, name);
      if !ps_assign_struct_info(s, infos, type.struct_name, next_prefix, depth + 1) return false;
    }
  }
  return true;
}

ps_get_ptr_to_ptr_type :: (s: *IR_SPV_Gen_State, ptr_to_ptr_types: *[..] IR_SPV_PS_Ptr_To_Ptr, ptr_type_id: s64) -> s64 {
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
#load "spv_resource_classification.jai";
#load "spv_invariants.jai";
#load "spv_lvalue_lowering.jai";
#load "../string_builder_util.jai";
