METAL_HEADER :: "#include <metal_stdlib>\nusing namespace metal;\n\n";
METAL_UNIFORM_BUFFER_INDEX :: 0;

METAL_RADIANS_HELPERS :: "inline float jai_radians(float v) { return v * 0.01745329251994329577f; }\ninline float2 jai_radians(float2 v) { return v * 0.01745329251994329577f; }\ninline float3 jai_radians(float3 v) { return v * 0.01745329251994329577f; }\ninline float4 jai_radians(float4 v) { return v * 0.01745329251994329577f; }\n\n";
METAL_DEGREES_HELPERS :: "inline float jai_degrees(float v) { return v * 57.29577951308232088f; }\ninline float2 jai_degrees(float2 v) { return v * 57.29577951308232088f; }\ninline float3 jai_degrees(float3 v) { return v * 57.29577951308232088f; }\ninline float4 jai_degrees(float4 v) { return v * 57.29577951308232088f; }\n\n";

write_metal_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, shader_type: Shader_Type) -> string {
  check_arguments(node.header, shader_type);

  if shader_type == .Compute {
    return write_metal_compute_shader(ctx, node);
  }
  
  main_function_name := tprint("%Main", shader_type);

  main_sb: String_Builder;
  if shader_type == {
  case .Vertex; append(*main_sb, "vertex ");
  case .Fragment; append(*main_sb, "fragment ");
  case .Compute; // nothing
  }
  append(*main_sb, get_struct_type_name(cast(*Type_Info_Struct) node.header.returns[0].type_inst.result));
  append(*main_sb, " ", main_function_name, "(");
  print_metal_stage_in_arg(*main_sb, node.header.arguments[0]);
  if node.header.arguments.count >= 2 {
    append(*main_sb, ", ");
    print_metal_uniform_arg(*main_sb, node.header.arguments[1]);
  }
  append(*main_sb, ") {\n");
  print_metal_local_bindings(ctx, *main_sb, node.header, indent=1);
  print_metal_stmt(ctx, *main_sb, node.block, is_main=true);
  print_metal_output_return(ctx, *main_sb, node.header, indent=1);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  return write_metal_shader_code(ctx, node);
}

write_metal_compute_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  main_sb: String_Builder;
  append(*main_sb, "kernel void ComputeMain(");
  print_metal_compute_main_args(*main_sb, node.header);
  append(*main_sb, ") {\n");
  print_metal_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  return write_metal_shader_code(ctx, node);
}

write_metal_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  sb: String_Builder;
  use_jai_radians := metal_shader_uses_function(ctx, "jai_radians(");
  use_jai_degrees := metal_shader_uses_function(ctx, "jai_degrees(");
  if as_jai_string {
    append(*sb, tprint("%_metal_string", node.header.name), " :: #string END\n");
  }
  append(*sb, METAL_HEADER);
  if use_jai_radians append(*sb, METAL_RADIANS_HELPERS);
  if use_jai_degrees append(*sb, METAL_DEGREES_HELPERS);
  print_metal_global_constants(*sb, node.header);
  if ctx.type != .Compute {
    print_metal_in_struct(*sb, node.header);
    if node.header.arguments.count >= 2 print_metal_uniform_struct(*sb, node.header);
    print_metal_out_struct(*sb, node.header, ctx.type);
  }
  for ctx.functions {
    if it.name != "main" print_metal_prototype(*sb, it.prototype);
  }
  append(*sb, "\n");
  for ctx.functions {
    append(*sb, it.code, "\n");
  }
  if as_jai_string {
    append(*sb, "\nEND");
  }

  return builder_to_string(*sb);
}

metal_shader_uses_function :: (ctx: *Shader_Write_Context, needle: string) -> bool {
  for ctx.functions {
    found, _ := contains(it.code, needle);
    if found return true;
  }
  return false;
}

