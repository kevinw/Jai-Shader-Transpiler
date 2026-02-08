METAL_HEADER :: "#include <metal_stdlib>\nusing namespace metal;\n\n";

write_metal_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, shader_type: Shader_Type) -> string {
  check_arguments(node.header, shader_type);

  main_sb: String_Builder;
  if shader_type == {
  case .Vertex; append(*main_sb, "vertex ");
  case .Fragment; append(*main_sb, "fragment ");
  case .Compute; // nothing
  }
  append(*main_sb, (cast(*Type_Info_Struct) node.header.returns[0].type_inst.result).name);
  append(*main_sb, " main(");
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

write_metal_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  sb: String_Builder;
  if as_jai_string {
    append(*sb, tprint("%_metal_string", node.header.name), " :: #string END\n");
  }
  append(*sb, METAL_HEADER);
  print_metal_in_struct(*sb, node.header);
  if node.header.arguments.count >= 2 print_metal_uniform_struct(*sb, node.header);
  print_metal_out_struct(*sb, node.header, ctx.type);
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

print_metal_in_struct :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("Metal Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  append(sb, tprint("struct % {\n", struct_type.name));
  attribute_i := 0;
  for * struct_type.members {
    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);

    if member_has_note(it, "inbuilt") {
      if it.name == "gl_FragCoord" append(sb, " [[position]]");
      else if it.name == "gl_Position" append(sb, " [[position]]");
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

  append(sb, tprint("struct % {\n", struct_type.name));
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

  append(sb, tprint("struct % {\n", struct_type.name));
  color_i := 0;
  for * struct_type.members {
    if shader_type == .Vertex && it.name == "gl_FragCoord" continue;

    append(sb, "    ");
    print_metal_member_with_typename(sb, it);
    if member_has_note(it, "inbuilt") {
      if it.name == "gl_Position" append(sb, " [[position]]");
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
  append(sb, "& ", arg.name, " [[buffer(0)]]");
}

print_metal_local_bindings :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Procedure_Header, indent: s64) {
  in_struct_type := cast(*Type_Info_Struct) node.arguments[0].type_inst.result;
  for * in_struct_type.members {
    if node_is_fragment_shader(node) && it.name == "gl_Position" continue;

    add_indents(sb, indent);
    print_metal_type(sb, it.type);
    append(sb, " ", it.name, " = ", node.arguments[0].name, ".", it.name, ";\n");
  }

  if node.arguments.count >= 2 {
    un_struct_type := cast(*Type_Info_Struct) node.arguments[1].type_inst.result;
    for * un_struct_type.members {
      add_indents(sb, indent);
      print_metal_type(sb, it.type);
      append(sb, " ", it.name, " = ", node.arguments[1].name, ".", it.name, ";\n");
    }
  }

  out_struct_type := cast(*Type_Info_Struct) node.returns[0].type_inst.result;
  for * out_struct_type.members {
    if ctx.type == .Vertex && it.name == "gl_FragCoord" continue;

    add_indents(sb, indent);
    print_metal_type(sb, it.type);
    append(sb, " ", it.name, ";\n");
  }
  append(sb, "\n");
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
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
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
    if ret.type_inst
      print_metal_type(sb, ret.type_inst.result);
    else
      print_metal_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", header.name));
  for header.arguments {
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
          print_metal_type(sb, op.type_inst.result);
        else
          print_metal_type(sb, op.expression.type);
        append(sb, " ", op.name);

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
        if !lit.struct_literal_info.type_expression {
          compiler_report("Unfortunately, we can't easily know enough about types without the explicit name here.", make_location(lit));
          return;
        }

        name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
        append(sb, jai_to_metal_type_name(name.name));
        append(sb, "(");
        for lit.struct_literal_info.arguments {
          if it_index != 0 append(sb, ", ");
          print_metal_expr(ctx, sb, it);
        }
        append(sb, ")");
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
  print_metal_expr(ctx, sb, bn.left);
  space: string = ifx cast(u8) bn.operator_type == "." then "" else " ";
  append(sb, space, operator_string(bn.operator_type), space);
  print_metal_expr(ctx, sb, bn.right);
}

print_metal_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_metal_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}

print_metal_member_with_typename :: (sb: *String_Builder, thing: *Type_Info_Struct_Member) {
  print_metal_type(sb, thing.type);
  append(sb, " ", thing.name);
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
      append(sb, jai_to_metal_type_name(structtype.name));
    }
    case .VOID; append(sb, "void");

    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

#scope_file

check_arguments :: (using header: *Code_Procedure_Header, shader_type: Shader_Type) {
  if shader_type == {
  case .Compute;
    if returns.count != 1
      compiler_report("Metal Backend: Jai Compute Shader must return a structure", make_location(header));
    if arguments.count == 0
      compiler_report("Metal Backend: Jai Compute Shader must get AT LEAST 1 structure as an argument", make_location(header));
    if arguments[0].type_inst.result.type != .STRUCT
      compiler_report("Metal Backend: Jai Compute Shader must have a structure as the input", make_location(header));
  case .Vertex;
    if returns.count != 1
      compiler_report("Metal Backend: Jai Vertex Shader must return a structure", make_location(header));
    if arguments.count != 2
      compiler_report("Metal Backend: Jai Vertex Shader must get two structures as arguments (Vertex Input and Uniforms)", make_location(header));
    if parameter_usings.count != 2
      compiler_report("Metal Backend: The struct arguments to a Jai Vertex Shader must be marked 'using'", make_location(header));
  case .Fragment;
    if returns.count != 1
      compiler_report("Metal Backend: Jai Fragment Shader must return a structure", make_location(header));
    if arguments.count != 2
      compiler_report("Metal Backend: Jai Fragment Shader must get two structures as arguments (Vertex output and Uniforms)", make_location(header));
    if parameter_usings.count != 2
      compiler_report("Metal Backend: The struct arguments to a Jai Fragment Shader must be marked 'using'", make_location(header));
  }
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
