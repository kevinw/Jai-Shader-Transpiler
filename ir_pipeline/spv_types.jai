#scope_module

IR_SPV_Id_Slot :: enum {
  NONE;
  TYPE_INT;
  TYPE_UINT;
  TYPE_INT64;
  TYPE_UINT64;
  TYPE_FLOAT;
  TYPE_FLOAT2;
  TYPE_FLOAT3;
  TYPE_FLOAT4;
  TYPE_FLOAT2X2;
  TYPE_BOOL;

  PTR_STORAGE_INT;
  PTR_STORAGE_UINT;
  PTR_STORAGE_INT64;
  PTR_STORAGE_UINT64;
  PTR_STORAGE_FLOAT;
  PTR_STORAGE_FLOAT2;
  PTR_STORAGE_FLOAT3;
  PTR_STORAGE_FLOAT4;

  PTR_INPUT_UINT;
  PTR_INPUT_FLOAT;
  PTR_INPUT_FLOAT2;
  PTR_INPUT_FLOAT3;
  PTR_INPUT_FLOAT4;

  PTR_OUTPUT_FLOAT;
  PTR_OUTPUT_FLOAT2;
  PTR_OUTPUT_FLOAT3;
  PTR_OUTPUT_FLOAT4;

  PTR_UNIFORM_INT;
  PTR_UNIFORM_UINT;
  PTR_UNIFORM_INT64;
  PTR_UNIFORM_UINT64;
  PTR_UNIFORM_FLOAT;
  PTR_UNIFORM_FLOAT2;
  PTR_UNIFORM_FLOAT3;
  PTR_UNIFORM_FLOAT4;

  PTR_FUNC_INT;
  PTR_FUNC_UINT;
  PTR_FUNC_INT64;
  PTR_FUNC_UINT64;
  PTR_FUNC_FLOAT;
  PTR_FUNC_FLOAT2;
  PTR_FUNC_FLOAT3;
  PTR_FUNC_FLOAT4;
  PTR_FUNC_FLOAT2X2;
  PTR_FUNC_BOOL;
}

IR_SPV_Kind_Info :: struct {
  kind: IR_SPV_Gen_Type;
  type_slot: IR_SPV_Id_Slot;
  storage_ptr_slot: IR_SPV_Id_Slot;
  input_ptr_slot: IR_SPV_Id_Slot;
  output_ptr_slot: IR_SPV_Id_Slot;
  uniform_ptr_slot: IR_SPV_Id_Slot;
  func_ptr_slot: IR_SPV_Id_Slot;
  byte_size: s64;
  is_integral: bool;
  is_signed: bool;
}