print_metal_in_struct :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("Metal Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", get_struct_type_name(struct_type)));
  attribute_i := 0;
  for * struct_type.members {
    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;
    if type_contains_array(it.type)
      compiler_report("Metal Backend: Array members are not supported in stage input/output structs. Use non-array varyings for now.", make_location(node.arguments[0]));

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);

    if member_is_stage_builtin(it) {
      if member_has_note_contains(it, "frag_coord") append(sb, " [[position]]");
      else if member_has_note_contains(it, "position") append(sb, " [[position]]");
    } else {
      if node_is_fragment_shader(node) append(sb, tprint(" [[user(%)]]", it.name));
      else append(sb, tprint(" [[attribute(%)]]", attribute_i));
      if !node_is_fragment_shader(node) attribute_i += 1;
    }
    append(sb, ";\n");
  }
  append(sb, "};\n\n");
}

print_metal_uniform_struct :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Metal Backend: Shader uniforms are not a struct", make_location(node.arguments[1]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", get_struct_type_name(struct_type)));
  for * struct_type.members {
    append(sb, "    ");
    print_metal_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "};\n\n");
}

print_metal_out_struct :: (sb: *String_Builder, node: *Code_Procedure_Header, shader_type: Shader_Type) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Metal Backend: Shader Output is not a struct", make_location(node.returns[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", get_struct_type_name(struct_type)));
  color_i := 0;
  for * struct_type.members {
    if shader_type == .Vertex && it.name == "gl_FragCoord" continue;
    if type_contains_array(it.type)
      compiler_report("Metal Backend: Array members are not supported in stage input/output structs. Use non-array varyings for now.", make_location(node.returns[0]));

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);
    if member_is_stage_builtin(it) {
      if member_has_note_contains(it, "position") append(sb, " [[position]]");
      else if member_has_note_contains(it, "frag_depth") append(sb, " [[depth(any)]]");
    } else if shader_type == .Fragment {
      append(sb, tprint(" [[color(%)]]", color_i));
      color_i += 1;
    } else if shader_type == .Vertex {
      append(sb, tprint(" [[user(%)]]", it.name));
    }
    append(sb, ";\n");
  }
  append(sb, "};\n\n");
}

print_metal_stage_in_arg :: (sb: *String_Builder, arg: *Code_Declaration) {
  print_metal_type(sb, arg.type_inst.result);
  append(sb, " ", arg.name, " [[stage_in]]");
}

print_metal_uniform_arg :: (sb: *String_Builder, arg: *Code_Declaration) {
  append(sb, "constant ");
  print_metal_type(sb, arg.type_inst.result);
  append(sb, tprint("& % [[buffer(%)]]", arg.name, METAL_UNIFORM_BUFFER_INDEX));
}

print_metal_compute_main_args :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  first := true;
  next_arg :: () #expand {
    if first first = false;
    else append(sb, ", ");
  }

  next_buffer_index: s64 = 0;
  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if declaration_is_parameter_using(header, it) && arg_type.type == .STRUCT {
      struct_type := cast(*Type_Info_Struct) arg_type;
      for * struct_type.members {
        builtin_name, found := member_get_compute_builtin_note(it);
        if !found
          compiler_report("Metal Backend: Compute using-struct members must have a supported @thread_* note", make_location(header));

        next_arg();
        print_metal_type(sb, it.type);
        append(sb, tprint(" % [[%]]", it.name, builtin_name));
      }
      continue;
    }

    if arg_type.type != .POINTER
      compiler_report("Metal Backend: Compute non-using arguments must currently be pointers (bound as buffers)", make_location(it));

    pointer := cast(*Type_Info_Pointer) arg_type;
    next_arg();
    append(sb, "device ");
    print_metal_type(sb, pointer.pointer_to);
    append(sb, tprint("* % [[buffer(%)]]", it.name, next_buffer_index));
    next_buffer_index += 1;
  }
}

