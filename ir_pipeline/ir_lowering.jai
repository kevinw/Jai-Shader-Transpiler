IR_Field :: struct {
  name: string;
  type_name: string;
  semantic: string;
}

IR_Struct :: struct {
  name: string;
  fields: [..] IR_Field;
}

IR_Vertex_Shader :: struct {
  source_name: string;
  entry_name: string;
  input: IR_Struct;
  output: IR_Struct;
  assignments: [..] IR_Assignment;
}

IR_Fragment_Shader :: struct {
  source_name: string;
  entry_name: string;
  input: IR_Struct;
  output: IR_Struct;
  assignments: [..] IR_Assignment;
}

IR_Compute_Buffer :: struct {
  name: string;
  element_type_name: string;
}

IR_Function_Arg :: struct {
  name: string;
  type_name: string;
}

IR_Helper_Function :: struct {
  name: string;
  return_type_name: string;
  args: [..] IR_Function_Arg;
  body_lines: [..] string;
}

IR_Compute_Shader :: struct {
  source_name: string;
  entry_name: string;
  input: IR_Struct;
  buffers: [..] IR_Compute_Buffer;
  helpers: [..] IR_Helper_Function;
  body_lines: [..] string;
}

IR_Assignment :: struct {
  output_field: string;
  rhs_expr: string;
}

ir_type_to_slang_name :: (type: *Type_Info) -> (string, bool) {
  if !type return "", false;

  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      return ifx inttype.signed then "int" else "uint", true;
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

ir_lower_struct_from_type :: (name: string, type: *Type_Info) -> (IR_Struct, bool) {
  out: IR_Struct;
  out.name = name;

  if !type || type.type != .STRUCT return out, false;

  struct_type := cast(*Type_Info_Struct) type;
  for *struct_type.members {
    type_name, ok := ir_type_to_slang_name(it.type);
    if !ok return out, false;
    field_semantic := member_get_semantic(it);
    array_add(*out.fields, .{
      name = it.name,
      type_name = type_name,
      semantic = field_semantic,
    });
  }

  return out, true;
}

ir_struct_has_field :: (s: *IR_Struct, name: string) -> bool {
  for s.fields if it.name == name return true;
  return false;
}

ir_field_type_name :: (s: *IR_Struct, name: string) -> string {
  for s.fields if it.name == name return it.type_name;
  return "";
}

ir_name_in_list :: (names: [] string, name: string) -> bool {
  for names if it == name return true;
  return false;
}

ir_binary_operator_to_slang :: (op: Operator_Type) -> string {
  if op == .SHIFT_LEFT return "<<";
  if op == .SHIFT_RIGHT return ">>";
  return operator_string(op);
}

ir_rewrite_simple_cast_expression :: (expr: string) -> string {
  trimmed := trim_ascii_whitespace(expr);
  if !begins_with(trimmed, "cast(") return expr;

  close_paren: s64 = -1;
  for i: 0..trimmed.count-1 {
    if trimmed[i] == #char ")" {
      close_paren = i;
      break;
    }
  }
  if close_paren == -1 return expr;

  type_name: string;
  type_name.data = trimmed.data + 5; // after "cast("
  type_name.count = close_paren - 5;
  type_name = trim_ascii_whitespace(type_name);
  if type_name.count == 0 return expr;

  rhs: string;
  rhs.data = trimmed.data + close_paren + 1;
  rhs.count = trimmed.count - (close_paren + 1);
  rhs = trim_ascii_whitespace(rhs);
  if rhs.count == 0 return expr;

  mapped_type := jai_to_hlsl_type_name(type_name);
  return tprint("((%)(%))", mapped_type, rhs);
}