SPV_KIND_INFO :: IR_SPV_Kind_Info.[
  .{kind=.INT,    type_slot=.TYPE_INT,    storage_ptr_slot=.PTR_STORAGE_INT,    input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_INT,    func_ptr_slot=.PTR_FUNC_INT,    byte_size=4,  is_integral=true,  is_signed=true},
  .{kind=.UINT,   type_slot=.TYPE_UINT,   storage_ptr_slot=.PTR_STORAGE_UINT,   input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_UINT,   func_ptr_slot=.PTR_FUNC_UINT,   byte_size=4,  is_integral=true,  is_signed=false},
  .{kind=.INT64,  type_slot=.TYPE_INT64,  storage_ptr_slot=.PTR_STORAGE_INT64,  input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_INT64,  func_ptr_slot=.PTR_FUNC_INT64,  byte_size=8,  is_integral=true,  is_signed=true},
  .{kind=.UINT64, type_slot=.TYPE_UINT64, storage_ptr_slot=.PTR_STORAGE_UINT64, input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_UINT64, func_ptr_slot=.PTR_FUNC_UINT64, byte_size=8,  is_integral=true,  is_signed=false},
  .{kind=.FLOAT,  type_slot=.TYPE_FLOAT,  storage_ptr_slot=.PTR_STORAGE_FLOAT,  input_ptr_slot=.PTR_INPUT_FLOAT, output_ptr_slot=.PTR_OUTPUT_FLOAT,  uniform_ptr_slot=.PTR_UNIFORM_FLOAT,  func_ptr_slot=.PTR_FUNC_FLOAT,  byte_size=4,  is_integral=false, is_signed=false},
  .{kind=.FLOAT2, type_slot=.TYPE_FLOAT2, storage_ptr_slot=.PTR_STORAGE_FLOAT2, input_ptr_slot=.PTR_INPUT_FLOAT2, output_ptr_slot=.PTR_OUTPUT_FLOAT2, uniform_ptr_slot=.PTR_UNIFORM_FLOAT2, func_ptr_slot=.PTR_FUNC_FLOAT2, byte_size=8,  is_integral=false, is_signed=false},
  .{kind=.FLOAT3, type_slot=.TYPE_FLOAT3, storage_ptr_slot=.PTR_STORAGE_FLOAT3, input_ptr_slot=.PTR_INPUT_FLOAT3, output_ptr_slot=.PTR_OUTPUT_FLOAT3, uniform_ptr_slot=.PTR_UNIFORM_FLOAT3, func_ptr_slot=.PTR_FUNC_FLOAT3, byte_size=12, is_integral=false, is_signed=false},
  .{kind=.FLOAT4, type_slot=.TYPE_FLOAT4, storage_ptr_slot=.PTR_STORAGE_FLOAT4, input_ptr_slot=.PTR_INPUT_FLOAT4, output_ptr_slot=.PTR_OUTPUT_FLOAT4, uniform_ptr_slot=.PTR_UNIFORM_FLOAT4, func_ptr_slot=.PTR_FUNC_FLOAT4, byte_size=16, is_integral=false, is_signed=false},
  .{kind=.FLOAT2X2, type_slot=.TYPE_FLOAT2X2, storage_ptr_slot=.NONE,           input_ptr_slot=.NONE,             output_ptr_slot=.NONE,               uniform_ptr_slot=.NONE,               func_ptr_slot=.PTR_FUNC_FLOAT2X2, byte_size=0, is_integral=false, is_signed=false},
  .{kind=.BOOL,   type_slot=.TYPE_BOOL,   storage_ptr_slot=.NONE,               input_ptr_slot=.NONE,             output_ptr_slot=.NONE,               uniform_ptr_slot=.NONE,               func_ptr_slot=.PTR_FUNC_BOOL,   byte_size=0,  is_integral=false, is_signed=false},
];

IR_SPV_Decl_Alias :: struct {
  name: string;
  kind: IR_SPV_Gen_Type;
}

SPV_DECL_ALIASES :: IR_SPV_Decl_Alias.[
  .{name="int", kind=.INT64},
  .{name="s64", kind=.INT64},
  .{name="int64_t", kind=.INT64},
  .{name="u64", kind=.UINT64},
  .{name="uint64_t", kind=.UINT64},
  .{name="s32", kind=.INT},
  .{name="int32_t", kind=.INT},
  .{name="uint", kind=.UINT},
  .{name="u32", kind=.UINT},
  .{name="uint32_t", kind=.UINT},
  .{name="float", kind=.FLOAT},
  .{name="float2", kind=.FLOAT2},
  .{name="float3", kind=.FLOAT3},
  .{name="float4", kind=.FLOAT4},
  .{name="float2x2", kind=.FLOAT2X2},
  .{name="Vector2", kind=.FLOAT2},
  .{name="Vector3", kind=.FLOAT3},
  .{name="Vector4", kind=.FLOAT4},
  .{name="Matrix2", kind=.FLOAT2X2},
  .{name="bool", kind=.BOOL},
];

kind_info :: (kind: IR_SPV_Gen_Type) -> *IR_SPV_Kind_Info {
  for *SPV_KIND_INFO if it.kind == kind return it;
  return null;
}

