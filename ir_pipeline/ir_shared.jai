// Shared IR lowering/emission utilities used across shader stages.
#scope_file

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
      decl_type_text := stmt.decl_type_name;
      if stmt.decl_type.display_name.count != 0 decl_type_text = stmt.decl_type.display_name;
      line := tprint("% % %", ir_shared_stmt_indent(indent), decl_type_text, stmt.decl_name);
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
      // Emit switch as an if/else-if chain with expanded fallthrough paths.
      // This avoids known SPIR-V codegen issues in downstream toolchains for some switch/fallthrough forms.
      cond, cond_ok := ir_expr_to_slang_from_ir(stmt.switch_condition);
      if !cond_ok return false;

      default_index := cast(s64) -1;
      for i: 0..stmt.switch_cases.count-1 {
        if !stmt.switch_cases[i].condition {
          default_index = i;
          break;
        }
      }

      emit_expanded_from_case :: (out_lines: *[..] string, cases: [] IR_Switch_Case, start_index: s64, indent: s64) -> bool {
        for j: start_index..cases.count-1 {
          if !ir_emit_ir_block_lines(out_lines, cases[j].body, indent) return false;
          if !cases[j].falls_through break;
        }
        return true;
      }

      emitted_any_branch := false;
      for i: 0..stmt.switch_cases.count-1 {
        c := stmt.switch_cases[i];
        if !c.condition continue;
        case_cond, case_ok := ir_expr_to_slang_from_ir(c.condition);
        if !case_ok return false;

        branch_kw := ifx emitted_any_branch then "} else if" else "if";
        array_add(out_lines, tprint("% % (% == %) {", ir_shared_stmt_indent(indent), branch_kw, cond, case_cond));
        if !emit_expanded_from_case(out_lines, stmt.switch_cases, i, indent+1) return false;
        emitted_any_branch = true;
      }

      if default_index != -1 {
        if emitted_any_branch array_add(out_lines, tprint("%} else {", ir_shared_stmt_indent(indent)));
        else array_add(out_lines, tprint("%{", ir_shared_stmt_indent(indent)));
        if !emit_expanded_from_case(out_lines, stmt.switch_cases, default_index, indent+1) return false;
        emitted_any_branch = true;
      }

      if emitted_any_branch {
        array_add(out_lines, tprint("%}", ir_shared_stmt_indent(indent)));
      }
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

#scope_module

ir_emit_ir_block_lines :: (out_lines: *[..] string, block: *IR_Block, indent: s64) -> bool {
  assert(out_lines != null);
  assert(block != null);
  for block.statements {
    if !ir_emit_ir_stmt_lines(out_lines, *it, indent) return false;
  }
  return true;
}

ir_shared_struct_fields_match_names :: (type: *Type_Info, field_names: [] string) -> bool {
  if !type || type.type != .STRUCT return false;
  st := cast(*Type_Info_Struct) type;
  if st.members.count != field_names.count return false;
  for i: 0..field_names.count-1 {
    if st.members[i].name != field_names[i] return false;
  }
  return true;
}

ir_shared_find_struct_member_type_by_name :: (type: *Type_Info, member_name: string) -> *Type_Info {
  if !type || type.type != .STRUCT return null;
  st := cast(*Type_Info_Struct) type;
  for *st.members if it.name == member_name return it.type;
  return null;
}

ir_shared_find_struct_member_type_by_index :: (type: *Type_Info, member_index: s64) -> *Type_Info {
  if !type || type.type != .STRUCT return null;
  st := cast(*Type_Info_Struct) type;
  if member_index < 0 || member_index >= st.members.count return null;
  return st.members[member_index].type;
}

