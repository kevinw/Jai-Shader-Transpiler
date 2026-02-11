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
  helpers: [..] IR_Helper_Function;
  body: IR_Block;
}

IR_Fragment_Shader :: struct {
  source_name: string;
  entry_name: string;
  input: IR_Struct;
  output: IR_Struct;
  helpers: [..] IR_Helper_Function;
  body: IR_Block;
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
  body: IR_Block;
}

IR_Compute_Shader :: struct {
  source_name: string;
  entry_name: string;
  input: IR_Struct;
  extra_structs: [..] IR_Struct;
  buffers: [..] IR_Compute_Buffer;
  helpers: [..] IR_Helper_Function;
  body: IR_Block;
}

IR_Using_Source :: struct {
  expression_node: *Code_Node;
  field_names: [..] string;
}

IR_Expr_Kind :: enum {
  IDENT;
  LITERAL;
  UNARY;
  BINARY;
  MEMBER;
  SUBSCRIPT;
  CALL;
  CAST;
  CONSTRUCTOR;
}

IR_Expr :: struct {
  kind: IR_Expr_Kind;
  text: string;
  left: *IR_Expr;
  right: *IR_Expr;
  args: [..] *IR_Expr;
}

IR_Stmt_Kind :: enum {
  DECL;
  BINARY;
  IF;
  SWITCH;
  FOR;
  WHILE;
  BREAK;
  CONTINUE;
  CALL;
  RETURN;
}

IR_Switch_Case :: struct {
  condition: *IR_Expr;
  body: *IR_Block;
  falls_through: bool;
}

IR_Stmt :: struct {
  kind: IR_Stmt_Kind;

  // DECL
  decl_type_name: string;
  decl_name: string;
  decl_init: *IR_Expr;

  // BINARY
  binary_left: *IR_Expr;
  binary_op: string;
  binary_right: *IR_Expr;

  // IF
  if_condition: *IR_Expr;
  if_then: *IR_Block;
  if_else: *IR_Block;

  // SWITCH
  switch_condition: *IR_Expr;
  switch_cases: [..] IR_Switch_Case;

  // FOR
  for_loop_name: string;
  for_start: *IR_Expr;
  for_end: *IR_Expr;
  for_cmp: string;
  for_step: string;
  for_body: *IR_Block;

  // WHILE
  while_condition: *IR_Expr;
  while_body: *IR_Block;

  // CALL
  call_expr: *IR_Expr;

  // RETURN
  return_expr: *IR_Expr;
}

