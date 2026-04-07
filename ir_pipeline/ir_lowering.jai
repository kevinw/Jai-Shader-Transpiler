#scope_export

// Shared lowering helpers used by the ir_lower_*_from_shader_context functions below.

#load "./public_structs.jai";
Program_Print :: #import "Program_Print";


ir_reset_diagnostic :: (using state: *IR_Lowering_State) {
    first_error = .{};
    array_reset(*input_builtin_fields);
} @jdll_export

ir_set_diagnostic :: (using state: *IR_Lowering_State, message: string, node: *Code_Node = null) #c_call {
    push_context,defer_pop;
    
    // 
    // TODO : chain errors?
    //
    
    if first_error.message.count != 0 return; // Preserve first failure.
  first_error.message = message;
  if node {
    first_error.location = make_location(node);
    first_error.has_location = true;
  }
} @jdll_export

ir_get_diagnostic :: (state: *IR_Lowering_State) -> IR_Diagnostic {
    return state.first_error;
} @jdll_export

ir_canonical_callee_name :: (name: string) -> string {
  if name.count == 0 return name;
  i := name.count - 1;
  while i >= 0 {
    if name[i] == #char "." {
      return string.{ name.count - i - 1, name.data + i + 1 };
    }
    if i == 0 break;
    i -= 1;
  }
  return name;
} @jdll_export

#scope_module

PP :: #import "Program_Print";

ir_lowering_expression_to_source_string :: (node: *Code_Node) -> string {
  sb: String_Builder;
  PP.print_expression(*sb, node);
  return builder_to_string(*sb);
}

ir_type_to_shader_name :: (type: *Type_Info) -> (string, bool) {
  if !type return "", false;

  if type.type == .VARIANT {
    variant := cast(*Type_Info_Variant) type;
    if variant.name == "Float16" return "half", true;
    if variant.variant_of {
      resolved_name, resolved_ok := ir_type_to_shader_name(variant.variant_of);
      return resolved_name, resolved_ok;
    }
    return "", false;
  }

  if type.type == .ENUM {
    enum_type := cast(*Type_Info_Enum) type;
    if !enum_type.internal_type return "", false;
    // SPIR-V path models enums as integer-backed scalar values.
    lowered_name, lowered_ok := ir_type_to_shader_name(enum_type.internal_type);
    return lowered_name, lowered_ok;
  }

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return "", false;
    pointee_name, pointee_ok := ir_type_to_shader_name(ptr.pointer_to);
    if !pointee_ok return "", false;
    return tprint("*%", pointee_name), true;
  }

  if type.type == .ARRAY {
    base_type, suffix := split_array_type_and_suffix("IR lowering", type);
    if !base_type return "", false;
    base_name, base_ok := ir_type_to_shader_name(base_type);
    if !base_ok return "", false;
    return tprint("%%", base_name, suffix), true;
  }

  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      if inttype.signed {
        if type.runtime_size == 8 return "int64_t", true;
        if type.runtime_size == 4 return "int32_t", true;
        if type.runtime_size == 2 return "int16_t", true;
        if type.runtime_size == 1 return "int8_t", true;
        return "", false;
      } else {
        if type.runtime_size == 8 return "uint64_t", true;
        if type.runtime_size == 4 return "uint", true;
        if type.runtime_size == 2 return "uint16_t", true;
        if type.runtime_size == 1 return "uint8_t", true;
        return "", false;
      }
    }
    case .FLOAT; {
      if type.runtime_size == 8 return "double", true;
      if type.runtime_size == 4 return "float", true;
      if type.runtime_size == 2 return "half", true;
      return "", false;
    }
    case .BOOL; return "bool", true;
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      return jai_to_hlsl_type_name(get_struct_type_name(structtype)), true;
    }
  }

  return "", false;
}

ir_type_kind_from_slang_name :: (name: string) -> IR_Type_Kind {
  if name == "bool" return .BOOL;
  if name == "int8_t" return .I8;
  if name == "uint8_t" || name == "u8" return .U8;
  if name == "int16_t" return .I16;
  if name == "uint16_t" || name == "u16" return .U16;
  if name == "int" || name == "int32_t" return .I32;
  if name == "uint" || name == "u32" return .U32;
  if name == "int64_t" return .I64;
  if name == "uint64_t" return .U64;
  if name == "half" return .F16;
  if name == "float" return .F32;
  if name == "float2" return .F32x2;
  if name == "float3" return .F32x3;
  if name == "float4" return .F32x4;
  if name == "float2x2" return .F32x2x2;
  if name == "float3x3" return .F32x3x3;
  if name == "float4x4" return .F32x4x4;
  return .UNKNOWN;
}

ir_type_from_type_info :: (type: *Type_Info) -> (IR_Type, bool) {
  out: IR_Type;
  if !type return out, false;

  display_name, display_ok := ir_type_to_shader_name(type);
  if !display_ok return out, false;
  out.display_name = display_name;

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return out, false;
    pointee, pointee_ok := ir_type_from_type_info(ptr.pointer_to);
    if !pointee_ok return out, false;
    pointee_kind := pointee.kind;
    if pointee_kind == .STRUCT {
      builtin_pointee_kind := ir_type_kind_from_slang_name(pointee.display_name);
      if builtin_pointee_kind != .UNKNOWN pointee_kind = builtin_pointee_kind;
    }
    out.kind = .POINTER;
    out.pointee_kind = pointee_kind;
    out.pointee_display_name = pointee.display_name;
    out.pointee_struct_name = pointee.struct_name;
    out.pointee_is_struct = pointee_kind == .STRUCT;
    if pointee.kind == .FIXED_ARRAY {
      out.pointee_array_count = pointee.array_count;
      out.pointee_element_kind = pointee.element_kind;
      out.pointee_element_display_name = pointee.element_display_name;
      out.pointee_element_struct_name = pointee.element_struct_name;
    }
    return out, true;
  }

  if type.type == .ARRAY {
    array_t := cast(*Type_Info_Array) type;
    elem_ir, elem_ok := ir_type_from_type_info(array_t.element_type);
    if !elem_ok return out, false;
    elem_kind := elem_ir.kind;
    if elem_kind == .STRUCT {
      builtin_elem_kind := ir_type_kind_from_slang_name(elem_ir.display_name);
      if builtin_elem_kind != .UNKNOWN elem_kind = builtin_elem_kind;
    }
    out.kind = .FIXED_ARRAY;
    out.element_kind = elem_kind;
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
    out.origin = st;
    return out, true;
  }

  out.kind = ir_type_kind_from_slang_name(display_name);
  if out.kind == .UNKNOWN return out, false;
  return out, true;
}

ir_lower_struct_from_type :: (name: string, type: *Type_Info) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;

  if !type || type.type != .STRUCT return out, false;

  struct_type := cast(*Type_Info_Struct) type;
  out.origin = struct_type;
  for *struct_type.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    field_semantic := member_get_semantic(it);
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      semantic = field_semantic,
      source_member_index = cast(s32) it_index,
    });
  }

  return out, true;
}

declaration_get_semantic :: (decl: *Code_Declaration) -> (string, bool) {
  if !decl return "", false;
  for decl.notes {
    note_text := it.text;
    if begins_with(note_text, "semantic_") {
      ret: string;
      ret.data = note_text.data + 9;
      ret.count = note_text.count - 9;
      return ret, true;
    }

    note_upper := to_upper_copy(note_text);
    if begins_with(note_upper, "SV_") return note_text, true;
    if begins_with(note_upper, "GL_") return note_text, true;
  }
  return "", false;
}

ir_collect_nested_structs_for_member_type :: (type: *Type_Info, extra_structs: *[..] IR_Struct) -> bool {
  if !type return false;

  if type.type == .ARRAY {
    arr := cast(*Type_Info_Array) type;
    if !arr.element_type return false;
    return ir_collect_nested_structs_for_member_type(arr.element_type, extra_structs);
  }

  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return false;
    if ptr.pointer_to.type == .STRUCT {
      st := cast(*Type_Info_Struct) ptr.pointer_to;
      nested_name := jai_to_hlsl_type_name(get_struct_type_name(st));
      if !ir_is_builtin_shader_type_name(nested_name) {
        nested_struct, nested_ok := ir_lower_struct_with_pointer_members_from_type(nested_name, ptr.pointer_to, extra_structs);
        if !nested_ok return false;
        ir_add_struct_unique_by_name(extra_structs, nested_struct);
      }
      return true;
    }

    _, elem_ok := ir_type_to_shader_name(ptr.pointer_to);
    return elem_ok;
  }

  if type.type == .STRUCT {
    st := cast(*Type_Info_Struct) type;
    nested_name := jai_to_hlsl_type_name(get_struct_type_name(st));
    if !ir_is_builtin_shader_type_name(nested_name) {
      nested_struct, nested_ok := ir_lower_struct_with_pointer_members_from_type(nested_name, type, extra_structs);
      if !nested_ok return false;
      ir_add_struct_unique_by_name(extra_structs, nested_struct);
    }
    return true;
  }

  _, type_ok := ir_type_to_shader_name(type);
  return type_ok;
}

ir_lower_struct_with_pointer_members_from_type :: (name: string, type: *Type_Info, extra_structs: *[..] IR_Struct) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;

  if !type || type.type != .STRUCT return out, false;

  st := cast(*Type_Info_Struct) type;
  out.origin = st;
  for *st.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    ok := ir_collect_nested_structs_for_member_type(it.type, extra_structs);
    if !ok return out, false;
    field_semantic := member_get_semantic(it);
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      semantic = field_semantic,
      source_member_index = cast(s32) it_index,
    });
  }

  return out, true;
}

ir_struct_has_field :: (s: *IR_Struct, name: string) -> bool {
  for s.fields if it.name == name return true;
  return false;
}

ir_find_field_index_in_struct :: (st: *IR_Struct, name: string) -> s32 {
  if !st return -1;
  for st.fields if it.name == name return cast(s32) it_index;
  return -1;
}

ir_add_struct_unique_by_name :: (structs: *[..] IR_Struct, s: IR_Struct) {
  if s.origin {
    for structs.* if it.origin && it.origin == s.origin return;
  }
  for structs.* if it.name == s.name return;
  array_add(structs, s);
}

ir_is_builtin_shader_type_name :: (name: string) -> bool {
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
    if !decl_type continue;

    st: *Type_Info_Struct = null;
    if decl_type.type == .STRUCT {
      st = cast(*Type_Info_Struct) decl_type;
    } else if decl_type.type == .POINTER {
      ptr := cast(*Type_Info_Pointer) decl_type;
      if ptr.pointer_to && ptr.pointer_to.type == .STRUCT {
        st = cast(*Type_Info_Struct) ptr.pointer_to;
      }
    }
    if !st continue;

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
    if it.declaration == declaration && it.member_name.count == 0 return it.replacement_text, true;
  }
  return "", false;
}