print_metal_local_bindings :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Procedure_Header, indent: s64) {
  in_struct_type := cast(*Type_Info_Struct) node.arguments[0].type_inst.result;
  for * in_struct_type.members {
    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;

    print_metal_local_binding(sb, it.type, it.name, tprint("%.%", node.arguments[0].name, it.name), indent);
  }

  if node.arguments.count >= 2 {
    un_struct_type := cast(*Type_Info_Struct) node.arguments[1].type_inst.result;
    for * un_struct_type.members {
      print_metal_local_binding(sb, it.type, it.name, tprint("%.%", node.arguments[1].name, it.name), indent);
    }
  }

  out_struct_type := cast(*Type_Info_Struct) node.returns[0].type_inst.result;
  for * out_struct_type.members {
    if ctx.type == .Vertex && it.name == "gl_FragCoord" continue;

    add_indents(sb, indent);
    print_metal_typed_name(sb, it.type, it.name);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_metal_local_binding :: (sb: *String_Builder, type: *Type_Info, local_name: string, source_expr: string, indent: s64) {
  add_indents(sb, indent);
  print_metal_typed_name(sb, type, local_name);
  if type.type == .ARRAY {
    append(sb, ";\n");
    print_metal_array_copy(sb, type, local_name, source_expr, indent);
  } else {
    append(sb, " = ", source_expr, ";\n");
  }
}

print_metal_array_copy :: (sb: *String_Builder, type: *Type_Info, dst_expr: string, src_expr: string, indent: s64) {
  if type.type != .ARRAY {
    add_indents(sb, indent);
    append(sb, dst_expr, " = ", src_expr, ";\n");
    return;
  }

  array_type := cast(*Type_Info_Array) type;
  if array_type.array_type != .FIXED
    compiler_report("Metal Backend: Only fixed-size arrays are currently supported in Jai Shaders");

  for i: 0..array_type.array_count-1 {
    dst_member := tprint("%[%]", dst_expr, i);
    src_member := tprint("%[%]", src_expr, i);
    print_metal_array_copy(sb, array_type.element_type, dst_member, src_member, indent);
  }
}

print_metal_output_return :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Procedure_Header, indent: s64) {
  out_type := cast(*Type_Info_Struct) node.returns[0].type_inst.result;
  add_indents(sb, indent);
  append(sb, out_type.name, " out;\n");
  for * out_type.members {
    if ctx.type == .Vertex && it.name == "gl_FragCoord" continue;

    add_indents(sb, indent);
    append(sb, "out.", it.name, " = ", it.name, ";\n");
  }
  add_indents(sb, indent);
  append(sb, "return out;\n");
}

print_metal_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: *Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    report_array_return_not_supported("Metal", ret);
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    report_array_parameter_not_supported("Metal", it);
    if it.type_inst
      print_metal_type(sb, it.type_inst.result);
    else
      print_metal_type(sb, it.expression.type);

    append(sb, " ", it.name);

    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_metal_stmt(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

print_metal_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    report_array_return_not_supported("Metal", ret);
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", header.name));
  for header.arguments {
    report_array_parameter_not_supported("Metal", it);
    if it.type_inst
      print_metal_type(sb, it.type_inst.result);
    else
      print_metal_type(sb, it.expression.type);
    append(sb, " ", it.name);
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}

print_metal_stmt :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        op := cast(*Code_Declaration) it;

        if op.type_inst
          print_metal_typed_name(sb, op.type_inst.result, op.name);
        else
          print_metal_typed_name(sb, op.expression.type, op.name);

        if op.expression {
          append(sb, " = ");
          print_metal_expr(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }

      case .BINARY_OPERATOR; {
        op := cast(*Code_Binary_Operator) it;
        add_indents(sb, indent);
        print_metal_binary_operator(ctx, sb, op);
        append(sb, ";\n");
      }

      case .IF; {
        op := cast(*Code_If) it;
        add_indents(sb, indent);

        if op.if_flags & .IS_SWITCH_STATEMENT {
          if op.condition.type.type == .INTEGER {
            append(sb, "switch (");
            print_metal_expr(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          } else {
            curr := 0;
            default_case: *Code_Case;
            while curr < op.then_block.statements.count {
              curr_case := cast(*Code_Case) op.then_block.statements[curr];

              if curr_case.condition == null {
                default_case = curr_case;
                curr += 1;
                continue;
              }
              append(sb, "if (");
              print_metal_expr(ctx, sb, op.condition);
              append(sb, " == ");
              print_metal_expr(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_metal_stmt(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);

              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else
                append(sb, "} else ");

              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_metal_stmt(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_metal_expr(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_metal_stmt(ctx, sb, op.else_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          }
        }
      }

      case .CASE; {
        add_indents(sb, indent);
        op := cast(*Code_Case) it;

        if op.condition {
          append(sb, "case ");
          print_metal_expr(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_metal_stmt(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }

      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_metal_expr(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_metal_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }

      case .FOR; {
        add_indents(sb, indent);
        op := cast(*Code_For) it;
        if op.macro_expansion_procedure_call || !op.iteration_expression_right
          compiler_report("Can't use special iterators in Jai Shaders", make_location(op));
        if op.for_flags & .POINTER
          compiler_report("Iteration by Pointers is disallowed in Jai Shaders", make_location(op));

        append(sb, "for (int ", op.ident_decl.name, " = ");
        print_metal_expr(ctx, sb, op.iteration_expression);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_metal_expr(ctx, sb, op.iteration_expression_right);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_metal_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }

      case .RETURN; {
        if is_main continue;
        add_indents(sb, indent);
        op := cast(*Code_Return) it;
        append(sb, "return ");
        if op.arguments_sorted.count == 0 {
          append(sb, ";\n");
        } else if op.arguments_sorted.count == 1 {
          print_metal_expr(ctx, sb, op.arguments_sorted[0]);
          append(sb, ";\n");
        } else
          compiler_report("Multiple Return Arguments Disallowed in Jai Shaders", make_location(op));
      }

      case .PROCEDURE_CALL; {
        add_indents(sb, indent);

        pc := cast(*Code_Procedure_Call) it;
        if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
          compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
        name := cast(*Code_Ident) pc.procedure_expression;
        if !table_contains(*METAL_INBUILT_FUNCTIONS, name.name)
          handle_custom_procedure_call(ctx, sb, pc);
        print_metal_procedure_call(ctx, sb, pc);

        append(sb, ";\n");
      }

      case .USING; continue;

      case; {
        compiler_report(tprint("The statement of type '%' is not supported in Jai Shaders", it.kind), make_location(it));
      }
    }
  }
}

print_metal_expr :: (using ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  if node.kind == {
    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        print_metal_struct_literal(ctx, sb, lit);
      } else if lit.value_type == .ARRAY {
        print_metal_array_literal(ctx, sb, lit);
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_metal_expr(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_metal_binary_operator(ctx, sb, bn);
    }

    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
        compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));

      name := cast(*Code_Ident) pc.procedure_expression;
      if !table_contains(*METAL_INBUILT_FUNCTIONS, name.name)
        handle_custom_procedure_call(ctx, sb, pc);
      print_metal_procedure_call(ctx, sb, pc);
    }

    case; PP.print_expression(sb, node);
  }
}

print_metal_binary_operator :: (ctx: *Shader_Write_Context, sb: *String_Builder, bn: *Code_Binary_Operator) {
  if bn.operator_type == .ARRAY_SUBSCRIPT {
    print_metal_expr(ctx, sb, bn.left);
    append(sb, "[");
    print_metal_subscript_index_expr(ctx, sb, bn.right);
    append(sb, "]");
    return;
  }

  print_metal_expr(ctx, sb, bn.left);
  space := " ";
  if bn.operator_type == cast(Operator_Type) #char "." space = "";
  append(sb, space, operator_string(bn.operator_type), space);
  print_metal_expr(ctx, sb, bn.right);
}

print_metal_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  if pc.procedure_expression.kind == .IDENT {
    name := cast(*Code_Ident) pc.procedure_expression;
    update_metal_helper_usage(ctx, name.name);
    append(sb, map_metal_procedure_name(name.name));
  } else {
    PP.print_expression(sb, pc.procedure_expression);
  }
  append(sb, "(");
  for pc.arguments_sorted {
    print_metal_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}

map_metal_procedure_name :: (name: string) -> string {
  if name == "mod" return "fmod";
  if name == "radians" return "jai_radians";
  if name == "degrees" return "jai_degrees";
  return name;
}

update_metal_helper_usage :: (ctx: *Shader_Write_Context, name: string) {
  if name == "radians" ctx.metal_use_jai_radians = true;
  if name == "degrees" ctx.metal_use_jai_degrees = true;
}

print_metal_member_with_typename :: (sb: *String_Builder, thing: *Type_Info_Struct_Member) {
  print_metal_typed_name(sb, thing.type, thing.name);
}

print_metal_type :: (sb: *String_Builder, type: *Type_Info) {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      append(sb, ifx inttype.signed then "int" else "uint");
    }
    case .FLOAT; append(sb, ifx type.runtime_size == 64 then "double" else "float");
    case .BOOL; append(sb, "bool");
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      append(sb, jai_to_metal_type_name(get_struct_type_name(structtype)));
    }
    case .VOID; append(sb, "void");

    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

print_metal_typed_name :: (sb: *String_Builder, type: *Type_Info, name: string) {
  base_type, array_suffix := split_array_type_and_suffix("Metal", type);
  print_metal_type(sb, base_type);
  append(sb, " ", name, array_suffix);
}

print_metal_array_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal) {
  info := lit.array_literal_info;
  append(sb, "{");
  for info.array_members {
    if it_index != 0 append(sb, ", ");
    print_metal_array_member_expr(ctx, sb, it, info.element_type.result);
  }
  append(sb, "}");
}

print_metal_array_member_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node, expected_type: *Type_Info) {
  if node.kind == .LITERAL {
    lit := cast(*Code_Literal) node;
    if lit.value_type == .STRUCT {
      print_metal_struct_literal(ctx, sb, lit, expected_type);
      return;
    }
  }
  print_metal_expr(ctx, sb, node);
}

print_metal_struct_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal, expected_type: *Type_Info = null) {
  constructor_name: string;
  if lit.struct_literal_info.type_expression {
    name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
    constructor_name = jai_to_metal_type_name(name.name);
  } else if expected_type && expected_type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) expected_type;
    constructor_name = jai_to_metal_type_name(get_struct_type_name(struct_type));
  } else if lit.type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) lit.type;
    constructor_name = jai_to_metal_type_name(get_struct_type_name(struct_type));
  } else {
    compiler_report("Unfortunately, we can't easily know enough about types without the explicit name here.", make_location(lit));
    return;
  }

  append(sb, constructor_name);
  matrix_dim, matrix_scalar_type := metal_matrix_info_from_constructor_name(constructor_name);
  if matrix_dim != 0 {
    print_metal_matrix_literal_args(ctx, sb, lit, matrix_dim, matrix_scalar_type);
    return;
  }

  append(sb, "(");
  for lit.struct_literal_info.arguments {
    if it_index != 0 append(sb, ", ");
    print_metal_expr(ctx, sb, it);
  }
  append(sb, ")");
}

