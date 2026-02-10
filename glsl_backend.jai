
GLSL_GRAPHICS_VERSION :: "#version 330 core\n";
GLSL_COMPUTE_VERSION  :: "#version 430 core\n";
GLSL_VULKAN_GRAPHICS_VERSION :: "#version 450 core\n";
GLSL_VULKAN_COMPUTE_VERSION  :: "#version 450 core\n";
GLSL_DEFAULT_LOCAL_SIZE_X :: 64;
GLSL_DEFAULT_LOCAL_SIZE_Y :: 1;
GLSL_DEFAULT_LOCAL_SIZE_Z :: 1;

write_glsl_shader_pair :: (pair_name: string, vertex_ctx: *Shader_Write_Context, fragment_ctx: *Shader_Write_Context, as_jai_string := true) -> string {
  write_glsl_shader(vertex_ctx, vertex_ctx.main_fn, .Vertex);
  write_glsl_shader(fragment_ctx, fragment_ctx.main_fn, .Fragment);

  vertex_source := write_glsl_shader_code(vertex_ctx, vertex_ctx.main_fn, as_jai_string=false);
  fragment_source := write_glsl_shader_code(fragment_ctx, fragment_ctx.main_fn, as_jai_string=false);

  sb: String_Builder;
  if as_jai_string {
    append(*sb, tprint("%_string", pair_name), " :: #string END\n");
  }

  append(*sb, "// Vertex Shader\n");
  append(*sb, vertex_source);
  append(*sb, "\n\n// Fragment Shader\n");
  append(*sb, fragment_source);

  if as_jai_string {
    append(*sb, "\nEND");
  }

  return builder_to_string(*sb);
}

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
  bindless_decl, _, has_bindless := find_bindless_param(node.header);
  if ctx.glsl_target == .VULKAN && !has_bindless {
    print_glsl_vulkan_uniform_local_bindings(*main_sb, node.header, indent=1);
  }
  if has_bindless {
    struct_type := cast(*Type_Info_Struct) bindless_decl.type_inst.result;
    add_indents(*main_sb, 1);
    append(*main_sb, tprint("% % = %(push_constants.%_addr);\n",
                            get_struct_type_name(struct_type),
                            bindless_decl.name,
                            get_struct_type_name(struct_type),
                            bindless_decl.name));
  }
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
  if ctx.type == .Compute {
    if ctx.glsl_target == .VULKAN append(*sb, GLSL_VULKAN_COMPUTE_VERSION);
    else append(*sb, GLSL_COMPUTE_VERSION);
  } else {
    if ctx.glsl_target == .VULKAN append(*sb, GLSL_VULKAN_GRAPHICS_VERSION);
    else append(*sb, GLSL_GRAPHICS_VERSION);
  }
  bindless_decl, _, has_bindless := find_bindless_param(node.header);
  if has_bindless {
    if ctx.glsl_target != .VULKAN
      compiler_report("GLSL Backend: Bindless params require Vulkan target", make_location(node.header));
    append(*sb, "#extension GL_EXT_buffer_reference : require\n");
    append(*sb, "#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require\n\n");
  }
  print_glsl_global_constants(*sb, node.header);
  if ctx.type == .Compute {
    print_glsl_compute_layout(*sb);
    print_glsl_compute_ssbo_bindings(*sb, node.header, use_vulkan_sets=ctx.glsl_target == .VULKAN);
  } else {
    if has_bindless print_glsl_bindless_param_definitions(*sb, node.header);
    print_glsl_in_vars(*sb, node.header, output_layout=ctx.glsl_target == .VULKAN);
    if !has_bindless print_glsl_uniforms(*sb, node.header, use_vulkan_ubo=ctx.glsl_target == .VULKAN);
    print_glsl_out_vars(*sb, node.header, output_layout=ctx.glsl_target == .VULKAN);
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


print_glsl_bindless_param_definitions :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  bindless_decl, binding, has_bindless := find_bindless_param(header);
  if !has_bindless return;
  if binding != 0
    compiler_report("GLSL Backend: Only @buffer(0) is currently supported for bindless params", make_location(bindless_decl));

  struct_type_generic := bindless_decl.type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Bindless param must be a struct", make_location(bindless_decl));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  ptr_type_names: [..] string;
  for *struct_type.members {
    if it.type.type != .POINTER continue;
    pointer := cast(*Type_Info_Pointer) it.type;
    if pointer.pointer_to.type == .STRUCT
      compiler_report("GLSL Backend: Bindless pointer-to-struct not yet supported", make_location(bindless_decl));

    ptr_name := glsl_ptr_type_name(pointer.pointer_to);
    already := false;
    for ptr_type_names if it == ptr_name { already = true; break; }
    if already continue;

    array_add(*ptr_type_names, ptr_name);
    append(sb, "layout(buffer_reference, std430) readonly buffer ", ptr_name, " {\n    ");
    append(sb, glsl_base_type_name(pointer.pointer_to), " data[];\n};\n\n");
  }

  append(sb, "layout(buffer_reference, std430) readonly buffer ", get_struct_type_name(struct_type), " {\n");
  for *struct_type.members {
    append(sb, "    ");
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "};\n\n");

  append(sb, "layout(push_constant) uniform PushConstants {\n    uint64_t ", bindless_decl.name, "_addr;\n} push_constants;\n\n");
}