ir_expr_to_slang :: (node: *Code_Node, input_fields: [] string, output_fields: [] string) -> (string, bool) {
  if !node return "", false;

  if node.kind == {
    case .IDENT; {
      ident := cast(*Code_Ident) node;
      if ident.name == "input" || ident.name == "o" || ident.name == "un" return ident.name, true;
      if ir_name_in_list(input_fields, ident.name) return tprint("input.%", ident.name), true;
      if ir_name_in_list(output_fields, ident.name) return tprint("o.%", ident.name), true;
      return ident.name, true;
    }

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        constructor_name := "";
        if lit.struct_literal_info.type_expression && lit.struct_literal_info.type_expression.type_valued_expression && lit.struct_literal_info.type_expression.type_valued_expression.kind == .IDENT {
          type_ident := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
          constructor_name = jai_to_hlsl_type_name(type_ident.name);
        } else if lit.type && lit.type.type == .STRUCT {
          struct_type := cast(*Type_Info_Struct) lit.type;
          constructor_name = jai_to_hlsl_type_name(get_struct_type_name(struct_type));
        }

        if constructor_name.count == 0 return "", false;

        b: String_Builder;
        append(*b, constructor_name, "(");
        for lit.struct_literal_info.arguments {
          arg_text, ok := ir_expr_to_slang(it, input_fields, output_fields);
          if !ok return "", false;
          if it_index != 0 append(*b, ", ");
          append(*b, arg_text);
        }
        append(*b, ")");
        return builder_to_string(*b), true;
      }

      b: String_Builder;
      PP.print_expression(*b, node);
      return builder_to_string(*b), true;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      inner, ok := ir_expr_to_slang(un.subexpression, input_fields, output_fields);
      if !ok return "", false;
      return tprint("%%", operator_string(un.operator_type), inner), true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      left, left_ok := ir_expr_to_slang(bn.left, input_fields, output_fields);
      if !left_ok return "", false;
      if bn.operator_type == .ARRAY_SUBSCRIPT {
        right, right_ok := ir_expr_to_slang(bn.right, input_fields, output_fields);
        if !right_ok return "", false;
        return tprint("%[%]", left, right), true;
      }
      op := ir_binary_operator_to_slang(bn.operator_type);
      if op == "." {
        if bn.right && bn.right.kind == .IDENT {
          right_ident := cast(*Code_Ident) bn.right;
          return tprint("%.%", left, right_ident.name), true;
        }
        right, right_ok := ir_expr_to_slang(bn.right, input_fields, output_fields);
        if !right_ok return "", false;
        return tprint("%.%", left, right), true;
      }
      right, right_ok := ir_expr_to_slang(bn.right, input_fields, output_fields);
      if !right_ok return "", false;
      return tprint("(% % %)", left, op, right), true;
    }

    case .PROCEDURE_CALL; {
      b: String_Builder;
      PP.print_expression(*b, node);
      raw := builder_to_string(*b);
      return ir_rewrite_simple_cast_expression(raw), true;
    }
  }

  b: String_Builder;
  PP.print_expression(*b, node);
  raw := builder_to_string(*b);
  return ir_rewrite_simple_cast_expression(raw), true;
}

ir_collect_vertex_assignments :: (ctx: *Shader_Write_Context, shader: *IR_Vertex_Shader) -> bool {
  if !ctx || !shader return false;
  header := ctx.main_fn.header;
  if !header || !header.body_or_null || !header.body_or_null.block return true;

  input_field_names: [..] string;
  output_field_names: [..] string;
  for shader.input.fields array_add(*input_field_names, it.name);
  for shader.output.fields array_add(*output_field_names, it.name);

  for header.body_or_null.block.statements {
    if it.kind != .BINARY_OPERATOR continue;
    bn := cast(*Code_Binary_Operator) it;
    if operator_string(bn.operator_type) != "=" continue;
    if !bn.left || bn.left.kind != .IDENT continue;

    lhs := cast(*Code_Ident) bn.left;
    if !ir_struct_has_field(*shader.output, lhs.name) continue;

    rhs_expr, ok := ir_expr_to_slang(bn.right, input_field_names, output_field_names);
    if !ok return false;
    array_add(*shader.assignments, .{
      output_field = lhs.name,
      rhs_expr = rhs_expr,
    });
  }

  return true;
}