state_id_from_slot :: (s: *IR_SPV_Gen_State, slot: IR_SPV_Id_Slot) -> s64 {
  assert(s != null);
  if slot == {
    case .NONE; return 0;
    case .TYPE_INT; return s.id_int;
    case .TYPE_UINT; return s.id_uint;
    case .TYPE_INT64; return s.id_int64;
    case .TYPE_UINT64; return s.id_uint64;
    case .TYPE_FLOAT; return s.id_float;
    case .TYPE_FLOAT2; return s.id_float2;
    case .TYPE_FLOAT3; return s.id_float3;
    case .TYPE_FLOAT4; return s.id_float4;
    case .TYPE_FLOAT2X2; return s.id_float2x2;
    case .TYPE_BOOL; return s.id_bool;
    case .PTR_STORAGE_INT; return s.id_ptr_storage_int;
    case .PTR_STORAGE_UINT; return s.id_ptr_storage_uint;
    case .PTR_STORAGE_INT64; return s.id_ptr_storage_int64;
    case .PTR_STORAGE_UINT64; return s.id_ptr_storage_uint64;
    case .PTR_STORAGE_FLOAT; return s.id_ptr_storage_float;
    case .PTR_STORAGE_FLOAT2; return s.id_ptr_storage_float2;
    case .PTR_STORAGE_FLOAT3; return s.id_ptr_storage_float3;
    case .PTR_STORAGE_FLOAT4; return s.id_ptr_storage_float4;
    case .PTR_INPUT_UINT; return s.id_ptr_input_uint;
    case .PTR_INPUT_FLOAT; return s.id_ptr_input_float;
    case .PTR_INPUT_FLOAT2; return s.id_ptr_input_float2;
    case .PTR_INPUT_FLOAT3; return s.id_ptr_input_float3;
    case .PTR_INPUT_FLOAT4; return s.id_ptr_input_float4;
    case .PTR_OUTPUT_FLOAT; return s.id_ptr_output_float;
    case .PTR_OUTPUT_FLOAT2; return s.id_ptr_output_float2;
    case .PTR_OUTPUT_FLOAT3; return s.id_ptr_output_float3;
    case .PTR_OUTPUT_FLOAT4; return s.id_ptr_output_float4;
    case .PTR_UNIFORM_INT; return s.id_ptr_uniform_int;
    case .PTR_UNIFORM_UINT; return s.id_ptr_uniform_uint;
    case .PTR_UNIFORM_INT64; return s.id_ptr_uniform_int64;
    case .PTR_UNIFORM_UINT64; return s.id_ptr_uniform_uint64;
    case .PTR_UNIFORM_FLOAT; return s.id_ptr_uniform_float;
    case .PTR_UNIFORM_FLOAT2; return s.id_ptr_uniform_float2;
    case .PTR_UNIFORM_FLOAT3; return s.id_ptr_uniform_float3;
    case .PTR_UNIFORM_FLOAT4; return s.id_ptr_uniform_float4;
    case .PTR_FUNC_INT; return s.id_ptr_func_int;
    case .PTR_FUNC_UINT; return s.id_ptr_func_uint;
    case .PTR_FUNC_INT64; return s.id_ptr_func_int64;
    case .PTR_FUNC_UINT64; return s.id_ptr_func_uint64;
    case .PTR_FUNC_FLOAT; return s.id_ptr_func_float;
    case .PTR_FUNC_FLOAT2; return s.id_ptr_func_float2;
    case .PTR_FUNC_FLOAT3; return s.id_ptr_func_float3;
    case .PTR_FUNC_FLOAT4; return s.id_ptr_func_float4;
    case .PTR_FUNC_FLOAT2X2; return s.id_ptr_func_float2x2;
    case .PTR_FUNC_BOOL; return s.id_ptr_func_bool;
  }
  return 0;
}