print_glsl_compute_layout :: (sb: *String_Builder) {
  append(sb, tprint("layout(local_size_x = %, local_size_y = %, local_size_z = %) in;\n\n",
                    GLSL_DEFAULT_LOCAL_SIZE_X, GLSL_DEFAULT_LOCAL_SIZE_Y, GLSL_DEFAULT_LOCAL_SIZE_Z));
}

print_glsl_compute_ssbo_bindings :: (sb: *String_Builder, header: *Code_Procedure_Header, use_vulkan_sets := false) {
  next_binding: s64 = 0;
  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else it.expression.type;
    if declaration_is_parameter_using(header, it) continue;

    if arg_type.type != .POINTER
      compiler_report("GLSL Backend: Compute non-using arguments must currently be pointers (bound as SSBOs)", make_location(it));

    pointer := cast(*Type_Info_Pointer) arg_type;
    if pointer.pointer_to.type == .ARRAY
      compiler_report("GLSL Backend: Compute pointers to arrays are not supported. Use a pointer to element type.", make_location(it));

    if use_vulkan_sets
      append(sb, tprint("layout(std430, set = 0, binding = %) buffer %_Buffer {\n    ", next_binding, it.name));
    else
      append(sb, tprint("layout(std430, binding = %) buffer %_Buffer {\n    ", next_binding, it.name));
    print_glsl_type(sb, pointer.pointer_to);
    append(sb, tprint(" %[];\n};\n", it.name));
    next_binding += 1;
  }
  if next_binding != 0 append(sb, "\n");
}

glsl_compute_builtin_name :: (member: *Type_Info_Struct_Member, header: *Code_Procedure_Header) -> string {
  note_suffix, found := member_get_compute_builtin_note(member);
  if !found
    compiler_report("GLSL Backend: Compute using-struct members must have a supported @thread_* note", make_location(header));

  if note_suffix == {
    case "thread_position_in_grid"; return "gl_GlobalInvocationID";
    case "thread_position_in_threadgroup"; return "gl_LocalInvocationID";
    case "threadgroup_position_in_grid"; return "gl_WorkGroupID";
    case "thread_index_in_threadgroup"; return "gl_LocalInvocationIndex";
  }

  compiler_report(tprint("GLSL Backend: Unsupported compute builtin note @%", note_suffix), make_location(header));
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
    if member_is_stage_builtin(it) continue;
    
    if output_layout
      append(sb, tprint("layout (location=%) in ", it_index));
    else
      append(sb, "in ");
    
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_out_vars :: (sb : *String_Builder, node : *Code_Procedure_Header, output_layout := false) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Shader Output is not a struct\n", make_location(node.returns[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for * struct_type.members {
    if member_is_stage_builtin(it) continue;

    if output_layout
      append(sb, tprint("layout (location=%) out ", it_index));
    else
      append(sb, "out ");
    print_glsl_member_with_typename(sb, it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_uniforms :: (sb: *String_Builder, node: *Code_Procedure_Header, use_vulkan_ubo := false) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Shader Input is not a struct\n", make_location(node.arguments[1]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  if use_vulkan_ubo {
    if struct_type.members.count == 0 {
      append(sb, "\n");
      return;
    }

    arg_name := node.arguments[1].name;
    append(sb, "layout(set = 0, binding = 0) uniform ", get_struct_type_name(struct_type), "_Block {\n");
    for * struct_type.members {
      append(sb, "    ");
      print_glsl_member_with_typename(sb, it);
      append(sb, ";\n");
    }
    append(sb, "} ", arg_name, ";\n");
  } else {
    for * struct_type.members {
      append(sb, "uniform ");
      print_glsl_member_with_typename(sb, it);
      append(sb, ";\n");
    }
  }
  append(sb, "\n");
}

