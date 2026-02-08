
GLSL_GRAPHICS_VERSION :: "#version 330 core\n";
GLSL_COMPUTE_VERSION  :: "#version 430 core\n";
GLSL_DEFAULT_LOCAL_SIZE_X :: 64;
GLSL_DEFAULT_LOCAL_SIZE_Y :: 1;
GLSL_DEFAULT_LOCAL_SIZE_Z :: 1;

// Short explanation...
// Every function is dumped to a separate string, which the Shader_Write_Context holds a list of
// The functions are appended onto the functions list, and then the for loop runs to push onto
// the main builder

write_glsl_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, shader_type: Shader_Type) -> string {
  check_arguments(node.header, shader_type);

  if shader_type == .Compute {
    return write_glsl_compute_shader(ctx, node);
  }

  // main function string builder
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_glsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });
  
  return write_glsl_shader_code(ctx, node);
}

write_glsl_compute_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_glsl_compute_local_bindings(*main_sb, node.header, indent=1);
  print_glsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  return write_glsl_shader_code(ctx, node);
}

write_glsl_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body, as_jai_string := true) -> string {
  sb: String_Builder;
  if as_jai_string {
    append(*sb, tprint("%_string", node.header.name), " :: #string END\n");
  }
  if ctx.type == .Compute append(*sb, GLSL_COMPUTE_VERSION);
  else append(*sb, GLSL_GRAPHICS_VERSION);
  print_glsl_global_constants(*sb, node.header);
  if ctx.type == .Compute {
    print_glsl_compute_layout(*sb);
    print_glsl_compute_ssbo_bindings(*sb, node.header);
  } else {
    print_glsl_in_vars(*sb, node.header, output_layout=false);
    print_glsl_uniforms(*sb, node.header);
    print_glsl_out_vars(*sb, node.header);
  }
  // Output prototypes for "late binding"
  for ctx.functions {
    if it.name != "main" print_glsl_prototype(*sb, it.prototype);
  }
  append(*sb, "\n");
  // Output code
  for ctx.functions {
    append(*sb, it.code, "\n");
  }
  if as_jai_string {
    append(*sb, "\nEND");
  }
  return builder_to_string(*sb);
}

print_glsl_compute_layout :: (sb: *String_Builder) {
  append(sb, tprint("layout(local_size_x = %, local_size_y = %, local_size_z = %) in;\n\n",
                    GLSL_DEFAULT_LOCAL_SIZE_X, GLSL_DEFAULT_LOCAL_SIZE_Y, GLSL_DEFAULT_LOCAL_SIZE_Z));
}

print_glsl_compute_ssbo_bindings :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  next_binding: s64 = 0;
  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if declaration_is_parameter_using(header, it) continue;

    if arg_type.type != .POINTER
      compiler_report("GLSL Backend: Compute non-using arguments must currently be pointers (bound as SSBOs)", make_location(it));

    pointer := cast(*Type_Info_Pointer) arg_type;
    if pointer.pointer_to.type == .ARRAY
      compiler_report("GLSL Backend: Compute pointers to arrays are not supported. Use a pointer to element type.", make_location(it));

    append(sb, tprint("layout(std430, binding = %) buffer %_Buffer {\n    ", next_binding, it.name));
    print_glsl_type(sb, pointer.pointer_to);
    append(sb, tprint(" %[];\n};\n", it.name));
    next_binding += 1;
  }
  if next_binding != 0 append(sb, "\n");
}

glsl_compute_builtin_name :: (member: *Type_Info_Struct_Member, header: *Code_Procedure_Header) -> string {
  note_suffix, found := member_get_note_suffix(member, "inbuilt_");
  if !found
    compiler_report("GLSL Backend: Compute using-struct members must have @inbuilt_* notes", make_location(header));

  if note_suffix == {
    case "thread_position_in_grid"; return "gl_GlobalInvocationID";
    case "thread_position_in_threadgroup"; return "gl_LocalInvocationID";
    case "threadgroup_position_in_grid"; return "gl_WorkGroupID";
    case "thread_index_in_threadgroup"; return "gl_LocalInvocationIndex";
  }

  compiler_report(tprint("GLSL Backend: Unsupported compute builtin note @inbuilt_%", note_suffix), make_location(header));
  return "";
}