IR_Block :: struct {
  statements: [..] IR_Stmt;
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

ir_add_struct_unique_by_name :: (structs: *[..] IR_Struct, s: IR_Struct) {
  for structs.* if it.name == s.name return;
  array_add(structs, s);
}

ir_name_in_list :: (names: [] string, name: string) -> bool {
  for names if it == name return true;
  return false;
}

ir_lookup_using_field_source :: (active_usings: [] IR_Using_Source, field_name: string) -> (*Code_Node, bool, bool) {
  found_node: *Code_Node = null;
  found := false;
  ambiguous := false;
  for active_usings {
    if !ir_name_in_list(it.field_names, field_name) continue;
    if !found {
      found_node = it.expression_node;
      found = true;
      continue;
    }
    if found_node != it.expression_node {
      ambiguous = true;
      break;
    }
  }
  return found_node, found, ambiguous;
}

ir_binary_operator_to_slang :: (op: Operator_Type) -> string {
  if op == .PLUS_ASSIGN return "+=";
  if op == .MINUS_ASSIGN return "-=";
  if op == .TIMES_ASSIGN return "*=";
  if op == .DIV_ASSIGN return "/=";
  if op == .MOD_ASSIGN return "%=";
  if op == .SHIFT_LEFT return "<<";
  if op == .SHIFT_RIGHT return ">>";
  if op == .SHIFT_LEFT_ASSIGN return "<<=";
  if op == .SHIFT_RIGHT_ASSIGN return ">>=";
  if op == .BITWISE_AND_ASSIGN return "&=";
  if op == .BITWISE_OR_ASSIGN return "|=";
  if op == .BITWISE_XOR_ASSIGN return "^=";
  return operator_string(op);
}

ir_expr_new :: (kind: IR_Expr_Kind) -> *IR_Expr {
  e := New(IR_Expr);
  e.kind = kind;
  return e;
}

ir_literal_to_text :: (lit: *Code_Literal) -> (string, bool) {
  assert(lit != null);
  if lit.value_type == .BOOLEAN return ifx lit._s64 != 0 then "true" else "false", true;
  if lit.value_type == .NUMBER {
    if lit.value_flags & .FLOAT return tprint("%", lit._float64), true;
    if lit.type && lit.type.type == .INTEGER {
      inttype := cast(*Type_Info_Integer) lit.type;
      if inttype.signed return tprint("%", lit._s64), true;
    }
    return tprint("%", lit._u64), true;
  }
  if lit.value_type == .STRING return tprint("\"%\"", lit._string), true;
  return "", false;
}

ir_lower_expr :: (node: *Code_Node, input_fields: [] string, output_fields: [] string, active_usings: [] IR_Using_Source = .[]) -> (*IR_Expr, bool) {
  assert(node != null);

  if node.kind == {
    case .IDENT; {
      ident := cast(*Code_Ident) node;

      if ident.name == "input" || ident.name == "o" || ident.name == "out" || ident.name == "un" {
        out := ir_expr_new(.IDENT);
        out.text = ifx ident.name == "out" then "o" else ident.name;
        return out, true;
      }

      if ir_name_in_list(input_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "input";
        out.text = ident.name;
        return out, true;
      }

      if ir_name_in_list(output_fields, ident.name) {
        out := ir_expr_new(.MEMBER);
        out.left = ir_expr_new(.IDENT);
        out.left.text = "o";
        out.text = ident.name;
        return out, true;
      }

      using_source, found_using, ambiguous := ir_lookup_using_field_source(active_usings, ident.name);
      if ambiguous return null, false;
      if found_using {
        base, ok := ir_lower_expr(using_source, input_fields, output_fields, active_usings);
        if !ok return null, false;
        out := ir_expr_new(.MEMBER);
        out.left = base;
        out.text = ident.name;
        return out, true;
      }

      out := ir_expr_new(.IDENT);
      out.text = ident.name;
      return out, true;
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
        if constructor_name.count == 0 return null, false;

        out := ir_expr_new(.CONSTRUCTOR);
        out.text = constructor_name;
        for lit.struct_literal_info.arguments {
          arg, ok := ir_lower_expr(it, input_fields, output_fields, active_usings);
          if !ok return null, false;
          array_add(*out.args, arg);
        }
        return out, true;
      }

      lit_text, lit_ok := ir_literal_to_text(lit);
      if !lit_ok return null, false;
      out := ir_expr_new(.LITERAL);
      out.text = lit_text;
      return out, true;
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      inner, ok := ir_lower_expr(un.subexpression, input_fields, output_fields, active_usings);
      if !ok return null, false;
      out := ir_expr_new(.UNARY);
      out.text = operator_string(un.operator_type);
      out.left = inner;
      return out, true;
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      left, left_ok := ir_lower_expr(bn.left, input_fields, output_fields, active_usings);
      if !left_ok return null, false;

      if bn.operator_type == .ARRAY_SUBSCRIPT {
        right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings);
        if !right_ok return null, false;
        out := ir_expr_new(.SUBSCRIPT);
        out.left = left;
        out.right = right;
        return out, true;
      }

      op := ir_binary_operator_to_slang(bn.operator_type);
      if op == "." {
        if bn.right && bn.right.kind == .IDENT {
          right_ident := cast(*Code_Ident) bn.right;
          out := ir_expr_new(.MEMBER);
          out.left = left;
          out.text = right_ident.name;
          return out, true;
        }
        return null, false;
      }

      right, right_ok := ir_lower_expr(bn.right, input_fields, output_fields, active_usings);
      if !right_ok return null, false;
      out := ir_expr_new(.BINARY);
      out.text = op;
      out.left = left;
      out.right = right;
      return out, true;
    }

    case .CAST; {
      cast_node := cast(*Code_Cast) node;
      if !cast_node.target_type return null, false;
      target_type_info := cast_node.target_type.result;
      type_name := "";
      if target_type_info {
        t, ok := ir_type_to_slang_name(target_type_info);
        if !ok return null, false;
        type_name = t;
      } else if cast_node.target_type.type_valued_expression && cast_node.target_type.type_valued_expression.kind == .IDENT {
        type_ident := cast(*Code_Ident) cast_node.target_type.type_valued_expression;
        type_name = jai_to_hlsl_type_name(type_ident.name);
      } else {
        return null, false;
      }

      inner, ok := ir_lower_expr(cast_node.expression, input_fields, output_fields, active_usings);
      if !ok return null, false;
      out := ir_expr_new(.CAST);
      out.text = type_name;
      out.left = inner;
      return out, true;
    }

    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      callee, callee_ok := ir_lower_expr(pc.procedure_expression, input_fields, output_fields, active_usings);
      if !callee_ok return null, false;
      out := ir_expr_new(.CALL);
      out.left = callee;
      for pc.arguments_sorted {
        arg, ok := ir_lower_expr(it, input_fields, output_fields, active_usings);
        if !ok return null, false;
        array_add(*out.args, arg);
      }
      return out, true;
    }
  }

  return null, false;
}

