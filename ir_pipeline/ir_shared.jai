// Shared IR lowering/emission helpers used across shader stages.

ir_shared_stmt_indent :: (indent: s64) -> string {
  s := "";
  for 0..indent-1 s = tprint("%    ", s);
  return s;
}

ir_emit_ir_stmt_lines :: (out_lines: *[..] string, stmt: *IR_Stmt, indent: s64) -> bool {
  assert(out_lines != null);
  assert(stmt != null);

  if stmt.kind == {
    case .DECL; {
      line := tprint("% % %", ir_shared_stmt_indent(indent), stmt.decl_type_name, stmt.decl_name);
      if stmt.decl_init {
        expr_text, ok := ir_expr_to_slang_from_ir(stmt.decl_init);
        if !ok return false;
        line = tprint("% = %", line, expr_text);
      }
      array_add(out_lines, tprint("%;", line));
      return true;
    }

    case .BINARY; {
      left, left_ok := ir_expr_to_slang_from_ir(stmt.binary_left);
      if !left_ok return false;
      right, right_ok := ir_expr_to_slang_from_ir(stmt.binary_right);
      if !right_ok return false;
      array_add(out_lines, tprint("% % % %;", ir_shared_stmt_indent(indent), left, stmt.binary_op, right));
      return true;
    }

    case .IF; {
      cond, cond_ok := ir_expr_to_slang_from_ir(stmt.if_condition);
      if !cond_ok return false;
      array_add(out_lines, tprint("%if (%) {", ir_shared_stmt_indent(indent), cond));
      if !ir_emit_ir_block_lines(out_lines, stmt.if_then, indent+1) return false;
      if stmt.if_else {
        array_add(out_lines, tprint("%} else {", ir_shared_stmt_indent(indent)));
        if !ir_emit_ir_block_lines(out_lines, stmt.if_else, indent+1) return false;
      }
      array_add(out_lines, tprint("%}", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .SWITCH; {
      cond, cond_ok := ir_expr_to_slang_from_ir(stmt.switch_condition);
      if !cond_ok return false;
      array_add(out_lines, tprint("%switch (%) {", ir_shared_stmt_indent(indent), cond));
      for stmt.switch_cases {
        if it.condition {
          case_cond, case_ok := ir_expr_to_slang_from_ir(it.condition);
          if !case_ok return false;
          array_add(out_lines, tprint("%case %:", ir_shared_stmt_indent(indent+1), case_cond));
        } else {
          array_add(out_lines, tprint("%default:", ir_shared_stmt_indent(indent+1)));
        }
        if !ir_emit_ir_block_lines(out_lines, it.body, indent+2) return false;
        if !it.falls_through array_add(out_lines, tprint("%break;", ir_shared_stmt_indent(indent+2)));
      }
      array_add(out_lines, tprint("%}", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .FOR; {
      start_text, start_ok := ir_expr_to_slang_from_ir(stmt.for_start);
      if !start_ok return false;
      end_text, end_ok := ir_expr_to_slang_from_ir(stmt.for_end);
      if !end_ok return false;
      array_add(out_lines,
                tprint("%for (int % = %; % % %; % %) {",
                       ir_shared_stmt_indent(indent),
                       stmt.for_loop_name, start_text,
                       stmt.for_loop_name, stmt.for_cmp, end_text,
                       stmt.for_loop_name, stmt.for_step));
      if !ir_emit_ir_block_lines(out_lines, stmt.for_body, indent+1) return false;
      array_add(out_lines, tprint("%}", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .WHILE; {
      cond, cond_ok := ir_expr_to_slang_from_ir(stmt.while_condition);
      if !cond_ok return false;
      array_add(out_lines, tprint("%while (%) {", ir_shared_stmt_indent(indent), cond));
      if !ir_emit_ir_block_lines(out_lines, stmt.while_body, indent+1) return false;
      array_add(out_lines, tprint("%}", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .BREAK; {
      array_add(out_lines, tprint("%break;", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .CONTINUE; {
      array_add(out_lines, tprint("%continue;", ir_shared_stmt_indent(indent)));
      return true;
    }

    case .CALL; {
      call_text, call_ok := ir_expr_to_slang_from_ir(stmt.call_expr);
      if !call_ok return false;
      array_add(out_lines, tprint("%%;", ir_shared_stmt_indent(indent), call_text));
      return true;
    }

    case .RETURN; {
      if !stmt.return_expr {
        array_add(out_lines, tprint("%return;", ir_shared_stmt_indent(indent)));
      } else {
        ret_text, ret_ok := ir_expr_to_slang_from_ir(stmt.return_expr);
        if !ret_ok return false;
        array_add(out_lines, tprint("%return %;", ir_shared_stmt_indent(indent), ret_text));
      }
      return true;
    }
  }

  return false;
}

ir_emit_ir_block_lines :: (out_lines: *[..] string, block: *IR_Block, indent: s64) -> bool {
  assert(out_lines != null);
  assert(block != null);
  for block.statements {
    if !ir_emit_ir_stmt_lines(out_lines, *it, indent) return false;
  }
  return true;
}

ir_shared_lower_stmt :: (stmt: *Code_Node, out_block: *IR_Block, input_fields: [] string, output_fields: [] string, allow_return_value: bool, active_usings: *[..] IR_Using_Source) -> bool {
  assert(stmt != null);
  assert(out_block != null);
  assert(active_usings != null);

  if stmt.kind == {
    case .DECLARATION; {
      decl := cast(*Code_Declaration) stmt;
      decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
      type_name, type_ok := ir_type_to_slang_name(decl_type);
      if !type_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .DECL;
      out_stmt.decl_type_name = type_name;
      out_stmt.decl_name = decl.name;
      if decl.expression {
        init_expr, init_ok := ir_lower_expr(decl.expression, input_fields, output_fields, active_usings.*);
        if !init_ok return false;
        out_stmt.decl_init = init_expr;
      }
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) stmt;
      if bn.operator_type == cast(Operator_Type) #char "=" && bn.left && bn.left.kind == .IDENT {
        lhs := cast(*Code_Ident) bn.left;
        if lhs.name == "_" return true; // discard assignment
      }
      left, left_ok := ir_lower_expr(bn.left, input_fields, output_fields, active_usings.*);
      if !left_ok return false;
      right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings.*);
      if !right_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .BINARY;
      out_stmt.binary_left = left;
      out_stmt.binary_op = ir_binary_operator_to_slang(bn.operator_type);
      out_stmt.binary_right = right;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .IF; {
      op := cast(*Code_If) stmt;
      if op.if_flags & .IS_SWITCH_STATEMENT {
        cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*);
        if !cond_ok return false;
        if !op.then_block return false;

        out_stmt: IR_Stmt;
        out_stmt.kind = .SWITCH;
        out_stmt.switch_condition = cond;

        for op.then_block.statements {
          if it.kind != .CASE return false;
          case_node := cast(*Code_Case) it;
          sw_case: IR_Switch_Case;
          sw_case.falls_through = case_node.marked_as_fallthrough;
          sw_case.body = New(IR_Block);
          if case_node.condition {
            lowered_case_cond, case_cond_ok := ir_lower_expr(case_node.condition, input_fields, output_fields, active_usings.*);
            if !case_cond_ok return false;
            sw_case.condition = lowered_case_cond;
          }
          if !ir_shared_lower_block(case_node.then_block, sw_case.body, input_fields, output_fields, allow_return_value, active_usings.*) return false;
          array_add(*out_stmt.switch_cases, sw_case);
        }

        if op.else_block return false;
        array_add(*out_block.statements, out_stmt);
        return true;
      }

      cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*);
      if !cond_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .IF;
      out_stmt.if_condition = cond;
      out_stmt.if_then = New(IR_Block);
      if !ir_shared_lower_block(op.then_block, out_stmt.if_then, input_fields, output_fields, allow_return_value, active_usings.*) return false;
      if op.else_block {
        out_stmt.if_else = New(IR_Block);
        if !ir_shared_lower_block(op.else_block, out_stmt.if_else, input_fields, output_fields, allow_return_value, active_usings.*) return false;
      }
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .FOR; {
      op := cast(*Code_For) stmt;
      if op.macro_expansion_procedure_call || !op.iteration_expression_right return false;
      if op.for_flags & .POINTER return false;

      start_expr, start_ok := ir_lower_expr(op.iteration_expression, input_fields, output_fields, active_usings.*);
      if !start_ok return false;
      end_expr, end_ok := ir_lower_expr(op.iteration_expression_right, input_fields, output_fields, active_usings.*);
      if !end_ok return false;

      out_stmt: IR_Stmt;
      out_stmt.kind = .FOR;
      out_stmt.for_loop_name = op.ident_decl.name;
      out_stmt.for_start = start_expr;
      out_stmt.for_end = end_expr;
      out_stmt.for_cmp = "<=";
      out_stmt.for_step = "+= 1";
      if op.for_flags & .REVERSE {
        out_stmt.for_cmp = ">=";
        out_stmt.for_step = "-= 1";
      }
      out_stmt.for_body = New(IR_Block);
      if !ir_shared_lower_block(op.block, out_stmt.for_body, input_fields, output_fields, allow_return_value, active_usings.*) return false;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .WHILE; {
      op := cast(*Code_While) stmt;
      cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*);
      if !cond_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .WHILE;
      out_stmt.while_condition = cond;
      out_stmt.while_body = New(IR_Block);
      if !ir_shared_lower_block(op.block, out_stmt.while_body, input_fields, output_fields, allow_return_value, active_usings.*) return false;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .LOOP_CONTROL; {
      op := cast(*Code_Loop_Control) stmt;
      out_stmt: IR_Stmt;
      if op.control_type == .BREAK out_stmt.kind = .BREAK;
      else if op.control_type == .CONTINUE out_stmt.kind = .CONTINUE;
      else return false;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .PROCEDURE_CALL; {
      call_expr, call_ok := ir_lower_expr(stmt, input_fields, output_fields, active_usings.*);
      if !call_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .CALL;
      out_stmt.call_expr = call_expr;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .RETURN; {
      op := cast(*Code_Return) stmt;
      out_stmt: IR_Stmt;
      out_stmt.kind = .RETURN;
      if op.arguments_sorted.count == 1 {
        if !allow_return_value return false;
        ret_expr, ret_ok := ir_lower_expr(op.arguments_sorted[0], input_fields, output_fields, active_usings.*);
        if !ret_ok return false;
        out_stmt.return_expr = ret_expr;
      } else if op.arguments_sorted.count > 1 {
        return false;
      }
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .USING; {
      op := cast(*Code_Using) stmt;
      if !op.expression return false;
      if op.filter_type != .NONE return false;

      using_type := op.expression.type;
      if !using_type || using_type.type != .STRUCT return false;
      using_struct := cast(*Type_Info_Struct) using_type;

      src: IR_Using_Source;
      src.expression_node = op.expression;
      for *using_struct.members array_add(*src.field_names, it.name);
      array_add(active_usings, src);
      return true;
    }
  }

  return false;
}

ir_shared_lower_block :: (block: *Code_Block, out_block: *IR_Block, input_fields: [] string, output_fields: [] string, allow_return_value: bool, incoming_usings: [] IR_Using_Source = .[]) -> bool {
  assert(out_block != null);
  if !block return true;
  active_usings: [..] IR_Using_Source;
  for incoming_usings array_add(*active_usings, it);
  for block.statements {
    if !ir_shared_lower_stmt(it, out_block, input_fields, output_fields, allow_return_value, *active_usings) return false;
  }
  return true;
}

ir_shared_header_in_list :: (headers: *[..] *Code_Procedure_Header, header: *Code_Procedure_Header) -> bool {
  for headers.* if it == header return true;
  return false;
}

ir_shared_collect_calls_in_node :: (node: *Code_Node, called_headers: *[..] *Code_Procedure_Header) {
  if !node return;

  if node.kind == {
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if pc.resolved_procedure_expression && pc.resolved_procedure_expression.kind == .PROCEDURE_HEADER {
        header := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
        if header.body_or_null && !ir_shared_header_in_list(called_headers, header) {
          array_add(called_headers, header);
        }
      }
      for pc.arguments_sorted ir_shared_collect_calls_in_node(it, called_headers);
      for pc.arguments_unsorted if it.expression ir_shared_collect_calls_in_node(it.expression, called_headers);
      return;
    }

    case .DECLARATION; {
      decl := cast(*Code_Declaration) node;
      if decl.expression ir_shared_collect_calls_in_node(decl.expression, called_headers);
      return;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      ir_shared_collect_calls_in_node(bn.left, called_headers);
      ir_shared_collect_calls_in_node(bn.right, called_headers);
      return;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      ir_shared_collect_calls_in_node(un.subexpression, called_headers);
      return;
    }

    case .IF; {
      op := cast(*Code_If) node;
      ir_shared_collect_calls_in_node(op.condition, called_headers);
      if op.then_block for op.then_block.statements ir_shared_collect_calls_in_node(it, called_headers);
      if op.else_block for op.else_block.statements ir_shared_collect_calls_in_node(it, called_headers);
      return;
    }

    case .FOR; {
      op := cast(*Code_For) node;
      ir_shared_collect_calls_in_node(op.iteration_expression, called_headers);
      ir_shared_collect_calls_in_node(op.iteration_expression_right, called_headers);
      if op.block for op.block.statements ir_shared_collect_calls_in_node(it, called_headers);
      return;
    }

    case .WHILE; {
      op := cast(*Code_While) node;
      ir_shared_collect_calls_in_node(op.condition, called_headers);
      if op.block for op.block.statements ir_shared_collect_calls_in_node(it, called_headers);
      return;
    }

    case .RETURN; {
      op := cast(*Code_Return) node;
      for op.arguments_sorted ir_shared_collect_calls_in_node(it, called_headers);
      return;
    }

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        for lit.struct_literal_info.arguments ir_shared_collect_calls_in_node(it, called_headers);
      } else if lit.value_type == .ARRAY {
        for lit.array_literal_info.array_members ir_shared_collect_calls_in_node(it, called_headers);
      }
      return;
    }
  }
}

ir_shared_lower_helper_function :: (header: *Code_Procedure_Header) -> (IR_Helper_Function, bool) {
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

  if !ir_shared_lower_block(header.body_or_null.block, *out.body, .[], .[], header.returns.count == 1, .[]) return out, false;
  return out, true;
}

ir_shared_collect_helper_functions_recursive :: (header: *Code_Procedure_Header,
                                                seen_headers: *[..] *Code_Procedure_Header,
                                                helpers: *[..] IR_Helper_Function,
                                                main_header: *Code_Procedure_Header) -> bool {
  if !header || !header.body_or_null || !header.body_or_null.block return false;
  if ir_shared_header_in_list(seen_headers, header) return true;
  array_add(seen_headers, header);

  called: [..] *Code_Procedure_Header;
  for header.body_or_null.block.statements ir_shared_collect_calls_in_node(it, *called);
  for called {
    if it == main_header continue;
    if !ir_shared_collect_helper_functions_recursive(it, seen_headers, helpers, main_header) return false;
  }

  if header != main_header {
    helper, ok := ir_shared_lower_helper_function(header);
    if !ok return false;
    array_add(helpers, helper);
  }
  return true;
}

ir_helper_signature_string :: (helper: *IR_Helper_Function, include_arg_names: bool) -> string {
  b: String_Builder;
  append(*b, helper.return_type_name, " ", helper.name, "(");
  for helper.args {
    if it_index != 0 append(*b, ", ");
    if include_arg_names append(*b, tprint("% %", it.type_name, it.name));
    else append(*b, it.type_name);
  }
  append(*b, ")");
  return builder_to_string(*b);
}

ir_emit_helper_prototypes :: (sb: *String_Builder, helpers: [] IR_Helper_Function) {
  if helpers.count == 0 return;
  for helpers {
    append(sb, ir_helper_signature_string(*it, include_arg_names=true), ";\n");
  }
  append(sb, "\n");
}

ir_emit_helper_definitions :: (sb: *String_Builder, helpers: [] IR_Helper_Function) -> bool {
  assert(sb != null);
  if helpers.count == 0 return true;
  for helpers {
    append(sb, ir_helper_signature_string(*it, include_arg_names=true), " {\n");
    body_lines: [..] string;
    if !ir_emit_ir_block_lines(*body_lines, *it.body, 1) return false;
    for body_lines append(sb, it, "\n");
    append(sb, "}\n\n");
  }
  return true;
}

ir_add_helper_unique_by_name :: (helpers: *[..] IR_Helper_Function, helper: IR_Helper_Function) {
  for helpers.* if it.name == helper.name return;
  array_add(helpers, helper);
}
