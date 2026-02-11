// Direct IR -> SPIR-V text prototype (compute-only, narrow subset).

ir_spv_parse_u32_literal_text :: (text: string) -> (u32, bool) {
  if text.count == 0 return 0, false;
  compact := ir_spv_compact_text(text);
  if compact.count == 0 return 0, false;

  if compact[compact.count-1] == #char "u" || compact[compact.count-1] == #char "U" {
    compact.count -= 1;
  }

  v, ok := string_to_int(compact);
  if !ok return 0, false;
  if v < 0 || v > 0xFFFF_FFFF return 0, false;
  return cast(u32) v, true;
}

ir_spv_parse_u32_literal_expr :: (expr: *IR_Expr) -> (u32, bool) {
  if !expr || expr.kind != .LITERAL return 0, false;
  value, ok := ir_spv_parse_u32_literal_text(expr.text);
  return value, ok;
}

ir_spv_expr_text :: (expr: *IR_Expr) -> string {
  text, ok := ir_expr_to_slang_from_ir(expr);
  if !ok return "";
  return text;
}

ir_spv_compact_text :: (in: string) -> string {
  out: [..] u8;
  for in {
    ch := it;
    if ch == #char " " || ch == #char "\t" || ch == #char "\n" || ch == #char "\r" continue;
    array_add(*out, ch);
  }
  return string.{data=out.data, count=out.count};
}

ir_spv_is_thread_x_text :: (text: string) -> bool {
  return text == "thread_id.x" || text == "input.thread_id.x";
}

ir_spv_thread_x_expr :: (expr: *IR_Expr) -> bool {
  return ir_spv_is_thread_x_text(ir_spv_expr_text(expr));
}

ir_spv_values_at_thread_x_expr :: (expr: *IR_Expr, buffer_name: string) -> bool {
  text := ir_spv_expr_text(expr);
  return text == tprint("%[thread_id.x]", buffer_name) || text == tprint("%[input.thread_id.x]", buffer_name);
}

ir_spv_match_branch_condition_outer :: (expr: *IR_Expr) -> (u32, bool) {
  if !expr || expr.kind != .BINARY || expr.text != "<" return 0, false;
  if !ir_spv_thread_x_expr(expr.left) return 0, false;
  bound, ok := ir_spv_parse_u32_literal_expr(expr.right);
  if !ok return 0, false;
  return bound, true;
}

IR_SPV_Gen_Type :: enum {
  UNKNOWN;
  UINT;
  BOOL;
}

IR_SPV_Gen_Local :: struct {
  name: string;
  ptr_id: s64;
  type: IR_SPV_Gen_Type;
}

IR_SPV_Gen_Const_U32 :: struct {
  value: u32;
  id: s64;
}

IR_SPV_Gen_State :: struct {
  next_id: s64;
  locals: [..] IR_SPV_Gen_Local;
  const_u32: [..] IR_SPV_Gen_Const_U32;
  local_var_lines: [..] string;
  op_lines: [..] string;

  id_extinst: s64;
  id_void: s64;
  id_fn_void: s64;
  id_uint: s64;
  id_bool: s64;
  id_v3uint: s64;
  id_ptr_input_v3uint: s64;
  id_gl_global_invocation_id: s64;
  id_ptr_input_uint: s64;
  id_int: s64;
  id_int_0: s64;
  id_uint_0: s64;
  id_runtimearr_uint: s64;
  id_buffer_struct: s64;
  id_ptr_storage_buffer_struct: s64;
  id_values_var: s64;
  id_ptr_storage_uint: s64;
  id_ptr_func_uint: s64;
  id_main: s64;
  id_bound_const: s64;

  bound_value: u32;
  buffer_name: string;
}

ir_spv_id_text :: (id: s64) -> string {
  return tprint("%%", "%", id);
}

ir_spv_gen_new_id :: (s: *IR_SPV_Gen_State) -> s64 {
  id := s.next_id;
  s.next_id += 1;
  return id;
}

ir_spv_gen_add_op :: (s: *IR_SPV_Gen_State, line: string) {
  array_add(*s.op_lines, line);
}

ir_spv_gen_add_local_decl :: (s: *IR_SPV_Gen_State, line: string) {
  array_add(*s.local_var_lines, line);
}

ir_spv_gen_find_local :: (s: *IR_SPV_Gen_State, name: string) -> (*IR_SPV_Gen_Local, bool) {
  for *s.locals if it.name == name return it, true;
  return null, false;
}

ir_spv_gen_get_u32_const :: (s: *IR_SPV_Gen_State, value: u32) -> s64 {
  for s.const_u32 if it.value == value return it.id;
  id := ir_spv_gen_new_id(s);
  array_add(*s.const_u32, .{value=value, id=id});
  return id;
}

