#scope_export

IR_Type_Kind :: enum {
  UNKNOWN;
  BOOL;
  I32;
  U32;
  I64;
  U64;
  F32;
  F32x2;
  F32x3;
  F32x4;
  F32x2x2;
  STRUCT;
  POINTER;
  FIXED_ARRAY;
}

IR_Type_Flags :: enum_flags u32 {
  PARAMETER_BLOCK :: 0x1;
}

IR_Type :: struct {
  kind: IR_Type_Kind;
  flags: IR_Type_Flags;
  display_name: string;
  struct_name: string;
  element_kind: IR_Type_Kind;
  element_display_name: string;
  element_struct_name: string;
  array_count: s64;
  pointee_kind: IR_Type_Kind;
  pointee_display_name: string;
  pointee_struct_name: string;
  pointee_is_struct: bool;
}

IR_Field :: struct {
  name: string;
  type: IR_Type;
  type_name: string;
  semantic: string;
  original_type_name: string;
  is_pointer: bool;
  pointer_pointee_type_name: string;
  pointer_pointee_is_struct: bool;
}

IR_Struct :: struct {
  name: string;
  fields: [..] IR_Field;
}

IR_Shader_Kind :: enum {
  Vertex;
  Fragment;
  Compute;
}

IR_Shader :: struct {
  source_name: string;
  entry_name: string;
  kind: IR_Shader_Kind;
  extra_structs: [..] IR_Struct;
  functions: [..] IR_Function;
  body: IR_Block;
}

IR_Vertex_Shader :: struct {
  using #as ir_shader: IR_Shader;
  input: IR_Struct;
  output: IR_Struct;
  args: [..] IR_Function_Arg;
}

IR_Fragment_Shader :: struct {
  using #as ir_shader: IR_Shader;
  input: IR_Struct;
  output: IR_Struct;
  args: [..] IR_Function_Arg;
}

IR_Compute_Buffer :: struct {
  name: string;
  element_type: IR_Type;
  element_type_name: string;
}

IR_Function_Arg :: struct {
  name: string;
  type: IR_Type;
  type_name: string;
  is_readonly: bool;
  original_type_name: string;
  is_pointer: bool;
  pointer_pointee_type_name: string;
  pointer_pointee_is_struct: bool;
}

IR_Function :: struct {
  name: string;
  return_type: IR_Type;
  return_type_name: string;
  args: [..] IR_Function_Arg;
  body: IR_Block;
}

IR_Compute_Shader :: struct {
  using #as ir_shader: IR_Shader;
  input: IR_Struct;
  buffers: [..] IR_Compute_Buffer;
}

IR_Using_Source :: struct {
  expression_node: *Code_Node;
  source_text: string;
  field_names: [..] string;
}

IR_Decl_Alias :: struct {
  declaration: *Code_Declaration;
  replacement_text: string;
}

IR_Expr_Kind :: enum {
  IDENT;
  LITERAL;
  ARRAY_LITERAL;
  UNARY;
  BINARY;
  MEMBER;
  SUBSCRIPT;
  CALL;
  CAST;
  CONSTRUCTOR;
}

IR_Expr :: struct {
  kind: IR_Expr_Kind;
  text: string;
  left: *IR_Expr;
  right: *IR_Expr;
  args: [..] *IR_Expr;
}

IR_Stmt_Kind :: enum {
  DECL;
  BINARY;
  IF;
  SWITCH;
  FOR;
  WHILE;
  BREAK;
  CONTINUE;
  CALL;
  RETURN;
}

IR_Switch_Case :: struct {
  condition: *IR_Expr;
  body: *IR_Block;
  falls_through: bool;
}

IR_Stmt :: struct {
  kind: IR_Stmt_Kind;

  // DECL
  decl_type: IR_Type;
  decl_type_name: string;
  decl_name: string;
  decl_init: *IR_Expr;

  // BINARY
  binary_left: *IR_Expr;
  binary_op: string;
  binary_right: *IR_Expr;

  // IF
  if_condition: *IR_Expr;
  if_then: *IR_Block;
  if_else: *IR_Block;

  // SWITCH
  switch_condition: *IR_Expr;
  switch_cases: [..] IR_Switch_Case;

  // FOR
  for_loop_name: string;
  for_start: *IR_Expr;
  for_end: *IR_Expr;
  for_cmp: string;
  for_step: string;
  for_body: *IR_Block;

  // WHILE
  while_condition: *IR_Expr;
  while_body: *IR_Block;

  // CALL
  call_expr: *IR_Expr;

  // RETURN
  return_expr: *IR_Expr;
}

IR_Block :: struct {
  statements: [..] IR_Stmt;
}

IR_Diagnostic :: struct {
  message: string;
  location: Source_Code_Location;
  has_location: bool;
}

IR_Lowering_State :: struct {
  first_error: IR_Diagnostic;
}

ir_reset_diagnostic :: (state: *IR_Lowering_State) {
  assert(state != null);
  state.first_error = .{};
}

ir_set_diagnostic :: (state: *IR_Lowering_State, message: string, node: *Code_Node = null) {
  assert(state != null);
  if state.first_error.message.count != 0 return; // Preserve first failure.
  state.first_error.message = message;
  if node {
    state.first_error.location = make_location(node);
    state.first_error.has_location = true;
  }
}

ir_get_diagnostic :: (state: *IR_Lowering_State) -> IR_Diagnostic {
  assert(state != null);
  return state.first_error;
}

#scope_module

ir_type_to_slang_name :: (type: *Type_Info) -> (string, bool) {
  if !type return "", false;

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return "", false;
    pointee_name, pointee_ok := ir_type_to_slang_name(ptr.pointer_to);
    if !pointee_ok return "", false;
    return tprint("*%", pointee_name), true;
  }

  if type.type == .ARRAY {
    base_type, suffix := split_array_type_and_suffix("IR lowering", type);
    if !base_type return "", false;
    base_name, base_ok := ir_type_to_slang_name(base_type);
    if !base_ok return "", false;
    return tprint("%%", base_name, suffix), true;
  }

  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      if inttype.signed {
        if type.runtime_size == 8 return "int64_t", true;
        if type.runtime_size == 4 return "int32_t", true;
        return "", false;
      } else {
        if type.runtime_size == 8 return "uint64_t", true;
        if type.runtime_size == 4 return "uint", true;
        return "", false;
      }
    }
    case .FLOAT; return ifx type.runtime_size == 64 then "double" else "float", true;
    case .BOOL; return "bool", true;
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      return jai_to_hlsl_type_name(get_struct_type_name(structtype)), true;
    }
  }

  return "", false;
}

ir_type_to_original_name :: (type: *Type_Info) -> (string, bool) {
  if !type return "", false;

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return "", false;
    pointee_name, pointee_ok := ir_type_to_original_name(ptr.pointer_to);
    if !pointee_ok return "", false;
    return tprint("*%", pointee_name), true;
  }

  if type.type == .ARRAY {
    base_type, suffix := split_array_type_and_suffix("IR lowering", type);
    if !base_type return "", false;
    base_name, base_ok := ir_type_to_original_name(base_type);
    if !base_ok return "", false;
    return tprint("%%", base_name, suffix), true;
  }

  type_name, type_ok := ir_type_to_slang_name(type);
  return type_name, type_ok;
}

ir_type_kind_from_slang_name :: (name: string) -> IR_Type_Kind {
  if name == "bool" return .BOOL;
  if name == "int" || name == "int32_t" return .I32;
  if name == "uint" || name == "u32" return .U32;
  if name == "int64_t" return .I64;
  if name == "uint64_t" return .U64;
  if name == "float" return .F32;
  if name == "float2" return .F32x2;
  if name == "float3" return .F32x3;
  if name == "float4" return .F32x4;
  if name == "float2x2" return .F32x2x2;
  return .UNKNOWN;
}

ir_type_from_type_info :: (type: *Type_Info) -> (IR_Type, bool) {
  out: IR_Type;
  if !type return out, false;

  display_name, display_ok := ir_type_to_slang_name(type);
  if !display_ok return out, false;
  out.display_name = display_name;

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return out, false;
    pointee, pointee_ok := ir_type_from_type_info(ptr.pointer_to);
    if !pointee_ok return out, false;
    out.kind = .POINTER;
    out.pointee_kind = pointee.kind;
    out.pointee_display_name = pointee.display_name;
    out.pointee_struct_name = pointee.struct_name;
    out.pointee_is_struct = pointee.kind == .STRUCT;
    return out, true;
  }

  if type.type == .ARRAY {
    array_t := cast(*Type_Info_Array) type;
    elem_ir, elem_ok := ir_type_from_type_info(array_t.element_type);
    if !elem_ok return out, false;
    out.kind = .FIXED_ARRAY;
    out.element_kind = elem_ir.kind;
    out.element_display_name = elem_ir.display_name;
    out.element_struct_name = elem_ir.struct_name;
    out.array_count = array_t.array_count;
    return out, true;
  }

  if type.type == .STRUCT {
    st := cast(*Type_Info_Struct) type;
    lowered_name := jai_to_hlsl_type_name(get_struct_type_name(st));
    builtin_kind := ir_type_kind_from_slang_name(lowered_name);
    if builtin_kind != .UNKNOWN {
      out.kind = builtin_kind;
      return out, true;
    }
    out.kind = .STRUCT;
    out.struct_name = lowered_name;
    return out, true;
  }

  out.kind = ir_type_kind_from_slang_name(display_name);
  if out.kind == .UNKNOWN return out, false;
  return out, true;
}