ir_collect_fragment_assignments :: (ctx: *Shader_Write_Context, shader: *IR_Fragment_Shader) -> bool {
  if !ctx || !shader return false;
  header := ctx.main_fn.header;
  if !header || !header.body_or_null || !header.body_or_null.block return true;

  input_field_names: [..] string;
  output_field_names: [..] string;
  for shader.input.fields array_add(*input_field_names, it.name);
  for shader.output.fields array_add(*output_field_names, it.name);

  for header.body_or_null.block.statements {
    if it.kind != .BINARY_OPERATOR continue;
    bn := cast(*Code_Binary_Operator) it;
    if operator_string(bn.operator_type) != "=" continue;
    if !bn.left || bn.left.kind != .IDENT continue;

    lhs := cast(*Code_Ident) bn.left;
    if !ir_struct_has_field(*shader.output, lhs.name) continue;

    rhs_expr, ok := ir_expr_to_slang(bn.right, input_field_names, output_field_names);
    if !ok return false;
    array_add(*shader.assignments, .{
      output_field = lhs.name,
      rhs_expr = rhs_expr,
    });
  }

  return true;
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
    builtin_name, found := member_get_compute_builtin_note(it);
    if !found return out, false;
    semantic, sem_ok := ir_compute_builtin_to_semantic(builtin_name);
    if !sem_ok return out, false;
    type_name, type_ok := ir_type_to_slang_name(it.type);
    if !type_ok return out, false;
    array_add(*out.fields, .{
      name = it.name,
      type_name = type_name,
      semantic = semantic,
    });
  }

  return out, true;
}

ir_stmt_indent :: (indent: s64) -> string {
  s := "";
  for 0..indent-1 s = tprint("%    ", s);
  return s;
}

ir_emit_compute_stmt_lines :: (out_lines: *[..] string, stmt: *Code_Node, indent: s64, input_fields: [] string, allow_return_value: bool) -> bool {
  if !out_lines || !stmt return false;

  if stmt.kind == {
    case .DECLARATION; {
      decl := cast(*Code_Declaration) stmt;
      decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
      type_name, ok := ir_type_to_slang_name(decl_type);
      if !ok return false;
      line := tprint("% % %", ir_stmt_indent(indent), type_name, decl.name);
      if decl.expression {
        expr, expr_ok := ir_expr_to_slang(decl.expression, input_fields, .[]);
        if !expr_ok return false;
        line = tprint("% = %", line, expr);
      }
      line = tprint("%;", line);
      array_add(out_lines, line);
      return true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) stmt;
      left, left_ok := ir_expr_to_slang(bn.left, input_fields, .[]);
      if !left_ok return false;
      right, right_ok := ir_expr_to_slang(bn.right, input_fields, .[]);
      if !right_ok return false;
      op := ir_binary_operator_to_slang(bn.operator_type);
      array_add(out_lines, tprint("% % % %;", ir_stmt_indent(indent), left, op, right));
      return true;
    }

    case .IF; {
      op := cast(*Code_If) stmt;
      cond, cond_ok := ir_expr_to_slang(op.condition, input_fields, .[]);
      if !cond_ok return false;
      array_add(out_lines, tprint("%if (%) {", ir_stmt_indent(indent), cond));
      if !ir_emit_compute_block_lines(out_lines, op.then_block, indent+1, input_fields, allow_return_value) return false;
      if op.else_block {
        array_add(out_lines, tprint("%} else {", ir_stmt_indent(indent)));
        if !ir_emit_compute_block_lines(out_lines, op.else_block, indent+1, input_fields, allow_return_value) return false;
      }
      array_add(out_lines, tprint("%}", ir_stmt_indent(indent)));
      return true;
    }

    case .FOR; {
      op := cast(*Code_For) stmt;
      if op.macro_expansion_procedure_call || !op.iteration_expression_right return false;
      if op.for_flags & .POINTER return false;

      start_expr, start_ok := ir_expr_to_slang(op.iteration_expression, input_fields, .[]);
      if !start_ok return false;
      end_expr, end_ok := ir_expr_to_slang(op.iteration_expression_right, input_fields, .[]);
      if !end_ok return false;

      cmp := "<=";
      step := "+= 1";
      if op.for_flags & .REVERSE {
        cmp = ">=";
        step = "-= 1";
      }

      loop_name := op.ident_decl.name;
      array_add(out_lines,
                tprint("%for (int % = %; % % %; % %) {",
                       ir_stmt_indent(indent), loop_name, start_expr,
                       loop_name, cmp, end_expr, loop_name, step));
      if !ir_emit_compute_block_lines(out_lines, op.block, indent+1, input_fields, allow_return_value) return false;
      array_add(out_lines, tprint("%}", ir_stmt_indent(indent)));
      return true;
    }

    case .PROCEDURE_CALL; {
      call_expr, call_ok := ir_expr_to_slang(stmt, input_fields, .[]);
      if !call_ok return false;
      array_add(out_lines, tprint("%%;", ir_stmt_indent(indent), call_expr));
      return true;
    }

    case .RETURN; {
      op := cast(*Code_Return) stmt;
      if op.arguments_sorted.count == 0 {
        array_add(out_lines, tprint("%return;", ir_stmt_indent(indent)));
        return true;
      }
      if allow_return_value && op.arguments_sorted.count == 1 {
        ret_expr, ret_ok := ir_expr_to_slang(op.arguments_sorted[0], input_fields, .[]);
        if !ret_ok return false;
        array_add(out_lines, tprint("%return %;", ir_stmt_indent(indent), ret_expr));
        return true;
      }
      return true;
    }

    case .USING; {
      return true;
    }
  }

  return false;
}

