IR_Shader_Kind :: enum {
  Vertex;
  Fragment;
  Compute;
}

IR_Shader_Header_Context :: struct {
  name: string;
  header: *Code_Procedure_Header;
}

IR_Type_Kind :: enum {
  UNKNOWN;
  BOOL;
  I32;
  U32;
  I64;
  U64;
  F32;
  F32x2;
  F32x3;
  F32x4;
  F32x2x2;
  STRUCT;
  POINTER;
  FIXED_ARRAY;
}

IR_Type_Flags :: enum_flags u32 {
  PARAMETER_BLOCK :: 0x1;
}

IR_Type :: struct {
  kind: IR_Type_Kind;
  flags: IR_Type_Flags;
  display_name: string;
  struct_name: string;
  element_kind: IR_Type_Kind;
  element_display_name: string;
  element_struct_name: string;
  array_count: s64;
  pointee_kind: IR_Type_Kind;
  pointee_display_name: string;
  pointee_struct_name: string;
  pointee_is_struct: bool;
}

IR_Field :: struct {
  name: string;
  type: IR_Type;
  type_name: string;
  semantic: string;
  original_type_name: string;
  is_pointer: bool;
  pointer_pointee_type_name: string;
  pointer_pointee_is_struct: bool;
}

IR_Struct :: struct {
  name: string;
  fields: [..] IR_Field;
}

IR_Shader :: struct {
  source_name: string;
  entry_name: string;
  kind: IR_Shader_Kind;
  extra_structs: [..] IR_Struct;
  functions: [..] IR_Function;
  body: IR_Block;
}

IR_Graphics_Shader :: struct {
    using #as ir_shader: IR_Shader;
    input: IR_Struct;
    output: IR_Struct;
    args: [..] IR_Function_Arg;
}

IR_Vertex_Shader :: struct {
  using #as ir_graphics_shader: IR_Graphics_Shader;
  kind = .Vertex;
}

IR_Fragment_Shader :: struct {
  using #as ir_graphics_shader: IR_Graphics_Shader;
  kind = .Fragment;
}

IR_Compute_Shader :: struct {
  using #as ir_shader: IR_Shader;
  input: IR_Struct;
  buffers: [..] IR_Compute_Buffer;
}

IR_Compute_Buffer :: struct {
  name: string;
  element_type: IR_Type;
  element_type_name: string;
  is_readonly: bool;
}

IR_Function_Arg :: struct {
  name: string;
  type: IR_Type;
  type_name: string;
  is_readonly: bool;
  original_type_name: string;
  is_pointer: bool;
  pointer_pointee_type_name: string;
  pointer_pointee_is_struct: bool;
}

IR_Function :: struct {
  name: string;
  return_type: IR_Type;
  return_type_name: string;
  args: [..] IR_Function_Arg;
  body: IR_Block;
}

IR_Using_Source :: struct {
  expression_node: *Code_Node;
  source_text: string;
  field_names: [..] string;
}

IR_Decl_Alias :: struct {
  declaration: *Code_Declaration;
  member_name: string;
  replacement_text: string;
}

IR_Expr_Kind :: enum {
  IDENT;
  LITERAL;
  ARRAY_LITERAL;
  UNARY;
  BINARY;
  SELECT;
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
  
  // TODO: union

  // DECL
  decl_type: IR_Type;
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

IR_Diagnostic :: struct {
  message: string;
  location: Source_Code_Location;
  has_location: bool;
}

IR_Lowering_State :: struct {
  first_error: IR_Diagnostic;
}

Toolchain_Target :: enum { METAL; VULKAN_GLSL; }

#scope_file
#import "Compiler";