print_glsl_compute_local_bindings :: (sb: *String_Builder, header: *Code_Procedure_Header, indent: s64) {
  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if !declaration_is_parameter_using(header, it) continue;

    if arg_type.type != .STRUCT
      compiler_report("GLSL Backend: Compute using arguments must be structs", make_location(it));

    struct_type := cast(*Type_Info_Struct) arg_type;
    for * struct_type.members {
      add_indents(sb, indent);
      print_glsl_typed_name(sb, it.type, it.name);
      append(sb, " = ", glsl_compute_builtin_name(it, header), ";\n");
    }
  }
}


// In, Out, Uniforms, and Prototypes

print_glsl_in_vars :: (sb: *String_Builder, node: *Code_Procedure_Header, output_layout := true) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("GLSL Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for * struct_type.members {
    if member_has_note(it, "inbuilt") continue;
    
    if output_layout
      append(sb, tprint("layout (location=%) in ", it_index));
    else
      append(sb, "in ");
    
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_out_vars :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Shader Output is not a struct\n", make_location(node.returns[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for * struct_type.members {
    if member_has_note(it, "inbuilt") continue;
    
    append(sb, "out ");
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_uniforms :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Shader Input is not a struct\n", make_location(node.arguments[1]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for * struct_type.members {
    append(sb, "uniform ");
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    report_array_return_not_supported("GLSL", ret);
    if ret.type_inst
      print_glsl_type(sb, ret.type_inst.result);
    else
      print_glsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", header.name));
  for header.arguments {
    report_array_parameter_not_supported("GLSL", it);
    if it.type_inst
      print_glsl_type(sb, it.type_inst.result);
    else
      print_glsl_type(sb, it.expression.type);
    
    append(sb, " ", it.name);
    
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}

print_glsl_member_with_typename :: (sb: *String_Builder, thing: *Type_Info_Struct_Member) {
  print_glsl_typed_name(sb, thing.type, thing.name);
}

print_glsl_type :: (sb: *String_Builder, type: *Type_Info) {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      append(sb, ifx inttype.signed then "int" else "uint");
    }
    case .FLOAT; append(sb, ifx type.runtime_size == 64 then "double" else "float");
    case .BOOL; append(sb, "bool");
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      append(sb, jai_to_glsl_type_name(structtype.name));
    }
    case .VOID; append(sb, "void");
    
    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

print_glsl_typed_name :: (sb: *String_Builder, type: *Type_Info, name: string) {
  base_type, array_suffix := split_array_type_and_suffix("GLSL", type);
  print_glsl_type(sb, base_type);
  append(sb, " ", name, array_suffix);
}