ir_lookup_decl_member_alias :: (active_aliases: [] IR_Decl_Alias, declaration: *Code_Declaration, member_name: string) -> (string, bool) {
  if !declaration || member_name.count == 0 return "", false;
  for active_aliases {
    if it.declaration == declaration && it.member_name == member_name return it.replacement_text, true;
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

ir_decl_has_note :: (decl: *Code_Declaration, note_name: string) -> bool {
  if !decl || note_name.count == 0 return false;
  for decl.notes if it.text == note_name return true;
  return false;
}

ir_code_struct_has_note :: (st: *Code_Struct, note_name: string) -> bool {
  if !st || note_name.count == 0 return false;
  for st.notes if it.text == note_name return true;
  return false;
}

ir_resolve_struct_node_from_type_expr :: (node: *Code_Node, depth: s64 = 0) -> *Code_Struct {
  if !node || depth > 8 return null;
  if node.kind == .STRUCT return cast(*Code_Struct) node;
  if node.kind == .UNARY_OPERATOR {
    un := cast(*Code_Unary_Operator) node;
    if un.subexpression return ir_resolve_struct_node_from_type_expr(un.subexpression, depth + 1);
    return null;
  }
  if node.kind == .CAST {
    cn := cast(*Code_Cast) node;
    if cn.expression return ir_resolve_struct_node_from_type_expr(cn.expression, depth + 1);
    return null;
  }
  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    if decl.expression return ir_resolve_struct_node_from_type_expr(decl.expression, depth + 1);
    return null;
  }
  if node.kind == .IDENT {
    ident := cast(*Code_Ident) node;
    if ident.resolved_declaration return ir_resolve_struct_node_from_type_expr(cast(*Code_Node) ident.resolved_declaration, depth + 1);
    return null;
  }
  if node.kind == .TYPE_INSTANTIATION {
    inst := cast(*Code_Type_Instantiation) node;
    if inst.type_valued_expression return ir_resolve_struct_node_from_type_expr(inst.type_valued_expression, depth + 1);
    return null;
  }
  return null;
}

ir_function_constants_struct_from_arg :: (arg: *Code_Declaration) -> (*Type_Info_Struct, *Code_Struct, bool) {
  if !arg || !arg.type_inst || !arg.type_inst.result return null, null, false;
  result_type := arg.type_inst.result;
  st: *Type_Info_Struct;
  if result_type.type == .STRUCT {
    st = cast(*Type_Info_Struct) result_type;
  } else if result_type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) result_type;
    if !ptr.pointer_to || ptr.pointer_to.type != .STRUCT return null, null, false;
    st = cast(*Type_Info_Struct) ptr.pointer_to;
  } else {
    return null, null, false;
  }
  struct_node := ir_resolve_struct_node_from_type_expr(arg.type_inst.type_valued_expression);
  type_decl: *Code_Declaration;
  ident_expr := arg.type_inst.type_valued_expression;
  if ident_expr && ident_expr.kind == .UNARY_OPERATOR {
    un := cast(*Code_Unary_Operator) ident_expr;
    ident_expr = un.subexpression;
  }
  if ident_expr && ident_expr.kind == .CAST {
    cn := cast(*Code_Cast) ident_expr;
    ident_expr = cn.expression;
  }
  if ident_expr && ident_expr.kind == .IDENT {
    ident := cast(*Code_Ident) ident_expr;
    type_decl = ident.resolved_declaration;
  }
  has_note := ir_code_struct_has_note(struct_node, "function_constants");
  if !has_note && type_decl has_note = ir_decl_has_note(type_decl, "function_constants");
  if !struct_node || !has_note return null, null, false;
  return st, struct_node, true;
}

ir_function_constant_type_from_type_info :: (type: *Type_Info) -> (IR_Function_Constant_Type, bool) {
    if !type {
        log_error("ir_function_constant_type_from_type_info: passed a null type");
        return .BOOL, false;
    }

  if type.type == .ENUM {
    enum_type := cast(*Type_Info_Enum) type;
    if !enum_type.internal_type return .BOOL, false;
    function_constant_type, ok := ir_function_constant_type_from_type_info(enum_type.internal_type);
    return function_constant_type, ok;
  }
    
  if type.type == {
    case .BOOL; return .BOOL, true;
    case .INTEGER;
      integer := cast(*Type_Info_Integer) type;
      if integer.signed {
        if integer.runtime_size == 1 return .S8, true;
        if integer.runtime_size == 2 return .S16, true;
        if integer.runtime_size == 4 return .S32, true;
        if integer.runtime_size == 8 return .S64, true;
      } else {
        if integer.runtime_size == 1 return .U8, true;
        if integer.runtime_size == 2 return .U16, true;
        if integer.runtime_size == 4 return .U32, true;
        if integer.runtime_size == 8 return .U64, true;
      }
      return .BOOL, false;
    case .FLOAT;
      fp := cast(*Type_Info_Float) type;
      if fp.runtime_size == 4 return .FLOAT, true;
    case .STRUCT;
        if type.(*Type_Info_Struct).name == {
        // TODO: this sucks. let's find or make a more robust "Vector" type matcher
        case "Vector2"; return .FLOAT2, true;
        case "Vector3"; return .FLOAT3, true;
        case "Vector4"; return .FLOAT4, true;
        }
  }
  return .BOOL, false;
}

ir_validate_function_constant_value :: (name: string,
                                        type: *Type_Info,
                                        expression: *Code_Node,
                                        source_node: *Code_Node,
                                        state: *IR_Lowering_State,
                                        source_struct_name: string = "",
                                        source_arg_name: string = "") -> (IR_Function_Constant, bool) {
  out: IR_Function_Constant;
  if !source_node return out, false;

  if !expression {
    if source_struct_name.count != 0 {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constants field '%.%' requires an initializer.", source_struct_name, name), source_node);
    } else {
      ir_set_diagnostic(state, "IR lowering: @function_constant requires an initializer.", source_node);
    }
    return out, false;
  }

  function_constant_type, type_ok := ir_function_constant_type_from_type_info(type);
  if !type_ok {
    if source_struct_name.count != 0 {
      ir_set_diagnostic(state,
                        tprint("IR lowering: @function_constants field '%.%' has unsupported type. Supported types are bool, integer scalar widths, enums backed by integer scalars, float, Vector2, Vector3, and Vector4.",
                               source_struct_name,
                               name),
                        source_node);
    } else {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constant '%' has unsupported type. Supported types are bool, integer scalar widths, enums backed by integer scalars, float, Vector2, Vector3, and Vector4.", name), source_node);
    }
    return out, false;
  }

  lowering_ctx := IR_Lowering_Context.{state = state};
  lowered_default, lowered_default_ok := ir_lower_expr(expression, lowering_ctx);
  if !lowered_default_ok {
    if state.first_error.message.count == 0 {
      if source_struct_name.count != 0 {
        ir_set_diagnostic(state,
                          tprint("IR lowering: @function_constants field '%.%' currently requires a compile-time constant default value.", source_struct_name, name),
                          expression);
      } else {
        ir_set_diagnostic(state, tprint("IR lowering: @function_constant '%' currently requires a compile-time constant default value.", name), expression);
      }
    }
    return out, false;
  }
  if lowered_default.kind == {
  case .LITERAL;
  case .CONSTRUCTOR;
    if lowered_default.kind == .CONSTRUCTOR {
      vector_constant_ok := false;
      if function_constant_type == {
      case .FLOAT2; vector_constant_ok = true;
      case .FLOAT3; vector_constant_ok = true;
      case .FLOAT4; vector_constant_ok = true;
      }
      if !vector_constant_ok {
        if source_struct_name.count != 0 {
          ir_set_diagnostic(state, tprint("IR lowering: @function_constants field '%.%' currently requires a compile-time scalar literal default value.", source_struct_name, name), expression);
        } else {
          ir_set_diagnostic(state, tprint("IR lowering: @function_constant '%' currently requires a compile-time scalar literal default value.", name), expression);
        }
        return out, false;
      }
    }
  case;
    if source_struct_name.count != 0 {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constants field '%.%' currently requires a compile-time constant literal or vector constructor default value.", source_struct_name, name), expression);
    } else {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constant '%' currently requires a compile-time constant literal or vector constructor default value.", name), expression);
    }
    return out, false;
  }

  default_value_text := compact_text(lowered_default.text);
  if lowered_default.kind == .CONSTRUCTOR {
    expression_builder: String_Builder;
    expression_builder.allocator = temp;
    Program_Print.print_expression(*expression_builder, expression);
    default_value_text = compact_text(builder_to_string(*expression_builder,, temp));
  }
  if default_value_text.count == 0 {
    if source_struct_name.count != 0 {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constants field '%.%' has an unsupported literal default value.", source_struct_name, name), expression);
    } else {
      ir_set_diagnostic(state, tprint("IR lowering: @function_constant '%' has an unsupported literal default value.", name), expression);
    }
    return out, false;
  }

  out = .{
    name = name,
    type = function_constant_type,
    default_value_text = default_value_text,
    source_struct_name = source_struct_name,
    source_arg_name = source_arg_name,
    location = make_location(source_node),
  };
  return out, true;
}

ir_lookup_struct_field_declaration :: (st: *Code_Struct, field_name: string) -> *Code_Declaration {
  if !st || !st.block || field_name.count == 0 return null;
  for st.block.members {
    if it.kind != .DECLARATION continue;
    decl := cast(*Code_Declaration) it;
    if decl.name == field_name return decl;
  }
  return null;
}

ir_collect_function_constants_from_struct_arg :: (arg: *Code_Declaration,
                                                  st: *Type_Info_Struct,
                                                  struct_node: *Code_Struct,
                                                  out_constants: *[..] IR_Function_Constant,
                                                  state: *IR_Lowering_State) -> bool {
  if !arg || !st || !struct_node return false;

  struct_name := get_struct_type_name(st);
  if struct_name.count == 0 {
    ir_set_diagnostic(state, "IR lowering: @function_constants struct arguments must use a named struct type.", arg);
    return false;
  }

  for *st.members {
    field_decl := ir_lookup_struct_field_declaration(struct_node, it.name);
    if !field_decl {
      ir_set_diagnostic(state,
                        tprint("IR lowering: @function_constants field '%.%' is missing a source declaration.", struct_name, it.name),
                        cast(*Code_Node) struct_node);
      return false;
    }

    lowered, ok := ir_validate_function_constant_value(it.name,
                                                       it.type,
                                                       field_decl.expression,
                                                       cast(*Code_Node) field_decl,
                                                       state,
                                                       struct_name,
                                                       arg.name);
    if !ok return false;
    array_add(out_constants, lowered);
  }

  return true;
}

ir_struct_has_pointer_members :: (type: *Type_Info) -> bool {
  if !type || type.type != .STRUCT return false;
  st := cast(*Type_Info_Struct) type;
  for *st.members if it.type && it.type.type == .POINTER return true;
  return false;
}

ir_align_up_s64 :: (value: s64, alignment: s64) -> s64 {
  if alignment <= 1 return value;
  rem := value % alignment;
  if rem == 0 return value;
  return value + (alignment - rem);
}