ir_expr_to_slang_from_ir :: (expr: *IR_Expr) -> (string, bool) {
  assert(expr != null);

  if expr.kind == {
    case .IDENT;   return expr.text, true;
    case .LITERAL; return expr.text, true;

    case .UNARY; {
      inner, ok := ir_expr_to_slang_from_ir(expr.left);
      if !ok return "", false;
      return tprint("%%", expr.text, inner), true;
    }

    case .BINARY; {
      left, left_ok := ir_expr_to_slang_from_ir(expr.left);
      if !left_ok return "", false;
      right, right_ok := ir_expr_to_slang_from_ir(expr.right);
      if !right_ok return "", false;
      return tprint("(% % %)", left, expr.text, right), true;
    }

    case .MEMBER; {
      left, left_ok := ir_expr_to_slang_from_ir(expr.left);
      if !left_ok return "", false;
      return tprint("%.%", left, expr.text), true;
    }

    case .SUBSCRIPT; {
      left, left_ok := ir_expr_to_slang_from_ir(expr.left);
      if !left_ok return "", false;
      right, right_ok := ir_expr_to_slang_from_ir(expr.right);
      if !right_ok return "", false;
      return tprint("%[%]", left, right), true;
    }

    case .CAST; {
      inner, ok := ir_expr_to_slang_from_ir(expr.left);
      if !ok return "", false;
      return tprint("((%)(%))", expr.text, inner), true;
    }

    case .CALL; {
      callee, callee_ok := ir_expr_to_slang_from_ir(expr.left);
      if !callee_ok return "", false;
      b: String_Builder;
      append(*b, callee, "(");
      for expr.args {
        arg_text, ok := ir_expr_to_slang_from_ir(it);
        if !ok return "", false;
        if it_index != 0 append(*b, ", ");
        append(*b, arg_text);
      }
      append(*b, ")");
      return builder_to_string(*b), true;
    }

    case .CONSTRUCTOR; {
      b: String_Builder;
      append(*b, expr.text, "(");
      for expr.args {
        arg_text, ok := ir_expr_to_slang_from_ir(it);
        if !ok return "", false;
        if it_index != 0 append(*b, ", ");
        append(*b, arg_text);
      }
      append(*b, ")");
      return builder_to_string(*b), true;
    }
  }

  return "", false;
}