// The big boy, statement converter
print_glsl_stmt :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        
        op := cast(*Code_Declaration) it;
        
        if op.type_inst
          print_glsl_typed_name(sb, op.type_inst.result, op.name);
        else
          print_glsl_typed_name(sb, op.expression.type, op.name);
        
        if op.expression {
          append(sb, " = ");
          print_glsl_expr(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }
      
      case .BINARY_OPERATOR; {
        op := cast(*Code_Binary_Operator) it;
        add_indents(sb, indent);
        print_glsl_binary_operator(ctx, sb, op);
        append(sb, ";\n");
      }
      
      case .IF; {
        op := cast(*Code_If) it;
        add_indents(sb, indent);
        
        if op.if_flags & .IS_SWITCH_STATEMENT {
          // GLSL switches only allow Integers for some reason, so we'll transpile other
          // things as a simple if-else chain
          if op.condition.type.type == .INTEGER {
            append(sb, "switch (");
            print_glsl_expr(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
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
              print_glsl_expr(ctx, sb, op.condition);
              append(sb, " == ");
              print_glsl_expr(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_glsl_stmt(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              
              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else append(sb, "} else ");
              
              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_glsl_stmt(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_glsl_expr(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_glsl_stmt(ctx, sb, op.else_block, indent=indent+1);
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
          print_glsl_expr(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }
      
      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_glsl_expr(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_glsl_stmt(ctx, sb, op.block, indent=indent+1);
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
        print_glsl_expr(ctx, sb, op.iteration_expression);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_glsl_expr(ctx, sb, op.iteration_expression_right);
        append(sb, "; ", op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_glsl_stmt(ctx, sb, op.block, indent=indent+1);
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
          print_glsl_expr(ctx, sb, op.arguments_sorted[0]);
          append(sb, ";\n");
        } else
          compiler_report("Multiple Return Arguments Disallowed in Jai Shaders", make_location(op));
      }
      
      case .PROCEDURE_CALL; {
        add_indents(sb, indent);
        
        pc := cast(*Code_Procedure_Call) node;
        if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
          compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
        name := cast(*Code_Ident) pc.procedure_expression;
        if !table_contains(*INBUILT_FUNCTIONS, name.name)
          handle_custom_procedure_call(ctx, sb, xx it);
        print_glsl_procedure_call(ctx, sb, xx it);
        
        append(sb, ";\n");
      }
      
      // Ignore the using statements in the shader
      case .USING; continue;
      
      case; {
        compiler_report(tprint("The statement of type '%' is not supported in Jai Shaders", it.kind), make_location(it));
      }
    }
  }
}

// Expressions. All expressions are "supported".
// Most of them are not converted to GLSL currently however.
// Will have to add specific things for many of these
// We can't simply print_expression in many of them because a struct literal could be a subexpression
// which has to be converted correctly
print_glsl_expr :: (using ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  if node.kind == {
    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        print_glsl_struct_literal(ctx, sb, lit);
      } else if lit.value_type == .ARRAY {
        print_glsl_array_literal(ctx, sb, lit);
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_glsl_expr(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_glsl_binary_operator(ctx, sb, bn);
    }
    
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
        compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
      
      name := cast(*Code_Ident) pc.procedure_expression;
      if !table_contains(*INBUILT_FUNCTIONS, name.name)
        handle_custom_procedure_call(ctx, sb, xx node);
      print_glsl_procedure_call(ctx, sb, xx node);
    }
    
    case; PP.print_expression(sb, node);
  }
}

print_glsl_binary_operator :: (ctx: *Shader_Write_Context, sb: *String_Builder, bn: *Code_Binary_Operator) {
  if bn.operator_type == .ARRAY_SUBSCRIPT {
    print_glsl_expr(ctx, sb, bn.left);
    append(sb, "[");
    print_glsl_subscript_index_expr(ctx, sb, bn.right);
    append(sb, "]");
    return;
  }

  print_glsl_expr(ctx, sb, bn.left);
  space := " ";
  if bn.operator_type == cast(Operator_Type) #char "." space = "";
  append(sb, space, operator_string(bn.operator_type), space);
  print_glsl_expr(ctx, sb, bn.right);
}

print_glsl_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_glsl_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}


print_glsl_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    report_array_return_not_supported("GLSL", ret);
    if ret.type_inst
      print_glsl_type(sb, ret.type_inst.result);
    else
      print_glsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    report_array_parameter_not_supported("GLSL", it);
    if it.type_inst
      print_glsl_type(sb, it.type_inst.result);
    else
      print_glsl_type(sb, it.expression.type);
    
    append(sb, " ", it.name);
    
    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_glsl_stmt(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

print_glsl_array_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal) {
  info := lit.array_literal_info;
  if !info.element_type {
    compiler_report("GLSL Backend: Untyped array literals are currently unsupported in Jai Shaders", make_location(lit));
    return;
  }

  print_glsl_array_constructor_type(sb, info.element_type.result);
  append(sb, "[](");
  for info.array_members {
    if it_index != 0 append(sb, ", ");
    print_glsl_array_member_expr(ctx, sb, it, info.element_type.result);
  }
  append(sb, ")");
}

print_glsl_array_constructor_type :: (sb: *String_Builder, type: *Type_Info) {
  base_type, array_suffix := split_array_type_and_suffix("GLSL", type);
  print_glsl_type(sb, base_type);
  append(sb, array_suffix);
}

print_glsl_array_member_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node, expected_type: *Type_Info) {
  if node.kind == .LITERAL {
    lit := cast(*Code_Literal) node;
    if lit.value_type == .STRUCT {
      print_glsl_struct_literal(ctx, sb, lit, expected_type);
      return;
    }
  }
  print_glsl_expr(ctx, sb, node);
}

print_glsl_struct_literal :: (ctx: *Shader_Write_Context, sb: *String_Builder, lit: *Code_Literal, expected_type: *Type_Info = null) {
  if lit.struct_literal_info.type_expression {
    name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
    append(sb, jai_to_glsl_type_name(name.name));
  } else if expected_type && expected_type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) expected_type;
    append(sb, jai_to_glsl_type_name(struct_type.name));
  } else if lit.type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) lit.type;
    append(sb, jai_to_glsl_type_name(struct_type.name));
  } else {
    compiler_report("Unfortunately, we can't easily know enough about types without the explicit name here.", make_location(lit));
    return;
  }

  append(sb, "(");
  for lit.struct_literal_info.arguments {
    if it_index != 0 append(sb, ", ");
    print_glsl_expr(ctx, sb, it);
  }
  append(sb, ")");
}