ir_pointer_pointee_lowered_name :: (pointer_type: *Type_Info) -> (string, bool, bool) {
  if !pointer_type || pointer_type.type != .POINTER return "", false, false;
  ptr := cast(*Type_Info_Pointer) pointer_type;
  if !ptr.pointer_to return "", false, false;

  if ptr.pointer_to.type == .STRUCT {
    st := cast(*Type_Info_Struct) ptr.pointer_to;
    return jai_to_hlsl_type_name(get_struct_type_name(st)), true, true;
  }

  pointee_name, pointee_ok := ir_type_to_slang_name(ptr.pointer_to);
  if !pointee_ok return "", false, false;
  return pointee_name, true, false;
}

ir_lower_struct_from_type :: (name: string, type: *Type_Info) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;

  if !type || type.type != .STRUCT return out, false;

  struct_type := cast(*Type_Info_Struct) type;
  for *struct_type.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    type_name, ok := ir_type_to_slang_name(it.type);
    if !ok return out, false;
    field_semantic := member_get_semantic(it);
    original_type_name, original_ok := ir_type_to_original_name(it.type);
    if !original_ok return out, false;
    pointee_name := "";
    pointee_ok := false;
    pointee_is_struct := false;
    if it.type && it.type.type == .POINTER {
      pointee_name, pointee_ok, pointee_is_struct = ir_pointer_pointee_lowered_name(it.type);
      if !pointee_ok return out, false;
    }
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      type_name = type_name,
      semantic = field_semantic,
      original_type_name = original_type_name,
      is_pointer = it.type && it.type.type == .POINTER,
      pointer_pointee_type_name = pointee_name,
      pointer_pointee_is_struct = pointee_is_struct,
    });
  }

  return out, true;
}

ir_lower_struct_member_type_name :: (type: *Type_Info, extra_structs: *[..] IR_Struct) -> (string, bool) {
  if !type return "", false;

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return "", false;
    if ptr.pointer_to.type == .STRUCT {
      st := cast(*Type_Info_Struct) ptr.pointer_to;
      nested_name := jai_to_hlsl_type_name(get_struct_type_name(st));
      if !ir_is_builtin_slang_type_name(nested_name) {
        nested_struct, nested_ok := ir_lower_struct_with_pointer_members_from_type(nested_name, ptr.pointer_to, extra_structs);
        if !nested_ok return "", false;
        ir_add_struct_unique_by_name(extra_structs, nested_struct);
      }
      if ir_struct_has_pointer_members(ptr.pointer_to) {
        // Model pointers-to-parameter-block structs as direct struct values.
        return nested_name, true;
      }
      return tprint("StructuredBuffer<%>", nested_name), true;
    }

    elem_name, elem_ok := ir_type_to_slang_name(ptr.pointer_to);
    if !elem_ok return "", false;
    return tprint("StructuredBuffer<%>", elem_name), true;
  }

  if type.type == .STRUCT {
    st := cast(*Type_Info_Struct) type;
    nested_name := jai_to_hlsl_type_name(get_struct_type_name(st));
    if !ir_is_builtin_slang_type_name(nested_name) {
      nested_struct, nested_ok := ir_lower_struct_with_pointer_members_from_type(nested_name, type, extra_structs);
      if !nested_ok return "", false;
      ir_add_struct_unique_by_name(extra_structs, nested_struct);
    }
    return nested_name, true;
  }

  type_name, type_ok := ir_type_to_slang_name(type);
  return type_name, type_ok;
}

ir_lower_struct_with_pointer_members_from_type :: (name: string, type: *Type_Info, extra_structs: *[..] IR_Struct) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;

  if !type || type.type != .STRUCT return out, false;

  st := cast(*Type_Info_Struct) type;
  for *st.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    type_name, ok := ir_lower_struct_member_type_name(it.type, extra_structs);
    if !ok return out, false;
    field_semantic := member_get_semantic(it);
    original_type_name, original_ok := ir_type_to_original_name(it.type);
    if !original_ok return out, false;
    pointee_name := "";
    pointee_ok := false;
    pointee_is_struct := false;
    if it.type && it.type.type == .POINTER {
      pointee_name, pointee_ok, pointee_is_struct = ir_pointer_pointee_lowered_name(it.type);
      if !pointee_ok return out, false;
    }
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      type_name = type_name,
      semantic = field_semantic,
      original_type_name = original_type_name,
      is_pointer = it.type && it.type.type == .POINTER,
      pointer_pointee_type_name = pointee_name,
      pointer_pointee_is_struct = pointee_is_struct,
    });
  }

  return out, true;
}

ir_struct_has_field :: (s: *IR_Struct, name: string) -> bool {
  for s.fields if it.name == name return true;
  return false;
}

ir_field_type_name :: (s: *IR_Struct, name: string) -> string {
  for s.fields {
    if it.name != name continue;
    if it.type.display_name.count != 0 return it.type.display_name;
    return it.type_name;
  }
  return "";
}

ir_add_struct_unique_by_name :: (structs: *[..] IR_Struct, s: IR_Struct) {
  for structs.* if it.name == s.name return;
  array_add(structs, s);
}

ir_is_builtin_slang_type_name :: (name: string) -> bool {
  if name == "bool" || name == "int" || name == "uint" || name == "float" || name == "double" return true;
  if name == "bool2" || name == "bool3" || name == "bool4" return true;
  if name == "int2" || name == "int3" || name == "int4" return true;
  if name == "uint2" || name == "uint3" || name == "uint4" return true;
  if name == "float2" || name == "float3" || name == "float4" return true;
  if name == "float2x2" || name == "float3x3" || name == "float4x4" return true;
  if name == "float4x3" || name == "float3x4" return true;
  return false;
}

ir_type_is_matrix_like :: (type: *Type_Info) -> bool {
  if !type || type.type != .STRUCT return false;
  st := cast(*Type_Info_Struct) type;
  name := get_struct_type_name(st);
  return begins_with(name, "Matrix");
}

ir_name_in_list :: (names: [] string, name: string) -> bool {
  for names if it == name return true;
  return false;
}

ir_lookup_using_field_source :: (active_usings: [] IR_Using_Source, field_name: string) -> (string, *Code_Node, bool, bool) {
  found_node: *Code_Node = null;
  found_text: string;
  found := false;
  ambiguous := false;
  for active_usings {
    if !ir_name_in_list(it.field_names, field_name) continue;
    if !found {
      found_node = it.expression_node;
      found_text = it.source_text;
      found = true;
      continue;
    }
    if found_node != it.expression_node || found_text != it.source_text {
      ambiguous = true;
      break;
    }
  }
  return found_text, found_node, found, ambiguous;
}

ir_collect_parameter_using_sources :: (header: *Code_Procedure_Header, out_sources: *[..] IR_Using_Source) {
  assert(out_sources != null);
  if !header return;
  for header.parameter_usings {
    if !it || !it.expression continue;

    decl: *Code_Declaration = null;
    if it.expression.kind == .DECLARATION {
      decl = cast(*Code_Declaration) it.expression;
    } else if it.expression.kind == .IDENT {
      ident := cast(*Code_Ident) it.expression;
      decl = ident.resolved_declaration;
      if !decl {
        for header.arguments {
          if it.name == ident.name {
            decl = it;
            break;
          }
        }
      }
    }
    if !decl continue;

    decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
    if !decl_type || decl_type.type != .STRUCT continue;
    st := cast(*Type_Info_Struct) decl_type;

    src: IR_Using_Source;
    src.expression_node = cast(*Code_Node) it.expression;
    src.source_text = decl.name;
    for *st.members array_add(*src.field_names, it.name);
    array_add(out_sources, src);
  }
}

ir_lookup_decl_alias :: (active_aliases: [] IR_Decl_Alias, declaration: *Code_Declaration) -> (string, bool) {
  if !declaration return "", false;
  for active_aliases {
    if it.declaration == declaration return it.replacement_text, true;
  }
  return "", false;
}

ir_decl_is_compile_constant :: (decl: *Code_Declaration) -> bool {
  if !decl return false;
  if !(decl.flags & .IS_CONSTANT) return false;
  if !decl.expression return false;
  // Do not inline procedure declarations through identifier lowering.
  if decl.expression.kind == .PROCEDURE_BODY || decl.expression.kind == .PROCEDURE_HEADER return false;
  return true;
}

