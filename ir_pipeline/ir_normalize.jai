// Canonicalize IR into a smaller set of control-flow shapes so backends need fewer special cases.
#scope_export

normalize_shader :: (shader: *IR_Shader) {
  assert(shader != null);

  for *shader.functions {
    normalize_value_return_if_chains_in_block(*it.body);
    normalize_function_struct_returns_to_temp(it);
    
    // Struct-return normalization can turn `return Struct.{...}` into
    // `tmp := Struct.{...}; return tmp;`, so run return-if canonicalization
    // again to catch newly multi-statement returning branches.
    normalize_value_return_if_chains_in_block(*it.body);
  }
  normalize_value_return_if_chains_in_block(*shader.body);
} @jdll_export


#scope_module

stmt_is_hard_terminator :: (stmt: *IR_Stmt) -> bool {
  if !stmt return false;
  return stmt.kind == .RETURN || stmt.kind == .BREAK || stmt.kind == .CONTINUE;
}

stmt_guarantees_value_return :: (stmt: *IR_Stmt) -> bool {
  if !stmt return false;
  if stmt.kind == .RETURN return stmt.return_expr != null;
  if stmt.kind == .IF && stmt.if_then && stmt.if_else {
    return block_guarantees_value_return(stmt.if_then) && block_guarantees_value_return(stmt.if_else);
  }
  return false;
}

block_guarantees_value_return :: (block: *IR_Block) -> bool {
  if !block return false;
  if block.statements.count == 0 return false;
  if block.statements.count > 1 {
    for i: 0..block.statements.count-2 {
      stmt := *block.statements[i];
      if stmt_is_hard_terminator(stmt) return false;
    }
  }
  return stmt_guarantees_value_return(*block.statements[block.statements.count-1]);
}

normalize_stmt_children :: (stmt: *IR_Stmt) -> bool {
  assert(stmt != null);
  changed := false;
  if stmt.if_then changed = normalize_value_return_if_chains_in_block(stmt.if_then) || changed;
  if stmt.if_else changed = normalize_value_return_if_chains_in_block(stmt.if_else) || changed;
  for stmt.switch_cases if it.body changed = normalize_value_return_if_chains_in_block(it.body) || changed;
  if stmt.for_body changed = normalize_value_return_if_chains_in_block(stmt.for_body) || changed;
  if stmt.while_body changed = normalize_value_return_if_chains_in_block(stmt.while_body) || changed;
  return changed;
}

normalize_value_return_if_chains_in_block :: (block: *IR_Block) -> bool {
  assert(block != null);
  changed_any := false;

  changed_in_pass := true;
  while changed_in_pass {
    changed_in_pass = false;
    i: s64 = 0;
    while i < block.statements.count {
      stmt := *block.statements[i];
      if normalize_stmt_children(stmt) changed_any = true;

      // Canonicalize:
      //   if (cond) return X;
      //   tail...
      // into:
      //   if (cond) return X;
      //   else { tail... }
      if stmt.kind == .IF &&
         stmt.if_else == null &&
         block_guarantees_value_return(stmt.if_then) &&
         i + 1 < block.statements.count {
        else_block := New(IR_Block);
        for j: i+1..block.statements.count-1 array_add(*else_block.statements, block.statements[j]);
        stmt.if_else = else_block;
        block.statements.count = i + 1;
        changed_in_pass = true;
        changed_any = true;
        break;
      }

      i += 1;
    }
  }

  return changed_any;
}

make_ident_expr :: (name: string) -> *IR_Expr {
  ident := New(IR_Expr);
  ident.kind = .IDENT;
  ident.text = name;
  return ident;
}

normalize_struct_return_exprs_in_block :: (block: *IR_Block, return_type: IR_Type, temp_counter: *s64) -> bool {
  assert(block != null);
  assert(temp_counter != null);
  changed := false;

  i: s64 = 0;
  while i < block.statements.count {
    stmt := *block.statements[i];
    if stmt.if_then changed = normalize_struct_return_exprs_in_block(stmt.if_then, return_type, temp_counter) || changed;
    if stmt.if_else changed = normalize_struct_return_exprs_in_block(stmt.if_else, return_type, temp_counter) || changed;
    for stmt.switch_cases if it.body changed = normalize_struct_return_exprs_in_block(it.body, return_type, temp_counter) || changed;
    if stmt.for_body changed = normalize_struct_return_exprs_in_block(stmt.for_body, return_type, temp_counter) || changed;
    if stmt.while_body changed = normalize_struct_return_exprs_in_block(stmt.while_body, return_type, temp_counter) || changed;

    if stmt.kind == .RETURN && stmt.return_expr {
      temp_name := tprint("__ret_struct_%", temp_counter.*);
      temp_counter.* += 1;

      decl_stmt: IR_Stmt;
      decl_stmt.kind = .DECL;
      decl_stmt.decl_type = return_type;
      decl_stmt.decl_name = temp_name;
      decl_stmt.decl_init = stmt.return_expr;

      ret_stmt: IR_Stmt;
      ret_stmt.kind = .RETURN;
      ret_stmt.return_expr = make_ident_expr(temp_name);

      block.statements[i] = decl_stmt;
      array_insert_at(*block.statements, ret_stmt, i + 1);
      changed = true;
      i += 1;
    }

    i += 1;
  }

  return changed;
}

normalize_function_struct_returns_to_temp :: (ir_function: *IR_Function) -> bool {
  assert(ir_function != null);
  if ir_function.return_type.kind != .STRUCT return false;
  counter: s64 = 0;
  return normalize_struct_return_exprs_in_block(*ir_function.body, ir_function.return_type, *counter);
}

#scope_file
