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

ir_spv_ident_is :: (expr: *IR_Expr, name: string) -> bool {
  return expr != null && expr.kind == .IDENT && expr.text == name;
}

ir_spv_literal_is :: (expr: *IR_Expr, text: string) -> bool {
  return expr != null && expr.kind == .LITERAL && expr.text == text;
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

ir_spv_match_branch_condition_inner :: (expr: *IR_Expr) -> (u32, u32, bool) {
  if !expr || expr.kind != .BINARY || expr.text != "==" return 0, 0, false;
  mod_expr := expr.left;
  if !mod_expr || mod_expr.kind != .BINARY || mod_expr.text != "%" return 0, 0, false;
  if !ir_spv_thread_x_expr(mod_expr.left) return 0, 0, false;

  mod_const, mod_ok := ir_spv_parse_u32_literal_expr(mod_expr.right);
  if !mod_ok return 0, 0, false;
  eq_const, eq_ok := ir_spv_parse_u32_literal_expr(expr.right);
  if !eq_ok return 0, 0, false;
  return mod_const, eq_const, true;
}

ir_spv_parse_linear_formula :: (expr: *IR_Expr, var_name: string) -> (u32, u32, bool) {
  if !expr || expr.kind != .BINARY || expr.text != "+" return 0, 0, false;

  lhs := expr.left;
  rhs := expr.right;

  add_const, add_ok := ir_spv_parse_u32_literal_expr(rhs);
  mul_expr := lhs;
  if !add_ok {
    add_const, add_ok = ir_spv_parse_u32_literal_expr(lhs);
    mul_expr = rhs;
  }
  if !add_ok return 0, 0, false;
  if !mul_expr || mul_expr.kind != .BINARY || mul_expr.text != "*" return 0, 0, false;

  mul_const: u32;
  mul_ok := false;
  if ir_spv_ident_is(mul_expr.left, var_name) {
    mul_const, mul_ok = ir_spv_parse_u32_literal_expr(mul_expr.right);
  } else if ir_spv_ident_is(mul_expr.right, var_name) {
    mul_const, mul_ok = ir_spv_parse_u32_literal_expr(mul_expr.left);
  } else {
    return 0, 0, false;
  }
  if !mul_ok return 0, 0, false;
  return mul_const, add_const, true;
}

ir_spv_match_assign_formula :: (stmt: *IR_Stmt, buffer_name: string, local_name: string) -> (u32, u32, bool) {
  if !stmt || stmt.kind != .BINARY return 0, 0, false;
  if stmt.binary_op != "=" return 0, 0, false;
  if !ir_spv_values_at_thread_x_expr(stmt.binary_left, buffer_name) return 0, 0, false;

  mul_const, add_const, ok := ir_spv_parse_linear_formula(stmt.binary_right, local_name);
  if !ok return 0, 0, false;
  return mul_const, add_const, true;
}

emit_ir_compute_to_spirv_text_branch :: (shader: IR_Compute_Shader) -> (string, bool, IR_Diagnostic) {
  diag: IR_Diagnostic;

  if shader.buffers.count != 1 {
    diag.message = "SPIR-V text backend (prototype): expected exactly one compute buffer.";
    return "", false, diag;
  }
  buffer := shader.buffers[0];
  if buffer.element_type_name != "uint" {
    diag.message = "SPIR-V text backend (prototype): only uint buffers are currently supported.";
    return "", false, diag;
  }

  // Match canonical branch shape:
  // if (thread_id.x < 64) { v := values[thread_id.x]; if ((thread_id.x % 2) == 0) values[...] = v * 3 + 1; else values[...] = v * 5 + 7; }
  if shader.body.statements.count != 1 {
    diag.message = "SPIR-V text backend (prototype): expected one top-level if-statement in compute body.";
    return "", false, diag;
  }
  outer_stmt := shader.body.statements[0];
  bound_const, outer_ok := ir_spv_match_branch_condition_outer(outer_stmt.if_condition);
  if outer_stmt.kind != .IF || !outer_ok {
    diag.message = tprint("SPIR-V text backend (prototype): expected outer condition `thread_id.x < CONST`, got `%`.",
                          ir_spv_expr_text(outer_stmt.if_condition));
    return "", false, diag;
  }
  if bound_const == 0 {
    diag.message = "SPIR-V text backend (prototype): outer bound constant must be > 0.";
    return "", false, diag;
  }
  if outer_stmt.if_else != null {
    diag.message = "SPIR-V text backend (prototype): outer if-else is not supported.";
    return "", false, diag;
  }
  if outer_stmt.if_then == null || outer_stmt.if_then.statements.count != 2 {
    diag.message = "SPIR-V text backend (prototype): expected declaration + nested if in then-block.";
    return "", false, diag;
  }

  decl_stmt := *outer_stmt.if_then.statements[0];
  nested_if := *outer_stmt.if_then.statements[1];
  if decl_stmt.kind != .DECL || decl_stmt.decl_type_name != "uint" {
    diag.message = "SPIR-V text backend (prototype): expected uint local declaration before nested if.";
    return "", false, diag;
  }
  local_name := decl_stmt.decl_name;
  if local_name.count == 0 || !ir_spv_values_at_thread_x_expr(decl_stmt.decl_init, buffer.name) {
    diag.message = "SPIR-V text backend (prototype): expected `v := values[thread_id.x]`-style declaration.";
    return "", false, diag;
  }

  mod_const, eq_const, inner_ok := ir_spv_match_branch_condition_inner(nested_if.if_condition);
  if nested_if.kind != .IF || !inner_ok {
    diag.message = tprint("SPIR-V text backend (prototype): expected nested modulo-equality condition, got `%`.",
                          ir_spv_expr_text(nested_if.if_condition));
    return "", false, diag;
  }
  if mod_const == 0 {
    diag.message = "SPIR-V text backend (prototype): modulo constant must be > 0.";
    return "", false, diag;
  }
  if nested_if.if_then == null || nested_if.if_then.statements.count != 1 {
    diag.message = "SPIR-V text backend (prototype): nested then-block shape is unsupported.";
    return "", false, diag;
  }
  if nested_if.if_else == null || nested_if.if_else.statements.count != 1 {
    diag.message = "SPIR-V text backend (prototype): nested else-block shape is unsupported.";
    return "", false, diag;
  }
  then_mul, then_add, then_ok := ir_spv_match_assign_formula(*nested_if.if_then.statements[0], buffer.name, local_name);
  if !then_ok {
    diag.message = "SPIR-V text backend (prototype): nested then assignment shape is unsupported.";
    return "", false, diag;
  }
  else_mul, else_add, else_ok := ir_spv_match_assign_formula(*nested_if.if_else.statements[0], buffer.name, local_name);
  if !else_ok {
    diag.message = "SPIR-V text backend (prototype): nested else assignment shape is unsupported.";
    return "", false, diag;
  }

  // Emit a canonical SPIR-V module for this matched branch subset.
  // Entry point is emitted as "main" and later renamed to shader.entry_name by spirv-cross.
  spvasm_template :: #string END
; SPIR-V
; Version: 1.5
; Generator: Jai Shader Transpiler IR SPIR-V text backend; 1
; Bound: 55
; Schema: 0
               OpCapability Shader
          %%1 = OpExtInstImport "GLSL.std.450"
               OpMemoryModel Logical GLSL450
               OpEntryPoint GLCompute %%main "main" %%gl_GlobalInvocationID %%_
               OpExecutionMode %%main LocalSize __BOUND__ 1 1
               OpSource Unknown 100000
               OpName %%main "main"
               OpName %%x "x"
               OpName %%gl_GlobalInvocationID "gl_GlobalInvocationID"
               OpName %%v "v"
               OpName %%Values "Values"
               OpMemberName %%Values 0 "__BUFFER_NAME__"
               OpName %%_ "__BUFFER_NAME__"
               OpDecorate %%gl_GlobalInvocationID BuiltIn GlobalInvocationId
               OpDecorate %%_runtimearr_uint ArrayStride 4
               OpDecorate %%Values Block
               OpMemberDecorate %%Values 0 Offset 0
               OpDecorate %%_ Binding 0
               OpDecorate %%_ DescriptorSet 0
               OpDecorate %%gl_WorkGroupSize BuiltIn WorkgroupSize
       %%void = OpTypeVoid
          %%3 = OpTypeFunction %%void
       %%uint = OpTypeInt 32 0
%%_ptr_Function_uint = OpTypePointer Function %%uint
     %%v3uint = OpTypeVector %%uint 3
%%_ptr_Input_v3uint = OpTypePointer Input %%v3uint
%%gl_GlobalInvocationID = OpVariable %%_ptr_Input_v3uint Input
     %%uint_0 = OpConstant %%uint 0
%%_ptr_Input_uint = OpTypePointer Input %%uint
    %%uint_BOUND = OpConstant %%uint __BOUND__
       %%bool = OpTypeBool
%%_runtimearr_uint = OpTypeRuntimeArray %%uint
     %%Values = OpTypeStruct %%_runtimearr_uint
%%_ptr_StorageBuffer_Values = OpTypePointer StorageBuffer %%Values
          %%_ = OpVariable %%_ptr_StorageBuffer_Values StorageBuffer
        %%int = OpTypeInt 32 1
      %%int_0 = OpConstant %%int 0
%%_ptr_StorageBuffer_uint = OpTypePointer StorageBuffer %%uint
     %%uint_MOD = OpConstant %%uint __MOD__
     %%uint_THEN_MUL = OpConstant %%uint __THEN_MUL__
     %%uint_1 = OpConstant %%uint 1
     %%uint_THEN_ADD = OpConstant %%uint __THEN_ADD__
     %%uint_ELSE_MUL = OpConstant %%uint __ELSE_MUL__
     %%uint_ELSE_ADD = OpConstant %%uint __ELSE_ADD__
     %%uint_EQ = OpConstant %%uint __EQ__
%%gl_WorkGroupSize = OpConstantComposite %%v3uint %%uint_BOUND %%uint_1 %%uint_1
       %%main = OpFunction %%void None %%3
          %%5 = OpLabel
          %%x = OpVariable %%_ptr_Function_uint Function
          %%v = OpVariable %%_ptr_Function_uint Function
         %%14 = OpAccessChain %%_ptr_Input_uint %%gl_GlobalInvocationID %%uint_0
         %%15 = OpLoad %%uint %%14
               OpStore %%x %%15
         %%16 = OpLoad %%uint %%x
         %%19 = OpULessThan %%bool %%16 %%uint_BOUND
               OpSelectionMerge %%21 None
               OpBranchConditional %%19 %%20 %%21
         %%20 = OpLabel
         %%29 = OpLoad %%uint %%x
         %%31 = OpAccessChain %%_ptr_StorageBuffer_uint %%_ %%int_0 %%29
         %%32 = OpLoad %%uint %%31
               OpStore %%v %%32
         %%33 = OpLoad %%uint %%x
         %%35 = OpUMod %%uint %%33 %%uint_MOD
         %%36 = OpIEqual %%bool %%35 %%uint_EQ
               OpSelectionMerge %%38 None
               OpBranchConditional %%36 %%37 %%46
         %%37 = OpLabel
         %%39 = OpLoad %%uint %%x
         %%40 = OpLoad %%uint %%v
         %%42 = OpIMul %%uint %%40 %%uint_THEN_MUL
         %%44 = OpIAdd %%uint %%42 %%uint_THEN_ADD
         %%45 = OpAccessChain %%_ptr_StorageBuffer_uint %%_ %%int_0 %%39
               OpStore %%45 %%44
               OpBranch %%38
         %%46 = OpLabel
         %%47 = OpLoad %%uint %%x
         %%48 = OpLoad %%uint %%v
         %%50 = OpIMul %%uint %%48 %%uint_ELSE_MUL
         %%52 = OpIAdd %%uint %%50 %%uint_ELSE_ADD
         %%53 = OpAccessChain %%_ptr_StorageBuffer_uint %%_ %%int_0 %%47
               OpStore %%53 %%52
               OpBranch %%38
         %%38 = OpLabel
               OpBranch %%21
         %%21 = OpLabel
               OpReturn
               OpFunctionEnd
END
  spvasm := replace(spvasm_template, "%%", "%");
  spvasm = replace(spvasm, "__BUFFER_NAME__", buffer.name);
  spvasm = replace(spvasm, "__BOUND__", tprint("%", bound_const));
  spvasm = replace(spvasm, "__MOD__", tprint("%", mod_const));
  spvasm = replace(spvasm, "__THEN_MUL__", tprint("%", then_mul));
  spvasm = replace(spvasm, "__THEN_ADD__", tprint("%", then_add));
  spvasm = replace(spvasm, "__ELSE_MUL__", tprint("%", else_mul));
  spvasm = replace(spvasm, "__ELSE_ADD__", tprint("%", else_add));
  spvasm = replace(spvasm, "__EQ__", tprint("%", eq_const));

  return spvasm, true, diag;
}