metal_matrix_info_from_constructor_name :: (name: string) -> (dim: s64, scalar_type: string) {
  if ends_with(name, "2x2") {
    return 2, slice(name, 0, name.count-3);
  }
  if ends_with(name, "3x3") {
    return 3, slice(name, 0, name.count-3);
  }
  if ends_with(name, "4x4") {
    return 4, slice(name, 0, name.count-3);
  }

  return 0, "";
}

print_metal_matrix_literal_args :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal, dim: s64, scalar_type: string) {
  needed := dim * dim;
  if lit.struct_literal_info.arguments.count != needed {
    compiler_report(
      tprint("Metal Backend: Matrix literal '%' requires exactly % scalar arguments (got %)",
             scalar_type, needed, lit.struct_literal_info.arguments.count),
      make_location(lit));
    return;
  }

  append(sb, "(");
  for col: 0..dim-1 {
    if col != 0 append(sb, ", ");
    append(sb, tprint("%%(", scalar_type, dim));
    for row: 0..dim-1 {
      if row != 0 append(sb, ", ");
      arg_index := col * dim + row;
      print_metal_expr(ctx, sb, lit.struct_literal_info.arguments[arg_index]);
    }
    append(sb, ")");
  }
  append(sb, ")");
}

print_metal_subscript_index_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  inner: String_Builder;
  print_metal_expr(ctx, *inner, node);
  expr := strip_redundant_outer_parens(builder_to_string(*inner));
  append(sb, expr);
}