ir_shared_lower_stmt :: (stmt: *Code_Node,
                         out_block: *IR_Block,
                         input_fields: [] string,
                         output_fields: [] string,
                         allow_return_value: bool,
                         active_usings: *[..] IR_Using_Source,
                         active_aliases: *[..] IR_Decl_Alias,
                         active_defer_entries: *[..] IR_Active_Defer,
                         scope_depth: s64,
                         nearest_loop_scope_depth: s64,
                         state: *IR_Lowering_State) -> bool {
  return_err :: (message: string, node: *Code_Node) #expand {
    ir_set_diagnostic(state, message, node);
    `return false;
  }

  assert(stmt != null);
  assert(out_block != null);
  assert(active_usings != null);
  assert(active_aliases != null);
  assert(active_defer_entries != null);
  assert(state != null);

  if stmt.kind == {
    case .DECLARATION; {
      decl := cast(*Code_Declaration) stmt;
      for decl.notes if it.text == "jai_only" return true;
      decl_type := ifx decl.type_inst then decl.type_inst.result else ifx decl.expression then decl.expression.type else null;
      type_name, type_ok := ir_type_to_shader_name(decl_type);
      if !type_ok {
        ir_set_diagnostic(state, tprint("IR lowering: unsupported declaration type for '%'", decl.name), stmt);
        return false;
      }
      out_stmt: IR_Stmt;
      out_stmt.kind = .DECL;
      out_stmt.decl_type_name = type_name;
      decl_ir_type, decl_ir_type_ok := ir_type_from_type_info(decl_type);
      if !decl_ir_type_ok {
        ir_set_diagnostic(state, tprint("IR lowering: unsupported typed declaration info for '%'", decl.name), stmt);
        return false;
      }
      out_stmt.decl_type = decl_ir_type;
      out_stmt.decl_name = decl.name;
      should_alias_pointer_local := false;
      should_alias_struct_resource_local := false;
      if decl_type && decl.expression {
        if decl_type.type == .POINTER {
          should_alias_pointer_local = true;
        } else if decl_type.type == .STRUCT && ir_struct_has_pointer_members(decl_type) {
          should_alias_struct_resource_local = true;
        }
      }
      if decl.expression {
        init_expr, init_ok := ir_lower_expr(decl.expression, input_fields, output_fields, active_usings.*, active_aliases.*, state, decl_type);
        if !init_ok return false;

        if should_alias_struct_resource_local {
          if decl.expression.kind != .LITERAL {
            ir_set_diagnostic(state, tprint("IR lowering: resource-backed local struct '%' requires a struct literal initializer", decl.name), stmt);
            return false;
          }
          lit := cast(*Code_Literal) decl.expression;
          if lit.value_type != .STRUCT {
            ir_set_diagnostic(state, tprint("IR lowering: resource-backed local struct '%' requires a struct literal initializer", decl.name), stmt);
            return false;
          }

          positional_index: s64 = 0;
          for lit.struct_literal_info.arguments {
            source_arg := it;
            field_name := "";
            value_node := source_arg;

            if source_arg && source_arg.kind == .BINARY_OPERATOR {
              named := cast(*Code_Binary_Operator) source_arg;
              if named.operator_type == cast(Operator_Type) #char "=" &&
                 named.left && named.left.kind == .IDENT {
                field_name = (cast(*Code_Ident) named.left).name;
                value_node = named.right;
              }
            }

            if field_name.count == 0 {
              if decl_type.type != .STRUCT {
                ir_set_diagnostic(state, tprint("IR lowering: malformed positional struct initializer for '%'", decl.name), stmt);
                return false;
              }
              decl_struct := cast(*Type_Info_Struct) decl_type;
              if positional_index >= decl_struct.members.count {
                ir_set_diagnostic(state, tprint("IR lowering: malformed positional struct initializer for '%'", decl.name), stmt);
                return false;
              }
              field_name = decl_struct.members[positional_index].name;
              positional_index += 1;
            }

            expected_rhs_type := ir_shared_find_struct_member_type_by_name(decl_type, field_name);
            lowered_value, lowered_ok := ir_lower_expr(value_node, input_fields, output_fields, active_usings.*, active_aliases.*, state, expected_rhs_type);
            if !lowered_ok return false;

            replacement_text, replacement_ok := ir_expr_to_slang_from_ir(lowered_value);
            if !replacement_ok || replacement_text.count == 0 {
              ir_set_diagnostic(state, tprint("IR lowering: failed to lower struct field alias '%.%'", decl.name, field_name), stmt);
              return false;
            }

            array_add(active_aliases, .{
              declaration = decl,
              member_name = field_name,
              replacement_text = replacement_text,
            });
          }
          return true;
        }

        if should_alias_pointer_local {
          replacement_text, replacement_ok := ir_expr_to_slang_from_ir(init_expr);
          if !replacement_ok || replacement_text.count == 0 {
            ir_set_diagnostic(state, tprint("IR lowering: failed to lower alias initializer for '%'", decl.name), stmt);
            return false;
          }
          array_add(active_aliases, .{
            declaration = decl,
            replacement_text = replacement_text,
          });
          return true;
        }
        out_stmt.decl_init = init_expr;
      }
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .COMPOUND_DECLARATION; {
      op := cast(*Code_Compound_Declaration) stmt;
      if !op.comma_separated_assignment || op.comma_separated_assignment.arguments.count == 0 {
        return_err("IR lowering: malformed compound declaration (missing arguments)", stmt);
      }

      lowered_resolved_decls: [..] *Code_Declaration;
      for op.comma_separated_assignment.arguments {
        arg_node := it.node;
        if !arg_node continue;

        if arg_node.kind == .DECLARATION {
          decl := cast(*Code_Declaration) arg_node;
          already := false;
          for lowered_resolved_decls if it == decl { already = true; break; }
          if !already array_add(*lowered_resolved_decls, decl);
          if !ir_shared_lower_stmt(arg_node, out_block, input_fields, output_fields, allow_return_value, active_usings, active_aliases, active_defer_entries, scope_depth, nearest_loop_scope_depth, state) return false;
          continue;
        }

        if arg_node.kind == .IDENT {
          ident := cast(*Code_Ident) arg_node;
          if ident.resolved_declaration {
            decl := ident.resolved_declaration;
            already := false;
            for lowered_resolved_decls if it == decl { already = true; break; }
            if !already {
              array_add(*lowered_resolved_decls, decl);
              if !ir_shared_lower_stmt(cast(*Code_Node) decl, out_block, input_fields, output_fields, allow_return_value, active_usings, active_aliases, active_defer_entries, scope_depth, nearest_loop_scope_depth, state) return false;
            }
            continue;
          }
        }

        if !ir_shared_lower_stmt(arg_node, out_block, input_fields, output_fields, allow_return_value, active_usings, active_aliases, active_defer_entries, scope_depth, nearest_loop_scope_depth, state) {
          return_err(tprint("IR lowering: unsupported compound declaration argument kind (%)", arg_node.kind), arg_node);
        }
      }

      return true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) stmt;
      if bn.operator_type == cast(Operator_Type) #char "=" && bn.left && bn.left.kind == .IDENT {
        lhs := cast(*Code_Ident) bn.left;
        if lhs.name == "_" return true; // discard assignment
      }
      left, left_ok := ir_lower_expr(bn.left, input_fields, output_fields, active_usings.*, active_aliases.*, state);
      if !left_ok return false;
      right_expected_type := ifx bn.left then bn.left.type else null;
      right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings.*, active_aliases.*, state, right_expected_type);
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
        cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*, active_aliases.*, state);
        if !cond_ok return false;
        if !op.then_block {
          ir_set_diagnostic(state, "IR lowering: switch statement missing body", stmt);
          return false;
        }

        out_stmt: IR_Stmt;
        out_stmt.kind = .SWITCH;
        out_stmt.switch_condition = cond;

        for op.then_block.statements {
          if it.kind != .CASE {
            ir_set_diagnostic(state, "IR lowering: switch body contains non-case statement", it);
            return false;
          }
          case_node := cast(*Code_Case) it;
          sw_case: IR_Switch_Case;
          sw_case.falls_through = case_node.marked_as_fallthrough;
          sw_case.body = New(IR_Block);
          if case_node.condition {
            lowered_case_cond, case_cond_ok := ir_lower_expr(case_node.condition, input_fields, output_fields, active_usings.*, active_aliases.*, state);
            if !case_cond_ok return false;
            sw_case.condition = lowered_case_cond;
          }
          if !ir_shared_lower_block(case_node.then_block, sw_case.body, input_fields, output_fields, allow_return_value, state, active_usings.*, active_aliases.*, active_defer_entries.*, scope_depth + 1, nearest_loop_scope_depth) return false;
          array_add(*out_stmt.switch_cases, sw_case);
        }

        if op.else_block {
          ir_set_diagnostic(state, "IR lowering: switch statement with else-block is unsupported", stmt);
          return false;
        }
        array_add(*out_block.statements, out_stmt);
        return true;
      }

      cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*, active_aliases.*, state);
      if !cond_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .IF;
      out_stmt.if_condition = cond;
      out_stmt.if_then = New(IR_Block);
      if !ir_shared_lower_block(op.then_block, out_stmt.if_then, input_fields, output_fields, allow_return_value, state, active_usings.*, active_aliases.*, active_defer_entries.*, scope_depth + 1, nearest_loop_scope_depth) return false;
      if op.else_block {
        out_stmt.if_else = New(IR_Block);
        if !ir_shared_lower_block(op.else_block, out_stmt.if_else, input_fields, output_fields, allow_return_value, state, active_usings.*, active_aliases.*, active_defer_entries.*, scope_depth + 1, nearest_loop_scope_depth) return false;
      }
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .FOR; {
      op := cast(*Code_For) stmt;
      if op.macro_expansion_procedure_call || !op.iteration_expression_right {
        return_err("IR lowering: unsupported for-loop form (expected numeric range)", stmt);
      }
      if op.for_flags & .POINTER {
        return_err("IR lowering: pointer-iteration for-loop is unsupported", stmt);
      }

      start_expr, start_ok := ir_lower_expr(op.iteration_expression, input_fields, output_fields, active_usings.*, active_aliases.*, state);
      if !start_ok return false;
      end_expr, end_ok := ir_lower_expr(op.iteration_expression_right, input_fields, output_fields, active_usings.*, active_aliases.*, state);
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
      if !ir_shared_lower_block(op.block, out_stmt.for_body, input_fields, output_fields, allow_return_value, state, active_usings.*, active_aliases.*, active_defer_entries.*, scope_depth + 1, scope_depth + 1) return false;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .WHILE; {
      op := cast(*Code_While) stmt;
      cond, cond_ok := ir_lower_expr(op.condition, input_fields, output_fields, active_usings.*, active_aliases.*, state);
      if !cond_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .WHILE;
      out_stmt.while_condition = cond;
      out_stmt.while_body = New(IR_Block);
      if !ir_shared_lower_block(op.block, out_stmt.while_body, input_fields, output_fields, allow_return_value, state, active_usings.*, active_aliases.*, active_defer_entries.*, scope_depth + 1, scope_depth + 1) return false;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .LOOP_CONTROL; {
      op := cast(*Code_Loop_Control) stmt;
      out_stmt: IR_Stmt;
      if op.control_type == .BREAK out_stmt.kind = .BREAK;
      else if op.control_type == .CONTINUE out_stmt.kind = .CONTINUE;
      else {
        return_err("IR lowering: unsupported loop-control statement", stmt);
      }
      if nearest_loop_scope_depth < 0 {
        return_err("IR lowering: break/continue outside of loop is unsupported", stmt);
      }
      ir_shared_emit_deferred_for_exit(out_block, active_defer_entries.*, nearest_loop_scope_depth);
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .PROCEDURE_CALL; {
      call_expr, call_ok := ir_lower_expr(stmt, input_fields, output_fields, active_usings.*, active_aliases.*, state);
      if !call_ok return false;
      out_stmt: IR_Stmt;
      out_stmt.kind = .CALL;
      out_stmt.call_expr = call_expr;
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .BLOCK; {
      nested_block := cast(*Code_Block) stmt;
      scoped_usings: [..] IR_Using_Source;
      scoped_aliases: [..] IR_Decl_Alias;
      for active_usings.* array_add(*scoped_usings, it);
      for active_aliases.* array_add(*scoped_aliases, it);
      if !ir_shared_lower_block(nested_block, out_block, input_fields, output_fields, allow_return_value, state, scoped_usings, scoped_aliases, active_defer_entries.*, scope_depth + 1, nearest_loop_scope_depth) return false;
      return true;
    }

    case .RETURN; {
      op := cast(*Code_Return) stmt;
      out_stmt: IR_Stmt;
      out_stmt.kind = .RETURN;
      if op.arguments_sorted.count == 1 {
        if !allow_return_value {
          return_err("IR lowering: return value not allowed in this context", stmt);
        }
        ret_node := op.arguments_sorted[0];
        ret_type := ret_node.type;

        // For entry shader outputs, lower `return { ... }` as assignments to `o` and `return o;`.
        if output_fields.count != 0 && ret_node.kind == .LITERAL {
          ret_lit := cast(*Code_Literal) ret_node;
          if ret_lit.value_type == .STRUCT {
            positional_index := cast(s64) 0;
            for ret_lit.struct_literal_info.arguments {
              field_name := "";
              value_node := it;

              if it.kind == .BINARY_OPERATOR {
                bn := cast(*Code_Binary_Operator) it;
                if bn.operator_type == cast(Operator_Type) #char "=" && bn.left && bn.left.kind == .IDENT {
                  field_name = (cast(*Code_Ident) bn.left).name;
                  value_node = bn.right;
                }
              }

              if field_name.count == 0 {
                if positional_index >= output_fields.count {
                  return_err("IR lowering: struct return literal has more positional fields than output struct", stmt);
                }
                field_name = output_fields[positional_index];
                positional_index += 1;
              }

              expected_rhs_type: *Type_Info = null;
              if field_name.count != 0 {
                expected_rhs_type = ir_shared_find_struct_member_type_by_name(ret_type, field_name);
              } else if positional_index > 0 {
                expected_rhs_type = ir_shared_find_struct_member_type_by_index(ret_type, positional_index - 1);
              }

              rhs, rhs_ok := ir_lower_expr(value_node, input_fields, output_fields, active_usings.*, active_aliases.*, state, expected_rhs_type);
              if !rhs_ok return false;

              lhs_base := ir_expr_new(.IDENT);
              lhs_base.text = "o";
              lhs := ir_expr_new(.MEMBER);
              lhs.left = lhs_base;
              lhs.text = field_name;

              assign_stmt: IR_Stmt;
              assign_stmt.kind = .BINARY;
              assign_stmt.binary_left = lhs;
              assign_stmt.binary_op = "=";
              assign_stmt.binary_right = rhs;
              array_add(*out_block.statements, assign_stmt);
            }

            out_stmt.return_expr = ir_expr_new(.IDENT);
            out_stmt.return_expr.text = "o";
            ir_shared_emit_deferred_for_exit(out_block, active_defer_entries.*, 0);
            array_add(*out_block.statements, out_stmt);
            return true;
          }
        }

        ret_expr, ret_ok := ir_lower_expr(ret_node, input_fields, output_fields, active_usings.*, active_aliases.*, state, ret_type);
        if !ret_ok return false;
        out_stmt.return_expr = ret_expr;
      } else if op.arguments_sorted.count > 1 {
        return_err("IR lowering: multi-value return is unsupported", stmt);
      }
      ir_shared_emit_deferred_for_exit(out_block, active_defer_entries.*, 0);
      array_add(*out_block.statements, out_stmt);
      return true;
    }

    case .USING; {
      op := cast(*Code_Using) stmt;
      if !op.expression {
        return_err("IR lowering: malformed using statement (missing expression)", stmt);
      }
      if op.filter_type != .NONE {
        return_err("IR lowering: using filters (only/except/map) are unsupported", stmt);
      }

      using_type := op.expression.type;
      if !using_type || using_type.type != .STRUCT {
        return_err("IR lowering: using currently supports struct expressions only", op.expression);
      }
      using_struct := cast(*Type_Info_Struct) using_type;

      src: IR_Using_Source;
      src.expression_node = op.expression;
      for *using_struct.members array_add(*src.field_names, it.name);
      array_add(active_usings, src);

      if output_fields.count != 0 && ir_shared_struct_fields_match_names(using_type, output_fields) {
        if op.expression.kind == .IDENT {
          ident := cast(*Code_Ident) op.expression;
          if ident.resolved_declaration {
            array_add(active_aliases, .{
              declaration = ident.resolved_declaration,
              replacement_text = "o",
            });
          }
        } else if op.expression.kind == .DECLARATION {
          decl := cast(*Code_Declaration) op.expression;
          array_add(active_aliases, .{
            declaration = decl,
            replacement_text = "o",
          });
        }
      }
      return true;
    }

    case .DIRECTIVE_RUN; {
      // Ignore compile-time directives (e.g. #assert) inside inline helper bodies.
      return true;
    }
  }

  return_err(tprint("IR lowering: unsupported statement node kind (%)", stmt.kind), stmt);
}

ir_shared_append_deferred_statements :: (out_block: *IR_Block, defer_blocks: [] IR_Block) {
  assert(out_block != null);
  if defer_blocks.count == 0 return;
  i := defer_blocks.count - 1;
  while i >= 0 {
    defer_block := defer_blocks[i];
    for defer_block.statements array_add(*out_block.statements, it);
    if i == 0 break;
    i -= 1;
  }
}

IR_Active_Defer :: struct {
  scope_depth: s64;
  block: IR_Block;
}

ir_shared_emit_deferred_for_exit :: (out_block: *IR_Block, active_defer_entries: [] IR_Active_Defer, min_scope_depth: s64) {
  assert(out_block != null);
  if active_defer_entries.count == 0 return;
  i := active_defer_entries.count - 1;
  while i >= 0 {
    entry := active_defer_entries[i];
    if entry.scope_depth >= min_scope_depth {
      for entry.block.statements array_add(*out_block.statements, it);
    }
    if i == 0 break;
    i -= 1;
  }
}

ir_shared_lower_block :: (block: *Code_Block,
                          out_block: *IR_Block,
                          input_fields: [] string,
                          output_fields: [] string,
                          allow_return_value: bool,
                          state: *IR_Lowering_State,
                          incoming_usings: [] IR_Using_Source = .[],
                          incoming_aliases: [] IR_Decl_Alias = .[],
                          incoming_defer_entries: [] IR_Active_Defer = .[],
                          scope_depth: s64 = 0,
                          nearest_loop_scope_depth: s64 = -1) -> bool {
  return_err :: (message: string, node: *Code_Node = null) #expand {
    ir_set_diagnostic(state, message, node);
    `return false;
  }

  assert(out_block != null);
  assert(state != null);
  if !block return true;
  active_usings: [..] IR_Using_Source;
  for incoming_usings array_add(*active_usings, it);
  active_aliases: [..] IR_Decl_Alias;
  for incoming_aliases array_add(*active_aliases, it);
  active_defer_entries: [..] IR_Active_Defer;
  for incoming_defer_entries array_add(*active_defer_entries, it);
  local_defer_blocks: [..] IR_Block;
  for block.statements {
    if it.kind == .DEFER {
      defer_node := cast(*Code_Defer) it;
      if !defer_node.block {
        return_err("IR lowering: malformed defer statement (missing block).", it);
      }
      defer_block: IR_Block;
      if !ir_shared_lower_block(defer_node.block, *defer_block, input_fields, output_fields, allow_return_value, state, active_usings, active_aliases, active_defer_entries, scope_depth + 1, nearest_loop_scope_depth) return false;
      array_add(*active_defer_entries, .{scope_depth = scope_depth, block = defer_block});
      array_add(*local_defer_blocks, defer_block);
      continue;
    }

    if !ir_shared_lower_stmt(it, out_block, input_fields, output_fields, allow_return_value, *active_usings, *active_aliases, *active_defer_entries, scope_depth, nearest_loop_scope_depth, state) return false;
  }
  ir_shared_append_deferred_statements(out_block, local_defer_blocks);
  return true;
}