ir_struct_has_pointer_members :: (type: *Type_Info) -> bool {
  if !type || type.type != .STRUCT return false;
  st := cast(*Type_Info_Struct) type;
  for *st.members if it.type && it.type.type == .POINTER return true;
  return false;
}

ir_type_name_is_parameter_block :: (type_name: string) -> bool {
  return begins_with(type_name, "ParameterBlock<");
}

ir_type_name_is_global_resource :: (type_name: string) -> bool {
  if ir_type_name_is_parameter_block(type_name) return true;
  if begins_with(type_name, "StructuredBuffer<") return true;
  if begins_with(type_name, "RWStructuredBuffer<") return true;
  if begins_with(type_name, "ByteAddressBuffer") return true;
  if begins_with(type_name, "RWByteAddressBuffer") return true;
  return false;
}

ir_lower_shader_arg_type_name :: (type: *Type_Info, extra_structs: *[..] IR_Struct) -> (string, bool) {
  if !type return "", false;
  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return "", false;
    if ptr.pointer_to.type == .STRUCT {
      st := cast(*Type_Info_Struct) ptr.pointer_to;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(st));
      if !ir_is_builtin_slang_type_name(struct_name) {
        lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ptr.pointer_to, extra_structs);
        if !lowered_ok return "", false;
        ir_add_struct_unique_by_name(extra_structs, lowered_struct);
      }
      if ir_struct_has_pointer_members(ptr.pointer_to) return struct_name, true;
      return tprint("StructuredBuffer<%>", struct_name), true;
    }
    elem_name, elem_ok := ir_type_to_slang_name(ptr.pointer_to);
    if !elem_ok return "", false;
    return tprint("StructuredBuffer<%>", elem_name), true;
  }
  if type.type == .STRUCT {
    st := cast(*Type_Info_Struct) type;
    struct_name := jai_to_hlsl_type_name(get_struct_type_name(st));
    if !ir_is_builtin_slang_type_name(struct_name) {
      lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, type, extra_structs);
      if !lowered_ok return "", false;
      ir_add_struct_unique_by_name(extra_structs, lowered_struct);
    }
    // For graphics stages, extra struct args represent uniforms/resources, not stage input varyings.
    return tprint("ParameterBlock<%>", struct_name), true;
  }
  type_name, type_ok := ir_type_to_slang_name(type);
  return type_name, type_ok;
}

op_to_text :: (op: Operator_Type) -> string {
  if op == {
    case cast(Operator_Type) #char "="; return "=";
    case cast(Operator_Type) #char "<"; return "<";
    case cast(Operator_Type) #char "?"; return "?";
    case cast(Operator_Type) #char ">"; return ">";
    case cast(Operator_Type) #char "!"; return "!";
    case cast(Operator_Type) #char "+"; return "+";
    case cast(Operator_Type) #char "-"; return "-";
    case cast(Operator_Type) #char "*"; return "*";
    case cast(Operator_Type) #char "/"; return "/";
    case cast(Operator_Type) #char "%"; return "%";
    case cast(Operator_Type) #char "&"; return "&";
    case cast(Operator_Type) #char "|"; return "|";
    case cast(Operator_Type) #char "^"; return "^";
    case cast(Operator_Type) #char "~"; return "~";
    case cast(Operator_Type) #char "."; return ".";
  }

  if op == {
    case .PLUS_ASSIGN; return "+=";
    case .MINUS_ASSIGN; return "-=";
    case .TIMES_ASSIGN; return "*=";
    case .DIV_ASSIGN; return "/=";
    case .MOD_ASSIGN; return "%=";
    case .IS_EQUAL; return "==";
    case .IS_NOT_EQUAL; return "!=";
    case .LOGICAL_AND; return "&&";
    case .LOGICAL_OR; return "||";
    case .LESS_OR_EQUAL; return "<=";
    case .GREATER_OR_EQUAL; return ">=";
    case .SHIFT_LEFT; return "<<";
    case .SHIFT_RIGHT; return ">>";
    case .ARRAY_SUBSCRIPT; return "[]";
    case; return "<operator_not_supported>";
  }
}

ir_binary_operator_to_slang :: (op: Operator_Type) -> string {
  if op == {
    case .PLUS_ASSIGN; return "+=";
    case .MINUS_ASSIGN; return "-=";
    case .TIMES_ASSIGN; return "*=";
    case .DIV_ASSIGN; return "/=";
    case .MOD_ASSIGN; return "%=";
    case .SHIFT_LEFT; return "<<";
    case .SHIFT_RIGHT; return ">>";
    case .SHIFT_LEFT_ASSIGN; return "<<=";
    case .SHIFT_RIGHT_ASSIGN; return ">>=";
    case .BITWISE_AND_ASSIGN; return "&=";
    case .BITWISE_OR_ASSIGN; return "|=";
    case .BITWISE_XOR_ASSIGN; return "^=";
  }
  return op_to_text(op);
}

compute_builtin_note_for_member :: (member: *Type_Info_Struct_Member) -> (string, bool) {
  for member.notes {
    found, _ := contains(it, "thread_position_in_grid");
    if found return "thread_position_in_grid", true;
    found, _ = contains(it, "thread_position_in_threadgroup");
    if found return "thread_position_in_threadgroup", true;
    found, _ = contains(it, "threadgroup_position_in_grid");
    if found return "threadgroup_position_in_grid", true;
    found, _ = contains(it, "thread_index_in_threadgroup");
    if found return "thread_index_in_threadgroup", true;
  }
  return "", false;
}

ir_expr_new :: (kind: IR_Expr_Kind) -> *IR_Expr {
  e := New(IR_Expr);
  e.kind = kind;
  return e;
}

ir_float_literal_to_text :: (v: float64) -> string {
  text := tprint("%", v);
  has_decimal_or_exp := false;
  for 0..text.count-1 {
    ch := text[it];
    if ch == #char "." || ch == #char "e" || ch == #char "E" {
      has_decimal_or_exp = true;
      break;
    }
  }
  if has_decimal_or_exp return text;
  return tprint("%.0", text);
}

ir_literal_to_text :: (using lit: *Code_Literal) -> (string, bool) {
  assert(lit != null);
  if value_type == .BOOLEAN return ifx _s64 != 0 then "true" else "false", true;
  if value_type == .NUMBER {
    if value_flags & .FLOAT return ir_float_literal_to_text(_float64), true;
    if type && type.type == .INTEGER {
      inttype := cast(*Type_Info_Integer) type;
      if inttype.signed return tprint("%", _s64), true;
    }
    return tprint("%", _u64), true;
  }
  if value_type == .STRING return tprint("\"%\"", _string), true;
  return "", false;
}