#scope_file

print_metal_global_constants :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if !header.constants_block return;
  for header.constants_block.statements {
    if it.kind != .DECLARATION continue;
    decl := cast(*Code_Declaration) it;
    if !(decl.flags & .IS_GLOBAL) continue;
    if !(decl.flags & .IS_CONSTANT)
      compiler_report("Metal Backend: Only global constant declarations are currently supported in Jai Shaders", make_location(decl));

    append(sb, "constant ");
    if decl.type_inst
      print_metal_typed_name(sb, decl.type_inst.result, decl.name);
    else
      print_metal_typed_name(sb, decl.expression.type, decl.name);

    if decl.expression {
      append(sb, " = ");
      print_metal_expr(xx null, sb, decl.expression);
    }
    append(sb, ";\n");
  }
  if header.constants_block.statements.count != 0 append(sb, "\n");
}

check_arguments :: (using header: *Code_Procedure_Header, shader_type: Shader_Type) {
  err :: (msg: string) #expand {
    compiler_report(tprint("Metal Backend: Jai % Shader %", shader_type, msg), make_location(header));
  }

  if shader_type == .Compute {
    if returns.count != 0 err("must not return a value (use buffer arguments instead)");
    if arguments.count == 0 err("must get AT LEAST 1 structure as an argument");
    if arguments.count != 0 {
      first_arg_type := ifx arguments[0].type_inst then arguments[0].type_inst.result else arguments[0].expression.type;
      if first_arg_type.type != .STRUCT err("must have a structure as the first input argument");
      if !declaration_is_parameter_using(header, arguments[0]) err("must mark the first struct input argument as 'using'");
    }
  } else {
    if returns.count != 1 err("must return a structure");
    if arguments.count != 2 {
      if shader_type == .Fragment err("must get two structures as arguments (Vertex output and Uniforms)");
      else err("must get two structures as arguments (Vertex Input and Uniforms)");
    }
    if parameter_usings.count != 2 err("must have struct arguments marked 'using'");
  }

  check_array_signature_support("Metal", header);
}


jai_to_metal_type_map :: #run -> Table(string, string) {
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
jai_to_metal_type_name :: (in: string) -> string {
  success, val := table_find(*jai_to_metal_type_map, in);
  return ifx success then val else in;
}

METAL_INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  "sin", "cos", "tan", "asin", "acos", "atan",
  "degrees", "radians",

  "abs", "ceil", "exp", "exp2", "floor", "isinf", "isnan", "log", "log2", "max", "min",
  "mix", "mod", "pow", "round", "roundEven", "sign", "smoothstep", "sqrt", "step", "trunc",

  "cross", "distance", "dot", "equal", "faceforward", "length", "normalize", "notEqual",
  "all", "any", "greaterThan", "lessThan", "greaterThanEqual", "lessThanEqual", "not",

  "texture",

  "reflect", "refract", "fract",
];
METAL_INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for METAL_INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