ir_uniform_field_layout_for_type :: (type: *Type_Info) -> (align: s64, size: s64, ok: bool, reason: string) {
  if !type return 0, 0, false, "missing type";

  if type.type == .ARRAY {
    arr := cast(*Type_Info_Array) type;
    if arr.array_type != .FIXED return 0, 0, false, "uniform arrays must be fixed-size";
    if arr.array_count < 0 return 0, 0, false, "uniform array has invalid element count";
    _, elem_size, elem_ok, _ := ir_uniform_field_layout_for_type(arr.element_type);
    if !elem_ok return 0, 0, false, "uniform array element type is unsupported";
    // Keep this in lock-step with spirv_text_backend_emitters.jai (std140-like array stride).
    stride: s64 = 16;
    return 16, stride * arr.array_count, true, "";
  }

  field_ir_type, field_ir_ok := ir_type_from_type_info(type);
  if !field_ir_ok return 0, 0, false, "unsupported field type";

  if field_ir_type.kind == .BOOL || field_ir_type.kind == .I32 || field_ir_type.kind == .U32 || field_ir_type.kind == .F32 {
    return 4, 4, true, "";
  }
  if field_ir_type.kind == .I8 || field_ir_type.kind == .U8 {
    return 1, 1, true, "";
  }
  if field_ir_type.kind == .I16 || field_ir_type.kind == .U16 || field_ir_type.kind == .F16 {
    return 2, 2, true, "";
  }
  if field_ir_type.kind == .I64 || field_ir_type.kind == .U64 {
    // Keep this in lock-step with current backend behavior.
    return 4, 8, true, "";
  }
  if field_ir_type.kind == .F32x2 {
    return 8, 8, true, "";
  }
  if field_ir_type.kind == .F32x3 {
    return 16, 16, true, "";
  }
  if field_ir_type.kind == .F32x4 {
    return 16, 16, true, "";
  }

  return 0, 0, false, "field type is not currently supported for uniform layout validation";
}

ir_validate_parameter_block_layout :: (arg_name: string, struct_type: *Type_Info_Struct, state: *IR_Lowering_State, node: *Code_Node = null) -> bool {
  if !struct_type || !state return true;
  // Ignore unions for now; we only validate standard struct parameter blocks.
  if struct_type.textual_flags & .UNION return true;

  expected_offset: s64 = 0;
  mismatch_count := 0;
  skipped_count := 0;
  sb: String_Builder;

  for struct_type.members {
    member := it;
    if member.flags & .CONSTANT continue;
    if member.offset_in_bytes < 0 continue;

    field_align, field_size, field_ok, _ := ir_uniform_field_layout_for_type(member.type);
    if !field_ok {
      skipped_count += 1;
      continue;
    }
    expected_offset = ir_align_up_s64(expected_offset, field_align);
    actual_offset := member.offset_in_bytes;
    if actual_offset != expected_offset {
      mismatch_count += 1;
      a(*sb, "  field '%': expected offset %, got % (align %, size %).",
        member.name, expected_offset, actual_offset, field_align, field_size);
      if field_align >= 16 {
        a(*sb, "    hint: add explicit padding before '%' (or use `#align 16`) so this field lands on a 16-byte boundary.", member.name);
      } else if field_align == 8 {
        a(*sb, "    hint: consider field reordering or explicit padding before '%'.", member.name);
      }
    }
    expected_offset += field_size;
  }

  if mismatch_count == 0 return true;
  message := tprint("IR lowering: parameter block layout mismatch for argument '%' (struct '%').\nExpected GPU-side offsets do not match Jai CPU layout.\n%\nhint: reorder fields and/or add explicit pad fields; `#align` can help enforce boundaries.", arg_name, struct_type.name, builder_to_string(*sb));
  if skipped_count > 0 {
    message = tprint("%\nnote: skipped % unsupported field(s) during validation.", message, skipped_count);
  }
  ir_set_diagnostic(state, message, node);
  return false;
}

ir_collect_nested_structs_for_shader_arg_type :: (type: *Type_Info, extra_structs: *[..] IR_Struct) -> bool {
  if !type return false;
  if type.type == .ARRAY {
    arr := cast(*Type_Info_Array) type;
    if !arr.element_type return false;
    return ir_collect_nested_structs_for_shader_arg_type(arr.element_type, extra_structs);
  }
  if type.type == .POINTER {
    ptr := cast(*Type_Info_Pointer) type;
    if !ptr.pointer_to return false;
    if ptr.pointer_to.type == .STRUCT {
      st := cast(*Type_Info_Struct) ptr.pointer_to;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(st));
      if !ir_is_builtin_shader_type_name(struct_name) {
        lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ptr.pointer_to, extra_structs);
        if !lowered_ok return false;
        ir_add_struct_unique_by_name(extra_structs, lowered_struct);
      }
      return true;
    }
    _, elem_ok := ir_type_to_shader_name(ptr.pointer_to);
    return elem_ok;
  }
  if type.type == .STRUCT {
    st := cast(*Type_Info_Struct) type;
    struct_name := jai_to_hlsl_type_name(get_struct_type_name(st));
    if !ir_is_builtin_shader_type_name(struct_name) {
      lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, type, extra_structs);
      if !lowered_ok return false;
      ir_add_struct_unique_by_name(extra_structs, lowered_struct);
    }
    return true;
  }
  _, type_ok := ir_type_to_shader_name(type);
  return type_ok;
}

op_to_text :: (op: Operator_Type) -> (string, bool) {
  if op == {
    case cast(Operator_Type) #char "="; return "=", true;
    case cast(Operator_Type) #char "<"; return "<", true;
    case cast(Operator_Type) #char "?"; return "?", true;
    case cast(Operator_Type) #char ">"; return ">", true;
    case cast(Operator_Type) #char "!"; return "!", true;
    case cast(Operator_Type) #char "+"; return "+", true;
    case cast(Operator_Type) #char "-"; return "-", true;
    case cast(Operator_Type) #char "*"; return "*", true;
    case cast(Operator_Type) #char "/"; return "/", true;
    case cast(Operator_Type) #char "%"; return "%", true;
    case cast(Operator_Type) #char "&"; return "&", true;
    case cast(Operator_Type) #char "|"; return "|", true;
    case cast(Operator_Type) #char "^"; return "^", true;
    case cast(Operator_Type) #char "~"; return "~", true;
    case cast(Operator_Type) #char "."; return ".", true;
  }

  if op == {
    case .PLUS_ASSIGN; return "+=", true;
    case .MINUS_ASSIGN; return "-=", true;
    case .TIMES_ASSIGN; return "*=", true;
    case .DIV_ASSIGN; return "/=", true;
    case .MOD_ASSIGN; return "%=", true;
    case .IS_EQUAL; return "==", true;
    case .IS_NOT_EQUAL; return "!=", true;
    case .LOGICAL_AND; return "&&", true;
    case .LOGICAL_OR; return "||", true;
    case .LESS_OR_EQUAL; return "<=", true;
    case .GREATER_OR_EQUAL; return ">=", true;
    case .SHIFT_LEFT; return "<<", true;
    case .SHIFT_RIGHT; return ">>", true;
    case .ARRAY_SUBSCRIPT; return "[]", true;
    case; return "", false;
  }
}

ir_binary_operator_to_slang :: (op: Operator_Type) -> (string, bool) {
  if op == {
    case .PLUS_ASSIGN; return "+=", true;
    case .MINUS_ASSIGN; return "-=", true;
    case .TIMES_ASSIGN; return "*=", true;
    case .DIV_ASSIGN; return "/=", true;
    case .MOD_ASSIGN; return "%=", true;
    case .SHIFT_LEFT; return "<<", true;
    case .SHIFT_RIGHT; return ">>", true;
    case .SHIFT_LEFT_ASSIGN; return "<<=", true;
    case .SHIFT_RIGHT_ASSIGN; return ">>=", true;
    case .BITWISE_AND_ASSIGN; return "&=", true;
    case .BITWISE_OR_ASSIGN; return "|=", true;
    case .BITWISE_XOR_ASSIGN; return "^=", true;
  }
  mapped, mapped_ok := op_to_text(op);
  return mapped, mapped_ok;
}

ir_unary_op_from_compiler_operator :: (op: Operator_Type) -> (IR_Unary_Op, bool) {
  if op == cast(Operator_Type) #char "+" return .PLUS, true;
  if op == cast(Operator_Type) #char "-" return .NEGATE, true;
  if op == cast(Operator_Type) #char "!" return .LOGICAL_NOT, true;
  if op == cast(Operator_Type) #char "~" return .BIT_NOT, true;
  if op == cast(Operator_Type) #char "*" return .ADDRESS_OF, true;
  if op == .POINTER_DEREFERENCE return .ADDRESS_OF, true;
  if op == .POSTFIX_DEREFERENCE return .DEREF, true;
  return .UNKNOWN, false;
}

ir_unary_op_to_slang :: (op: IR_Unary_Op) -> (string, bool) {
  if op == .PLUS return "+", true;
  if op == .NEGATE return "-", true;
  if op == .LOGICAL_NOT return "!", true;
  if op == .BIT_NOT return "~", true;
  if op == .ADDRESS_OF return "*", true;
  if op == .DEREF return ".*", true;
  return "", false;
}

ir_expr_binary_op_text :: (expr: *IR_Expr) -> (string, bool) {
  if !expr return "", false;
  mapped, mapped_ok := ir_binary_operator_to_slang(expr.binary_operator_type);
  if !mapped_ok return "", false;
  return mapped, true;
}

ir_expr_unary_op_text :: (expr: *IR_Expr) -> (string, bool) {
  if !expr return "", false;
  mapped, mapped_ok := ir_unary_op_to_slang(expr.unary_op);
  if !mapped_ok return "", false;
  return mapped, true;
}

ir_stmt_binary_op_text :: (stmt: *IR_Stmt) -> (string, bool) {
  if !stmt return "", false;
  mapped, mapped_ok := ir_binary_operator_to_slang(stmt.binary_operator_type);
  if !mapped_ok return "", false;
  return mapped, true;
}