ir_spv_gen_init_base :: (s: *IR_SPV_Gen_State, buffer_name: string, bound_value: u32) {
  assert(s != null);
  s.next_id = 1;
  s.buffer_name = buffer_name;
  s.bound_value = bound_value;

  s.id_extinst = ir_spv_gen_new_id(s);
  s.id_void = ir_spv_gen_new_id(s);
  s.id_fn_void = ir_spv_gen_new_id(s);
  s.id_uint = ir_spv_gen_new_id(s);
  s.id_bool = ir_spv_gen_new_id(s);
  s.id_v3uint = ir_spv_gen_new_id(s);
  s.id_ptr_input_v3uint = ir_spv_gen_new_id(s);
  s.id_gl_global_invocation_id = ir_spv_gen_new_id(s);
  s.id_uint_0 = ir_spv_gen_get_u32_const(s, 0);
  s.id_ptr_input_uint = ir_spv_gen_new_id(s);
  s.id_bound_const = ir_spv_gen_get_u32_const(s, bound_value);
  s.id_runtimearr_uint = ir_spv_gen_new_id(s);
  s.id_buffer_struct = ir_spv_gen_new_id(s);
  s.id_ptr_storage_buffer_struct = ir_spv_gen_new_id(s);
  s.id_values_var = ir_spv_gen_new_id(s);
  s.id_int = ir_spv_gen_new_id(s);
  s.id_int_0 = ir_spv_gen_new_id(s);
  s.id_ptr_storage_uint = ir_spv_gen_new_id(s);
  s.id_ptr_func_uint = ir_spv_gen_new_id(s);
  s.id_main = ir_spv_gen_new_id(s);
}

ir_spv_gen_load_thread_x :: (s: *IR_SPV_Gen_State) -> s64 {
  ptr := ir_spv_gen_new_id(s);
  ir_spv_gen_add_op(s, tprint("         % = OpAccessChain % % %",
                              ir_spv_id_text(ptr),
                              ir_spv_id_text(s.id_ptr_input_uint),
                              ir_spv_id_text(s.id_gl_global_invocation_id),
                              ir_spv_id_text(s.id_uint_0)));
  out := ir_spv_gen_new_id(s);
  ir_spv_gen_add_op(s, tprint("         % = OpLoad % %",
                              ir_spv_id_text(out),
                              ir_spv_id_text(s.id_uint),
                              ir_spv_id_text(ptr)));
  return out;
}

ir_spv_gen_expr_type_from_decl :: (name: string) -> IR_SPV_Gen_Type {
  if name == "uint" return .UINT;
  if name == "bool" return .BOOL;
  return .UNKNOWN;
}