ir_emit_compute_block_lines :: (out_lines: *[..] string, block: *Code_Block, indent: s64, input_fields: [] string, allow_return_value: bool) -> bool {
  if !out_lines || !block return true;
  for block.statements {
    if !ir_emit_compute_stmt_lines(out_lines, it, indent, input_fields, allow_return_value) return false;
  }
  return true;
}

ir_header_in_list :: (headers: *[..] *Code_Procedure_Header, header: *Code_Procedure_Header) -> bool {
  for headers.* if it == header return true;
  return false;
}

ir_collect_calls_in_node :: (node: *Code_Node, called_headers: *[..] *Code_Procedure_Header) {
  if !node return;

  if node.kind == {
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if pc.resolved_procedure_expression && pc.resolved_procedure_expression.kind == .PROCEDURE_HEADER {
        header := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
        if header.body_or_null && !ir_header_in_list(called_headers, header) {
          array_add(called_headers, header);
        }
      }
      for pc.arguments_sorted ir_collect_calls_in_node(it, called_headers);
      for pc.arguments_unsorted if it.expression ir_collect_calls_in_node(it.expression, called_headers);
      return;
    }

    case .DECLARATION; {
      decl := cast(*Code_Declaration) node;
      if decl.expression ir_collect_calls_in_node(decl.expression, called_headers);
      return;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      ir_collect_calls_in_node(bn.left, called_headers);
      ir_collect_calls_in_node(bn.right, called_headers);
      return;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      ir_collect_calls_in_node(un.subexpression, called_headers);
      return;
    }

    case .IF; {
      op := cast(*Code_If) node;
      ir_collect_calls_in_node(op.condition, called_headers);
      if op.then_block for op.then_block.statements ir_collect_calls_in_node(it, called_headers);
      if op.else_block for op.else_block.statements ir_collect_calls_in_node(it, called_headers);
      return;
    }

    case .FOR; {
      op := cast(*Code_For) node;
      ir_collect_calls_in_node(op.iteration_expression, called_headers);
      ir_collect_calls_in_node(op.iteration_expression_right, called_headers);
      if op.block for op.block.statements ir_collect_calls_in_node(it, called_headers);
      return;
    }

    case .RETURN; {
      op := cast(*Code_Return) node;
      for op.arguments_sorted ir_collect_calls_in_node(it, called_headers);
      return;
    }

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        for lit.struct_literal_info.arguments ir_collect_calls_in_node(it, called_headers);
      } else if lit.value_type == .ARRAY {
        for lit.array_literal_info.array_members ir_collect_calls_in_node(it, called_headers);
      }
      return;
    }
  }
}