compute_builtin_note_for_member :: (member: *Type_Info_Struct_Member) -> (string, bool) {
  trim_ascii_whitespace_local :: (in: string) -> string {
    if in.count == 0 return in;

    start := cast(s64) 0;
    while start < in.count {
      ch := in[start];
      if ch != #char " " && ch != #char "\t" && ch != #char "\n" && ch != #char "\r" break;
      start += 1;
    }

    if start >= in.count {
      out: string;
      out.data = in.data + in.count;
      out.count = 0;
      return out;
    }

    end := in.count - 1;
    while end >= start {
      ch := in[end];
      if ch != #char " " && ch != #char "\t" && ch != #char "\n" && ch != #char "\r" break;
      end -= 1;
    }

    out: string;
    out.data = in.data + start;
    out.count = end - start + 1;
    return out;
  }

  normalize_builtin_note_text :: (text: string) -> string {
    out := trim_ascii_whitespace_local(text);
    if out.count == 0 return out;
    if out[0] == #char "@" {
      trimmed: string;
      trimmed.data = out.data + 1;
      trimmed.count = out.count - 1;
      out = trim_ascii_whitespace_local(trimmed);
    }
    if out.count > 2 && out[out.count-1] == #char ")" {
      open_index := find_index_from_left(out, "(");
      if open_index != -1 {
        fn_name: string;
        fn_name.data = out.data;
        fn_name.count = open_index;
        out = trim_ascii_whitespace_local(fn_name);
      }
    }
    return out;
  }

  builtin_name_from_note_text :: (text: string) -> (string, bool) {
    note := normalize_builtin_note_text(text);
    if note == "thread_position_in_grid" return "thread_position_in_grid", true;
    if note == "thread_position_in_threadgroup" return "thread_position_in_threadgroup", true;
    if note == "threadgroup_position_in_grid" return "threadgroup_position_in_grid", true;
    if note == "thread_index_in_threadgroup" return "thread_index_in_threadgroup", true;
    return "", false;
  }

  for member.notes {
    builtin_name, builtin_found := builtin_name_from_note_text(it);
    if builtin_found return builtin_name, true;
  }
  return "", false;
}

ir_expr_new :: (kind: IR_Expr_Kind, node: *Code_Node = null) -> *IR_Expr {
  e := New(IR_Expr);
  e.kind = kind;
  e.origin_node = node;
  e.builtin_ref.component = -1;
  if node && node.type {
    lowered_type, lowered_ok := ir_type_from_type_info(node.type);
    if lowered_ok e.result_type = lowered_type;
  }
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

ir_extract_ifx_branch_expr :: (branch: *Code_Block, branch_label: string, state: *IR_Lowering_State, root_node: *Code_Node) -> (*Code_Node, bool) {
  assert(root_node != null);
  if !branch {
    ir_set_diagnostic(state, tprint("IR lowering: ifx is missing '%' branch.", branch_label), root_node);
    return null, false;
  }
  if branch.statements.count != 1 {
    ir_set_diagnostic(state, tprint("IR lowering: ifx '%' branch must contain exactly one return.", branch_label), root_node);
    return null, false;
  }
  branch_stmt := branch.statements[0];
  if !branch_stmt {
    ir_set_diagnostic(state, tprint("IR lowering: ifx '%' branch is empty.", branch_label), root_node);
    return null, false;
  }
  if branch_stmt.kind == .RETURN {
    ret := cast(*Code_Return) branch_stmt;
    if ret.arguments_sorted.count != 1 {
      ir_set_diagnostic(state, tprint("IR lowering: ifx '%' branch must return exactly one value.", branch_label), branch_stmt);
      return null, false;
    }
    return ret.arguments_sorted[0], true;
  }
  // Some ifx forms keep branch payloads as direct expression nodes.
  return branch_stmt, true;
}

ir_lower_expr :: (node: *Code_Node,
                  using ctx: IR_Lowering_Context,
                  active_usings: [] IR_Using_Source = .[],
                  active_aliases: [] IR_Decl_Alias = .[],
                  expected_type: *Type_Info = null) -> (*IR_Expr, bool) {
  assert(node != null);

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
          inlined, inlined_ok := ir_lower_expr(ident.resolved_declaration.expression, ctx, active_usings, active_aliases, expected_type);
          if inlined_ok return inlined, true;
        }

      }

      if ident.name == "input" || ident.name == "o" || ident.name == "un" {
        out := ir_expr_new(.IDENT, node);
        out.text = ident.name;
        return out, true;
      }

      if ir_name_in_list(input_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "input";
        out.text = ident.name;
        out.resolved_field_index = ir_find_field_index_in_struct(input_struct, ident.name);
        builtin_ref, builtin_ok := ir_lookup_input_builtin_ref(state, ident.name);
        if builtin_ok out.builtin_ref = builtin_ref;
        return out, true;
      }

      if ir_name_in_list(output_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "o";
        out.text = ident.name;
        out.resolved_field_index = ir_find_field_index_in_struct(output_struct, ident.name);
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
          lowered_base, ok := ir_lower_expr(using_source_node, ctx, active_usings, active_aliases);
          if !ok return null, false;
          base = lowered_base;
        }
        out := ir_expr_new(.MEMBER);
        out.left = base;
        out.text = ident.name;
        out.member_access = ir_member_access_kind_from_name(ident.name);
        if base && base.builtin_ref.kind != .NONE {
          out.builtin_ref = base.builtin_ref;
          component, component_ok := ir_vector_component_index(ident.name);
          if component_ok out.builtin_ref.component = component;
        }
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
          lowered_type_name, lowered_type_ok := ir_type_to_shader_name(lit.type);
          if lowered_type_ok constructor_name = lowered_type_name;
        }
        if constructor_name.count == 0 && expected_type {
          expected_name, expected_ok := ir_type_to_shader_name(expected_type);
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

        out := ir_expr_new(.CONSTRUCTOR, node);
        if out.result_type.kind == .UNKNOWN {
          ctor_type := lit.type;
          if !ctor_type ctor_type = expected_type;
          if ctor_type {
            lowered_ctor_type, lowered_ctor_ok := ir_type_from_type_info(ctor_type);
            if lowered_ctor_ok out.result_type = lowered_ctor_type;
          }
        }
        out.text = constructor_name;
        if out.result_type.kind == .UNKNOWN {
          if constructor_name == "float" {
            out.result_type.kind = .F32;
          } else if constructor_name == "float2" {
            out.result_type.kind = .F32x2;
          } else if constructor_name == "float3" {
            out.result_type.kind = .F32x3;
          } else if constructor_name == "float4" {
            out.result_type.kind = .F32x4;
          } else if constructor_name == "float2x2" {
            out.result_type.kind = .F32x2x2;
          } else if constructor_name == "float3x3" {
            out.result_type.kind = .F32x3x3;
          } else if constructor_name == "float4x4" {
            out.result_type.kind = .F32x4x4;
          }
          if out.result_type.kind != .UNKNOWN {
            out.result_type.display_name = constructor_name;
          } else {
            out.result_type.kind = .STRUCT;
            out.result_type.struct_name = constructor_name;
            out.result_type.display_name = constructor_name;
          }
        }
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

              lowered_right, right_ok := ir_lower_expr(named.right, ctx, active_usings, active_aliases, arg_expected_type);
              if !right_ok return null, false;
              if ir_is_builtin_shader_type_name(constructor_name) {
                // Builtin vector/matrix constructors expect positional args only.
                array_add(*out.args, lowered_right);
                continue;
              }

              lowered_left, left_ok := ir_lower_expr(named.left, ctx, active_usings, active_aliases);
              if !left_ok return null, false;
              arg := ir_expr_new(.BINARY);
              arg.binary_operator_type = cast(Operator_Type) #char "=";
              arg.left = lowered_left;
              arg.right = lowered_right;
              array_add(*out.args, arg);
              continue;
            }
          }

          if struct_type_info && positional_index < struct_type_info.members.count {
            arg_expected_type = struct_type_info.members[positional_index].type;
          }
          arg, ok := ir_lower_expr(source_arg, ctx, active_usings, active_aliases, arg_expected_type);
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
          arg, ok := ir_lower_expr(it, ctx, active_usings, active_aliases, member_expected_type);
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

      if un.operator_type == cast(Operator_Type) #char "." {
        // Distinguish enum shorthand `.Value` from postfix dereference `value.*`.
        if un.subexpression && un.subexpression.kind == .IDENT {
          ident := cast(*Code_Ident) un.subexpression;
          if ident.resolved_declaration && ir_decl_is_compile_constant(ident.resolved_declaration) {
            lowered_enum, lowered_enum_ok := ir_lower_expr(un.subexpression, ctx, active_usings, active_aliases);
            return lowered_enum, lowered_enum_ok;
          }
        }
        inner, ok := ir_lower_expr(un.subexpression, ctx, active_usings, active_aliases);
        if !ok return null, false;
        out := ir_expr_new(.UNARY);
        out.unary_op = .DEREF;
        out.left = inner;
        return out, true;
      }

      inner, ok := ir_lower_expr(un.subexpression, ctx, active_usings, active_aliases);
      if !ok return null, false;
      out := ir_expr_new(.UNARY);
      unary_op, unary_op_ok := ir_unary_op_from_compiler_operator(un.operator_type);
      if !unary_op_ok {
        ir_set_diagnostic(state, tprint("IR lowering: unsupported unary operator (%)", un.operator_type), node);
        return null, false;
      }
      out.unary_op = unary_op;
      out.left = inner;
      return out, true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      if bn.operator_type == cast(Operator_Type) #char "." &&
         bn.left && bn.left.kind == .IDENT &&
         bn.right && bn.right.kind == .IDENT {
        left_ident := cast(*Code_Ident) bn.left;
        right_ident := cast(*Code_Ident) bn.right;
        // Support enum type member constants like `Brush_Type.RAISE` by
        // lowering the RHS compile-time constant directly.
        if right_ident.resolved_declaration && ir_decl_is_compile_constant(right_ident.resolved_declaration) &&
           left_ident.resolved_declaration && left_ident.resolved_declaration.expression &&
           (left_ident.resolved_declaration.expression.kind == .TYPE_DEFINITION ||
            left_ident.resolved_declaration.expression.kind == .ENUM) {
          lowered_const, lowered_const_ok := ir_lower_expr(bn.right, ctx, active_usings, active_aliases, expected_type);
          if lowered_const_ok return lowered_const, true;
        }
      }

      if bn.operator_type == cast(Operator_Type) #char "." &&
         bn.left && bn.left.kind == .IDENT &&
         bn.right && bn.right.kind == .IDENT {
        left_ident := cast(*Code_Ident) bn.left;
        right_ident := cast(*Code_Ident) bn.right;
        if left_ident.resolved_declaration {
          member_alias, member_aliased := ir_lookup_decl_member_alias(active_aliases, left_ident.resolved_declaration, right_ident.name);
          if member_aliased {
            out := ir_expr_new(.IDENT);
            out.text = member_alias;
            return out, true;
          }
        }
      }

      left, left_ok := ir_lower_expr(bn.left, ctx, active_usings, active_aliases);
      if !left_ok return null, false;

      right_expected_type: *Type_Info = null;
      if bn.right && bn.right.kind == .LITERAL && bn.left {
        right_lit := cast(*Code_Literal) bn.right;
        // Anonymous struct/vector literals like `.{...}` in binary expressions need
        // expected-type propagation from the opposite operand for constructor inference.
        if right_lit.value_type == .STRUCT {
          has_explicit_ctor_type := false;
          if right_lit.struct_literal_info.type_expression && right_lit.struct_literal_info.type_expression.type_valued_expression {
            has_explicit_ctor_type = true;
          }
          if !has_explicit_ctor_type right_expected_type = bn.left.type;
        }
      }

      if bn.operator_type == .ARRAY_SUBSCRIPT {
        right, right_ok := ir_lower_expr(bn.right, ctx, active_usings, active_aliases);
        if !right_ok return null, false;
        out := ir_expr_new(.SUBSCRIPT);
        out.left = left;
        out.right = right;
        return out, true;
      }

      if bn.operator_type == cast(Operator_Type) #char "*" {
        left_type := ifx bn.left then bn.left.type else null;
        right_type := ifx bn.right then bn.right.type else null;
        left_is_matrix := ir_type_is_matrix_like(left_type);
        right_is_matrix := ir_type_is_matrix_like(right_type);
        if left_is_matrix || right_is_matrix {
          right, right_ok := ir_lower_expr(bn.right, ctx, active_usings, active_aliases, right_expected_type);
          if !right_ok return null, false;
          out := ir_expr_new(.CALL);
          out.left = ir_expr_new(.IDENT);
          out.left.text = "mul";
          out.call_target_kind = .BUILTIN;
          out.call_builtin_kind = .MUL;
          if left_is_matrix && !right_is_matrix {
            // Jai's matrix*vector convention matches Slang/HLSL mul(vector, matrix).
            array_add(*out.args, right, left);
          } else {
            array_add(*out.args, left, right);
          }
          return out, true;
        }
      }
      if bn.operator_type == cast(Operator_Type) #char "." {
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
          out.member_access = ir_member_access_kind_from_name(right_ident.name);
          if left_for_member && left_for_member.builtin_ref.kind != .NONE {
            out.builtin_ref = left_for_member.builtin_ref;
            component, component_ok := ir_vector_component_index(right_ident.name);
            if component_ok out.builtin_ref.component = component;
          } else if left_for_member &&
                    left_for_member.kind == .IDENT &&
                    left_for_member.text == "input" {
            builtin_ref, builtin_ok := ir_lookup_input_builtin_ref(state, right_ident.name);
            if builtin_ok out.builtin_ref = builtin_ref;
          }
          return out, true;
        }
        ir_set_diagnostic(state, "IR lowering: member access requires identifier on right-hand side", node);
        return null, false;
      }

      right, right_ok := ir_lower_expr(bn.right, ctx, active_usings, active_aliases, right_expected_type);
      if !right_ok return null, false;
      out := ir_expr_new(.BINARY);
      out.binary_operator_type = bn.operator_type;
      out.left = left;
      out.right = right;
      return out, true;
    }

    case .IF; {
      if_node := cast(*Code_If) node;
      if if_node.if_flags & .IS_SWITCH_STATEMENT {
        ir_set_diagnostic(state, "IR lowering: switch statement cannot be used as an expression", node);
        return null, false;
      }

      cond, cond_ok := ir_lower_expr(if_node.condition, ctx, active_usings, active_aliases);
      if !cond_ok return null, false;

      then_node, then_node_ok := ir_extract_ifx_branch_expr(if_node.then_block, "then", state, node);
      if !then_node_ok return null, false;
      else_node, else_node_ok := ir_extract_ifx_branch_expr(if_node.else_block, "else", state, node);
      if !else_node_ok return null, false;

      then_expr, then_ok := ir_lower_expr(then_node, ctx, active_usings, active_aliases, expected_type);
      if !then_ok return null, false;

      else_expected_type := expected_type;
      if !else_expected_type else_expected_type = then_node.type;
      else_expr, else_ok := ir_lower_expr(else_node, ctx, active_usings, active_aliases, else_expected_type);
      if !else_ok return null, false;

      out := ir_expr_new(.SELECT, node);
      out.left = cond;
      out.right = then_expr;
      array_add(*out.args, else_expr);
      result_type := expected_type;
      if !result_type result_type = node.type;
      if result_type {
        result_type_name, result_type_ok := ir_type_to_shader_name(result_type);
        if result_type_ok out.text = result_type_name;
      }
      return out, true;
    }

    case .CAST; {
      cast_node := cast(*Code_Cast) node;
      if !cast_node.target_type {
        // Some implicit conversion casts arrive without an explicit target_type node.
        // In that case, recover the destination type from the cast expression type.
        fallback_type := node.type;
        if !fallback_type fallback_type = expected_type;
        inner, inner_ok := ir_lower_expr(cast_node.expression, ctx, active_usings, active_aliases, fallback_type);
        if !inner_ok return null, false;
        if !fallback_type return inner, true;

        fallback_type_name, fallback_ok := ir_type_to_shader_name(fallback_type);
        if !fallback_ok {
          ir_set_diagnostic(state, "IR lowering: cast is missing target type and fallback type is unsupported", node);
          return null, false;
        }
        out := ir_expr_new(.CAST, node);
        out.text = fallback_type_name;
        out.left = inner;
        return out, true;
      }
      target_type_info := cast_node.target_type.result;
      type_name := "";
      if target_type_info {
        t, ok := ir_type_to_shader_name(target_type_info);
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

      inner, ok := ir_lower_expr(cast_node.expression, ctx, active_usings, active_aliases);
      if !ok return null, false;
      out := ir_expr_new(.CAST, node);
      out.text = type_name;
      out.left = inner;
      return out, true;
    }

    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      callee, callee_ok := ir_lower_expr(pc.procedure_expression, ctx, active_usings, active_aliases);
      if !callee_ok return null, false;
      out := ir_expr_new(.CALL);
      out.left = callee;
      for pc.arguments_sorted {
        arg, ok := ir_lower_expr(it, ctx, active_usings, active_aliases);
        if !ok return null, false;
        array_add(*out.args, arg);
      }
      resolved_name, resolved_ok := ir_resolve_call_target_name_from_code_node(pc.resolved_procedure_expression);
      if !resolved_ok resolved_name, resolved_ok = ir_resolve_call_target_name_from_code_node(pc.procedure_expression);
      if resolved_ok {
        out.call_resolved_name = resolved_name;
        resolved_builtin := ir_builtin_call_kind_from_callee(resolved_name);
        if resolved_builtin != .NONE {
          out.call_target_kind = .BUILTIN;
          out.call_builtin_kind = resolved_builtin;
        } else {
          out.call_target_kind = .HELPER;
          out.call_builtin_kind = .NONE;
        }
      } else {
        out.call_target_kind, out.call_builtin_kind = ir_classify_call_target(callee);
      }
      return out, true;
    }

    case .EXTRACT; {
      ex := cast(*Code_Extract) node;
      if !ex.from {
        ir_set_diagnostic(state, "IR lowering: extract expression missing source", node);
        return null, false;
      }

      if ex.from.kind == .COMMA_SEPARATED_ARGUMENTS {
        comma_args := cast(*Code_Comma_Separated_Arguments) ex.from;
        if ex.index < 0 || ex.index >= comma_args.arguments.count {
          ir_set_diagnostic(state, "IR lowering: extract index out of range for comma-separated arguments", node);
          return null, false;
        }
        target := comma_args.arguments[ex.index].node;
        if !target {
          ir_set_diagnostic(state, "IR lowering: extract target argument is missing", node);
          return null, false;
        }
        extracted_expr, extracted_ok := ir_lower_expr(target, ctx, active_usings, active_aliases, expected_type);
        return extracted_expr, extracted_ok;
      }

      from_expr, from_ok := ir_lower_expr(ex.from, ctx, active_usings, active_aliases);
      if !from_ok return null, false;

      member_name := "";
      if ex.from.type && ex.from.type.type == .STRUCT {
        st := cast(*Type_Info_Struct) ex.from.type;
        if ex.index >= 0 && ex.index < st.members.count {
          member_name = st.members[ex.index].name;
        }
      }
      if member_name.count == 0 {
        member_name = tprint("_%", ex.index);
      }

      out := ir_expr_new(.MEMBER);
      out.left = from_expr;
      out.text = member_name;
      return out, true;
    }
  }

  ir_set_diagnostic(state, tprint("IR lowering: unsupported expression node kind (%)", node.kind), node);
  return null, false;
}

