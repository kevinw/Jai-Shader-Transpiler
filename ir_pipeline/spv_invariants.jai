#scope_module

ir_validate_builtin_ref :: (expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if !expr return true, {};
  ref := expr.builtin_ref;
  if ref.kind == .NONE return true, {};
  if ref.kind == .GROUP_INDEX {
    if ref.component != -1 {
      return false, make_diag("IR invariant: GROUP_INDEX expression '%' must not carry a component (%).", expr_text(expr), ref.component);
    }
    return true, {};
  }
  if ref.component < -1 || ref.component > 2 {
    return false, make_diag("IR invariant: builtin expression '%' has invalid component %.", expr_text(expr), ref.component);
  }
  return true, {};
}

ir_validate_expr_invariants :: (expr: *IR_Expr) -> (ok: bool, diag: IR_Diagnostic) {
  if !expr return true, {};
  builtin_ok, builtin_diag := ir_validate_builtin_ref(expr);
  if !builtin_ok return false, builtin_diag;
  if expr.kind == .CALL {
    if expr.call_target_kind == .BUILTIN && expr.call_builtin_kind == .NONE {
      return false, make_diag("IR invariant: call expression '%' is marked builtin but has no builtin kind.", expr_text(expr));
    }
    if expr.call_target_kind == .HELPER && expr.call_builtin_kind != .NONE {
      return false, make_diag("IR invariant: call expression '%' is marked helper but also has builtin kind %.", expr_text(expr), expr.call_builtin_kind);
    }
    if expr.call_target_kind != .UNKNOWN {
      if !expr.left || (expr.left.kind != .IDENT && expr.left.kind != .MEMBER) {
        return false, make_diag("IR invariant: typed call metadata on '%' requires ident/member callee expression.", expr_text(expr));
      }
    }
  }
  left_ok, left_diag := ir_validate_expr_invariants(expr.left);
  if !left_ok return false, left_diag;
  right_ok, right_diag := ir_validate_expr_invariants(expr.right);
  if !right_ok return false, right_diag;
  for expr.args {
    arg_ok, arg_diag := ir_validate_expr_invariants(it);
    if !arg_ok return false, arg_diag;
  }
  return true, {};
}

ir_validate_block_invariants :: (block: *IR_Block) -> (ok: bool, diag: IR_Diagnostic) {
  if !block return true, {};
  for block.statements {
    stmt := it;
    if stmt.kind == {
      case .DECL; {
        // Jai declarations default-initialize to zero unless explicitly uninitialized (`---`).
        // Null decl_init is valid and intentionally relies on backend default-initializer emission.
        stmt_ok, stmt_diag := ir_validate_expr_invariants(stmt.decl_init);
        if !stmt_ok return false, stmt_diag;
      }
      case .BINARY; {
        left_ok, left_diag := ir_validate_expr_invariants(stmt.binary_left);
        if !left_ok return false, left_diag;
        right_ok, right_diag := ir_validate_expr_invariants(stmt.binary_right);
        if !right_ok return false, right_diag;
      }
      case .IF; {
        cond_ok, cond_diag := ir_validate_expr_invariants(stmt.if_condition);
        if !cond_ok return false, cond_diag;
        then_ok, then_diag := ir_validate_block_invariants(stmt.if_then);
        if !then_ok return false, then_diag;
        else_ok, else_diag := ir_validate_block_invariants(stmt.if_else);
        if !else_ok return false, else_diag;
      }
      case .SWITCH; {
        cond_ok, cond_diag := ir_validate_expr_invariants(stmt.switch_condition);
        if !cond_ok return false, cond_diag;
        for stmt.switch_cases {
          case_cond_ok, case_cond_diag := ir_validate_expr_invariants(it.condition);
          if !case_cond_ok return false, case_cond_diag;
          case_body_ok, case_body_diag := ir_validate_block_invariants(it.body);
          if !case_body_ok return false, case_body_diag;
        }
      }
      case .FOR; {
        start_ok, start_diag := ir_validate_expr_invariants(stmt.for_start);
        if !start_ok return false, start_diag;
        end_ok, end_diag := ir_validate_expr_invariants(stmt.for_end);
        if !end_ok return false, end_diag;
        body_ok, body_diag := ir_validate_block_invariants(stmt.for_body);
        if !body_ok return false, body_diag;
      }
      case .WHILE; {
        cond_ok, cond_diag := ir_validate_expr_invariants(stmt.while_condition);
        if !cond_ok return false, cond_diag;
        body_ok, body_diag := ir_validate_block_invariants(stmt.while_body);
        if !body_ok return false, body_diag;
      }
      case .CALL; {
        call_ok, call_diag := ir_validate_expr_invariants(stmt.call_expr);
        if !call_ok return false, call_diag;
      }
      case .RETURN; {
        ret_ok, ret_diag := ir_validate_expr_invariants(stmt.return_expr);
        if !ret_ok return false, ret_diag;
      }
      case .BREAK;
      case .CONTINUE;
    }
  }
  return true, {};
}

ir_validate_shader_invariants :: (shader: *IR_Shader) -> (ok: bool, diag: IR_Diagnostic) {
  if !shader return false, make_diag("IR invariant: shader pointer is null.");
  body_ok, body_diag := ir_validate_block_invariants(*shader.body);
  if !body_ok return false, body_diag;
  for shader.functions {
    func_ok, func_diag := ir_validate_block_invariants(*it.body);
    if !func_ok return false, func_diag;
  }
  return true, {};
}