// Stage-neutral helper lowering entry point.
// Current body emission uses the compute statement subset and should be generalized
// to shared shader-body lowering for vertex/fragment/compute as that lands.
ir_lower_helper_function :: (header: *Code_Procedure_Header) -> (IR_Helper_Function, bool) {
  out: IR_Helper_Function;
  if !header return out, false;
  if !header.body_or_null || !header.body_or_null.block return out, false;
  if header.returns.count > 1 return out, false;

  out.name = header.name;
  if header.returns.count == 1 {
    ret := header.returns[0];
    ret_type := ifx ret.type_inst then ret.type_inst.result else ifx ret.expression then ret.expression.type else null;
    ret_name, ret_ok := ir_type_to_slang_name(ret_type);
    if !ret_ok return out, false;
    out.return_type_name = ret_name;
  } else {
    out.return_type_name = "void";
  }

  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
    arg_type_name, arg_ok := ir_type_to_slang_name(arg_type);
    if !arg_ok return out, false;
    array_add(*out.args, .{
      name = it.name,
      type_name = arg_type_name,
    });
  }

  if !ir_emit_compute_block_lines(*out.body_lines, header.body_or_null.block, 1, .[], header.returns.count == 1) return out, false;
  return out, true;
}

ir_collect_helper_functions_recursive :: (header: *Code_Procedure_Header,
                                         seen_headers: *[..] *Code_Procedure_Header,
                                         helpers: *[..] IR_Helper_Function,
                                         main_header: *Code_Procedure_Header) -> bool {
  if !header || !header.body_or_null || !header.body_or_null.block return false;
  if ir_header_in_list(seen_headers, header) return true;
  array_add(seen_headers, header);

  called: [..] *Code_Procedure_Header;
  for header.body_or_null.block.statements ir_collect_calls_in_node(it, *called);
  for called {
    if it == main_header continue;
    if !ir_collect_helper_functions_recursive(it, seen_headers, helpers, main_header) return false;
  }

  if header != main_header {
    helper, ok := ir_lower_helper_function(header);
    if !ok return false;
    array_add(helpers, helper);
  }
  return true;
}

ir_lower_vertex_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Vertex_Shader, bool) {
  out: IR_Vertex_Shader;
  if !ctx return out, false;
  if ctx.type != .Vertex return out, false;

  if ctx.main_fn.header.arguments.count < 1 return out, false;
  if ctx.main_fn.header.returns.count != 1 return out, false;

  arg0 := ctx.main_fn.header.arguments[0];
  ret0 := ctx.main_fn.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok return out, false;

  out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
  if !out_ok return out, false;

  out.source_name = ctx.name;
  out.entry_name = "VertexMain";
  out.input = in_struct;
  out.output = out_struct;
  if !ir_collect_vertex_assignments(ctx, *out) return out, false;

  return out, true;
}

ir_lower_fragment_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Fragment_Shader, bool) {
  out: IR_Fragment_Shader;
  if !ctx return out, false;
  if ctx.type != .Fragment return out, false;

  if ctx.main_fn.header.arguments.count < 1 return out, false;
  if ctx.main_fn.header.returns.count != 1 return out, false;

  arg0 := ctx.main_fn.header.arguments[0];
  ret0 := ctx.main_fn.header.returns[0];

  in_type := ifx arg0.type_inst then arg0.type_inst.result else ifx arg0.expression then arg0.expression.type else null;
  out_type := ifx ret0.type_inst then ret0.type_inst.result else ifx ret0.expression then ret0.expression.type else null;

  in_struct, in_ok := ir_lower_struct_from_type(tprint("%_In", ctx.name), in_type);
  if !in_ok return out, false;

  out_struct, out_ok := ir_lower_struct_from_type(tprint("%_Out", ctx.name), out_type);
  if !out_ok return out, false;

  out.source_name = ctx.name;
  out.entry_name = "FragmentMain";
  out.input = in_struct;
  out.output = out_struct;
  if !ir_collect_fragment_assignments(ctx, *out) return out, false;

  return out, true;
}