print_glsl_subscript_index_expr :: (ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  inner: String_Builder;
  print_glsl_expr(ctx, *inner, node);
  expr := strip_redundant_outer_parens(builder_to_string(*inner));
  append(sb, expr);
}

#scope_file

// This is some hardcoding, and is incomplete.
// More types need to be added here
jai_to_glsl_type_map :: #run -> Table(string, string) {
  ret: Table(string, string);
  table_add(*ret, "s32", "int");
  table_add(*ret, "u32", "uint");
  table_add(*ret, "float32", "float");
  table_add(*ret, "float64", "double");
  table_add(*ret, "Vector2", "vec2");
  table_add(*ret, "Vector3", "vec3");
  table_add(*ret, "Vector4", "vec4");
  table_add(*ret, "IVector2", "ivec2");
  table_add(*ret, "IVector3", "ivec3");
  table_add(*ret, "IVector4", "ivec4");
  table_add(*ret, "UVector2", "uvec2");
  table_add(*ret, "UVector3", "uvec3");
  table_add(*ret, "UVector4", "uvec4");
  table_add(*ret, "BVector2", "bvec2");
  table_add(*ret, "BVector3", "bvec3");
  table_add(*ret, "BVector4", "bvec4");
  table_add(*ret, "Matrix2", "mat2");
  table_add(*ret, "Matrix3", "mat3");
  table_add(*ret, "Matrix4", "mat4");
  table_add(*ret, "Sampler1D", "sampler1D");
  table_add(*ret, "Sampler2D", "sampler2D");
  table_add(*ret, "Sampler3D", "sampler3D");
  return ret;
}
jai_to_glsl_type_name :: (in: string) -> string {
  success, val := table_find(*jai_to_glsl_type_map, in);
  return ifx success then val else in;
}

//~
// Here are some functions that glsl supports
// Unfortunately this is going to mean that you have to import this module in the places where
// you want to use these functions.
#scope_export