expr_type_from_decl :: (name: string) -> IR_SPV_Gen_Type {
  compact := compact_text(name);
  for SPV_DECL_ALIASES if it.name == compact return it.kind;
  return .UNKNOWN;
}

type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.type_slot);
}

storage_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.storage_ptr_slot);
}

input_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.input_ptr_slot);
}

output_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.output_ptr_slot);
}

uniform_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.uniform_ptr_slot);
}

func_ptr_type_id_from_kind :: (s: *IR_SPV_Gen_State, kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return state_id_from_slot(s, info.func_ptr_slot);
}

byte_size_of_kind :: (kind: IR_SPV_Gen_Type) -> s64 {
  info := kind_info(kind);
  if !info return 0;
  return info.byte_size;
}

is_integral_kind :: (kind: IR_SPV_Gen_Type) -> bool {
  info := kind_info(kind);
  return ifx info then info.is_integral else false;
}

is_signed_integral_kind :: (kind: IR_SPV_Gen_Type) -> bool {
  info := kind_info(kind);
  return ifx info then info.is_signed else false;
}

kind_uses_int64 :: (kind: IR_SPV_Gen_Type) -> bool {
  return kind == .INT64 || kind == .UINT64;
}

state_uses_int64 :: (s: *IR_SPV_Gen_State) -> bool {
  assert(s != null);
  if s.const_i64.count > 0 || s.const_u64.count > 0 return true;
  for s.locals if kind_uses_int64(it.type) return true;
  for s.local_arrays if kind_uses_int64(it.element_type) return true;
  for s.buffers {
    if kind_uses_int64(it.element_kind) return true;
    for it.fields if kind_uses_int64(it.type) return true;
  }
  for s.uniform_blocks for it.fields if kind_uses_int64(it.type) return true;
  for s.input_vars if kind_uses_int64(it.type) return true;
  for s.output_vars if kind_uses_int64(it.type) return true;
  return false;
}

promote_integral_kind :: (a: IR_SPV_Gen_Type, b: IR_SPV_Gen_Type) -> IR_SPV_Gen_Type {
  assert(is_integral_kind(a));
  assert(is_integral_kind(b));
  if a == b return a;
  if a == .INT64 || b == .INT64 return .INT64;
  if a == .UINT64 || b == .UINT64 {
    if a == .INT || b == .INT return .INT64;
    return .UINT64;
  }
  if a == .INT || b == .INT return .INT;
  return .UINT;
}

spv_append_capabilities :: (sb: *String_Builder, state: *IR_SPV_Gen_State, use_physical_storage := false) {
  assert(sb != null);
  assert(state != null);
  append(sb, "               OpCapability Shader\n");
  if state_uses_int64(state) append(sb, "               OpCapability Int64\n");
  if state.uses_write_2d append(sb, "               OpCapability StorageImageWriteWithoutFormat\n");
  if use_physical_storage append(sb, "               OpCapability PhysicalStorageBufferAddresses\n");
}