ir_lower_expr :: (node: *Code_Node,
                  input_fields: [] string,
                  output_fields: [] string,
                  active_usings: [] IR_Using_Source = .[],
                  active_aliases: [] IR_Decl_Alias = .[],
                  state: *IR_Lowering_State = null,
                  expected_type: *Type_Info = null) -> (*IR_Expr, bool) {
  assert(node != null);
  assert(state != null);

  if node.kind == {
    case .IDENT; {
      ident := cast(*Code_Ident) node;

      if ident.resolved_declaration {
        alias_text, aliased := ir_lookup_decl_alias(active_aliases, ident.resolved_declaration);
        if aliased {
          out := ir_expr_new(.IDENT);
          out.text = alias_text;
          return out, true;
        }

        if ir_decl_is_compile_constant(ident.resolved_declaration) {
          inlined, inlined_ok := ir_lower_expr(ident.resolved_declaration.expression, input_fields, output_fields, active_usings, active_aliases, state, expected_type);
          if inlined_ok return inlined, true;
        }
      }

      if ident.name == "input" || ident.name == "o" || ident.name == "un" {
        out := ir_expr_new(.IDENT);
        out.text = ident.name;
        return out, true;
      }

      if ir_name_in_list(input_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "input";
        out.text = ident.name;
        return out, true;
      }

      if ir_name_in_list(output_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "o";
        out.text = ident.name;
        return out, true;
      }

      using_source_text, using_source_node, found_using, ambiguous := ir_lookup_using_field_source(active_usings, ident.name);
      if ambiguous {
        ir_set_diagnostic(state, tprint("IR lowering: identifier '%' is ambiguous due to multiple active using sources", ident.name), node);
        return null, false;
      }
      if found_using {
        base: *IR_Expr = null;
        if using_source_text.count != 0 {
          base = ir_expr_new(.IDENT);
          base.text = using_source_text;
        } else {
          lowered_base, ok := ir_lower_expr(using_source_node, input_fields, output_fields, active_usings, active_aliases, state);
          if !ok return null, false;
          base = lowered_base;
        }
        out := ir_expr_new(.MEMBER);
        out.left = base;
        out.text = ident.name;
        return out, true;
      }

      out := ir_expr_new(.IDENT);
      out.text = ident.name;
      return out, true;
    }

    case .LITERAL; {
      lit := cast(*Code_Literal) node;

      if lit.value_type == .STRUCT {
        struct_type_info: *Type_Info_Struct = null;
        if lit.type && lit.type.type == .STRUCT {
          struct_type_info = cast(*Type_Info_Struct) lit.type;
        } else if expected_type && expected_type.type == .STRUCT {
          struct_type_info = cast(*Type_Info_Struct) expected_type;
        }

        field_expected_type :: (st: *Type_Info_Struct, field_name: string) -> *Type_Info {
          if !st return null;
          for *st.members if it.name == field_name return it.type;
          return null;
        }

        constructor_name := "";
        if lit.struct_literal_info.type_expression && lit.struct_literal_info.type_expression.type_valued_expression && lit.struct_literal_info.type_expression.type_valued_expression.kind == .IDENT {
          type_ident := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
          constructor_name = jai_to_hlsl_type_name(type_ident.name);
        } else if lit.type {
          lowered_type_name, lowered_type_ok := ir_type_to_slang_name(lit.type);
          if lowered_type_ok constructor_name = lowered_type_name;
        }
        if constructor_name.count == 0 && expected_type {
          expected_name, expected_ok := ir_type_to_slang_name(expected_type);
          if expected_ok constructor_name = expected_name;
        }
        if constructor_name.count == 0 && lit.type && lit.type.type == .STRUCT {
          struct_type := cast(*Type_Info_Struct) lit.type;
          constructor_name = jai_to_hlsl_type_name(get_struct_type_name(struct_type));
        }
        if constructor_name.count == 0 {
          ir_set_diagnostic(state, "IR lowering: could not infer constructor type for struct/vector literal", node);
          return null, false;
        }

        out := ir_expr_new(.CONSTRUCTOR);
        out.text = constructor_name;
        positional_index: s64 = 0;
        for lit.struct_literal_info.arguments {
          source_arg := it;
          arg_expected_type: *Type_Info = null;

          if source_arg && source_arg.kind == .BINARY_OPERATOR {
            named := cast(*Code_Binary_Operator) source_arg;
            if named.operator_type == cast(Operator_Type) #char "=" &&
               named.left && named.left.kind == .IDENT {
              field_name := (cast(*Code_Ident) named.left).name;
              arg_expected_type = field_expected_type(struct_type_info, field_name);

              lowered_right, right_ok := ir_lower_expr(named.right, input_fields, output_fields, active_usings, active_aliases, state, arg_expected_type);
              if !right_ok return null, false;
              if ir_is_builtin_slang_type_name(constructor_name) {
                // Builtin vector/matrix constructors expect positional args only.
                array_add(*out.args, lowered_right);
                continue;
              }

              lowered_left, left_ok := ir_lower_expr(named.left, input_fields, output_fields, active_usings, active_aliases, state);
              if !left_ok return null, false;
              arg := ir_expr_new(.BINARY);
              arg.text = "=";
              arg.left = lowered_left;
              arg.right = lowered_right;
              array_add(*out.args, arg);
              continue;
            }
          }

          if struct_type_info && positional_index < struct_type_info.members.count {
            arg_expected_type = struct_type_info.members[positional_index].type;
          }
          arg, ok := ir_lower_expr(source_arg, input_fields, output_fields, active_usings, active_aliases, state, arg_expected_type);
          if !ok return null, false;
          array_add(*out.args, arg);
          positional_index += 1;
        }
        return out, true;
      }

      if lit.value_type == .ARRAY {
        out := ir_expr_new(.ARRAY_LITERAL);
        info := lit.array_literal_info;
        if !info {
          ir_set_diagnostic(state, "IR lowering: array literal is missing literal info", node);
          return null, false;
        }
        member_expected_type: *Type_Info = null;
        if info.element_type {
          if info.element_type.result member_expected_type = info.element_type.result;
          else if info.element_type.type_valued_expression member_expected_type = info.element_type.type_valued_expression.type;
        }
        for info.array_members {
          arg, ok := ir_lower_expr(it, input_fields, output_fields, active_usings, active_aliases, state, member_expected_type);
          if !ok return null, false;
          array_add(*out.args, arg);
        }
        return out, true;
      }

      lit_text, lit_ok := ir_literal_to_text(lit);
      if !lit_ok {
        ir_set_diagnostic(state, tprint("IR lowering: unsupported literal kind (%)", lit.value_type), node);
        return null, false;
      }
      out := ir_expr_new(.LITERAL);
      out.text = lit_text;
      return out, true;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      inner, ok := ir_lower_expr(un.subexpression, input_fields, output_fields, active_usings, active_aliases, state);
      if !ok return null, false;
      out := ir_expr_new(.UNARY);
      out.text = op_to_text(un.operator_type);
      out.left = inner;
      return out, true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      left, left_ok := ir_lower_expr(bn.left, input_fields, output_fields, active_usings, active_aliases, state);
      if !left_ok return null, false;

      if bn.operator_type == .ARRAY_SUBSCRIPT {
        right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings, active_aliases, state);
        if !right_ok return null, false;
        out := ir_expr_new(.SUBSCRIPT);
        out.left = left;
        out.right = right;
        return out, true;
      }

      op := ir_binary_operator_to_slang(bn.operator_type);
      if bn.operator_type == cast(Operator_Type) #char "*" {
        left_type := ifx bn.left then bn.left.type else null;
        right_type := ifx bn.right then bn.right.type else null;
        left_is_matrix := ir_type_is_matrix_like(left_type);
        right_is_matrix := ir_type_is_matrix_like(right_type);
        if left_is_matrix || right_is_matrix {
          right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings, active_aliases, state);
          if !right_ok return null, false;
          out := ir_expr_new(.CALL);
          out.left = ir_expr_new(.IDENT);
          out.left.text = "mul";
          if left_is_matrix && !right_is_matrix {
            // Jai's matrix*vector convention matches Slang/HLSL mul(vector, matrix).
            array_add(*out.args, right, left);
          } else {
            array_add(*out.args, left, right);
          }
          return out, true;
        }
      }
      if op == "." {
        if bn.right && bn.right.kind == .IDENT {
          right_ident := cast(*Code_Ident) bn.right;
          left_for_member := left;
          if bn.left && bn.left.type && bn.left.type.type == .POINTER {
            ptr_type := cast(*Type_Info_Pointer) bn.left.type;
            should_emit_implicit_deref := true;
            if ptr_type.pointer_to && ptr_type.pointer_to.type == .STRUCT && ir_struct_has_pointer_members(ptr_type.pointer_to) {
              should_emit_implicit_deref = false;
            }

            if should_emit_implicit_deref {
              deref_index := ir_expr_new(.LITERAL);
              deref_index.text = "0";
              deref := ir_expr_new(.SUBSCRIPT);
              deref.left = left;
              deref.right = deref_index;
              left_for_member = deref;
            }
          }
          out := ir_expr_new(.MEMBER);
          out.left = left_for_member;
          out.text = right_ident.name;
          return out, true;
        }
        ir_set_diagnostic(state, "IR lowering: member access requires identifier on right-hand side", node);
        return null, false;
      }

      right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings, active_aliases, state);
      if !right_ok return null, false;
      out := ir_expr_new(.BINARY);
      out.text = op;
      out.left = left;
      out.right = right;
      return out, true;
    }

    case .CAST; {
      cast_node := cast(*Code_Cast) node;
      if !cast_node.target_type {
        ir_set_diagnostic(state, "IR lowering: cast is missing target type", node);
        return null, false;
      }
      target_type_info := cast_node.target_type.result;
      type_name := "";
      if target_type_info {
        t, ok := ir_type_to_slang_name(target_type_info);
        if !ok {
          ir_set_diagnostic(state, "IR lowering: unsupported cast target type", cast_node.target_type.type_valued_expression);
          return null, false;
        }
        type_name = t;
      } else if cast_node.target_type.type_valued_expression && cast_node.target_type.type_valued_expression.kind == .IDENT {
        type_ident := cast(*Code_Ident) cast_node.target_type.type_valued_expression;
        type_name = jai_to_hlsl_type_name(type_ident.name);
      } else {
        ir_set_diagnostic(state, "IR lowering: unsupported cast target expression", node);
        return null, false;
      }

      inner, ok := ir_lower_expr(cast_node.expression, input_fields, output_fields, active_usings, active_aliases, state);
      if !ok return null, false;
      out := ir_expr_new(.CAST);
      out.text = type_name;
      out.left = inner;
      return out, true;
    }

    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      callee, callee_ok := ir_lower_expr(pc.procedure_expression, input_fields, output_fields, active_usings, active_aliases, state);
      if !callee_ok return null, false;
      out := ir_expr_new(.CALL);
      out.left = callee;
      for pc.arguments_sorted {
        arg, ok := ir_lower_expr(it, input_fields, output_fields, active_usings, active_aliases, state);
        if !ok return null, false;
        array_add(*out.args, arg);
      }
      return out, true;
    }
  }

  ir_set_diagnostic(state, tprint("IR lowering: unsupported expression node kind (%)", node.kind), node);
  return null, false;
}