floor :: inline (v: Vector2) -> Vector2 { return Vector2.{ floor(v.x), floor(v.y) }; }
floor :: inline (v: Vector3) -> Vector3 { return Vector3.{ floor(v.x), floor(v.y), floor(v.z) }; }
floor :: inline (v: Vector4) -> Vector4 { return Vector4.{ floor(v.x), floor(v.y), floor(v.z), floor(v.w) }; }


radians :: inline (degrees: $T) -> T {
  #assert T == float || T == float64;
  return degrees * xx (3.1415926535/ 180);
}
radians :: inline (v: Vector2) -> Vector2 { return Vector2.{ radians(v.x), radians(v.y) }; }
radians :: inline (v: Vector3) -> Vector3 { return Vector3.{ radians(v.x), radians(v.y), radians(v.z) }; }
radians :: inline (v: Vector4) -> Vector4 { return Vector4.{ radians(v.x), radians(v.y), radians(v.z), radians(v.w) }; }

degrees :: inline (radians: $T) -> T {
  #assert T == float || T == float64;
  return radians * xx (180 / 3.1415926535);
}
degrees :: inline (v: Vector2) -> Vector2 { return Vector2.{ degrees(v.x), degrees(v.y) }; }
degrees :: inline (v: Vector3) -> Vector3 { return Vector3.{ degrees(v.x), degrees(v.y), degrees(v.z) }; }
degrees :: inline (v: Vector4) -> Vector4 { return Vector4.{ degrees(v.x), degrees(v.y), degrees(v.z), degrees(v.w) }; }

exp2 :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return xx pow(2, x);
}
exp2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ exp2(v.x), exp2(v.y) }; }
exp2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ exp2(v.x), exp2(v.y), exp2(v.z) }; }
exp2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ exp2(v.x), exp2(v.y), exp2(v.z), exp2(v.w) }; }

fma :: inline (a: $T, b: T, c: T) -> T {
  #assert T == float || T == float64;
  return a * b + c;
}
fma :: inline (a: Vector2, b: Vector2, c: Vector2) -> Vector2 { return Vector2.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y) }; }
fma :: inline (a: Vector3, b: Vector3, c: Vector3) -> Vector3 { return Vector3.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z) }; }
fma :: inline (a: Vector4, b: Vector4, c: Vector4) -> Vector4 { return Vector4.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z), fma(a.w, b.w, c.w) }; }

fract :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return x - floor(x);
}
fract :: inline (v: Vector2) -> Vector2 { return Vector2.{ fract(v.x), fract(v.y) }; }
fract :: inline (v: Vector3) -> Vector3 { return Vector3.{ fract(v.x), fract(v.y), fract(v.z) }; }
fract :: inline (v: Vector4) -> Vector4 { return Vector4.{ fract(v.x), fract(v.y), fract(v.z), fract(v.w) }; }

inversesqrt :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return 1 / sqrt(x);
}
inversesqrt :: inline (v: Vector2) -> Vector2 { return Vector2.{ inversesqrt(v.x), inversesqrt(v.y) }; }
inversesqrt :: inline (v: Vector3) -> Vector3 { return Vector3.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z) }; }
inversesqrt :: inline (v: Vector4) -> Vector4 { return Vector4.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z), inversesqrt(v.w) }; }

log2 :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return log(x) / log(2);
}
log2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ log2(v.x), log2(v.y) }; }
log2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ log2(v.x), log2(v.y), log2(v.z) }; }
log2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ log2(v.x), log2(v.y), log2(v.z), log2(v.w) }; }

mix :: (x: $T, y: T, t: $M) -> T #expand {
  #assert (T == float || T == float64) && (M == float || M == float64 || M == bool);
  return lerp(x, y, xx t);
}
mix :: inline (a: Vector2, b: Vector2, m: BVector2) -> Vector2 { return Vector2.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y) }; }
mix :: inline (a: Vector3, b: Vector3, m: BVector3) -> Vector3 { return Vector3.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z) }; }
mix :: inline (a: Vector4, b: Vector4, m: BVector4) -> Vector4 { return Vector4.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z), mix(a.w, b.w, m.w) }; }