ir_lower_compute_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Compute_Shader, bool) {
  out: IR_Compute_Shader;
  if !ctx return out, false;
  if ctx.type != .Compute return out, false;

  header := ctx.main_fn.header;
  if !header return out, false;
  if header.arguments.count < 2 return out, false;
  if header.returns.count != 0 return out, false;

  input_arg := header.arguments[0];
  input_type := ifx input_arg.type_inst then input_arg.type_inst.result else ifx input_arg.expression then input_arg.expression.type else null;
  input_struct, input_ok := ir_lower_compute_input_struct(tprint("%_In", ctx.name), input_type);
  if !input_ok return out, false;

  out.source_name = ctx.name;
  out.entry_name = "ComputeMain";
  out.input = input_struct;

  for i: 1..header.arguments.count-1 {
    arg := header.arguments[i];
    arg_type := ifx arg.type_inst then arg.type_inst.result else ifx arg.expression then arg.expression.type else null;
    if !arg_type || arg_type.type != .POINTER return out, false;
    ptr := cast(*Type_Info_Pointer) arg_type;
    elem_type_name, elem_ok := ir_type_to_slang_name(ptr.pointer_to);
    if !elem_ok return out, false;
    array_add(*out.buffers, .{
      name = arg.name,
      element_type_name = elem_type_name,
    });
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_collect_helper_functions_recursive(header, *seen_headers, *out.helpers, header) return out, false;

  input_field_names: [..] string;
  for out.input.fields array_add(*input_field_names, it.name);
  if !ir_emit_compute_block_lines(*out.body_lines, header.body_or_null.block, 1, input_field_names, false) return out, false;
  return out, true;
}

ir_emit_struct_slang :: (sb: *String_Builder, s: *IR_Struct) {
  append(sb, tprint("struct % {\n", s.name));
  for s.fields {
    if it.semantic.count != 0 append(sb, tprint("    % % : %;\n", it.type_name, it.name, it.semantic));
    else append(sb, tprint("    % %;\n", it.type_name, it.name));
  }
  append(sb, "};\n\n");
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

emit_ir_vertex_to_slang :: (shader: IR_Vertex_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input) {\n", shader.output.name, shader.entry_name, shader.input.name));
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  if shader.assignments.count != 0 {
    for shader.assignments {
      append(*sb, tprint("    o.% = %;\n", it.output_field, it.rhs_expr));
    }
  } else {
    position_field := find_output_position_field(*shader.output);
    if position_field.count != 0 {
      append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
    }
  }

  append(*sb, "    return o;\n}");
  return builder_to_string(*sb), true;
}

emit_ir_fragment_to_slang :: (shader: IR_Fragment_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input) {\n", shader.output.name, shader.entry_name, shader.input.name));
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  for shader.assignments {
    append(*sb, tprint("    o.% = %;\n", it.output_field, it.rhs_expr));
  }

  append(*sb, "    return o;\n}");
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

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input) {\n", vertex.output.name, vertex.entry_name, vertex.input.name));
  append(*sb, tprint("    % o = (%)0;\n", vertex.output.name, vertex.output.name));
  if vertex.assignments.count != 0 {
    for vertex.assignments {
      append(*sb, tprint("    o.% = %;\n", it.output_field, it.rhs_expr));
    }
  } else {
    position_field := find_output_position_field(*vertex.output);
    if position_field.count != 0 append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
  }
  append(*sb, "    return o;\n}\n\n");

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input) {\n", fragment.output.name, fragment.entry_name, fragment.input.name));
  append(*sb, tprint("    % o = (%)0;\n", fragment.output.name, fragment.output.name));
  for fragment.assignments {
    append(*sb, tprint("    o.% = %;\n", it.output_field, it.rhs_expr));
  }
  append(*sb, "    return o;\n}\n");

  return builder_to_string(*sb), true;
}

emit_ir_compute_to_slang :: (shader: IR_Compute_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));
  ir_emit_struct_slang(*sb, *shader.input);

  for shader.helpers {
    append(*sb, tprint("% %(", it.return_type_name, it.name));
    for it.args {
      if it_index != 0 append(*sb, ", ");
      append(*sb, tprint("% %", it.type_name, it.name));
    }
    append(*sb, ") {\n");
    for it.body_lines append(*sb, it, "\n");
    append(*sb, "}\n\n");
  }

  append(*sb, "[shader(\"compute\")]\n");
  append(*sb, "void ");
  append(*sb, shader.entry_name);
  append(*sb, tprint("(% input", shader.input.name));
  for shader.buffers {
    append(*sb, tprint(", RWStructuredBuffer<%> %", it.element_type_name, it.name));
  }
  append(*sb, ") {\n");
  for shader.body_lines append(*sb, it, "\n");
  append(*sb, "}\n");
  return builder_to_string(*sb), true;
}