ir_expr_to_slang :: (node: *Code_Node, input_fields: [] string, output_fields: [] string, active_usings: [] IR_Using_Source = .[]) -> (string, bool) {
  expr, ok := ir_lower_expr(node, input_fields, output_fields, active_usings);
  if !ok return "", false;
  text, text_ok := ir_expr_to_slang_from_ir(expr);
  if !text_ok return "", false;
  return text, true;
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

// Shared lowering helpers moved to ir_pipeline/ir_shared.jai.

ir_lower_vertex_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Vertex_Shader, bool) {
  out: IR_Vertex_Shader;
  assert(ctx != null);
  if ctx.type != .Vertex return out, false;

  assert(ctx.main_fn.header != null);
  assert(ctx.main_fn.header.body_or_null != null);
  assert(ctx.main_fn.header.body_or_null.block != null);
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
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_helper_functions_recursive(ctx.main_fn.header, *seen_headers, *out.helpers, ctx.main_fn.header) return out, false;
  input_field_names: [..] string;
  output_field_names: [..] string;
  for out.input.fields array_add(*input_field_names, it.name);
  for out.output.fields array_add(*output_field_names, it.name);
  if !ir_shared_lower_block(ctx.main_fn.header.body_or_null.block, *out.body, input_field_names, output_field_names, true, .[]) return out, false;

  return out, true;
}

ir_lower_fragment_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Fragment_Shader, bool) {
  out: IR_Fragment_Shader;
  assert(ctx != null);
  if ctx.type != .Fragment return out, false;

  assert(ctx.main_fn.header != null);
  assert(ctx.main_fn.header.body_or_null != null);
  assert(ctx.main_fn.header.body_or_null.block != null);
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
  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_helper_functions_recursive(ctx.main_fn.header, *seen_headers, *out.helpers, ctx.main_fn.header) return out, false;
  input_field_names: [..] string;
  output_field_names: [..] string;
  for out.input.fields array_add(*input_field_names, it.name);
  for out.output.fields array_add(*output_field_names, it.name);
  if !ir_shared_lower_block(ctx.main_fn.header.body_or_null.block, *out.body, input_field_names, output_field_names, true, .[]) return out, false;

  return out, true;
}

ir_lower_compute_from_shader_context :: (ctx: *Shader_Write_Context) -> (IR_Compute_Shader, bool) {
  out: IR_Compute_Shader;
  assert(ctx != null);
  if ctx.type != .Compute return out, false;

  header := ctx.main_fn.header;
  assert(header != null);
  assert(header.body_or_null != null);
  assert(header.body_or_null.block != null);
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
    if ptr.pointer_to && ptr.pointer_to.type == .STRUCT {
      struct_type := cast(*Type_Info_Struct) ptr.pointer_to;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
      lowered_struct, lowered_ok := ir_lower_struct_from_type(struct_name, ptr.pointer_to);
      if !lowered_ok return out, false;
      ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
    }
    array_add(*out.buffers, .{
      name = arg.name,
      element_type_name = elem_type_name,
    });
  }

  seen_headers: [..] *Code_Procedure_Header;
  if !ir_shared_collect_helper_functions_recursive(header, *seen_headers, *out.helpers, header) return out, false;

  for seen_headers {
    if it == header continue;
    for it.arguments {
      arg_type := ifx it.type_inst then it.type_inst.result else ifx it.expression then it.expression.type else null;
      if !arg_type || arg_type.type != .STRUCT continue;
      struct_type := cast(*Type_Info_Struct) arg_type;
      struct_name := jai_to_hlsl_type_name(get_struct_type_name(struct_type));
      lowered_struct, lowered_ok := ir_lower_struct_from_type(struct_name, arg_type);
      if !lowered_ok return out, false;
      ir_add_struct_unique_by_name(*out.extra_structs, lowered_struct);
    }
  }

  input_field_names: [..] string;
  for out.input.fields array_add(*input_field_names, it.name);
  if !ir_shared_lower_block(header.body_or_null.block, *out.body, input_field_names, .[], false, .[]) return out, false;
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

ir_block_has_return_stmt :: (block: *IR_Block) -> bool {
  assert(block != null);
  for block.statements {
    if it.kind == .RETURN return true;
    if it.kind == .IF {
      if it.if_then && ir_block_has_return_stmt(it.if_then) return true;
      if it.if_else && ir_block_has_return_stmt(it.if_else) return true;
    } else if it.kind == .FOR {
      if it.for_body && ir_block_has_return_stmt(it.for_body) return true;
    }
  }
  return false;
}