mod :: inline (x: $T, y: T) -> T {
  #assert T == float || T == float64;
  return x - y * floor(x / y);
}
mod :: inline (a: Vector2, b: Vector2) -> Vector2 { return Vector2.{ mod(a.x, b.x), mod(a.y, b.y) }; }
mod :: inline (a: Vector3, b: Vector3) -> Vector3 { return Vector3.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z) }; }
mod :: inline (a: Vector4, b: Vector4) -> Vector4 { return Vector4.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z), mod(a.w, b.w) }; }

round :: (x: $T) -> T {
  #assert T == float || T == float64;
  if x - floor(x) > 0.5 return ceil(x);
  else return floor(x);
}
round :: inline (v: Vector2) -> Vector2 { return Vector2.{ round(v.x), round(v.y) }; }
round :: inline (v: Vector3) -> Vector3 { return Vector3.{ round(v.x), round(v.y), round(v.z) }; }
round :: inline (v: Vector4) -> Vector4 { return Vector4.{ round(v.x), round(v.y), round(v.z), round(v.w) }; }

roundEven :: (x: $T) -> T {
  #assert T == float || T == float64;
  pivot := x - floor(x);
  if pivot > 0.5 return ceil(x);
  else if pivot < 0.5 return floor(x);
  else return ifx is_even(ceil(x)) then ceil(x) else floor(x);
}
roundEven :: inline (v: Vector2) -> Vector2 { return Vector2.{ roundEven(v.x), roundEven(v.y) }; }
roundEven :: inline (v: Vector3) -> Vector3 { return Vector3.{ roundEven(v.x), roundEven(v.y), roundEven(v.z) }; }
roundEven :: inline (v: Vector4) -> Vector4 { return Vector4.{ roundEven(v.x), roundEven(v.y), roundEven(v.z), roundEven(v.w) }; }

sign :: (x: $T) -> T
#modify { return is_number(T); }
{
  if x == 0 return 0;
  return ifx x < 0 then -1 else xx 1;
}
sign :: inline (v: $T) -> T { #assert T == Vector2 || T == IVector2 || T == UVector2; return Vector2.{ sign(v.x), sign(v.y) }; }
sign :: inline (v: $T) -> T { #assert T == Vector3 || T == IVector3 || T == UVector3; return Vector3.{ sign(v.x), sign(v.y), sign(v.z) }; }
sign :: inline (v: $T) -> T { #assert T == Vector4 || T == IVector4 || T == UVector4; return Vector4.{ sign(v.x), sign(v.y), sign(v.z), sign(v.w) }; }

smoothstep :: inline (edge0: $T, edge1: T, x: T) -> T {
  #assert T == float || T == float64;
  t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
smoothstep :: inline (a: Vector2, b: Vector2, t: Vector2) -> Vector2 { return Vector2.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y) }; }
smoothstep :: inline (a: Vector3, b: Vector3, t: Vector3) -> Vector3 { return Vector3.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z) }; }
smoothstep :: inline (a: Vector4, b: Vector4, t: Vector4) -> Vector4 { return Vector4.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z), smoothstep(a.w, b.w, t.w) }; }

step :: (x: $T, pivot: T) -> T {
  #assert T == float || T == float64;
  return ifx x < pivot then 0.0 else 1.0;
}
step :: inline (v: Vector2, s: Vector2) -> Vector2 { return Vector2.{ step(v.x, s.x), step(v.y, s.y) }; }
step :: inline (v: Vector3, s: Vector3) -> Vector3 { return Vector3.{ step(v.x, s.x), step(v.y, s.y), step(v.z, s.z) }; }
step :: inline (v: Vector4, s: Vector4) -> Vector4 { return Vector4.{ step(v.x, s.x), step(v.y, s.y), step(v.z, s.z), step(v.w, s.w) }; }