ir_parse_float_matrix_dims :: (type_name: string) -> (cols: s64, rows: s64, ok: bool) {
  if !begins_with(type_name, "float") return 0, 0, false;
  dims: string = { type_name.count - 5, type_name.data + 5 };
  if dims.count < 3 return 0, 0, false;

  x_index := cast(s64) -1;
  for i: 0..dims.count-1 {
    if dims[i] == #char "x" {
      x_index = i;
      break;
    }
  }
  if x_index <= 0 || x_index >= dims.count-1 return 0, 0, false;

  cols_text: string = { x_index, dims.data };
  rows_text: string = { dims.count - x_index - 1, dims.data + x_index + 1 };

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
      if expr.unary_op == .DEREF return tprint("(%).*", inner), true;
      op, op_ok := ir_expr_unary_op_text(expr);
      if !op_ok return "", false;
      return tprint("%%", op, inner), true;
    }

    case .BINARY; {
      left, left_ok := ir_expr_to_slang_from_ir(expr.left);
      if !left_ok return "", false;
      right, right_ok := ir_expr_to_slang_from_ir(expr.right);
      if !right_ok return "", false;
      op, op_ok := ir_expr_binary_op_text(expr);
      if !op_ok return "", false;
      return tprint("(% % %)", left, op, right), true;
    }

    case .SELECT; {
      if !expr.left || !expr.right || expr.args.count != 1 return "", false;
      cond, cond_ok := ir_expr_to_slang_from_ir(expr.left);
      if !cond_ok return "", false;
      then_expr, then_ok := ir_expr_to_slang_from_ir(expr.right);
      if !then_ok return "", false;
      else_expr, else_ok := ir_expr_to_slang_from_ir(expr.args[0]);
      if !else_ok return "", false;
      return tprint("((%) ? (%) : (%))", cond, then_expr, else_expr), true;
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
      if expr.call_builtin_kind == .MIX callee = "lerp";
      if expr.call_builtin_kind == .MOD callee = "fmod";
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
  text, ok := ir_expr_to_slang_from_ir(expr);
  if !ok return "", false;

  need_parens := false;
  if expr.kind == .UNARY need_parens = true;
  if expr.kind == .BINARY need_parens = true;
  if expr.kind == .SELECT need_parens = true;
  if expr.kind == .CAST need_parens = true;
  if expr.kind == .CONSTRUCTOR need_parens = true;

  if need_parens return tprint("(%)", text), true;
  return text, true;
}