ir_shared_header_in_list :: (headers: *[..] *Code_Procedure_Header, header: *Code_Procedure_Header) -> bool {
  for headers.* if it == header return true;
  return false;
}

ir_shared_is_slang_builtin_name :: (name: string) -> bool {
  if name == "floor" return true;
  if name == "ceil" return true;
  if name == "min" return true;
  if name == "max" return true;
  if name == "abs" return true;
  if name == "sqrt" return true;
  if name == "sin" return true;
  if name == "cos" return true;
  if name == "tan" return true;
  if name == "pow" return true;
  if name == "radians" return true;
  if name == "degrees" return true;
  if name == "exp" return true;
  if name == "log" return true;
  if name == "mod" return true;
  if name == "clamp" return true;
  if name == "step" return true;
  if name == "smoothstep" return true;
  if name == "fract" return true;
  if name == "length" return true;
  if name == "normalize" return true;
  if name == "dot" return true;
  if name == "cross" return true;
  if name == "mix" return true;
  if name == "sample_2d" return true;
  if name == "write_2d" return true;
  has_sample_2d, _ := contains(name, "sample_2d");
  if has_sample_2d return true;
  has_write_2d, _ := contains(name, "write_2d");
  if has_write_2d return true;
  return false;
}

ir_shared_collect_calls_in_node :: (node: *Code_Node, called_headers: *[..] *Code_Procedure_Header) {
  if !node return;

  if node.kind == {
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      header: *Code_Procedure_Header;
      if pc.resolved_procedure_expression && pc.resolved_procedure_expression.kind == .PROCEDURE_HEADER {
        header = cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
      } else if pc.procedure_expression && pc.procedure_expression.kind == .IDENT {
        ident := cast(*Code_Ident) pc.procedure_expression;
        if ident.resolved_declaration && ident.resolved_declaration.expression &&
          ident.resolved_declaration.expression.kind == .PROCEDURE_HEADER {
          header = cast(*Code_Procedure_Header) ident.resolved_declaration.expression;
        }
      }

      if header {
        if ir_shared_is_slang_builtin_name(header.name) {
          // Keep as direct call in emitted Slang instead of lowering Jai stdlib bodies.
        } else if header.body_or_null && !ir_shared_header_in_list(called_headers, header) {
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

    case .COMPOUND_DECLARATION; {
      op := cast(*Code_Compound_Declaration) node;
      if op.comma_separated_assignment {
        for op.comma_separated_assignment.arguments {
          arg_node := it.node;
          if !arg_node continue;
          ir_shared_collect_calls_in_node(arg_node, called_headers);
          if arg_node.kind == .IDENT {
            ident := cast(*Code_Ident) arg_node;
            if ident.resolved_declaration {
              ir_shared_collect_calls_in_node(cast(*Code_Node) ident.resolved_declaration, called_headers);
            }
          }
        }
      }
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

    case .EXTRACT; {
      op := cast(*Code_Extract) node;
      if op.from ir_shared_collect_calls_in_node(op.from, called_headers);
      return;
    }

    case .COMMA_SEPARATED_ARGUMENTS; {
      op := cast(*Code_Comma_Separated_Arguments) node;
      for op.arguments if it.node ir_shared_collect_calls_in_node(it.node, called_headers);
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

ir_shared_lower_function :: (header: *Code_Procedure_Header, state: *IR_Lowering_State) -> (IR_Function, bool) {
  assert(state != null);
  
  out: IR_Function;
  if !header return out, false;
  if !header.body_or_null || !header.body_or_null.block return out, false;
  if header.returns.count > 1 return out, false;

  out.name = header.name;
  if header.returns.count == 1 {
    ret := header.returns[0];
    ret_type := ifx ret.type_inst then ret.type_inst.result else ifx ret.expression then ret.expression.type else null;
    ret_ir_type, ret_ir_ok := ir_type_from_type_info(ret_type);
    if !ret_ir_ok return out, false;
    ret_name, ret_ok := ir_type_to_shader_name(ret_type);
    if !ret_ok return out, false;
    out.return_type = ret_ir_type;
    out.return_type_name = ret_name;
  } else {
    out.return_type = .{kind = .UNKNOWN, display_name = "void"};
    out.return_type_name = "void";
  }

  for header.arguments {
    arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
    arg_type_name, arg_ok := ir_type_to_shader_name(arg_type);
    if !arg_ok return out, false;
    original_type_name, original_ok := ir_type_to_original_name(arg_type);
    if !original_ok return out, false;
    arg_ir_type, arg_ir_type_ok := ir_type_from_type_info(arg_type);
    if !arg_ir_type_ok return out, false;
    pointee_name := "";
    pointee_ok := false;
    pointee_is_struct := false;
    if arg_type && arg_type.type == .POINTER {
      pointee_name, pointee_ok, pointee_is_struct = ir_pointer_pointee_lowered_name(arg_type);
      if !pointee_ok return out, false;
    }
    array_add(*out.args, .{
      name = it.name,
      type = arg_ir_type,
      type_name = arg_type_name,
      original_type_name = original_type_name,
      is_pointer = arg_type && arg_type.type == .POINTER,
      pointer_pointee_type_name = pointee_name,
      pointer_pointee_is_struct = pointee_is_struct,
    });
  }

  if !ir_shared_lower_block(header.body_or_null.block, *out.body, .[], .[], header.returns.count == 1, state, .[], .[]) return out, false;
  return out, true;
}

ir_shared_collect_functions_recursive :: (header: *Code_Procedure_Header,
                                          seen_headers: *[..] *Code_Procedure_Header,
                                          functions: *[..] IR_Function,
                                          main_header: *Code_Procedure_Header,
                                          state: *IR_Lowering_State) -> bool {
  assert(state != null);
  if !header || !header.body_or_null || !header.body_or_null.block return false;
  if ir_shared_header_in_list(seen_headers, header) return true;
  array_add(seen_headers, header);

  called: [..] *Code_Procedure_Header;
  for header.body_or_null.block.statements ir_shared_collect_calls_in_node(it, *called);
  for called {
    if it == main_header continue;
    if !ir_shared_collect_functions_recursive(it, seen_headers, functions, main_header, state) return false;
  }

  if header != main_header {
    function_ir, ok := ir_shared_lower_function(header, state);
    if !ok return false;
    array_add(functions, function_ir);
  }
  return true;
}

ir_function_signature_string :: (ir_function: *IR_Function, include_arg_names: bool) -> string {
  b: String_Builder;
  ret_type_name := ir_function.return_type_name;
  if ir_function.return_type.display_name.count != 0 ret_type_name = ir_function.return_type.display_name;
  append(*b, ret_type_name, " ", ir_function.name, "(");
  for ir_function.args {
    if it_index != 0 append(*b, ", ");
    arg_type_name := it.type_name;
    if it.type.display_name.count != 0 arg_type_name = it.type.display_name;
    if include_arg_names append(*b, tprint("% %", arg_type_name, it.name));
    else append(*b, arg_type_name);
  }
  append(*b, ")");
  return builder_to_string(*b);
}

ir_emit_function_prototypes :: (sb: *String_Builder, functions: [] IR_Function) {
  if functions.count == 0 return;
  for functions {
    append(sb, ir_function_signature_string(*it, include_arg_names=true), ";\n");
  }
  append(sb, "\n");
}

ir_emit_function_definitions :: (sb: *String_Builder, functions: [] IR_Function) -> bool {
  assert(sb != null);
  if functions.count == 0 return true;
  for functions {
    a(sb, ir_function_signature_string(*it, include_arg_names=true), " {");
    body_lines: [..] string;
    if !ir_emit_ir_block_lines(*body_lines, *it.body, 1) return false;
    for body_lines a(sb, it);
    a(sb, "}\n");
  }
  return true;
}

ir_add_function_unique_by_name :: (functions: *[..] IR_Function, ir_function: IR_Function) {
  for functions.* if it.name == ir_function.name return;
  array_add(functions, ir_function);
}