trunc :: inline (x: $T) -> T { #assert T == float || T == float64; return floor(x); };
trunc :: inline (v: Vector2) -> Vector2 { return Vector2.{ trunc(v.x), trunc(v.y) }; }
trunc :: inline (v: Vector3) -> Vector3 { return Vector3.{ trunc(v.x), trunc(v.y), trunc(v.z) }; }
trunc :: inline (v: Vector4) -> Vector4 { return Vector4.{ trunc(v.x), trunc(v.y), trunc(v.z), trunc(v.w) }; }

equal :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x == b.x, a.y == b.y }; }
equal :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x == b.x, a.y == b.y, a.z == b.z }; }
equal :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x == b.x, a.y == b.y, a.z == b.z, a.w == b.w }; }

faceforward :: inline (N: $T, I: T, Nref: T) -> T {
  return T == Vector2 || T == Vector3 || T == Vector4;
  return ifx dot(Nref, I) < 0 then N else -N;
}

normalize :: inline (v: $T) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  return v / length(v);
}

notEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x != b.x, a.y != b.y }; }
notEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x != b.x, a.y != b.y, a.z != b.z }; }
notEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x != b.x, a.y != b.y, a.z != b.z, a.w != b.w }; }

reflect :: (I: $T, N: T) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  return I - 2 * dot(N, I) * N;
}

refract :: (I: $T, N: T, eta: float) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  k := 1.0 - eta * eta * (1.0 - dot(N, I) * dot(N, I));
  if (k < 0.0)
      return .{};
  else
      return eta * I - (eta * dot(N, I) + sqrt(k)) * N;
}

all :: inline (v: BVector2) -> bool { return v.x && v.y; }
all :: inline (v: BVector3) -> bool { return v.x && v.y && v.z; }
all :: inline (v: BVector4) -> bool { return v.x && v.y && v.z && v.w; }
any :: inline (v: BVector2) -> bool { return v.x || v.y; }
any :: inline (v: BVector3) -> bool { return v.x || v.y || v.z; }
any :: inline (v: BVector4) -> bool { return v.x || v.y || v.z || v.w; }
greaterThan :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x > b.x, a.y > b.y }; }
greaterThan :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x > b.x, a.y > b.y, a.z > b.z }; }
greaterThan :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector3.{ a.x > b.x, a.y > b.y, a.z > b.z, a.w > b.w }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x >= b.x, a.y >= b.y }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x >= b.x, a.y >= b.y, a.z >= b.z }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector3.{ a.x >= b.x, a.y >= b.y, a.z >= b.z, a.w >= b.w }; }
lessThan :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x < b.x, a.y < b.y }; }
lessThan :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x < b.x, a.y < b.y, a.z < b.z }; }
lessThan :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector3.{ a.x < b.x, a.y < b.y, a.z < b.z, a.w < b.w }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x <= b.x, a.y <= b.y }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x <= b.x, a.y <= b.y, a.z <= b.z }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector3.{ a.x <= b.x, a.y <= b.y, a.z <= b.z, a.w <= b.w }; }
not :: inline (v: BVector2) -> BVector2 { return BVector2.{ !v.x, !v.y }; }
not :: inline (v: BVector3) -> BVector3 { return BVector3.{ !v.x, !v.y, !v.z }; }
not :: inline (v: BVector4) -> BVector4 { return BVector4.{ !v.x, !v.y, !v.z, !v.w }; }


texture :: (sampler: $T, point: $S, bias: float = 0) -> Vector4 { 
  #assert (T == Sampler1D && S == float) || (T == Sampler2D && S == Vector2) || (T == Sampler3D && S == Vector3);
}



//~ Types and Helpers for GLSL


#scope_file