emit_ir_vertex_to_slang :: (shader: IR_Vertex_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);
  ir_emit_helper_prototypes(*sb, shader.helpers);
  if !ir_emit_helper_definitions(*sb, shader.helpers) return "", false;

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input) {\n", shader.output.name, shader.entry_name, shader.input.name));
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");

  if !ir_block_has_return_stmt(*shader.body) {
    position_field := find_output_position_field(*shader.output);
    if position_field.count != 0 append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
    append(*sb, "    return o;\n");
  }
  append(*sb, "}");
  return builder_to_string(*sb), true;
}

emit_ir_fragment_to_slang :: (shader: IR_Fragment_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));

  ir_emit_struct_slang(*sb, *shader.input);
  ir_emit_struct_slang(*sb, *shader.output);
  ir_emit_helper_prototypes(*sb, shader.helpers);
  if !ir_emit_helper_definitions(*sb, shader.helpers) return "", false;

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input) {\n", shader.output.name, shader.entry_name, shader.input.name));
  append(*sb, tprint("    % o = (%)0;\n", shader.output.name, shader.output.name));

  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*shader.body) append(*sb, "    return o;\n");
  append(*sb, "}");
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

  pair_helpers: [..] IR_Helper_Function;
  for vertex.helpers ir_add_helper_unique_by_name(*pair_helpers, it);
  for fragment.helpers ir_add_helper_unique_by_name(*pair_helpers, it);
  ir_emit_helper_prototypes(*sb, pair_helpers);
  if !ir_emit_helper_definitions(*sb, pair_helpers) return "", false;

  append(*sb, "[shader(\"vertex\")]\n");
  append(*sb, tprint("% %(% input) {\n", vertex.output.name, vertex.entry_name, vertex.input.name));
  append(*sb, tprint("    % o = (%)0;\n", vertex.output.name, vertex.output.name));
  vertex_body_lines: [..] string;
  if !ir_emit_ir_block_lines(*vertex_body_lines, *vertex.body, 1) return "", false;
  for vertex_body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*vertex.body) {
    position_field := find_output_position_field(*vertex.output);
    if position_field.count != 0 append(*sb, tprint("    o.% = float4(0.0, 0.0, 0.0, 1.0);\n", position_field));
    append(*sb, "    return o;\n");
  }
  append(*sb, "}\n\n");

  append(*sb, "[shader(\"fragment\")]\n");
  append(*sb, tprint("% %(% input) {\n", fragment.output.name, fragment.entry_name, fragment.input.name));
  append(*sb, tprint("    % o = (%)0;\n", fragment.output.name, fragment.output.name));
  fragment_body_lines: [..] string;
  if !ir_emit_ir_block_lines(*fragment_body_lines, *fragment.body, 1) return "", false;
  for fragment_body_lines append(*sb, it, "\n");
  if !ir_block_has_return_stmt(*fragment.body) append(*sb, "    return o;\n");
  append(*sb, "}\n");

  return builder_to_string(*sb), true;
}

emit_ir_compute_to_slang :: (shader: IR_Compute_Shader) -> (string, bool) {
  if shader.entry_name.count == 0 return "", false;

  sb: String_Builder;
  append(*sb, "// generated_by_ir_pipeline\n");
  append(*sb, tprint("// source_shader: %\n\n", shader.source_name));
  ir_emit_struct_slang(*sb, *shader.input);
  for shader.extra_structs ir_emit_struct_slang(*sb, *it);
  ir_emit_helper_prototypes(*sb, shader.helpers);
  if !ir_emit_helper_definitions(*sb, shader.helpers) return "", false;

  append(*sb, "[shader(\"compute\")]\n");
  append(*sb, "void ");
  append(*sb, shader.entry_name);
  append(*sb, tprint("(% input", shader.input.name));
  for shader.buffers {
    append(*sb, tprint(", RWStructuredBuffer<%> %", it.element_type_name, it.name));
  }
  append(*sb, ") {\n");
  body_lines: [..] string;
  if !ir_emit_ir_block_lines(*body_lines, *shader.body, 1) return "", false;
  for body_lines append(*sb, it, "\n");
  append(*sb, "}\n");
  return builder_to_string(*sb), true;
}