ir_parse_float_matrix_dims :: (type_name: string) -> (cols: s64, rows: s64, ok: bool) {
  if !begins_with(type_name, "float") return 0, 0, false;
  dims: string;
  dims.data = type_name.data + 5;
  dims.count = type_name.count - 5;
  if dims.count < 3 return 0, 0, false;

  x_index := cast(s64) -1;
  for i: 0..dims.count-1 {
    if dims[i] == #char "x" {
      x_index = i;
      break;
    }
  }
  if x_index <= 0 || x_index >= dims.count-1 return 0, 0, false;

  cols_text: string;
  cols_text.data = dims.data;
  cols_text.count = x_index;
  rows_text: string;
  rows_text.data = dims.data + x_index + 1;
  rows_text.count = dims.count - x_index - 1;

  parse_decimal_s64 :: (s: string) -> (s64, bool) {
    if s.count == 0 return 0, false;
    v: s64 = 0;
    for 0..s.count-1 {
      ch := s[it];
      if ch < #char "0" || ch > #char "9" return 0, false;
      v = v * 10 + cast(s64) (ch - #char "0");
    }
    return v, true;
  }

  cols_value, cols_ok := parse_decimal_s64(cols_text);
  rows_value, rows_ok := parse_decimal_s64(rows_text);
  if !cols_ok || !rows_ok return 0, 0, false;
  if cols_value <= 0 || rows_value <= 0 return 0, 0, false;
  return cols_value, rows_value, true;
}

ir_emit_matrix_constructor_from_scalar_args :: (expr: *IR_Expr) -> (string, bool, bool) {
  cols, rows, is_matrix := ir_parse_float_matrix_dims(expr.text);
  if !is_matrix return "", true, false;
  if expr.args.count != cols * rows return "", false, true;

  b: String_Builder;
  append(*b, expr.text, "(");
  for c: 0..cols-1 {
    if c != 0 append(*b, ", ");
    append(*b, tprint("float%(", rows));
    for r: 0..rows-1 {
      if r != 0 append(*b, ", ");
      arg_index := r * cols + c; // Jai matrix fields are row-major: _11, _12, _21, _22, ...
      arg_text, ok := ir_expr_to_slang_from_ir(expr.args[arg_index]);
      if !ok return "", false, true;
      append(*b, arg_text);
    }
    append(*b, ")");
  }
  append(*b, ")");
  return builder_to_string(*b), true, true;
}

ir_expr_to_slang_from_ir :: (expr: *IR_Expr) -> (string, bool) {
  assert(expr != null);

  if expr.kind == {
    case .IDENT;   return expr.text, true;
    case .LITERAL; return expr.text, true;
    case .ARRAY_LITERAL; {
      b: String_Builder;
      append(*b, "{");
      for expr.args {
        arg_text, ok := ir_expr_to_slang_from_ir(it);
        if !ok return "", false;
        if it_index != 0 append(*b, ", ");
        append(*b, arg_text);
      }
      append(*b, "}");
      return builder_to_string(*b), true;
    }

    case .UNARY; {
      inner, ok := ir_expr_to_slang_from_ir(expr.left);
      if !ok return "", false;
      return tprint("%%", expr.text, inner), true;
    }

    case .BINARY; {
      left, left_ok := ir_expr_to_slang_from_ir(expr.left);
      if !left_ok return "", false;
      right, right_ok := ir_expr_to_slang_from_ir(expr.right);
      if !right_ok return "", false;
      return tprint("(% % %)", left, expr.text, right), true;
    }

    case .MEMBER; {
      left, left_ok := ir_expr_to_slang_postfix_base(expr.left);
      if !left_ok return "", false;
      return tprint("%.%", left, expr.text), true;
    }

    case .SUBSCRIPT; {
      left, left_ok := ir_expr_to_slang_postfix_base(expr.left);
      if !left_ok return "", false;
      right, right_ok := ir_expr_to_slang_from_ir(expr.right);
      if !right_ok return "", false;
      return tprint("%[%]", left, right), true;
    }

    case .CAST; {
      inner, ok := ir_expr_to_slang_from_ir(expr.left);
      if !ok return "", false;
      return tprint("%(%)", expr.text, inner), true;
    }

    case .CALL; {
      callee, callee_ok := ir_expr_to_slang_postfix_base(expr.left);
      if !callee_ok return "", false;
      if expr.left && expr.left.kind == .IDENT && expr.left.text == "mix" callee = "lerp";
      if expr.left && expr.left.kind == .IDENT && expr.left.text == "mod" callee = "fmod";
      b: String_Builder;
      append(*b, callee, "(");
      for expr.args {
        arg_text, ok := ir_expr_to_slang_from_ir(it);
        if !ok return "", false;
        if it_index != 0 append(*b, ", ");
        append(*b, arg_text);
      }
      append(*b, ")");
      return builder_to_string(*b), true;
    }

    case .CONSTRUCTOR; {
      matrix_text, matrix_ok, handled_matrix := ir_emit_matrix_constructor_from_scalar_args(expr);
      if handled_matrix return matrix_text, matrix_ok;
      b: String_Builder;
      append(*b, expr.text, "(");
      for expr.args {
        arg_text, ok := ir_expr_to_slang_from_ir(it);
        if !ok return "", false;
        if it_index != 0 append(*b, ", ");
        append(*b, arg_text);
      }
      append(*b, ")");
      return builder_to_string(*b), true;
    }
  }

  return "", false;
}

// Postfix forms like `.member`, `[index]`, and call argument lists bind tighter than
// unary/cast/binary forms, so parenthesize those bases to preserve Jai expression meaning.
ir_expr_to_slang_postfix_base :: (expr: *IR_Expr) -> (string, bool) {
  assert(expr != null);
  text, ok := ir_expr_to_slang_from_ir(expr);
  if !ok return "", false;

  need_parens := false;
  if expr.kind == .UNARY need_parens = true;
  if expr.kind == .BINARY need_parens = true;
  if expr.kind == .CAST need_parens = true;
  if expr.kind == .CONSTRUCTOR need_parens = true;

  if need_parens return tprint("(%)", text), true;
  return text, true;
}

ir_expr_to_slang :: (node: *Code_Node,
                     input_fields: [] string,
                     output_fields: [] string,
                     active_usings: [] IR_Using_Source = .[],
                     active_aliases: [] IR_Decl_Alias = .[],
                     state: *IR_Lowering_State = null) -> (string, bool) {
  assert(state != null);
  expr, ok := ir_lower_expr(node, input_fields, output_fields, active_usings, active_aliases, state);
  if !ok return "", false;
  text, text_ok := ir_expr_to_slang_from_ir(expr);
  if !text_ok return "", false;
  return text, true;
}

ir_compute_builtin_to_semantic :: (builtin_name: string) -> (string, bool) {
  if builtin_name == "thread_position_in_grid" return "SV_DispatchThreadID", true;
  if builtin_name == "thread_position_in_threadgroup" return "SV_GroupThreadID", true;
  if builtin_name == "threadgroup_position_in_grid" return "SV_GroupID", true;
  if builtin_name == "thread_index_in_threadgroup" return "SV_GroupIndex", true;
  return "", false;
}

ir_lower_compute_input_struct :: (name: string, type: *Type_Info) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;
  if !type || type.type != .STRUCT return out, false;

  st := cast(*Type_Info_Struct) type;
  for *st.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    builtin_name, found := compute_builtin_note_for_member(it);
    if !found return out, false;
    semantic, sem_ok := ir_compute_builtin_to_semantic(builtin_name);
    if !sem_ok return out, false;
    type_name, type_ok := ir_type_to_slang_name(it.type);
    if !type_ok return out, false;
    original_type_name, original_ok := ir_type_to_original_name(it.type);
    if !original_ok return out, false;
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      type_name = type_name,
      semantic = semantic,
      original_type_name = original_type_name,
    });
  }

  return out, true;
}

ir_collect_compute_declared_struct_type :: (ti: *Type_Info, state: *IR_Lowering_State, loc_node: *Code_Node, out_extra_structs: *[..] IR_Struct) -> bool {
  if !ti return true;

  if ti.type == .ARRAY {
    base_type, _ := split_array_type_and_suffix("IR lowering(compute)", ti);
    if !base_type return false;
    return ir_collect_compute_declared_struct_type(base_type, state, loc_node, out_extra_structs);
  }

  if ti.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) ti;
    if !ptr.pointer_to return true;
    return ir_collect_compute_declared_struct_type(ptr.pointer_to, state, loc_node, out_extra_structs);
  }

  if ti.type != .STRUCT return true;
  st := cast(*Type_Info_Struct) ti;
  struct_name := jai_to_hlsl_type_name(get_struct_type_name(st));
  if ir_is_builtin_slang_type_name(struct_name) return true;
  lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ti, out_extra_structs);
  if !lowered_ok {
    ir_set_diagnostic(state, tprint("IR lowering(compute): could not lower declared struct type '%'", struct_name), loc_node);
    return false;
  }
  ir_add_struct_unique_by_name(out_extra_structs, lowered_struct);
  return true;
}