print_glsl_vulkan_uniform_local_bindings :: (sb: *String_Builder, header: *Code_Procedure_Header, indent: s64) {
  if header.arguments.count < 2 return;
  arg_name := header.arguments[1].name;

  struct_type_generic := header.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("GLSL Backend: Shader Input is not a struct\n", make_location(header.arguments[1]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;

  for * struct_type.members {
    add_indents(sb, indent);
    print_glsl_typed_name(sb, it.type, it.name);
    append(sb, " = ", arg_name, ".", it.name, ";\n");
  }
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



glsl_base_type_name :: (type: *Type_Info) -> string {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      return ifx inttype.signed then "int" else "uint";
    }
    case .FLOAT; return ifx type.runtime_size == 64 then "double" else "float";
    case .BOOL; return "bool";
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      return jai_to_glsl_type_name(get_struct_type_name(structtype));
    }
    case .VOID; return "void";
  }
  compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  return "<unsupported>";
}

glsl_ptr_type_name :: (element_type: *Type_Info) -> string {
  return tprint("Ptr_%", glsl_base_type_name(element_type));
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
      append(sb, jai_to_glsl_type_name(get_struct_type_name(structtype)));
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
    left_type := bn.left.type;
    _, _, has_bindless := find_bindless_param(ctx.main_fn.header);
    if has_bindless && left_type && left_type.type == .POINTER {
      print_glsl_expr(ctx, sb, bn.left);
      append(sb, ".data[");
      print_glsl_subscript_index_expr(ctx, sb, bn.right);
      append(sb, "]");
    } else {
      print_glsl_expr(ctx, sb, bn.left);
      append(sb, "[");
      print_glsl_subscript_index_expr(ctx, sb, bn.right);
      append(sb, "]");
    }
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
    append(sb, jai_to_glsl_type_name(get_struct_type_name(struct_type)));
  } else if lit.type.type == .STRUCT {
    struct_type := cast(*Type_Info_Struct) lit.type;
    append(sb, jai_to_glsl_type_name(get_struct_type_name(struct_type)));
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
// Shader intrinsics are provided by #import "ShaderFuncs".

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

  bindless_decl, _, has_bindless := find_bindless_param(header);
  if has_bindless {
    if arguments.count != 2 {
      if shader_type == .Fragment err("must get input struct and bindless params");
      else err("must get input struct and bindless params");
    }
    if parameter_usings.count != 1 {
      err("must have exactly one using struct argument when using bindless params");
    }

    in_arg := arguments[0];
    if !declaration_is_parameter_using(header, in_arg) err("first argument must be a using input struct");
    in_type := ifx in_arg.type_inst then in_arg.type_inst.result else in_arg.expression.type;
    if in_type.type != .STRUCT err("first argument must be a struct");

    bindless_type := ifx bindless_decl.type_inst then bindless_decl.type_inst.result else bindless_decl.expression.type;
    if bindless_type.type != .STRUCT err("bindless param must be a struct");
    if declaration_is_parameter_using(header, bindless_decl) err("bindless param must not be marked using");
  } else {
    if arguments.count != 2 {
      if shader_type == .Fragment err("must get two structures as arguments (Vertex output and Uniforms)");
      else err("must get two structures as arguments (Vertex Input and Uniforms)");
    }

    if parameter_usings.count != 2 {
      if shader_type == .Fragment err("must have struct arguments marked 'using'");
      else err("must have struct arguments marked 'using'");
    }
  }

  check_array_signature_support("GLSL", header);
  
}



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