ir_expr_to_slang :: (node: *Code_Node,
                     using ctx: IR_Lowering_Context,
                     active_usings: [] IR_Using_Source = .[],
                     active_aliases: [] IR_Decl_Alias = .[]) -> (string, bool) {
  expr, ok := ir_lower_expr(node, ctx, active_usings, active_aliases);
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

ir_builtin_kind_from_semantic :: (semantic: string) -> (IR_Expr_Builtin_Kind, bool) {
  if semantic == "SV_DispatchThreadID" return .DISPATCH_THREAD_ID, true;
  if semantic == "SV_GroupThreadID" return .GROUP_THREAD_ID, true;
  if semantic == "SV_GroupID" return .GROUP_ID, true;
  if semantic == "SV_GroupIndex" return .GROUP_INDEX, true;
  return .NONE, false;
}

ir_lookup_input_builtin_ref :: (state: *IR_Lowering_State, field_name: string) -> (IR_Builtin_Ref, bool) {
  if !state return .{}, false;
  for state.input_builtin_fields {
    if it.field_name == field_name return it.builtin_ref, true;
  }
  return .{}, false;
}

ir_vector_component_index :: (field_name: string) -> (s32, bool) {
  if field_name == "x" return 0, true;
  if field_name == "y" return 1, true;
  if field_name == "z" return 2, true;
  if field_name == "w" return 3, true;
  return -1, false;
}

ir_member_access_kind_from_name :: (field_name: string) -> IR_Member_Access_Kind {
  if field_name == "x" return .COMPONENT_X;
  if field_name == "y" return .COMPONENT_Y;
  if field_name == "z" return .COMPONENT_Z;
  if field_name == "w" return .COMPONENT_W;
  if field_name == "xy" return .SWIZZLE_XY;
  if field_name == "xyz" return .SWIZZLE_XYZ;
  return .NONE;
}


ir_callee_matches_builtin :: (callee: string, builtin: string) -> bool {
  if callee == builtin return true;
  if callee.count <= builtin.count return false;
  if !begins_with(callee, builtin) return false;
  next := callee[builtin.count];
  is_digit := next >= #char "0" && next <= #char "9";
  is_alpha := (next >= #char "a" && next <= #char "z") || (next >= #char "A" && next <= #char "Z");
  return !is_alpha || is_digit;
}

ir_builtin_call_kind_from_callee :: (callee: string) -> IR_Call_Builtin_Kind {
  name := ir_canonical_callee_name(callee);
  if ir_callee_matches_builtin(name, "sample_2d_lod") return .SAMPLE_2D_LOD;
  if ir_callee_matches_builtin(name, "sample_cube_lod") return .SAMPLE_CUBE_LOD;
  if ir_callee_matches_builtin(name, "sample_2d") return .SAMPLE_2D;
  if ir_callee_matches_builtin(name, "sample_cube") return .SAMPLE_CUBE;
  if ir_callee_matches_builtin(name, "sample_3d") return .SAMPLE_3D;
  if ir_callee_matches_builtin(name, "write_2d") return .WRITE_2D;
  if ir_callee_matches_builtin(name, "write_3d") return .WRITE_3D;
  if ir_callee_matches_builtin(name, "discard") return .DISCARD;
  if ir_callee_matches_builtin(name, "task_set_mesh_groups") return .TASK_SET_MESH_GROUPS;
  if ir_callee_matches_builtin(name, "task_group_id_x") return .TASK_GROUP_ID_X;
  if ir_callee_matches_builtin(name, "task_payload_ptr") return .TASK_PAYLOAD_PTR;
  if ir_callee_matches_builtin(name, "mesh_set_max_output_counts") return .MESH_SET_MAX_OUTPUT_COUNTS;
  if ir_callee_matches_builtin(name, "mesh_set_output_counts") return .MESH_SET_OUTPUT_COUNTS;
  if ir_callee_matches_builtin(name, "mesh_group_id_x") return .MESH_GROUP_ID_X;
  if ir_callee_matches_builtin(name, "mesh_group_id_y") return .MESH_GROUP_ID_Y;
  if ir_callee_matches_builtin(name, "mesh_payload_ptr") return .MESH_PAYLOAD_PTR;
  if ir_callee_matches_builtin(name, "mesh_set_vertex") return .MESH_SET_VERTEX;
  if ir_callee_matches_builtin(name, "mesh_set_triangle") return .MESH_SET_TRIANGLE;
  if ir_callee_matches_builtin(name, "saturate") return .SATURATE;
  if ir_callee_matches_builtin(name, "mix") return .MIX;
  if ir_callee_matches_builtin(name, "lerp") return .LERP;
  if ir_callee_matches_builtin(name, "reflect") return .REFLECT;
  if name == "clamp" return .CLAMP;
  if name == "step" return .STEP;
  if name == "pow" return .POW;
  if name == "smoothstep" return .SMOOTHSTEP;
  if name == "mod" return .MOD;
  if name == "fmod_cycling" return .FMOD_CYCLING;
  if name == "mul" return .MUL;
  if name == "floor" return .FLOOR;
  if name == "min" return .MIN;
  if name == "max" return .MAX;
  if name == "abs" return .ABS;
  if name == "sqrt" return .SQRT;
  if name == "exp" return .EXP;
  if name == "sin" return .SIN;
  if name == "cos" return .COS;
  if name == "fract" return .FRACT;
  if name == "length" return .LENGTH;
  if name == "normalize" return .NORMALIZE;
  if name == "radians" return .RADIANS;
  if name == "degrees" return .DEGREES;
  if name == "atomic_add_u32" return .ATOMIC_ADD_U32;
  if name == "atomic_sub_u32" return .ATOMIC_SUB_U32;
  if name == "atomic_exchange_u32" return .ATOMIC_EXCHANGE_U32;
  if name == "atomic_compare_exchange_u32" return .ATOMIC_COMPARE_EXCHANGE_U32;
  if name == "atomic_min_u32" return .ATOMIC_MIN_U32;
  if name == "atomic_max_u32" return .ATOMIC_MAX_U32;
  return .NONE;
}

ir_classify_call_target :: (callee_expr: *IR_Expr) -> (IR_Call_Target_Kind, IR_Call_Builtin_Kind) {
  if !callee_expr return .UNKNOWN, .NONE;
  if callee_expr.kind == .IDENT || callee_expr.kind == .MEMBER {
    builtin := ir_builtin_call_kind_from_callee(callee_expr.text);
    if builtin != .NONE return .BUILTIN, builtin;
    return .HELPER, .NONE;
  }
  return .UNKNOWN, .NONE;
}

ir_resolve_call_target_name_from_code_node :: (node: *Code_Node, depth: s64 = 0) -> (string, bool) {
  if !node || depth > 8 return "", false;

  if node.kind == .PROCEDURE_HEADER {
    header := cast(*Code_Procedure_Header) node;
    if header.name.count == 0 return "", false;
    return ir_canonical_callee_name(header.name), true;
  }

  if node.kind == .PROCEDURE_BODY {
    body := cast(*Code_Procedure_Body) node;
    if body && body.header && body.header.name.count != 0 return ir_canonical_callee_name(body.header.name), true;
    return "", false;
  }

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    if !decl.expression return "", false;
    nested_name, nested_ok := ir_resolve_call_target_name_from_code_node(decl.expression, depth + 1);
    return nested_name, nested_ok;
  }

  if node.kind == .IDENT {
    ident := cast(*Code_Ident) node;
    if ident.resolved_declaration {
      resolved_name, resolved_ok := ir_resolve_call_target_name_from_code_node(cast(*Code_Node) ident.resolved_declaration, depth + 1);
      if resolved_ok return resolved_name, true;
    }
    if ident.name.count == 0 return "", false;
    return ir_canonical_callee_name(ident.name), true;
  }

  if node.kind == .CAST {
    cast_node := cast(*Code_Cast) node;
    if !cast_node.expression return "", false;
    nested_name, nested_ok := ir_resolve_call_target_name_from_code_node(cast_node.expression, depth + 1);
    return nested_name, nested_ok;
  }

  return "", false;
}

ir_lower_compute_input_struct :: (name: string, type: *Type_Info) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;
  if !type || type.type != .STRUCT return out, false;

  st := cast(*Type_Info_Struct) type;
  out.origin = st;
  for *st.members {
    ir_type, ir_type_ok := ir_type_from_type_info(it.type);
    if !ir_type_ok return out, false;
    builtin_name, found := compute_builtin_note_for_member(it);
    if !found return out, false;
    semantic, sem_ok := ir_compute_builtin_to_semantic(builtin_name);
    if !sem_ok return out, false;
    array_add(*out.fields, .{
      name = it.name,
      type = ir_type,
      semantic = semantic,
      source_member_index = cast(s32) it_index,
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
  if ir_is_builtin_shader_type_name(struct_name) return true;
  lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ti, out_extra_structs);
  if !lowered_ok {
    ir_set_diagnostic(state, tprint("could not lower declared struct type '%'", struct_name), loc_node);
    return false;
  }
  ir_add_struct_unique_by_name(out_extra_structs, lowered_struct);
  return true;
}

ir_collect_payload_structs_in_expr :: (node: *Code_Node, out_extra_structs: *[..] IR_Struct, state: *IR_Lowering_State) -> bool {
  if !node return true;

  if node.kind == .PROCEDURE_CALL {
    pc := cast(*Code_Procedure_Call) node;
    callee_name, callee_ok := ir_resolve_call_target_name_from_code_node(pc.procedure_expression);
    if callee_ok && (ir_callee_matches_builtin(callee_name, "task_payload_ptr") || ir_callee_matches_builtin(callee_name, "mesh_payload_ptr")) {
      if !ir_collect_compute_declared_struct_type(node.type, state, node, out_extra_structs) return false;
    }
    if pc.procedure_expression && !ir_collect_payload_structs_in_expr(pc.procedure_expression, out_extra_structs, state) return false;
    for pc.arguments_sorted if !ir_collect_payload_structs_in_expr(it, out_extra_structs, state) return false;
    for pc.arguments_unsorted {
      if it.expression && !ir_collect_payload_structs_in_expr(it.expression, out_extra_structs, state) return false;
    }
    return true;
  }

  if node.kind == .BINARY_OPERATOR {
    bn := cast(*Code_Binary_Operator) node;
    if bn.left && !ir_collect_payload_structs_in_expr(bn.left, out_extra_structs, state) return false;
    if bn.right && !ir_collect_payload_structs_in_expr(bn.right, out_extra_structs, state) return false;
    return true;
  }

  if node.kind == .UNARY_OPERATOR {
    un := cast(*Code_Unary_Operator) node;
    if un.subexpression && !ir_collect_payload_structs_in_expr(un.subexpression, out_extra_structs, state) return false;
    return true;
  }

  if node.kind == .CAST {
    cn := cast(*Code_Cast) node;
    if cn.expression && !ir_collect_payload_structs_in_expr(cn.expression, out_extra_structs, state) return false;
    return true;
  }

  if node.kind == .LITERAL {
    lit := cast(*Code_Literal) node;
    if lit.value_type == .STRUCT {
      for lit.struct_literal_info.arguments if !ir_collect_payload_structs_in_expr(it, out_extra_structs, state) return false;
    } else if lit.value_type == .ARRAY {
      for lit.array_literal_info.array_members if !ir_collect_payload_structs_in_expr(it, out_extra_structs, state) return false;
    }
    return true;
  }

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    if decl.expression && !ir_collect_payload_structs_in_expr(decl.expression, out_extra_structs, state) return false;
    return true;
  }

  if node.kind == .RETURN {
    rn := cast(*Code_Return) node;
    for rn.arguments_sorted if !ir_collect_payload_structs_in_expr(it, out_extra_structs, state) return false;
    return true;
  }

  return true;
}

ir_collect_compute_declared_structs_in_node :: (node: *Code_Node, out_extra_structs: *[..] IR_Struct, state: *IR_Lowering_State) -> bool {
  if !node return true;

  if node.kind == .DECLARATION {
    decl := cast(*Code_Declaration) node;
    decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
    if !ir_collect_compute_declared_struct_type(decl_type, state, node, out_extra_structs) return false;
    return ir_collect_payload_structs_in_expr(cast(*Code_Node) decl, out_extra_structs, state);
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

  if node.kind == .RETURN || node.kind == .PROCEDURE_CALL || node.kind == .BINARY_OPERATOR || node.kind == .UNARY_OPERATOR || node.kind == .CAST || node.kind == .LITERAL {
    return ir_collect_payload_structs_in_expr(node, out_extra_structs, state);
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

ir_sort_function_constants_deterministic :: (constants: *[..] IR_Function_Constant) {
  if constants.count <= 1 return;
  string_less :: (a: string, b: string) -> bool {
    limit := ifx a.count < b.count then a.count else b.count;
    for i: 0..limit-1 {
      if a[i] < b[i] return true;
      if a[i] > b[i] return false;
    }
    return a.count < b.count;
  }
  function_constant_less :: (a: IR_Function_Constant, b: IR_Function_Constant) -> bool {
    a_file := a.location.fully_pathed_filename;
    b_file := b.location.fully_pathed_filename;
    if a_file != b_file return string_less(a_file, b_file);
    if a.location.line_number != b.location.line_number return a.location.line_number < b.location.line_number;
    if a.location.character_number != b.location.character_number return a.location.character_number < b.location.character_number;
    return string_less(a.name, b.name);
  }

  i: s64 = 1;
  while i < constants.count {
    current := constants.*[i];
    j := i;
    while j > 0 && function_constant_less(current, constants.*[j - 1]) {
      constants.*[j] = constants.*[j - 1];
      j -= 1;
    }
    constants.*[j] = current;
    i += 1;
  }
}


ir_lower_extra_args_readonly :: (
    header: *Code_Procedure_Header,
    out_args: *[..] IR_Function_Arg,
    extra_structs: *[..] IR_Struct,
    out_function_constants: *[..] IR_Function_Constant,
    state: *IR_Lowering_State,
    start_arg_index: s64 = 1,
) -> (ok: bool, error_msg: string) {
    function_constants_arg_name: string;
    for i: start_arg_index..header.arguments.count-1 {
        arg := header.arguments[i];
        arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
        function_constants_struct, function_constants_struct_node, function_constants_ok := ir_function_constants_struct_from_arg(arg);
        if function_constants_ok {
            if function_constants_arg_name.count != 0 {
                return false, "only one @function_constants struct argument is supported per shader entry";
            }
            function_constants_arg_name = arg.name;
            if !ir_collect_function_constants_from_struct_arg(arg, function_constants_struct, function_constants_struct_node, out_function_constants, state) {
                return false, "";
            }
            continue;
        }
        arg_ok := ir_collect_nested_structs_for_shader_arg_type(arg_type, extra_structs);
        if !arg_ok return false, tprint("unsupported extra argument '%'", arg.name);
        arg_ir_type, arg_ir_type_ok := ir_type_from_type_info(arg_type);
        if !arg_ir_type_ok return false, tprint("unsupported typed IR argument '%'", arg.name);
        if arg_type && arg_type.type == .STRUCT {
            arg_ir_type.flags |= .PARAMETER_BLOCK;
            if !ir_validate_parameter_block_layout(arg.name, cast(*Type_Info_Struct) arg_type, state, cast(*Code_Node) arg) {
                return false, "";
            }
        }
        array_add(out_args, .{
            name = arg.name,
            type = arg_ir_type,
            is_readonly = true,
        });
    }
    return true, "";
}

ir_lower_collect_structs_from_helpers :: (
    main_header: *Code_Procedure_Header,
    seen_headers: [] *Code_Procedure_Header,
    extra_structs: *[..] IR_Struct,
    state: *IR_Lowering_State,
    use_graphics_arg_collection: bool,
) -> (ok: bool, error_msg: string) {
    for seen_headers {
        if it == main_header continue;
        for it.arguments {
            arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
            if use_graphics_arg_collection {
                arg_ok := ir_collect_nested_structs_for_shader_arg_type(arg_type, extra_structs);
                if !arg_ok return false, tprint("unsupported helper argument '%'", it.name);
            } else {
                if !arg_type || arg_type.type != .STRUCT continue;
                struct_type := cast(*Type_Info_Struct) arg_type;
                struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
                if ir_is_builtin_shader_type_name(struct_name) continue;
                lowered_struct, lowered_ok := ir_lower_struct_from_type(struct_name, arg_type);
                if !lowered_ok return false, tprint("could not lower helper struct argument type '%'", struct_name);
                ir_add_struct_unique_by_name(extra_structs, lowered_struct);
            }
        }
        for it.returns {
            ret_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
            if !ret_type || ret_type.type != .STRUCT continue;
            ret_struct_type := cast(*Type_Info_Struct) ret_type;
            ret_struct_name := jai_to_hlsl_type_name(get_struct_type_name(ret_struct_type));
            if ir_is_builtin_shader_type_name(ret_struct_name) continue;
            lowered_struct, lowered_ok := ir_lower_struct_from_type(ret_struct_name, ret_type);
            if !lowered_ok return false, tprint("could not lower helper struct return type '%'", ret_struct_name);
            ir_add_struct_unique_by_name(extra_structs, lowered_struct);
        }
        if it.body_or_null && it.body_or_null.block {
            if !ir_collect_compute_declared_structs_in_block(it.body_or_null.block, extra_structs, state) {
                return false, "";
            }
        }
    }
    return true, "";
}

#scope_export

ir_lower_vertex_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Vertex_Shader) {
    return_err :: (msg: string, args: ..Any) #expand {
        ir_set_diagnostic(*state, sprint(join("IR lowering(vertex): ", msg), ..args), ctx.header);
        `return { {}, false, ir_get_diagnostic(*state) };
    }
  out: IR_Vertex_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  assert(ctx.header != null);
  assert(ctx.header.body_or_null != null);
  assert(ctx.header.body_or_null.block != null);
  if ctx.header.arguments.count < 1 return_err("expected at least one input argument");
  if ctx.header.returns.count != 1  return_err("expected exactly one return value");

  arg0 := ctx.header.arguments[0];
  ret0 := ctx.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok return_err("could not lower input struct type");
  out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
  if !out_ok  return_err("could not lower output struct type");

  out.source_name = ctx.name;
  out.entry_name = "VertexMain";
  out.kind = .Vertex;
  out.input = in_struct;
  out.output = out_struct;
  {
    args_ok, args_err := ir_lower_extra_args_readonly(ctx.header, *out.args, *out.extra_structs, *out.function_constants, *state, 1);
    if !args_ok {
      if args_err.count != 0 return_err("%", args_err);
      return { {}, false, ir_get_diagnostic(*state) };
    }
  }
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(ctx.header, *seen_headers, *out.functions, ctx.header, *state) {
      return_err("failed while collecting/lowering helper functions");
  }
  {
    helpers_ok, helpers_err := ir_lower_collect_structs_from_helpers(ctx.header, seen_headers, *out.extra_structs, *state, true);
    if !helpers_ok {
      if helpers_err.count != 0 return_err("%", helpers_err);
      return {out, false, ir_get_diagnostic(*state)};
    }
  }
  if !ir_collect_compute_declared_structs_in_block(ctx.header.body_or_null.block, *out.extra_structs, *state) {
    return {out, false, ir_get_diagnostic(*state)};
  }
  input_field_names: [..] string;
  output_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(ctx.header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  for out.output.fields array_add(*output_field_names, it.name);
  lowering_ctx: IR_Lowering_Context;
  lowering_ctx.input_fields = input_field_names;
  lowering_ctx.output_fields = output_field_names;
  lowering_ctx.state = *state;
  lowering_ctx.input_struct = *out.input;
  lowering_ctx.output_struct = *out.output;
  if !ir_shared_lower_block(ctx.header.body_or_null.block, *out.body, lowering_ctx, true, parameter_usings) {
      return_err("failed while lowering function body");
  }
  ir_sort_function_constants_deterministic(*out.function_constants);
  return {out, true, ir_get_diagnostic(*state)};
} @jdll_export


ir_lower_fragment_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Fragment_Shader) {
    return_err :: (msg: string, args: ..Any, node: *Code_Node = null) #expand {
        ir_set_diagnostic(*state, sprint(join("IR lowering(fragment): ", msg), ..args), ctx.header);
        `return { {}, false, ir_get_diagnostic(*state) };
    }
    
  out: IR_Fragment_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  assert(ctx.header != null);
  assert(ctx.header.body_or_null != null);
  assert(ctx.header.body_or_null.block != null);
  if ctx.header.arguments.count < 1 return_err("expected at least one input argument");
  if ctx.header.returns.count != 1  return_err("expected exactly one return value");

  arg0 := ctx.header.arguments[0];
  ret0 := ctx.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;
  out_type_name_for_classify, out_type_name_ok := ir_type_to_shader_name(out_type);
  out_type_is_builtin_value := out_type_name_ok && ir_is_builtin_shader_type_name(out_type_name_for_classify);

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok return_err("could not lower input struct type");
  
  // Fragment-stage gl_FragCoord should map to rasterized screen position.
  for *in_struct.fields {
    sem_upper := to_upper_copy(it.semantic,, temp);
    if sem_upper == "GL_FRAGCOORD" || sem_upper == "FRAG_COORD" {
      it.semantic = "SV_Position";
    }
  }

  ret_semantic, has_ret_semantic := declaration_get_semantic(ret0);
  out_type_is_struct := out_type && out_type.type == .STRUCT && !out_type_is_builtin_value;
  out_struct: IR_Struct;
  if out_type_is_struct {
    lowered_out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
    if !out_ok  return_err("could not lower output struct type");
    
    out_struct = lowered_out_struct;
    if has_ret_semantic {
      if out_struct.fields.count != 1 return_err("return semantic notes require exactly one output field.", node=ret0);
      out_struct.fields[0].semantic = ret_semantic;
    }
  } else {
    if !has_ret_semantic {
        return_err("non-struct return type requires a return semantic note (for example, @SV_Target).", node=ret0);
    }
    ret_ir_type, ret_ir_ok := ir_type_from_type_info(out_type);
    if !ret_ir_ok {
        return_err("unsupported non-struct return type.", node=ret0);
    }
    ret_type_name := out_type_name_for_classify;
    if !out_type_name_ok {
      ret_type_name, out_type_name_ok = ir_type_to_shader_name(out_type);
    }
    if !out_type_name_ok {
        return_err("unsupported non-struct return type name.", node=ret0);
    }
    out_struct.name = tprint("%_Out", ctx.name);
    array_add(*out_struct.fields, .{
      name = "out_color",
      type = ret_ir_type,
      semantic = ret_semantic,
    });
  }

  out.source_name = ctx.name;
  out.entry_name = "FragmentMain";
  out.kind = .Fragment;
  out.input = in_struct;
  out.output = out_struct;
  {
    args_ok, args_err := ir_lower_extra_args_readonly(ctx.header, *out.args, *out.extra_structs, *out.function_constants, *state, 1);
    if !args_ok {
      if args_err.count != 0 return_err("%", args_err);
      return { {}, false, ir_get_diagnostic(*state) };
    }
  }
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(ctx.header, *seen_headers, *out.functions, ctx.header, *state) {
      return_err("failed while collecting/lowering helper functions");
  }
  {
    helpers_ok, helpers_err := ir_lower_collect_structs_from_helpers(ctx.header, seen_headers, *out.extra_structs, *state, true);
    if !helpers_ok {
      if helpers_err.count != 0 return_err("%", helpers_err);
      return {out, false, ir_get_diagnostic(*state)};
    }
  }
  if !ir_collect_compute_declared_structs_in_block(ctx.header.body_or_null.block, *out.extra_structs, *state) {
    return {out, false, ir_get_diagnostic(*state)};
  }
  input_field_names: [..] string;
  output_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(ctx.header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  if out_type_is_struct {
    for out.output.fields array_add(*output_field_names, it.name);
  }
  lowering_ctx: IR_Lowering_Context;
  lowering_ctx.input_fields = input_field_names;
  lowering_ctx.output_fields = output_field_names;
  lowering_ctx.state = *state;
  lowering_ctx.input_struct = *out.input;
  lowering_ctx.output_struct = *out.output;
  if !ir_shared_lower_block(ctx.header.body_or_null.block, *out.body, lowering_ctx, true, parameter_usings) {
      return_err("failed while lowering function body", node=ctx.header.body_or_null.block);
  }
  ir_sort_function_constants_deterministic(*out.function_constants);

  return { out, true, ir_get_diagnostic(*state) };
} @jdll_export

ir_lower_compute_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Compute_Shader) {
    return_err :: (msg: string, args: ..Any, node: *Code_Node = null) #expand {
        ir_set_diagnostic(*state, sprint(join("IR lowering(compute): ", msg), ..args), ctx.header);
        `return { {}, false, ir_get_diagnostic(*state) };
    }
    
  out: IR_Compute_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  header := ctx.header;
  assert(header != null);
  assert(header.body_or_null != null);
  assert(header.body_or_null.block != null);
  if header.arguments.count < 2 {
      return_err("expected input struct + at least one buffer argument");
  }
  if header.returns.count != 0 {
      return_err("compute kernels must have zero return values");
  }

  input_arg := header.arguments[0];
  input_type := ifx input_arg.type_inst then input_arg.type_inst.result else ifx input_arg.expression then input_arg.expression.type else null;
  input_struct, input_ok := ir_lower_compute_input_struct(tprint("%_In", ctx.name), input_type);
  if !input_ok return_err("could not lower compute input struct/builtins");
  for input_struct.fields {
    builtin_kind, builtin_ok := ir_builtin_kind_from_semantic(it.semantic);
    if !builtin_ok continue;
    array_add(*state.input_builtin_fields, .{
      field_name = it.name,
      builtin_ref = .{
        kind = builtin_kind,
        component = -1,
      },
    });
  }

  out.source_name = ctx.name;
  out.entry_name = "ComputeMain";
  out.kind = .Compute;
  out.input = input_struct;

  for i: 1..header.arguments.count-1 {
    arg := header.arguments[i];
    arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
    function_constants_struct, function_constants_struct_node, function_constants_ok := ir_function_constants_struct_from_arg(arg);
    if function_constants_ok {
        if out.function_constants.count != 0 {
            return_err("only one @function_constants struct argument is supported per shader entry");
        }
        if !ir_collect_function_constants_from_struct_arg(arg, function_constants_struct, function_constants_struct_node, *out.function_constants, *state) {
            return {out, false, ir_get_diagnostic(*state)};
        }
        continue;
    }
    if !arg_type || arg_type.type != .POINTER {
        return_err("argument '%' must be a pointer/buffer", arg.name);
    }
    ptr := cast(*Type_Info_Pointer) arg_type;
    elem_ir_type, elem_ir_ok := ir_type_from_type_info(ptr.pointer_to);
    if !elem_ir_ok {
        return_err("unsupported typed pointee for argument '%'", arg.name, node=arg);
    }
    if ptr.pointer_to && ptr.pointer_to.type == .STRUCT {
      struct_type := cast(*Type_Info_Struct) ptr.pointer_to;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
      if !ir_is_builtin_shader_type_name(struct_name) {
        lowered_struct, lowered_ok := ir_lower_struct_with_pointer_members_from_type(struct_name, ptr.pointer_to, *out.extra_structs);
        if !lowered_ok {
            return_err("could not lower struct type '%' for argument '%'", struct_name, arg.name, node=arg);
        }
        ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
      }
    }
    array_add(*out.buffers, .{
      name = arg.name,
      element_type = elem_ir_type,
      is_readonly = false,
    });
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(header, *seen_headers, *out.functions, header, *state) {
      return_err("failed while collecting/lowering helper functions");
  }
  {
    helpers_ok, helpers_err := ir_lower_collect_structs_from_helpers(header, seen_headers, *out.extra_structs, *state, false);
    if !helpers_ok {
      if helpers_err.count != 0 return_err("%", helpers_err);
      return {out, false, ir_get_diagnostic(*state)};
    }
  }
  if !ir_collect_compute_declared_structs_in_block(header.body_or_null.block, *out.extra_structs, *state) {
    return {out, false, ir_get_diagnostic(*state)};
  }

  input_field_names: [..] string;
  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(header, *parameter_usings);
  for out.input.fields array_add(*input_field_names, it.name);
  lowering_ctx: IR_Lowering_Context;
  lowering_ctx.input_fields = input_field_names;
  lowering_ctx.state = *state;
  lowering_ctx.input_struct = *out.input;
  if !ir_shared_lower_block(header.body_or_null.block, *out.body, lowering_ctx, false, parameter_usings) {
      return_err("failed while lowering function body", node=header.body_or_null.block);
  }
  ir_sort_function_constants_deterministic(*out.function_constants);
  return {out, true, ir_get_diagnostic(*state)};
} @jdll_export

ir_lower_task_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Task_Shader) {
  return_err :: (msg: string, args: ..Any, node: *Code_Node = null) #expand {
      ir_set_diagnostic(*state, sprint(join("IR lowering(task): ", msg), ..args), ctx.header);
      `return { {}, false, ir_get_diagnostic(*state) };
  }

  out: IR_Task_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  header := ctx.header;
  assert(header != null);
  assert(header.body_or_null != null);
  assert(header.body_or_null.block != null);
  if header.returns.count != 0 {
      return_err("task shaders must have zero return values.");
  }

  out.source_name = ctx.name;
  out.entry_name = "TaskMain";
  out.kind = .Task;
  {
    args_ok, args_err := ir_lower_extra_args_readonly(ctx.header, *out.args, *out.extra_structs, *out.function_constants, *state, 0);
    if !args_ok {
      if args_err.count != 0 return_err("%", args_err);
      return { {}, false, ir_get_diagnostic(*state) };
    }
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(header, *seen_headers, *out.functions, header, *state) {
      return_err("failed while collecting/lowering helper functions");
  }
  {
    helpers_ok, helpers_err := ir_lower_collect_structs_from_helpers(header, seen_headers, *out.extra_structs, *state, true);
    if !helpers_ok {
      if helpers_err.count != 0 return_err("%", helpers_err);
      return {out, false, ir_get_diagnostic(*state)};
    }
  }

  if !ir_collect_compute_declared_structs_in_block(header.body_or_null.block, *out.extra_structs, *state) {
    return {out, false, ir_get_diagnostic(*state)};
  }

  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(header, *parameter_usings);
  lowering_ctx: IR_Lowering_Context;
  lowering_ctx.state = *state;
  if !ir_shared_lower_block(header.body_or_null.block, *out.body, lowering_ctx, false, parameter_usings) {
      return_err("failed while lowering function body", node=header.body_or_null.block);
  }

  ir_sort_function_constants_deterministic(*out.function_constants);
  return {out, true, ir_get_diagnostic(*state)};
} @jdll_export

ir_lower_mesh_from_shader_context :: (ctx: IR_Shader_Header_Context) -> IR_Result(IR_Mesh_Shader) {
  return_err :: (msg: string, args: ..Any, node: *Code_Node = null) #expand {
      ir_set_diagnostic(*state, sprint(join("IR lowering(mesh): ", msg), ..args), ctx.header);
      `return { {}, false, ir_get_diagnostic(*state) };
  }

  out: IR_Mesh_Shader;
  state: IR_Lowering_State;
  ir_reset_diagnostic(*state);
  header := ctx.header;
  assert(header != null);
  assert(header.body_or_null != null);
  assert(header.body_or_null.block != null);
  if header.returns.count != 0 {
      return_err("mesh shaders must have zero return values.");
  }

  out.source_name = ctx.name;
  out.entry_name = "MeshMain";
  out.kind = .Mesh;
  {
    args_ok, args_err := ir_lower_extra_args_readonly(ctx.header, *out.args, *out.extra_structs, *out.function_constants, *state, 0);
    if !args_ok {
      if args_err.count != 0 return_err("%", args_err);
      return { {}, false, ir_get_diagnostic(*state) };
    }
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_functions_recursive(header, *seen_headers, *out.functions, header, *state) {
      return_err("failed while collecting/lowering helper functions");
  }
  {
    helpers_ok, helpers_err := ir_lower_collect_structs_from_helpers(header, seen_headers, *out.extra_structs, *state, true);
    if !helpers_ok {
      if helpers_err.count != 0 return_err("%", helpers_err);
      return {out, false, ir_get_diagnostic(*state)};
    }
  }

  if !ir_collect_compute_declared_structs_in_block(header.body_or_null.block, *out.extra_structs, *state) {
    return {out, false, ir_get_diagnostic(*state)};
  }

  parameter_usings: [..] IR_Using_Source;
  ir_collect_parameter_using_sources(header, *parameter_usings);
  lowering_ctx: IR_Lowering_Context;
  lowering_ctx.state = *state;
  if !ir_shared_lower_block(header.body_or_null.block, *out.body, lowering_ctx, false, parameter_usings) {
      return_err("failed while lowering function body", node=header.body_or_null.block);
  }

  ir_sort_function_constants_deterministic(*out.function_constants);

  return {out, true, ir_get_diagnostic(*state)};
} @jdll_export

#scope_file

member_get_semantic :: (member: *Type_Info_Struct_Member) -> string {
  for member.notes {
    if begins_with(it, "semantic_") {
      ret: string;
      ret.data = it.data + 9;
      ret.count = it.count - 9;
      return ret;
    }
    sem_upper := to_upper_copy(it);
    if begins_with(sem_upper, "SV_") return it;
    if begins_with(sem_upper, "GL_") return it;
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

#scope_file
Math :: #import "Math";