ir_collect_compute_declared_structs_in_node :: (node: *Code_Node, out_extra_structs: *[..] IR_Struct, state: *IR_Lowering_State) -> bool {
  if !node return true;

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
    return ir_collect_compute_declared_struct_type(decl_type, state, node, out_extra_structs);
  }

  if node.kind == .IF {
    n := cast(*Code_If) node;
    if !ir_collect_compute_declared_structs_in_block(n.then_block, out_extra_structs, state) return false;
    if !ir_collect_compute_declared_structs_in_block(n.else_block, out_extra_structs, state) return false;
    return true;
  }

  if node.kind == .FOR {
    n := cast(*Code_For) node;
    return ir_collect_compute_declared_structs_in_block(n.block, out_extra_structs, state);
  }

  if node.kind == .WHILE {
    n := cast(*Code_While) node;
    return ir_collect_compute_declared_structs_in_block(n.block, out_extra_structs, state);
  }

  if node.kind == .CASE {
    n := cast(*Code_Case) node;
    return ir_collect_compute_declared_structs_in_block(n.then_block, out_extra_structs, state);
  }

  if node.kind == .BLOCK {
    return ir_collect_compute_declared_structs_in_block(cast(*Code_Block) node, out_extra_structs, state);
  }

  return true;
}

ir_collect_compute_declared_structs_in_block :: (block: *Code_Block, out_extra_structs: *[..] IR_Struct, state: *IR_Lowering_State) -> bool {
  if !block return true;
  for block.statements if !ir_collect_compute_declared_structs_in_node(it, out_extra_structs, state) return false;
  return true;
}

// Shared lowering functions moved to ir_pipeline/ir_shared.jai.

IR_Shader_Header_Context :: struct {
  name: string;
  header: *Code_Procedure_Header;
}

#scope_export