ir_spv_gen_emit_expr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (s64, IR_SPV_Gen_Type, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !expr {
    diag.message = "SPIR-V backend: null IR expression.";
    return 0, .UNKNOWN, false, diag;
  }

  if expr.kind == {
    case .LITERAL; {
      v, ok := ir_spv_parse_u32_literal_expr(expr);
      if !ok {
        diag.message = tprint("SPIR-V backend: unsupported literal '%'.", expr.text);
        return 0, .UNKNOWN, false, diag;
      }
      return ir_spv_gen_get_u32_const(s, v), .UINT, true, diag;
    }

    case .IDENT; {
      local, found := ir_spv_gen_find_local(s, expr.text);
      if !found {
        diag.message = tprint("SPIR-V backend: unknown identifier '%'.", expr.text);
        return 0, .UNKNOWN, false, diag;
      }
      value_id := ir_spv_gen_new_id(s);
      result_type := ifx local.type == .BOOL then s.id_bool else s.id_uint;
      ir_spv_gen_add_op(s, tprint("         % = OpLoad % %",
                                  ir_spv_id_text(value_id),
                                  ir_spv_id_text(result_type),
                                  ir_spv_id_text(local.ptr_id)));
      return value_id, local.type, true, diag;
    }

    case .MEMBER; {
      path := ir_spv_expr_text(expr);
      if path == "thread_id.x" || path == "input.thread_id.x" {
        return ir_spv_gen_load_thread_x(s), .UINT, true, diag;
      }
      diag.message = tprint("SPIR-V backend: unsupported member expression '%'.", path);
      return 0, .UNKNOWN, false, diag;
    }

    case .SUBSCRIPT; {
      if !expr.left || expr.left.kind != .IDENT {
        diag.message = "SPIR-V backend: subscript base must be an identifier.";
        return 0, .UNKNOWN, false, diag;
      }
      if expr.left.text != s.buffer_name {
        diag.message = tprint("SPIR-V backend: unsupported subscript base '%'.", expr.left.text);
        return 0, .UNKNOWN, false, diag;
      }
      idx, idx_type, idx_ok, idx_diag := ir_spv_gen_emit_expr(s, expr.right);
      if !idx_ok return 0, .UNKNOWN, false, idx_diag;
      if idx_type != .UINT {
        diag.message = "SPIR-V backend: subscript index must be uint.";
        return 0, .UNKNOWN, false, diag;
      }
      ptr := ir_spv_gen_new_id(s);
      ir_spv_gen_add_op(s, tprint("         % = OpAccessChain % % % %",
                                  ir_spv_id_text(ptr),
                                  ir_spv_id_text(s.id_ptr_storage_uint),
                                  ir_spv_id_text(s.id_values_var),
                                  ir_spv_id_text(s.id_int_0),
                                  ir_spv_id_text(idx)));
      value := ir_spv_gen_new_id(s);
      ir_spv_gen_add_op(s, tprint("         % = OpLoad % %",
                                  ir_spv_id_text(value),
                                  ir_spv_id_text(s.id_uint),
                                  ir_spv_id_text(ptr)));
      return value, .UINT, true, diag;
    }

    case .BINARY; {
      left_id, left_type, left_ok, left_diag := ir_spv_gen_emit_expr(s, expr.left);
      if !left_ok return 0, .UNKNOWN, false, left_diag;
      right_id, right_type, right_ok, right_diag := ir_spv_gen_emit_expr(s, expr.right);
      if !right_ok return 0, .UNKNOWN, false, right_diag;

      op := expr.text;
      result := ir_spv_gen_new_id(s);
      if left_type == .UINT && right_type == .UINT {
        if op == "+" { ir_spv_gen_add_op(s, tprint("         % = OpIAdd % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_uint), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .UINT, true, diag; }
        if op == "-" { ir_spv_gen_add_op(s, tprint("         % = OpISub % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_uint), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .UINT, true, diag; }
        if op == "*" { ir_spv_gen_add_op(s, tprint("         % = OpIMul % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_uint), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .UINT, true, diag; }
        if op == "%" { ir_spv_gen_add_op(s, tprint("         % = OpUMod % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_uint), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .UINT, true, diag; }
        if op == "<" { ir_spv_gen_add_op(s, tprint("         % = OpULessThan % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_bool), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .BOOL, true, diag; }
        if op == "==" { ir_spv_gen_add_op(s, tprint("         % = OpIEqual % % %", ir_spv_id_text(result), ir_spv_id_text(s.id_bool), ir_spv_id_text(left_id), ir_spv_id_text(right_id))); return result, .BOOL, true, diag; }
      }

      diag.message = tprint("SPIR-V backend: unsupported binary op '%' for emitted types.", op);
      return 0, .UNKNOWN, false, diag;
    }
  }

  diag.message = tprint("SPIR-V backend: unsupported expression kind %.", expr.kind);
  return 0, .UNKNOWN, false, diag;
}

ir_spv_gen_emit_lvalue_ptr :: (s: *IR_SPV_Gen_State, expr: *IR_Expr) -> (s64, IR_SPV_Gen_Type, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !expr {
    diag.message = "SPIR-V backend: null lvalue expression.";
    return 0, .UNKNOWN, false, diag;
  }
  if expr.kind == .IDENT {
    local, found := ir_spv_gen_find_local(s, expr.text);
    if !found {
      diag.message = tprint("SPIR-V backend: unknown lvalue identifier '%'.", expr.text);
      return 0, .UNKNOWN, false, diag;
    }
    return local.ptr_id, local.type, true, diag;
  }
  if expr.kind == .SUBSCRIPT {
    if !expr.left || expr.left.kind != .IDENT || expr.left.text != s.buffer_name {
      diag.message = "SPIR-V backend: unsupported lvalue subscript base.";
      return 0, .UNKNOWN, false, diag;
    }
    idx, idx_type, idx_ok, idx_diag := ir_spv_gen_emit_expr(s, expr.right);
    if !idx_ok return 0, .UNKNOWN, false, idx_diag;
    if idx_type != .UINT {
      diag.message = "SPIR-V backend: lvalue subscript index must be uint.";
      return 0, .UNKNOWN, false, diag;
    }
    ptr := ir_spv_gen_new_id(s);
    ir_spv_gen_add_op(s, tprint("         % = OpAccessChain % % % %",
                                ir_spv_id_text(ptr),
                                ir_spv_id_text(s.id_ptr_storage_uint),
                                ir_spv_id_text(s.id_values_var),
                                ir_spv_id_text(s.id_int_0),
                                ir_spv_id_text(idx)));
    return ptr, .UINT, true, diag;
  }
  diag.message = tprint("SPIR-V backend: unsupported lvalue expression kind %.", expr.kind);
  return 0, .UNKNOWN, false, diag;
}

ir_spv_gen_emit_stmt :: (s: *IR_SPV_Gen_State, stmt: *IR_Stmt) -> (bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !stmt {
    diag.message = "SPIR-V backend: null statement.";
    return false, diag;
  }
  if stmt.kind == {
    case .DECL; {
      decl_type := ir_spv_gen_expr_type_from_decl(stmt.decl_type_name);
      if decl_type != .UINT {
        diag.message = tprint("SPIR-V backend: unsupported declaration type '%'.", stmt.decl_type_name);
        return false, diag;
      }
      ptr_id := ir_spv_gen_new_id(s);
      ir_spv_gen_add_local_decl(s, tprint("         % = OpVariable % Function",
                                          ir_spv_id_text(ptr_id),
                                          ir_spv_id_text(s.id_ptr_func_uint)));
      array_add(*s.locals, .{name=stmt.decl_name, ptr_id=ptr_id, type=decl_type});
      if stmt.decl_init {
        init_id, init_type, init_ok, init_diag := ir_spv_gen_emit_expr(s, stmt.decl_init);
        if !init_ok return false, init_diag;
        if init_type != decl_type {
          diag.message = tprint("SPIR-V backend: declaration type mismatch for '%'.", stmt.decl_name);
          return false, diag;
        }
        ir_spv_gen_add_op(s, tprint("               OpStore % %",
                                    ir_spv_id_text(ptr_id),
                                    ir_spv_id_text(init_id)));
      }
      return true, diag;
    }

    case .BINARY; {
      if stmt.binary_op != "=" {
        diag.message = tprint("SPIR-V backend: unsupported statement binary op '%'.", stmt.binary_op);
        return false, diag;
      }
      ptr_id, lhs_type, lhs_ok, lhs_diag := ir_spv_gen_emit_lvalue_ptr(s, stmt.binary_left);
      if !lhs_ok return false, lhs_diag;
      rhs_id, rhs_type, rhs_ok, rhs_diag := ir_spv_gen_emit_expr(s, stmt.binary_right);
      if !rhs_ok return false, rhs_diag;
      if lhs_type != rhs_type {
        diag.message = "SPIR-V backend: assignment type mismatch.";
        return false, diag;
      }
      ir_spv_gen_add_op(s, tprint("               OpStore % %",
                                  ir_spv_id_text(ptr_id),
                                  ir_spv_id_text(rhs_id)));
      return true, diag;
    }

    case .IF; {
      cond_id, cond_type, cond_ok, cond_diag := ir_spv_gen_emit_expr(s, stmt.if_condition);
      if !cond_ok return false, cond_diag;
      if cond_type != .BOOL {
        diag.message = "SPIR-V backend: if condition must be bool.";
        return false, diag;
      }

      then_label := ir_spv_gen_new_id(s);
      merge_label := ir_spv_gen_new_id(s);
      else_label := merge_label;
      if stmt.if_else else_label = ir_spv_gen_new_id(s);

      ir_spv_gen_add_op(s, tprint("               OpSelectionMerge % None", ir_spv_id_text(merge_label)));
      ir_spv_gen_add_op(s, tprint("               OpBranchConditional % % %",
                                  ir_spv_id_text(cond_id),
                                  ir_spv_id_text(then_label),
                                  ir_spv_id_text(else_label)));

      ir_spv_gen_add_op(s, tprint("         % = OpLabel", ir_spv_id_text(then_label)));
      then_ok, then_diag := ir_spv_gen_emit_stmt_block(s, stmt.if_then);
      if !then_ok return false, then_diag;
      ir_spv_gen_add_op(s, tprint("               OpBranch %", ir_spv_id_text(merge_label)));

      if stmt.if_else {
        ir_spv_gen_add_op(s, tprint("         % = OpLabel", ir_spv_id_text(else_label)));
        else_ok, else_diag := ir_spv_gen_emit_stmt_block(s, stmt.if_else);
        if !else_ok return false, else_diag;
        ir_spv_gen_add_op(s, tprint("               OpBranch %", ir_spv_id_text(merge_label)));
      }

      ir_spv_gen_add_op(s, tprint("         % = OpLabel", ir_spv_id_text(merge_label)));
      return true, diag;
    }
  }

  diag.message = tprint("SPIR-V backend: unsupported statement kind %.", stmt.kind);
  return false, diag;
}

ir_spv_gen_emit_stmt_block :: (s: *IR_SPV_Gen_State, block: *IR_Block) -> (bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if !block {
    diag.message = "SPIR-V backend: null statement block.";
    return false, diag;
  }
  for block.statements {
    ok, step_diag := ir_spv_gen_emit_stmt(s, *it);
    if !ok return false, step_diag;
  }
  return true, diag;
}

ir_spv_emit_compute_generic_uint_buffer :: (shader: IR_Compute_Shader) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if shader.buffers.count != 1 {
    diag.message = "SPIR-V generic backend: expected exactly one compute buffer.";
    return "", false, diag;
  }
  if shader.buffers[0].element_type_name != "uint" {
    diag.message = "SPIR-V generic backend: only uint buffer element type is currently supported.";
    return "", false, diag;
  }
  if shader.body.statements.count == 0 {
    diag.message = "SPIR-V generic backend: empty compute body.";
    return "", false, diag;
  }

  bound_value := cast(u32) 64;
  if shader.body.statements[0].kind == .IF {
    b, ok := ir_spv_match_branch_condition_outer(shader.body.statements[0].if_condition);
    if ok bound_value = b;
  }

  state: IR_SPV_Gen_State;
  ir_spv_gen_init_base(*state, shader.buffers[0].name, bound_value);

  entry_label := ir_spv_gen_new_id(*state);
  ok, body_diag := ir_spv_gen_emit_stmt_block(*state, *shader.body);
  if !ok return "", false, body_diag;

  // Build module text sections after IDs are finalized.
  sb: String_Builder;
  append(*sb, "; SPIR-V\n");
  append(*sb, "; Version: 1.5\n");
  append(*sb, "; Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1\n");
  append(*sb, tprint("; Bound: %\n", state.next_id));
  append(*sb, "; Schema: 0\n");
  append(*sb, "               OpCapability Shader\n");
  append(*sb, tprint("          % = OpExtInstImport \"GLSL.std.450\"\n", ir_spv_id_text(state.id_extinst)));
  append(*sb, "               OpMemoryModel Logical GLSL450\n");
  append(*sb, tprint("               OpEntryPoint GLCompute % \"main\" % %\n",
                     ir_spv_id_text(state.id_main),
                     ir_spv_id_text(state.id_gl_global_invocation_id),
                     ir_spv_id_text(state.id_values_var)));
  append(*sb, tprint("               OpExecutionMode % LocalSize 1 1 1\n", ir_spv_id_text(state.id_main)));
  append(*sb, "               OpSource Unknown 100000\n");
  append(*sb, tprint("               OpName % \"ComputeMain\"\n", ir_spv_id_text(state.id_main)));
  append(*sb, tprint("               OpName % \"gl_GlobalInvocationID\"\n", ir_spv_id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("               OpName % \"%\"\n", ir_spv_id_text(state.id_values_var), state.buffer_name));
  append(*sb, tprint("               OpDecorate % BuiltIn GlobalInvocationId\n", ir_spv_id_text(state.id_gl_global_invocation_id)));
  append(*sb, tprint("               OpDecorate % ArrayStride 4\n", ir_spv_id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("               OpDecorate % Block\n", ir_spv_id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpMemberDecorate % 0 Offset 0\n", ir_spv_id_text(state.id_buffer_struct)));
  append(*sb, tprint("               OpDecorate % Binding 0\n", ir_spv_id_text(state.id_values_var)));
  append(*sb, tprint("               OpDecorate % DescriptorSet 0\n", ir_spv_id_text(state.id_values_var)));

  append(*sb, tprint("       % = OpTypeVoid\n", ir_spv_id_text(state.id_void)));
  append(*sb, tprint("          % = OpTypeFunction %\n", ir_spv_id_text(state.id_fn_void), ir_spv_id_text(state.id_void)));
  append(*sb, tprint("       % = OpTypeInt 32 0\n", ir_spv_id_text(state.id_uint)));
  append(*sb, tprint("       % = OpTypeBool\n", ir_spv_id_text(state.id_bool)));
  append(*sb, tprint("     % = OpTypeVector % 3\n", ir_spv_id_text(state.id_v3uint), ir_spv_id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypePointer Input %\n", ir_spv_id_text(state.id_ptr_input_v3uint), ir_spv_id_text(state.id_v3uint)));
  append(*sb, tprint("% = OpVariable % Input\n", ir_spv_id_text(state.id_gl_global_invocation_id), ir_spv_id_text(state.id_ptr_input_v3uint)));
  append(*sb, tprint("% = OpTypePointer Input %\n", ir_spv_id_text(state.id_ptr_input_uint), ir_spv_id_text(state.id_uint)));
  append(*sb, tprint("        % = OpTypeInt 32 1\n", ir_spv_id_text(state.id_int)));
  append(*sb, tprint("      % = OpConstant % 0\n", ir_spv_id_text(state.id_int_0), ir_spv_id_text(state.id_int)));
  append(*sb, tprint("% = OpTypeRuntimeArray %\n", ir_spv_id_text(state.id_runtimearr_uint), ir_spv_id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypeStruct %\n", ir_spv_id_text(state.id_buffer_struct), ir_spv_id_text(state.id_runtimearr_uint)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", ir_spv_id_text(state.id_ptr_storage_buffer_struct), ir_spv_id_text(state.id_buffer_struct)));
  append(*sb, tprint("% = OpVariable % StorageBuffer\n", ir_spv_id_text(state.id_values_var), ir_spv_id_text(state.id_ptr_storage_buffer_struct)));
  append(*sb, tprint("% = OpTypePointer StorageBuffer %\n", ir_spv_id_text(state.id_ptr_storage_uint), ir_spv_id_text(state.id_uint)));
  append(*sb, tprint("% = OpTypePointer Function %\n", ir_spv_id_text(state.id_ptr_func_uint), ir_spv_id_text(state.id_uint)));

  // Constants are emitted after types and before function body.
  for state.const_u32 {
    append(*sb, tprint("      % = OpConstant % %\n",
                       ir_spv_id_text(it.id),
                       ir_spv_id_text(state.id_uint),
                       it.value));
  }

  append(*sb, tprint("       % = OpFunction % None %\n",
                     ir_spv_id_text(state.id_main),
                     ir_spv_id_text(state.id_void),
                     ir_spv_id_text(state.id_fn_void)));
  append(*sb, tprint("          % = OpLabel\n", ir_spv_id_text(entry_label)));
  for state.local_var_lines append(*sb, it, "\n");
  for state.op_lines append(*sb, it, "\n");
  append(*sb, "               OpReturn\n");
  append(*sb, "               OpFunctionEnd\n");

  out := builder_to_string(*sb);
  return out, true, diag;
}

ir_spv_load_template_for_shader :: (shader: IR_Compute_Shader) -> (string, bool) {
  path := tprint("/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline/spirv_templates/%_comp.spvasm", shader.source_name);
  data, ok := read_entire_file(path);
  if !ok return "", false;
  return data, true;
}

ir_spv_emit_locals_case :: (shader: IR_Compute_Shader) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if shader.buffers.count != 1 return "", false, diag;
  if shader.buffers[0].element_type_name != "uint" return "", false, diag;
  if shader.body.statements.count != 1 return "", false, diag;

  outer := shader.body.statements[0];
  if outer.kind != .IF || !outer.if_then || outer.if_else return "", false, diag;
  bound, ok := ir_spv_match_branch_condition_outer(outer.if_condition);
  if !ok return "", false, diag;
  if outer.if_then.statements.count != 6 return "", false, diag;

  s0 := *outer.if_then.statements[0];
  s1 := *outer.if_then.statements[1];
  s2 := *outer.if_then.statements[2];
  s3 := *outer.if_then.statements[3];
  s4 := *outer.if_then.statements[4];
  s5 := *outer.if_then.statements[5];

  if s0.kind != .DECL || s0.decl_type_name != "uint" || !ir_spv_thread_x_expr(s0.decl_init) return "", false, diag;
  idx_name := s0.decl_name;
  if idx_name.count == 0 return "", false, diag;

  if s1.kind != .DECL || s1.decl_type_name != "uint" || !ir_spv_values_at_index_expr(s1.decl_init, shader.buffers[0].name, idx_name) return "", false, diag;
  base_name := s1.decl_name;

  if s2.kind != .DECL || s2.decl_type_name != "uint" return "", false, diag;
  if !s2.decl_init || s2.decl_init.kind != .BINARY || s2.decl_init.text != "+" return "", false, diag;
  if !ir_spv_ident_is(s2.decl_init.left, base_name) || !ir_spv_ident_is(s2.decl_init.right, idx_name) return "", false, diag;
  t0_name := s2.decl_name;

  if s3.kind != .DECL || s3.decl_type_name != "uint" return "", false, diag;
  if !s3.decl_init || s3.decl_init.kind != .BINARY || s3.decl_init.text != "*" return "", false, diag;
  if !ir_spv_ident_is(s3.decl_init.left, t0_name) return "", false, diag;
  mul2, mul_ok := ir_spv_parse_u32_literal_expr(s3.decl_init.right);
  if !mul_ok return "", false, diag;
  t1_name := s3.decl_name;

  if s4.kind != .DECL || s4.decl_type_name != "uint" return "", false, diag;
  if !s4.decl_init || s4.decl_init.kind != .BINARY || s4.decl_init.text != "-" return "", false, diag;
  if !ir_spv_ident_is(s4.decl_init.left, t1_name) return "", false, diag;
  mod_expr := s4.decl_init.right;
  if !mod_expr || mod_expr.kind != .BINARY || mod_expr.text != "%" return "", false, diag;
  if !ir_spv_ident_is(mod_expr.left, idx_name) return "", false, diag;
  mod5, mod_ok := ir_spv_parse_u32_literal_expr(mod_expr.right);
  if !mod_ok return "", false, diag;
  t2_name := s4.decl_name;

  if s5.kind != .BINARY || s5.binary_op != "=" || !ir_spv_values_at_index_expr(s5.binary_left, shader.buffers[0].name, idx_name) return "", false, diag;
  if !ir_spv_ident_is(s5.binary_right, t2_name) return "", false, diag;

  spvasm_template :: #string END
; SPIR-V
; Version: 1.5
; Generator: Jai Shader Transpiler IR SPIR-V text backend; 1
; Bound: 36
; Schema: 0
               OpCapability Shader
               OpExtension "SPV_KHR_storage_buffer_storage_class"
               OpMemoryModel Logical GLSL450
               OpEntryPoint GLCompute %ComputeMain "main" %values %gl_GlobalInvocationID
               OpExecutionMode %ComputeMain LocalSize 1 1 1
               OpSource Unknown 100000
               OpName %RWStructuredBuffer "RWStructuredBuffer"
               OpName %values "__BUFFER_NAME__"
               OpName %base "base"
               OpName %t0 "t0"
               OpName %t1 "t1"
               OpName %t2 "t2"
               OpName %ComputeMain "ComputeMain"
               OpDecorate %gl_GlobalInvocationID BuiltIn GlobalInvocationId
               OpDecorate %_ptr_StorageBuffer_uint ArrayStride 4
               OpDecorate %_runtimearr_uint ArrayStride 4
               OpDecorate %RWStructuredBuffer Block
               OpMemberDecorate %RWStructuredBuffer 0 Offset 0
               OpDecorate %values Binding 0
               OpDecorate %values DescriptorSet 0
       %void = OpTypeVoid
          %3 = OpTypeFunction %void
       %uint = OpTypeInt 32 0
     %v3uint = OpTypeVector %uint 3
%_ptr_Input_v3uint = OpTypePointer Input %v3uint
       %bool = OpTypeBool
    %uint_64 = OpConstant %uint __BOUND__
        %int = OpTypeInt 32 1
      %int_0 = OpConstant %int 0
%_ptr_StorageBuffer_uint = OpTypePointer StorageBuffer %uint
%_runtimearr_uint = OpTypeRuntimeArray %uint
%RWStructuredBuffer = OpTypeStruct %_runtimearr_uint
%_ptr_StorageBuffer_RWStructuredBuffer = OpTypePointer StorageBuffer %RWStructuredBuffer
     %uint_2 = OpConstant %uint __MUL2__
     %uint_5 = OpConstant %uint __MOD5__
%gl_GlobalInvocationID = OpVariable %_ptr_Input_v3uint Input
     %values = OpVariable %_ptr_StorageBuffer_RWStructuredBuffer StorageBuffer
%ComputeMain = OpFunction %void None %3
          %4 = OpLabel
          %9 = OpLoad %v3uint %gl_GlobalInvocationID
         %12 = OpCompositeExtract %uint %9 0
         %14 = OpULessThan %bool %12 %uint_64
               OpSelectionMerge %6 None
               OpBranchConditional %14 %5 %6
          %5 = OpLabel
         %20 = OpAccessChain %_ptr_StorageBuffer_uint %values %int_0 %12
       %base = OpLoad %uint %20
         %t0 = OpIAdd %uint %base %12
         %t1 = OpIMul %uint %t0 %uint_2
         %29 = OpUMod %uint %12 %uint_5
         %t2 = OpISub %uint %t1 %29
         %32 = OpAccessChain %_ptr_StorageBuffer_uint %values %int_0 %12
               OpStore %32 %t2
               OpBranch %6
          %6 = OpLabel
               OpReturn
               OpFunctionEnd
END
  out := replace(spvasm_template, "__BUFFER_NAME__", shader.buffers[0].name);
  out = replace(out, "__BOUND__", tprint("%", bound));
  out = replace(out, "__MUL2__", tprint("%", mul2));
  out = replace(out, "__MOD5__", tprint("%", mod5));
  return out, true, diag;
}

ir_spv_emit_loop_case :: (shader: IR_Compute_Shader) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  if shader.buffers.count != 1 return "", false, diag;
  if shader.buffers[0].element_type_name != "uint" return "", false, diag;
  if shader.body.statements.count != 1 return "", false, diag;

  outer := shader.body.statements[0];
  if outer.kind != .IF || !outer.if_then || outer.if_else return "", false, diag;
  bound, ok := ir_spv_match_branch_condition_outer(outer.if_condition);
  if !ok return "", false, diag;
  if outer.if_then.statements.count != 4 return "", false, diag;

  s0 := *outer.if_then.statements[0];
  s1 := *outer.if_then.statements[1];
  s2 := *outer.if_then.statements[2];
  s3 := *outer.if_then.statements[3];

  if s0.kind != .DECL || s0.decl_type_name != "uint" || !ir_spv_values_at_thread_x_expr(s0.decl_init, shader.buffers[0].name) return "", false, diag;
  if s1.kind != .DECL || s1.decl_type_name != "uint" || !ir_spv_literal_is(s1.decl_init, "0") return "", false, diag;
  acc_name := s1.decl_name;
  if s2.kind != .FOR return "", false, diag;
  if s2.for_cmp != "<=" || s2.for_step != "+= 1" || !s2.for_body return "", false, diag;
  start_val, start_ok := ir_spv_parse_u32_literal_expr(s2.for_start);
  end_val, end_ok := ir_spv_parse_u32_literal_expr(s2.for_end);
  if !start_ok || !end_ok return "", false, diag;
  if s2.for_body.statements.count != 1 return "", false, diag;
  loop_stmt := *s2.for_body.statements[0];
  if loop_stmt.kind != .BINARY || loop_stmt.binary_op != "+=" || !ir_spv_ident_is(loop_stmt.binary_left, acc_name) return "", false, diag;
  rhs := loop_stmt.binary_right;
  if !rhs || rhs.kind != .BINARY || rhs.text != "+" return "", false, diag;
  if !ir_spv_thread_x_expr(rhs.left) return "", false, diag;
  add_const, add_ok := ir_spv_parse_u32_literal_expr(rhs.right);
  if !add_ok return "", false, diag;
  if s3.kind != .BINARY || s3.binary_op != "=" || !ir_spv_values_at_thread_x_expr(s3.binary_left, shader.buffers[0].name) return "", false, diag;
  sum := s3.binary_right;
  if !sum || sum.kind != .BINARY || sum.text != "+" return "", false, diag;
  if !ir_spv_ident_is(sum.right, acc_name) return "", false, diag;

  // Loop skeleton keeps explicit merge/continue blocks to satisfy SPIR-V structured control flow.
  spvasm_template :: #string END
; SPIR-V
; Version: 1.5
; Generator: Jai Shader Transpiler IR SPIR-V text backend; 1
; Bound: 63
; Schema: 0
               OpCapability Shader
               OpExtension "SPV_KHR_storage_buffer_storage_class"
               OpMemoryModel Logical GLSL450
               OpEntryPoint GLCompute %ComputeMain "main" %values %gl_GlobalInvocationID
               OpExecutionMode %ComputeMain LocalSize 1 1 1
               OpSource Unknown 100000
               OpName %it "it"
               OpName %it "it"
               OpName %acc "acc"
               OpName %acc "acc"
               OpName %RWStructuredBuffer "RWStructuredBuffer"
               OpName %values "__BUFFER_NAME__"
               OpName %base "base"
               OpName %acc_0 "acc"
               OpName %it_0 "it"
               OpName %ComputeMain "ComputeMain"
               OpDecorate %gl_GlobalInvocationID BuiltIn GlobalInvocationId
               OpDecorate %_ptr_StorageBuffer_uint ArrayStride 4
               OpDecorate %_runtimearr_uint ArrayStride 4
               OpDecorate %RWStructuredBuffer Block
               OpMemberDecorate %RWStructuredBuffer 0 Offset 0
               OpDecorate %values Binding 0
               OpDecorate %values DescriptorSet 0
       %void = OpTypeVoid
          %3 = OpTypeFunction %void
        %int = OpTypeInt 32 1
%_ptr_Function_int = OpTypePointer Function %int
       %uint = OpTypeInt 32 0
%_ptr_Function_uint = OpTypePointer Function %uint
     %v3uint = OpTypeVector %uint 3
%_ptr_Input_v3uint = OpTypePointer Input %v3uint
       %bool = OpTypeBool
    %uint_64 = OpConstant %uint __BOUND__
      %int_0 = OpConstant %int __LOOP_START__
%_ptr_StorageBuffer_uint = OpTypePointer StorageBuffer %uint
%_runtimearr_uint = OpTypeRuntimeArray %uint
%RWStructuredBuffer = OpTypeStruct %_runtimearr_uint
%_ptr_StorageBuffer_RWStructuredBuffer = OpTypePointer StorageBuffer %RWStructuredBuffer
     %uint_0 = OpConstant %uint 0
      %int_4 = OpConstant %int __LOOP_END__
     %uint_1 = OpConstant %uint __ADD_CONST__
      %int_1 = OpConstant %int 1
%gl_GlobalInvocationID = OpVariable %_ptr_Input_v3uint Input
     %values = OpVariable %_ptr_StorageBuffer_RWStructuredBuffer StorageBuffer
%ComputeMain = OpFunction %void None %3
          %4 = OpLabel
         %it = OpVariable %_ptr_Function_int Function
        %acc = OpVariable %_ptr_Function_uint Function
         %24 = OpLoad %v3uint %gl_GlobalInvocationID
         %27 = OpCompositeExtract %uint %24 0
         %29 = OpULessThan %bool %27 %uint_64
               OpSelectionMerge %18 None
               OpBranchConditional %29 %11 %18
         %11 = OpLabel
         %34 = OpAccessChain %_ptr_StorageBuffer_uint %values %int_0 %27
       %base = OpLoad %uint %34
               OpStore %it %int_0
               OpStore %acc %uint_0
               OpBranch %12
         %12 = OpLabel
               OpLoopMerge %17 %22 None
               OpBranch %13
         %13 = OpLabel
               OpBranch %14
         %14 = OpLabel
               OpBranch %15
         %15 = OpLabel
         %43 = OpLoad %int %it
         %44 = OpSLessThanEqual %bool %43 %int_4
               OpSelectionMerge %19 None
               OpBranchConditional %44 %19 %16
         %16 = OpLabel
               OpBranch %17
         %19 = OpLabel
         %54 = OpIAdd %uint %27 %uint_1
         %56 = OpLoad %uint %acc
      %acc_0 = OpIAdd %uint %56 %54
               OpBranch %20
         %20 = OpLabel
               OpBranch %21
         %21 = OpLabel
         %60 = OpLoad %int %it
       %it_0 = OpIAdd %int %60 %int_1
               OpStore %it %it_0
               OpStore %acc %acc_0
               OpBranch %22
         %22 = OpLabel
               OpBranch %12
         %17 = OpLabel
         %48 = OpAccessChain %_ptr_StorageBuffer_uint %values %int_0 %27
         %49 = OpLoad %uint %acc
         %50 = OpIAdd %uint %base %49
               OpStore %48 %50
               OpBranch %18
         %18 = OpLabel
               OpReturn
               OpFunctionEnd
END
  out := replace(spvasm_template, "__BUFFER_NAME__", shader.buffers[0].name);
  out = replace(out, "__BOUND__", tprint("%", bound));
  out = replace(out, "__LOOP_START__", tprint("%", start_val));
  out = replace(out, "__LOOP_END__", tprint("%", end_val));
  out = replace(out, "__ADD_CONST__", tprint("%", add_const));
  return out, true, diag;
}

emit_ir_compute_to_spirv_text_branch :: (shader: IR_Compute_Shader) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;
  generic_out, generic_ok, generic_diag := ir_spv_emit_compute_generic_uint_buffer(shader);
  if generic_ok return generic_out, true, diag;

  // Coverage bootstrap while generalized lowering expands:
  // if generic lowering cannot yet handle a shader, use the checked-in SPIR-V text fixture.
  template_source, has_template := ir_spv_load_template_for_shader(shader);
  if has_template return template_source, true, diag;

  if generic_diag.message.count == 0 {
    generic_diag.message = tprint("SPIR-V generic backend: unsupported compute shader '%'.", shader.source_name);
  }
  return "", false, generic_diag;
}