spv_append_common_type_decls :: (sb: *String_Builder, state: *IR_SPV_Gen_State, storage_class: string) {
  assert(sb != null);
  assert(state != null);
  append(sb, tprint("       % = OpTypeVoid\n", id_text(state.id_void)));
  append(sb, tprint("          % = OpTypeFunction %\n", id_text(state.id_fn_void), id_text(state.id_void)));
  append(sb, tprint("       % = OpTypeInt 32 0\n", id_text(state.id_uint)));
  append(sb, tprint("        % = OpTypeInt 32 1\n", id_text(state.id_int)));
  append(sb, tprint("      % = OpTypeInt 64 1\n", id_text(state.id_int64)));
  append(sb, tprint("      % = OpTypeInt 64 0\n", id_text(state.id_uint64)));
  append(sb, tprint("      % = OpTypeFloat 32\n", id_text(state.id_float)));
  append(sb, tprint("     % = OpTypeVector % 2\n", id_text(state.id_float2), id_text(state.id_float)));
  append(sb, tprint("     % = OpTypeVector % 3\n", id_text(state.id_float3), id_text(state.id_float)));
  append(sb, tprint("     % = OpTypeVector % 4\n", id_text(state.id_float4), id_text(state.id_float)));
  append(sb, tprint("   % = OpTypeMatrix % 2\n", id_text(state.id_float2x2), id_text(state.id_float2)));
  append(sb, tprint("       % = OpTypeBool\n", id_text(state.id_bool)));
  append(sb, tprint("       % = OpConstantTrue %\n", id_text(state.id_bool_true), id_text(state.id_bool)));
  append(sb, tprint("       % = OpConstantFalse %\n", id_text(state.id_bool_false), id_text(state.id_bool)));
  append(sb, tprint("     % = OpTypeVector % 3\n", id_text(state.id_v3uint), id_text(state.id_uint)));
  append(sb, tprint("     % = OpTypeVector % 2\n", id_text(state.id_v2uint), id_text(state.id_uint)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_v3uint), id_text(state.id_v3uint)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_uint), id_text(state.id_uint)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float), id_text(state.id_float)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float2), id_text(state.id_float2)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float3), id_text(state.id_float3)));
  append(sb, tprint("% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float4), id_text(state.id_float4)));
  append(sb, tprint("% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float), id_text(state.id_float)));
  append(sb, tprint("% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float2), id_text(state.id_float2)));
  append(sb, tprint("% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float3), id_text(state.id_float3)));
  append(sb, tprint("% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float4), id_text(state.id_float4)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int), id_text(state.id_int)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint), id_text(state.id_uint)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int64), id_text(state.id_int64)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint64), id_text(state.id_uint64)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float), id_text(state.id_float)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float2), id_text(state.id_float2)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float3), id_text(state.id_float3)));
  append(sb, tprint("% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float4), id_text(state.id_float4)));
  append(sb, tprint("% = OpTypeRuntimeArray %\n", id_text(state.id_runtimearr_uint), id_text(state.id_uint)));
  append(sb, tprint("% = OpTypeStruct %\n", id_text(state.id_buffer_struct), id_text(state.id_runtimearr_uint)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_buffer_struct), storage_class, id_text(state.id_buffer_struct)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int), storage_class, id_text(state.id_int)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint), storage_class, id_text(state.id_uint)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int64), storage_class, id_text(state.id_int64)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint64), storage_class, id_text(state.id_uint64)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float), storage_class, id_text(state.id_float)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float2), storage_class, id_text(state.id_float2)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float3), storage_class, id_text(state.id_float3)));
  append(sb, tprint("% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float4), storage_class, id_text(state.id_float4)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int), id_text(state.id_int)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint), id_text(state.id_uint)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int64), id_text(state.id_int64)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint64), id_text(state.id_uint64)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float), id_text(state.id_float)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2), id_text(state.id_float2)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float3), id_text(state.id_float3)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float4), id_text(state.id_float4)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2x2), id_text(state.id_float2x2)));
  append(sb, tprint("% = OpTypePointer Function %\n", id_text(state.id_ptr_func_bool), id_text(state.id_bool)));
}

spv_append_numeric_constants :: (sb: *String_Builder, state: *IR_SPV_Gen_State) {
  assert(sb != null);
  assert(state != null);
  for state.const_u32 append(sb, tprint("% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint), it.value));
  for state.const_i32 append(sb, tprint("% = OpConstant % %\n", id_text(it.id), id_text(state.id_int), it.value));
  for state.const_i64 append(sb, tprint("% = OpConstant % %\n", id_text(it.id), id_text(state.id_int64), it.value));
  for state.const_u64 append(sb, tprint("% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint64), it.value));
  for state.const_f32 append(sb, tprint("% = OpConstant % %\n", id_text(it.id), id_text(state.id_float), it.text));
}