ir_lower_vertex_from_shader_context :: (ctx: IR_Shader_Header_Context) -> (IR_Vertex_Shader, bool, IR_Diagnostic) {
  out: IR_Vertex_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  assert(ctx.header != null);
  assert(ctx.header.body_or_null != null);
  assert(ctx.header.body_or_null.block != null);
  if ctx.header.arguments.count < 1 {
    ir_set_diagnostic(*state, "IR lowering(vertex): expected at least one input argument", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }
  if ctx.header.returns.count != 1 {
    ir_set_diagnostic(*state, "IR lowering(vertex): expected exactly one return value", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }

  arg0 := ctx.header.arguments[0];
  ret0 := ctx.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok {
    ir_set_diagnostic(*state, "IR lowering(vertex): could not lower input struct type", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }

  out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
  if !out_ok {
    ir_set_diagnostic(*state, "IR lowering(vertex): could not lower output struct type", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }

  out.source_name = ctx.name;
  out.entry_name = "VertexMain";
  out.kind = .Vertex;
  out.input = in_struct;
  out.output = out_struct;
  for i: 1..ctx.header.arguments.count-1 {
    arg := ctx.header.arguments[i];
    arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
    arg_type_name, arg_ok := ir_lower_shader_arg_type_name(arg_type, *out.extra_structs);
    if !arg_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(vertex): unsupported extra argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    original_type_name, original_ok := ir_type_to_original_name(arg_type);
    if !original_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(vertex): unsupported original type for argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    arg_ir_type, arg_ir_type_ok := ir_type_from_type_info(arg_type);
    if !arg_ir_type_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(vertex): unsupported typed IR argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    if arg_type && arg_type.type == .STRUCT {
      arg_ir_type.flags |= .PARAMETER_BLOCK;
    }
    pointee_name := "";
    pointee_ok := false;
    pointee_is_struct := false;
    if arg_type && arg_type.type == .POINTER {
      pointee_name, pointee_ok, pointee_is_struct = ir_pointer_pointee_lowered_name(arg_type);
      if !pointee_ok {
        ir_set_diagnostic(*state, tprint("IR lowering(vertex): unsupported pointer pointee type for argument '%'", arg.name), cast(*Code_Node) ctx.header);
        return out, false, ir_get_diagnostic(*state);
      }
    }
    array_add(*out.args, .{
      name = arg.name,
      type = arg_ir_type,
      type_name = arg_type_name,
      is_readonly = true,
      original_type_name = original_type_name,
      is_pointer = arg_type && arg_type.type == .POINTER,
      pointer_pointee_type_name = pointee_name,
      pointer_pointee_is_struct = pointee_is_struct,
    });
  }
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(ctx.header, *seen_headers, *out.functions, ctx.header, *state) {
    ir_set_diagnostic(*state, "IR lowering(vertex): failed while collecting/lowering helper functions", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }
  input_field_names: [..] string;
  output_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(ctx.header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  for out.output.fields array_add(*output_field_names, it.name);
  if !ir_shared_lower_block(ctx.header.body_or_null.block, *out.body, input_field_names, output_field_names, true, *state, parameter_usings, .[]) {
    ir_set_diagnostic(*state, "IR lowering(vertex): failed while lowering function body", cast(*Code_Node) ctx.header.body_or_null.block);
    return out, false, ir_get_diagnostic(*state);
  }

  return out, true, ir_get_diagnostic(*state);
}

ir_lower_fragment_from_shader_context :: (ctx: IR_Shader_Header_Context) -> (IR_Fragment_Shader, bool, IR_Diagnostic) {
  out: IR_Fragment_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  assert(ctx.header != null);
  assert(ctx.header.body_or_null != null);
  assert(ctx.header.body_or_null.block != null);
  if ctx.header.arguments.count < 1 {
    ir_set_diagnostic(*state, "IR lowering(fragment): expected at least one input argument", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }
  if ctx.header.returns.count != 1 {
    ir_set_diagnostic(*state, "IR lowering(fragment): expected exactly one return value", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }

  arg0 := ctx.header.arguments[0];
  ret0 := ctx.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok {
    ir_set_diagnostic(*state, "IR lowering(fragment): could not lower input struct type", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }
  // Fragment-stage gl_FragCoord should map to rasterized screen position.
  for *in_struct.fields {
    sem_upper := to_upper_copy(it.semantic);
    if sem_upper == "GL_FRAGCOORD" || sem_upper == "FRAG_COORD" {
      it.semantic = "SV_Position";
    }
  }

  out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
  if !out_ok {
    ir_set_diagnostic(*state, "IR lowering(fragment): could not lower output struct type", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }

  out.source_name = ctx.name;
  out.entry_name = "FragmentMain";
  out.kind = .Fragment;
  out.input = in_struct;
  out.output = out_struct;
  for i: 1..ctx.header.arguments.count-1 {
    arg := ctx.header.arguments[i];
    arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
    arg_type_name, arg_ok := ir_lower_shader_arg_type_name(arg_type, *out.extra_structs);
    if !arg_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(fragment): unsupported extra argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    original_type_name, original_ok := ir_type_to_original_name(arg_type);
    if !original_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(fragment): unsupported original type for argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    arg_ir_type, arg_ir_type_ok := ir_type_from_type_info(arg_type);
    if !arg_ir_type_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(fragment): unsupported typed IR argument '%'", arg.name), cast(*Code_Node) ctx.header);
      return out, false, ir_get_diagnostic(*state);
    }
    if arg_type && arg_type.type == .STRUCT {
      arg_ir_type.flags |= .PARAMETER_BLOCK;
    }
    pointee_name := "";
    pointee_ok := false;
    pointee_is_struct := false;
    if arg_type && arg_type.type == .POINTER {
      pointee_name, pointee_ok, pointee_is_struct = ir_pointer_pointee_lowered_name(arg_type);
      if !pointee_ok {
        ir_set_diagnostic(*state, tprint("IR lowering(fragment): unsupported pointer pointee type for argument '%'", arg.name), cast(*Code_Node) ctx.header);
        return out, false, ir_get_diagnostic(*state);
      }
    }
    array_add(*out.args, .{
      name = arg.name,
      type = arg_ir_type,
      type_name = arg_type_name,
      is_readonly = true,
      original_type_name = original_type_name,
      is_pointer = arg_type && arg_type.type == .POINTER,
      pointer_pointee_type_name = pointee_name,
      pointer_pointee_is_struct = pointee_is_struct,
    });
  }
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(ctx.header, *seen_headers, *out.functions, ctx.header, *state) {
    ir_set_diagnostic(*state, "IR lowering(fragment): failed while collecting/lowering helper functions", cast(*Code_Node) ctx.header);
    return out, false, ir_get_diagnostic(*state);
  }
  input_field_names: [..] string;
  output_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(ctx.header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  for out.output.fields array_add(*output_field_names, it.name);
  if !ir_shared_lower_block(ctx.header.body_or_null.block, *out.body, input_field_names, output_field_names, true, *state, parameter_usings, .[]) {
    ir_set_diagnostic(*state, "IR lowering(fragment): failed while lowering function body", cast(*Code_Node) ctx.header.body_or_null.block);
    return out, false, ir_get_diagnostic(*state);
  }

  return out, true, ir_get_diagnostic(*state);
}

ir_lower_compute_from_shader_context :: (ctx: IR_Shader_Header_Context) -> (IR_Compute_Shader, bool, IR_Diagnostic) {
  out: IR_Compute_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  header := ctx.header;
  assert(header != null);
  assert(header.body_or_null != null);
  assert(header.body_or_null.block != null);
  if header.arguments.count < 2 {
    ir_set_diagnostic(*state, "IR lowering(compute): expected input struct + at least one buffer argument", cast(*Code_Node) header);
    return out, false, ir_get_diagnostic(*state);
  }
  if header.returns.count != 0 {
    ir_set_diagnostic(*state, "IR lowering(compute): compute shaders must return void", cast(*Code_Node) header);
    return out, false, ir_get_diagnostic(*state);
  }

  input_arg := header.arguments[0];
  input_type := ifx input_arg.type_inst then input_arg.type_inst.result else ifx input_arg.expression then input_arg.expression.type else null;
  input_struct, input_ok := ir_lower_compute_input_struct(tprint("%_In", ctx.name), input_type);
  if !input_ok {
    ir_set_diagnostic(*state, "IR lowering(compute): could not lower compute input struct/builtins", cast(*Code_Node) header);
    return out, false, ir_get_diagnostic(*state);
  }

  out.source_name = ctx.name;
  out.entry_name = "ComputeMain";
  out.kind = .Compute;
  out.input = input_struct;

  for i: 1..header.arguments.count-1 {
    arg := header.arguments[i];
    arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
    if !arg_type || arg_type.type != .POINTER {
      ir_set_diagnostic(*state, tprint("IR lowering(compute): argument '%' must be a pointer/buffer", arg.name), cast(*Code_Node) header);
      return out, false, ir_get_diagnostic(*state);
    }
    ptr := cast(*Type_Info_Pointer) arg_type;
    elem_ir_type, elem_ir_ok := ir_type_from_type_info(ptr.pointer_to);
    if !elem_ir_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(compute): unsupported typed pointee for argument '%'", arg.name), cast(*Code_Node) header);
      return out, false, ir_get_diagnostic(*state);
    }
    elem_type_name, elem_ok := ir_type_to_slang_name(ptr.pointer_to);
    if !elem_ok {
      ir_set_diagnostic(*state, tprint("IR lowering(compute): unsupported pointee type for argument '%'", arg.name), cast(*Code_Node) header);
      return out, false, ir_get_diagnostic(*state);
    }
    if ptr.pointer_to && ptr.pointer_to.type == .STRUCT {
      struct_type := cast(*Type_Info_Struct) ptr.pointer_to;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
      if !ir_is_builtin_slang_type_name(struct_name) {
        lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ptr.pointer_to, *out.extra_structs);
        if !lowered_ok {
          ir_set_diagnostic(*state, tprint("IR lowering(compute): could not lower struct type '%' for argument '%'", struct_name, arg.name), cast(*Code_Node) header);
          return out, false, ir_get_diagnostic(*state);
        }
        ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
      }
    }
    array_add(*out.buffers, .{
      name = arg.name,
      element_type = elem_ir_type,
      element_type_name = elem_type_name,
    });
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(header, *seen_headers, *out.functions, header, *state) {
    ir_set_diagnostic(*state, "IR lowering(compute): failed while collecting/lowering helper functions", cast(*Code_Node) header);
    return out, false, ir_get_diagnostic(*state);
  }

  for seen_headers {
    if it == header continue;
    for it.arguments {
      arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
      if !arg_type || arg_type.type != .STRUCT continue;
      struct_type := cast(*Type_Info_Struct) arg_type;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
      if ir_is_builtin_slang_type_name(struct_name) continue;
      lowered_struct, lowered_ok := ir_lower_struct_from_type(struct_name, arg_type);
      if !lowered_ok {
        ir_set_diagnostic(*state, tprint("IR lowering(compute): could not lower helper struct argument type '%' ", struct_name), cast(*Code_Node) it);
        return out, false, ir_get_diagnostic(*state);
      }
      ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
    }
    for it.returns {
      ret_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
      if !ret_type || ret_type.type != .STRUCT continue;
      ret_struct_type := cast(*Type_Info_Struct) ret_type;
      ret_struct_name := jai_to_hlsl_type_name(get_struct_type_name(ret_struct_type));
      if ir_is_builtin_slang_type_name(ret_struct_name) continue;
      lowered_struct, lowered_ok := ir_lower_struct_from_type(ret_struct_name, ret_type);
      if !lowered_ok {
        ir_set_diagnostic(*state, tprint("IR lowering(compute): could not lower helper struct return type '%'", ret_struct_name), cast(*Code_Node) it);
        return out, false, ir_get_diagnostic(*state);
      }
      ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
    }
    if it.body_or_null && it.body_or_null.block {
      if !ir_collect_compute_declared_structs_in_block(it.body_or_null.block, *out.extra_structs, *state) {
        return out, false, ir_get_diagnostic(*state);
      }
    }
  }
  if !ir_collect_compute_declared_structs_in_block(header.body_or_null.block, *out.extra_structs, *state) {
    return out, false, ir_get_diagnostic(*state);
  }

  input_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  if !ir_shared_lower_block(header.body_or_null.block, *out.body, input_field_names, .[], false, *state, parameter_usings, .[]) {
    ir_set_diagnostic(*state, "IR lowering(compute): failed while lowering function body", cast(*Code_Node) header.body_or_null.block);
    return out, false, ir_get_diagnostic(*state);
  }
  return out, true, ir_get_diagnostic(*state);
}

#scope_module

ir_emit_struct_slang :: (sb: *String_Builder, s: *IR_Struct) {
  append(sb, tprint("struct % {\n", s.name));
  for s.fields {
    type_name := it.type_name;
    if it.type.display_name.count != 0 type_name = it.type.display_name;
    semantic := ir_normalize_semantic_for_slang(it.semantic);
    if semantic.count != 0 append(sb, tprint("    % % : %;\n", type_name, it.name, semantic));
    else append(sb, tprint("    % %;\n", type_name, it.name));
  }
  append(sb, "};\n\n");
}

ir_arg_display_type_name :: (arg: IR_Function_Arg) -> string {
  if arg.type.display_name.count != 0 return arg.type.display_name;
  return arg.type_name;
}

ir_arg_is_global_resource :: (arg: IR_Function_Arg) -> bool {
  if arg.type.flags & .PARAMETER_BLOCK return true;
  type_name := ir_arg_display_type_name(arg);
  return ir_type_name_is_global_resource(type_name);
}

ir_normalize_semantic_for_slang :: (semantic: string) -> string {
  if semantic.count == 0 return "";
  sem_upper := to_upper_copy(semantic);
  if sem_upper == "SV_POSITION" return "SV_Position";
  if sem_upper == "GL_POSITION" return "SV_Position";
  if sem_upper == "POSITION" return "SV_Position";
  if sem_upper == "VERTEX_ID" return "SV_VertexID";
  if sem_upper == "INSTANCE_ID" return "SV_InstanceID";
  if sem_upper == "PRIMITIVE_ID" return "SV_PrimitiveID";
  if sem_upper == "FRONT_FACING" return "SV_IsFrontFace";
  return semantic;
}

find_output_position_field :: (s: *IR_Struct) -> string {
  for s.fields {
    sem := to_upper_copy(it.semantic);
    if sem == "SV_POSITION" return it.name;
    if sem == "POSITION" return it.name;
  }
  for s.fields if it.name == "gl_Position" || it.name == "position" return it.name;
  return "";
}

ir_block_has_return_stmt :: (block: *IR_Block) -> bool {
  assert(block != null);
  for block.statements {
    if it.kind == .RETURN return true;
    if it.kind == .IF {
      if it.if_then && ir_block_has_return_stmt(it.if_then) return true;
      if it.if_else && ir_block_has_return_stmt(it.if_else) return true;
    } else if it.kind == .FOR {
      if it.for_body && ir_block_has_return_stmt(it.for_body) return true;
    }
  }
  return false;
}

ir_emit_graphics_global_resource_args :: (sb: *String_Builder, args: [] IR_Function_Arg) -> bool {
  assert(sb != null);
  emitted_any := false;
  for args {
    type_name := ir_arg_display_type_name(it);
    if !ir_type_name_is_global_resource(type_name) continue;
    append(sb, tprint("% %;\n", type_name, it.name));
    emitted_any = true;
  }
  if emitted_any append(sb, "\n");
  return true;
}

ir_pair_global_resource_arg_conflicts :: (vertex_args: [] IR_Function_Arg, fragment_args: [] IR_Function_Arg) -> bool {
  for vertex_args {
    va := it;
    va_type_name := ir_arg_display_type_name(va);
    if !ir_type_name_is_global_resource(va_type_name) continue;
    for fragment_args {
      fa := it;
      fa_type_name := ir_arg_display_type_name(fa);
      if !ir_type_name_is_global_resource(fa_type_name) continue;
      if va.name != fa.name continue;
      if va_type_name != fa_type_name return true;
    }
  }
  return false;
}

ir_emit_pair_global_resource_args :: (sb: *String_Builder, vertex_args: [] IR_Function_Arg, fragment_args: [] IR_Function_Arg) -> bool {
  assert(sb != null);
  if ir_pair_global_resource_arg_conflicts(vertex_args, fragment_args) return false;

  emitted_any := false;
  seen_names: [..] string;

  emit_from_args :: (sb: *String_Builder, args: [] IR_Function_Arg, seen_names: *[..] string, emitted_any: *bool) {
    for args {
      arg := it;
      type_name := ir_arg_display_type_name(arg);
      if !ir_type_name_is_global_resource(type_name) continue;
      already_seen := false;
      for seen_names.* if it == arg.name { already_seen = true; break; }
      if already_seen continue;
      append(sb, tprint("% %;\n", type_name, arg.name));
      array_add(seen_names, arg.name);
      emitted_any.* = true;
    }
  }

  emit_from_args(sb, vertex_args, *seen_names, *emitted_any);
  emit_from_args(sb, fragment_args, *seen_names, *emitted_any);
  if emitted_any append(sb, "\n");
  return true;
}

ir_emit_compute_global_buffers :: (sb: *String_Builder, buffers: [] IR_Compute_Buffer) {
  assert(sb != null);
  if buffers.count == 0 return;
  for buffers {
    elem_type_name := it.element_type_name;
    if it.element_type.display_name.count != 0 elem_type_name = it.element_type.display_name;
    append(sb, tprint("RWStructuredBuffer<%> %;\n", elem_type_name, it.name));
  }
  append(sb, "\n");
}

#scope_export

emit_ir_vertex_to_slang :: (shader: IR_Vertex_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);
  for shader.extra_structs ir_emit_struct_slang(*sb, *it);
  ir_emit_function_prototypes(*sb, shader.functions);
  if !ir_emit_function_definitions(*sb, shader.functions) return "", false;
  if !ir_emit_graphics_global_resource_args(*sb, shader.args) return "", false;

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input", shader.output.name, shader.entry_name, shader.input.name));
  for shader.args {
    arg_type_name := ir_arg_display_type_name(it);
    if ir_arg_is_global_resource(it) continue;
    if it.is_readonly append(*sb, tprint(", const % %", arg_type_name, it.name));
    else append(*sb, tprint(", % %", arg_type_name, it.name));
  }
  append(*sb, ") {\n");
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");

  if !ir_block_has_return_stmt(*shader.body) {
    position_field := find_output_position_field(*shader.output);
    if position_field.count != 0 append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
    append(*sb, "    return o;\n");
  }
  append(*sb, "}");
  return builder_to_string(*sb), true;
}

emit_ir_fragment_to_slang :: (shader: IR_Fragment_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);
  for shader.extra_structs ir_emit_struct_slang(*sb, *it);
  ir_emit_function_prototypes(*sb, shader.functions);
  if !ir_emit_function_definitions(*sb, shader.functions) return "", false;
  if !ir_emit_graphics_global_resource_args(*sb, shader.args) return "", false;

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input", shader.output.name, shader.entry_name, shader.input.name));
  for shader.args {
    arg_type_name := ir_arg_display_type_name(it);
    if ir_arg_is_global_resource(it) continue;
    if it.is_readonly append(*sb, tprint(", const % %", arg_type_name, it.name));
    else append(*sb, tprint(", % %", arg_type_name, it.name));
  }
  append(*sb, ") {\n");
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*shader.body) append(*sb, "    return o;\n");
  append(*sb, "}");
  return builder_to_string(*sb), true;
}

emit_ir_graphics_pair_to_slang :: (vertex: IR_Vertex_Shader, fragment: IR_Fragment_Shader) -> (string, bool) {
  if vertex.entry_name.count == 0 || fragment.entry_name.count == 0 return "", false;

  append_ir_struct_once :: (sb: *String_Builder, emitted_names: *[..] string, s: *IR_Struct) {
    for emitted_names.* if it == s.name return;
    array_add(emitted_names, s.name);
    ir_emit_struct_slang(sb, s);
  }

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader_vertex: %\n", vertex.source_name));
  append(*sb, tprint("// source_shader_fragment: %\n\n", fragment.source_name));

  emitted_names: [..] string;
  append_ir_struct_once(*sb, *emitted_names, *vertex.input);
  append_ir_struct_once(*sb, *emitted_names, *vertex.output);
  append_ir_struct_once(*sb, *emitted_names, *fragment.input);
  append_ir_struct_once(*sb, *emitted_names, *fragment.output);
  for vertex.extra_structs append_ir_struct_once(*sb, *emitted_names, *it);
  for fragment.extra_structs append_ir_struct_once(*sb, *emitted_names, *it);

  pair_functions: [..] IR_Function;
  for vertex.functions ir_add_function_unique_by_name(*pair_functions, it);
  for fragment.functions ir_add_function_unique_by_name(*pair_functions, it);
  ir_emit_function_prototypes(*sb, pair_functions);
  if !ir_emit_function_definitions(*sb, pair_functions) return "", false;
  if !ir_emit_pair_global_resource_args(*sb, vertex.args, fragment.args) return "", false;

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input", vertex.output.name, vertex.entry_name, vertex.input.name));
  for vertex.args {
    arg_type_name := ir_arg_display_type_name(it);
    if ir_arg_is_global_resource(it) continue;
    if it.is_readonly append(*sb, tprint(", const % %", arg_type_name, it.name));
    else append(*sb, tprint(", % %", arg_type_name, it.name));
  }
  append(*sb, ") {\n");
  append(*sb, tprint("    % o = (%)0;\n", vertex.output.name, vertex.output.name));
  vertex_body_lines: [..] string;
  if !ir_emit_ir_block_lines(*vertex_body_lines, *vertex.body, 1) return "", false;
  for vertex_body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*vertex.body) {
    position_field := find_output_position_field(*vertex.output);
    if position_field.count != 0 append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
    append(*sb, "    return o;\n");
  }
  append(*sb, "}\n\n");

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input", fragment.output.name, fragment.entry_name, fragment.input.name));
  for fragment.args {
    arg_type_name := ir_arg_display_type_name(it);
    if ir_arg_is_global_resource(it) continue;
    if it.is_readonly append(*sb, tprint(", const % %", arg_type_name, it.name));
    else append(*sb, tprint(", % %", arg_type_name, it.name));
  }
  append(*sb, ") {\n");
  append(*sb, tprint("    % o = (%)0;\n", fragment.output.name, fragment.output.name));
  fragment_body_lines: [..] string;
  if !ir_emit_ir_block_lines(*fragment_body_lines, *fragment.body, 1) return "", false;
  for fragment_body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*fragment.body) append(*sb, "    return o;\n");
  append(*sb, "}\n");

  return builder_to_string(*sb), true;
}

emit_ir_compute_to_slang :: (shader: IR_Compute_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));
  ir_emit_struct_slang(*sb, *shader.input);
  for shader.extra_structs ir_emit_struct_slang(*sb, *it);
  ir_emit_function_prototypes(*sb, shader.functions);
  if !ir_emit_function_definitions(*sb, shader.functions) return "", false;
  ir_emit_compute_global_buffers(*sb, shader.buffers);

  append(*sb, "[shader(\"compute\")]\n");
  append(*sb, "void ", shader.entry_name);
  append(*sb, tprint("(% input) {\n", shader.input.name));
  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");
  append(*sb, "}\n");
  return builder_to_string(*sb), true;
}

#scope_file

member_get_semantic :: (member: *Type_Info_Struct_Member) -> string {
  for member.notes if begins_with(it, "semantic_") {
    ret: string;
    ret.data = it.data + 9;
    ret.count = it.count - 9;
    return ret;
  }
  return to_upper_copy(member.name);
}

// This is some hardcoding, and is incomplete.
// More types need to be added here
jai_to_hlsl_type_map :: #run -> Table(string, string) {
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
jai_to_hlsl_type_name :: (in: string) -> string {
  success, val := table_find(*jai_to_hlsl_type_map, in);
  return ifx success then val else in;
}