print_glsl_global_constants :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if !header.constants_block return;
  for header.constants_block.statements {
    if it.kind != .DECLARATION continue;
    decl := cast(*Code_Declaration) it;
    if !(decl.flags & .IS_GLOBAL) continue;
    if !(decl.flags & .IS_CONSTANT)
      compiler_report("GLSL Backend: Only global constant declarations are currently supported in Jai Shaders", make_location(decl));

    append(sb, "const ");
    if decl.type_inst
      print_glsl_typed_name(sb, decl.type_inst.result, decl.name);
    else
      print_glsl_typed_name(sb, decl.expression.type, decl.name);

    if decl.expression {
      append(sb, " = ");
      print_glsl_expr(xx null, sb, decl.expression);
    }
    append(sb, ";\n");
  }
  if header.constants_block.statements.count != 0 append(sb, "\n");
}

check_arguments :: (using header: *Code_Procedure_Header, shader_type: Shader_Type) {
  err :: (msg: string) #expand {
    compiler_report(tprint("GLSL Backend: Jai % Shader %", shader_type, msg), make_location(header));
  }

  if shader_type == .Compute {
    if returns.count != 0 {
      err("must return no values");
    }

    if arguments.count < 1 {
      err("must have at least one argument (using input struct + optional pointer buffers)");
    }

    if parameter_usings.count < 1 {
      err("must have a using struct argument for compute builtins");
    }

    for arguments {
      arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
      if declaration_is_parameter_using(header, it) {
        if arg_type.type != .STRUCT
          err("using arguments must be structs");
      } else {
        if arg_type.type != .POINTER
          err("non-using arguments must currently be pointers");
      }
    }

    check_array_signature_support("GLSL", header);
    return;
  }

  if returns.count != 1 {
    if shader_type == .Fragment err("must return a structure with at least one Vector4");
    else err("must return a structure with at least a Vector4 gl_Position field");
  }

  if arguments.count != 2 {
    if shader_type == .Fragment err("must get two structures as arguments (Vertex output and Uniforms)");
    else err("must get two structures as arguments (Vertex Input and Uniforms)");
  }

  if parameter_usings.count != 2 {
    if shader_type == .Fragment err("must have struct arguments marked 'using'");
    else err("must have struct arguments marked 'using'");
  }

  check_array_signature_support("GLSL", header);
  
}


is_number :: (T: Type) -> bool {
  return T == float ||
         T == float64 ||
         T == int ||
         T == s8  ||
         T == s16 ||
         T == s32 ||
         T == s64 ||
         T == u8  ||
         T == u16 ||
         T == u32 ||
         T == u64;
}
is_even :: (v: float) -> bool   { return (cast(s32) floor(v)) % 2 == 0; }
is_even :: (v: float64) -> bool { return (cast(s32) floor(v)) % 2 == 0; }

INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  "sin", "cos", "tan", "asin", "acos", "atan",
  "degrees", "radians",
  
  "abs", "ceil", "exp", "exp2", "floor", "isinf", "isnan", "log", "log2", "max", "min",
  "mix", "mod", "pow", "round", "roundEven", "sign", "smoothstep", "sqrt", "step", "trunc",
  
  "cross", "distance", "dot", "equal", "faceforward", "length", "normalize", "notEqual",
  "all", "any", "greaterThan", "lessThan", "greaterThanEqual", "lessThanEqual", "not",
  
  "texture",
  
  "reflect", "refract", "fract",
  
  // These don't exist in jai yet and I have no idea how to implement them efficiently :P
  // "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
  // "dFdx", "dFdy", "fwidth", "noise1", "noise2", "noise3", "noise4",
  
  // These require higher glsl versions than 3.3 which is hardcoded for now
  // "fma",
  // "interpolateAtCentroid", "interpolateAtOffset", "interpolateAtSample",
  
  // These require "out" parameters, which haven't been implemented yet
  // "modf"
];
// This is an obvious case for a HashSet... but whatever
INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
// END
