#scope_module

SPV_STORAGE_CLASS_PRIVATE :: 6;
SPV_OP_CONSTANT_COMPOSITE :: 44;

IR_SPV_Id_Slot :: enum {
  NONE;
  TYPE_INT8;
  TYPE_UINT8;
  TYPE_INT16;
  TYPE_UINT16;
  TYPE_INT;
  TYPE_UINT;
  TYPE_INT64;
  TYPE_UINT64;
  TYPE_FLOAT16;
  TYPE_FLOAT;
  TYPE_FLOAT2;
  TYPE_FLOAT3;
  TYPE_FLOAT4;
  TYPE_FLOAT2X2;
  TYPE_FLOAT3X3;
  TYPE_FLOAT4X4;
  TYPE_BOOL;

  PTR_STORAGE_INT8;
  PTR_STORAGE_UINT8;
  PTR_STORAGE_INT16;
  PTR_STORAGE_UINT16;
  PTR_STORAGE_INT;
  PTR_STORAGE_UINT;
  PTR_STORAGE_INT64;
  PTR_STORAGE_UINT64;
  PTR_STORAGE_FLOAT16;
  PTR_STORAGE_FLOAT;
  PTR_STORAGE_FLOAT2;
  PTR_STORAGE_FLOAT3;
  PTR_STORAGE_FLOAT4;
  PTR_STORAGE_FLOAT2X2;
  PTR_STORAGE_FLOAT3X3;
  PTR_STORAGE_FLOAT4X4;

  PTR_INPUT_INT8;
  PTR_INPUT_UINT8;
  PTR_INPUT_INT16;
  PTR_INPUT_UINT16;
  PTR_INPUT_UINT;
  PTR_INPUT_FLOAT16;
  PTR_INPUT_FLOAT;
  PTR_INPUT_FLOAT2;
  PTR_INPUT_FLOAT3;
  PTR_INPUT_FLOAT4;

  PTR_OUTPUT_INT8;
  PTR_OUTPUT_UINT8;
  PTR_OUTPUT_INT16;
  PTR_OUTPUT_UINT16;
  PTR_OUTPUT_FLOAT;
  PTR_OUTPUT_FLOAT2;
  PTR_OUTPUT_FLOAT3;
  PTR_OUTPUT_FLOAT4;

  PTR_UNIFORM_INT8;
  PTR_UNIFORM_UINT8;
  PTR_UNIFORM_INT16;
  PTR_UNIFORM_UINT16;
  PTR_UNIFORM_INT;
  PTR_UNIFORM_UINT;
  PTR_UNIFORM_INT64;
  PTR_UNIFORM_UINT64;
  PTR_UNIFORM_FLOAT16;
  PTR_UNIFORM_FLOAT;
  PTR_UNIFORM_FLOAT2;
  PTR_UNIFORM_FLOAT3;
  PTR_UNIFORM_FLOAT4;
  PTR_UNIFORM_FLOAT2X2;
  PTR_UNIFORM_FLOAT3X3;
  PTR_UNIFORM_FLOAT4X4;

  PTR_FUNC_INT8;
  PTR_FUNC_UINT8;
  PTR_FUNC_INT16;
  PTR_FUNC_UINT16;
  PTR_FUNC_INT;
  PTR_FUNC_UINT;
  PTR_FUNC_INT64;
  PTR_FUNC_UINT64;
  PTR_FUNC_FLOAT16;
  PTR_FUNC_FLOAT;
  PTR_FUNC_FLOAT2;
  PTR_FUNC_FLOAT3;
  PTR_FUNC_FLOAT4;
  PTR_FUNC_FLOAT2X2;
  PTR_FUNC_FLOAT3X3;
  PTR_FUNC_FLOAT4X4;
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
  .{kind=.INT8,   type_slot=.TYPE_INT8,   storage_ptr_slot=.PTR_STORAGE_INT8,   input_ptr_slot=.PTR_INPUT_INT8,  output_ptr_slot=.PTR_OUTPUT_INT8,  uniform_ptr_slot=.PTR_UNIFORM_INT8,   func_ptr_slot=.PTR_FUNC_INT8,   byte_size=1,  is_integral=true,  is_signed=true},
  .{kind=.UINT8,  type_slot=.TYPE_UINT8,  storage_ptr_slot=.PTR_STORAGE_UINT8,  input_ptr_slot=.PTR_INPUT_UINT8, output_ptr_slot=.PTR_OUTPUT_UINT8, uniform_ptr_slot=.PTR_UNIFORM_UINT8,  func_ptr_slot=.PTR_FUNC_UINT8,  byte_size=1,  is_integral=true,  is_signed=false},
  .{kind=.INT16,  type_slot=.TYPE_INT16,  storage_ptr_slot=.PTR_STORAGE_INT16,  input_ptr_slot=.PTR_INPUT_INT16, output_ptr_slot=.PTR_OUTPUT_INT16, uniform_ptr_slot=.PTR_UNIFORM_INT16,  func_ptr_slot=.PTR_FUNC_INT16,  byte_size=2,  is_integral=true,  is_signed=true},
  .{kind=.UINT16, type_slot=.TYPE_UINT16, storage_ptr_slot=.PTR_STORAGE_UINT16, input_ptr_slot=.PTR_INPUT_UINT16, output_ptr_slot=.PTR_OUTPUT_UINT16, uniform_ptr_slot=.PTR_UNIFORM_UINT16, func_ptr_slot=.PTR_FUNC_UINT16, byte_size=2,  is_integral=true,  is_signed=false},
  .{kind=.INT,    type_slot=.TYPE_INT,    storage_ptr_slot=.PTR_STORAGE_INT,    input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_INT,    func_ptr_slot=.PTR_FUNC_INT,    byte_size=4,  is_integral=true,  is_signed=true},
  .{kind=.UINT,   type_slot=.TYPE_UINT,   storage_ptr_slot=.PTR_STORAGE_UINT,   input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_UINT,   func_ptr_slot=.PTR_FUNC_UINT,   byte_size=4,  is_integral=true,  is_signed=false},
  .{kind=.INT64,  type_slot=.TYPE_INT64,  storage_ptr_slot=.PTR_STORAGE_INT64,  input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_INT64,  func_ptr_slot=.PTR_FUNC_INT64,  byte_size=8,  is_integral=true,  is_signed=true},
  .{kind=.UINT64, type_slot=.TYPE_UINT64, storage_ptr_slot=.PTR_STORAGE_UINT64, input_ptr_slot=.PTR_INPUT_UINT, output_ptr_slot=.NONE,               uniform_ptr_slot=.PTR_UNIFORM_UINT64, func_ptr_slot=.PTR_FUNC_UINT64, byte_size=8,  is_integral=true,  is_signed=false},
  .{kind=.FLOAT16, type_slot=.TYPE_FLOAT16, storage_ptr_slot=.PTR_STORAGE_FLOAT16, input_ptr_slot=.PTR_INPUT_FLOAT16, output_ptr_slot=.NONE, uniform_ptr_slot=.PTR_UNIFORM_FLOAT16, func_ptr_slot=.PTR_FUNC_FLOAT16, byte_size=2, is_integral=false, is_signed=false},
  .{kind=.FLOAT,  type_slot=.TYPE_FLOAT,  storage_ptr_slot=.PTR_STORAGE_FLOAT,  input_ptr_slot=.PTR_INPUT_FLOAT, output_ptr_slot=.PTR_OUTPUT_FLOAT,  uniform_ptr_slot=.PTR_UNIFORM_FLOAT,  func_ptr_slot=.PTR_FUNC_FLOAT,  byte_size=4,  is_integral=false, is_signed=false},
  .{kind=.FLOAT2, type_slot=.TYPE_FLOAT2, storage_ptr_slot=.PTR_STORAGE_FLOAT2, input_ptr_slot=.PTR_INPUT_FLOAT2, output_ptr_slot=.PTR_OUTPUT_FLOAT2, uniform_ptr_slot=.PTR_UNIFORM_FLOAT2, func_ptr_slot=.PTR_FUNC_FLOAT2, byte_size=8,  is_integral=false, is_signed=false},
  .{kind=.FLOAT3, type_slot=.TYPE_FLOAT3, storage_ptr_slot=.PTR_STORAGE_FLOAT3, input_ptr_slot=.PTR_INPUT_FLOAT3, output_ptr_slot=.PTR_OUTPUT_FLOAT3, uniform_ptr_slot=.PTR_UNIFORM_FLOAT3, func_ptr_slot=.PTR_FUNC_FLOAT3, byte_size=12, is_integral=false, is_signed=false},
  .{kind=.FLOAT4, type_slot=.TYPE_FLOAT4, storage_ptr_slot=.PTR_STORAGE_FLOAT4, input_ptr_slot=.PTR_INPUT_FLOAT4, output_ptr_slot=.PTR_OUTPUT_FLOAT4, uniform_ptr_slot=.PTR_UNIFORM_FLOAT4, func_ptr_slot=.PTR_FUNC_FLOAT4, byte_size=16, is_integral=false, is_signed=false},
  .{kind=.FLOAT2X2, type_slot=.TYPE_FLOAT2X2, storage_ptr_slot=.PTR_STORAGE_FLOAT2X2, input_ptr_slot=.NONE, output_ptr_slot=.NONE, uniform_ptr_slot=.PTR_UNIFORM_FLOAT2X2, func_ptr_slot=.PTR_FUNC_FLOAT2X2, byte_size=16, is_integral=false, is_signed=false},
  .{kind=.FLOAT3X3, type_slot=.TYPE_FLOAT3X3, storage_ptr_slot=.PTR_STORAGE_FLOAT3X3, input_ptr_slot=.NONE, output_ptr_slot=.NONE, uniform_ptr_slot=.PTR_UNIFORM_FLOAT3X3, func_ptr_slot=.PTR_FUNC_FLOAT3X3, byte_size=48, is_integral=false, is_signed=false},
  .{kind=.FLOAT4X4, type_slot=.TYPE_FLOAT4X4, storage_ptr_slot=.PTR_STORAGE_FLOAT4X4, input_ptr_slot=.NONE, output_ptr_slot=.NONE, uniform_ptr_slot=.PTR_UNIFORM_FLOAT4X4, func_ptr_slot=.PTR_FUNC_FLOAT4X4, byte_size=64, is_integral=false, is_signed=false},
  .{kind=.BOOL,   type_slot=.TYPE_BOOL,   storage_ptr_slot=.NONE,               input_ptr_slot=.NONE,             output_ptr_slot=.NONE,               uniform_ptr_slot=.NONE,               func_ptr_slot=.PTR_FUNC_BOOL,   byte_size=0,  is_integral=false, is_signed=false},
];

kind_info :: (kind: IR_SPV_Gen_Type) -> *IR_SPV_Kind_Info {
  for *SPV_KIND_INFO if it.kind == kind return it;
  return null;
}

state_id_from_slot :: (s: *IR_SPV_Gen_State, slot: IR_SPV_Id_Slot) -> s64 {
  if slot == {
    case .NONE; return 0;
    case .TYPE_INT8; return s.id_int8;
    case .TYPE_UINT8; return s.id_uint8;
    case .TYPE_INT16; return s.id_int16;
    case .TYPE_UINT16; return s.id_uint16;
    case .TYPE_INT; return s.id_int;
    case .TYPE_UINT; return s.id_uint;
    case .TYPE_INT64; return s.id_int64;
    case .TYPE_UINT64; return s.id_uint64;
    case .TYPE_FLOAT16; return s.id_half;
    case .TYPE_FLOAT; return s.id_float;
    case .TYPE_FLOAT2; return s.id_float2;
    case .TYPE_FLOAT3; return s.id_float3;
    case .TYPE_FLOAT4; return s.id_float4;
    case .TYPE_FLOAT2X2; return s.id_float2x2;
    case .TYPE_FLOAT3X3; return s.id_float3x3;
    case .TYPE_FLOAT4X4; return s.id_float4x4;
    case .TYPE_BOOL; return s.id_bool;
    case .PTR_STORAGE_INT8; return s.id_ptr_storage_int8;
    case .PTR_STORAGE_UINT8; return s.id_ptr_storage_uint8;
    case .PTR_STORAGE_INT16; return s.id_ptr_storage_int16;
    case .PTR_STORAGE_UINT16; return s.id_ptr_storage_uint16;
    case .PTR_STORAGE_INT; return s.id_ptr_storage_int;
    case .PTR_STORAGE_UINT; return s.id_ptr_storage_uint;
    case .PTR_STORAGE_INT64; return s.id_ptr_storage_int64;
    case .PTR_STORAGE_UINT64; return s.id_ptr_storage_uint64;
    case .PTR_STORAGE_FLOAT16; return s.id_ptr_storage_half;
    case .PTR_STORAGE_FLOAT; return s.id_ptr_storage_float;
    case .PTR_STORAGE_FLOAT2; return s.id_ptr_storage_float2;
    case .PTR_STORAGE_FLOAT3; return s.id_ptr_storage_float3;
    case .PTR_STORAGE_FLOAT4; return s.id_ptr_storage_float4;
    case .PTR_STORAGE_FLOAT2X2; return s.id_ptr_storage_float2x2;
    case .PTR_STORAGE_FLOAT3X3; return s.id_ptr_storage_float3x3;
    case .PTR_STORAGE_FLOAT4X4; return s.id_ptr_storage_float4x4;
    case .PTR_INPUT_INT8; return s.id_ptr_input_int8;
    case .PTR_INPUT_UINT8; return s.id_ptr_input_uint8;
    case .PTR_INPUT_INT16; return s.id_ptr_input_int16;
    case .PTR_INPUT_UINT16; return s.id_ptr_input_uint16;
    case .PTR_INPUT_UINT; return s.id_ptr_input_uint;
    case .PTR_INPUT_FLOAT16; return s.id_ptr_input_half;
    case .PTR_INPUT_FLOAT; return s.id_ptr_input_float;
    case .PTR_INPUT_FLOAT2; return s.id_ptr_input_float2;
    case .PTR_INPUT_FLOAT3; return s.id_ptr_input_float3;
    case .PTR_INPUT_FLOAT4; return s.id_ptr_input_float4;
    case .PTR_OUTPUT_INT8; return s.id_ptr_output_int8;
    case .PTR_OUTPUT_UINT8; return s.id_ptr_output_uint8;
    case .PTR_OUTPUT_INT16; return s.id_ptr_output_int16;
    case .PTR_OUTPUT_UINT16; return s.id_ptr_output_uint16;
    case .PTR_OUTPUT_FLOAT; return s.id_ptr_output_float;
    case .PTR_OUTPUT_FLOAT2; return s.id_ptr_output_float2;
    case .PTR_OUTPUT_FLOAT3; return s.id_ptr_output_float3;
    case .PTR_OUTPUT_FLOAT4; return s.id_ptr_output_float4;
    case .PTR_UNIFORM_INT8; return s.id_ptr_uniform_int8;
    case .PTR_UNIFORM_UINT8; return s.id_ptr_uniform_uint8;
    case .PTR_UNIFORM_INT16; return s.id_ptr_uniform_int16;
    case .PTR_UNIFORM_UINT16; return s.id_ptr_uniform_uint16;
    case .PTR_UNIFORM_INT; return s.id_ptr_uniform_int;
    case .PTR_UNIFORM_UINT; return s.id_ptr_uniform_uint;
    case .PTR_UNIFORM_INT64; return s.id_ptr_uniform_int64;
    case .PTR_UNIFORM_UINT64; return s.id_ptr_uniform_uint64;
    case .PTR_UNIFORM_FLOAT16; return s.id_ptr_uniform_half;
    case .PTR_UNIFORM_FLOAT; return s.id_ptr_uniform_float;
    case .PTR_UNIFORM_FLOAT2; return s.id_ptr_uniform_float2;
    case .PTR_UNIFORM_FLOAT3; return s.id_ptr_uniform_float3;
    case .PTR_UNIFORM_FLOAT4; return s.id_ptr_uniform_float4;
    case .PTR_UNIFORM_FLOAT2X2; return s.id_ptr_uniform_float2x2;
    case .PTR_UNIFORM_FLOAT3X3; return s.id_ptr_uniform_float3x3;
    case .PTR_UNIFORM_FLOAT4X4; return s.id_ptr_uniform_float4x4;
    case .PTR_FUNC_INT8; return s.id_ptr_func_int8;
    case .PTR_FUNC_UINT8; return s.id_ptr_func_uint8;
    case .PTR_FUNC_INT16; return s.id_ptr_func_int16;
    case .PTR_FUNC_UINT16; return s.id_ptr_func_uint16;
    case .PTR_FUNC_INT; return s.id_ptr_func_int;
    case .PTR_FUNC_UINT; return s.id_ptr_func_uint;
    case .PTR_FUNC_INT64; return s.id_ptr_func_int64;
    case .PTR_FUNC_UINT64; return s.id_ptr_func_uint64;
    case .PTR_FUNC_FLOAT16; return s.id_ptr_func_half;
    case .PTR_FUNC_FLOAT; return s.id_ptr_func_float;
    case .PTR_FUNC_FLOAT2; return s.id_ptr_func_float2;
    case .PTR_FUNC_FLOAT3; return s.id_ptr_func_float3;
    case .PTR_FUNC_FLOAT4; return s.id_ptr_func_float4;
    case .PTR_FUNC_FLOAT2X2; return s.id_ptr_func_float2x2;
    case .PTR_FUNC_FLOAT3X3; return s.id_ptr_func_float3x3;
    case .PTR_FUNC_FLOAT4X4; return s.id_ptr_func_float4x4;
    case .PTR_FUNC_BOOL; return s.id_ptr_func_bool;
  }
  return 0;
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

kind_uses_int16 :: (kind: IR_SPV_Gen_Type) -> bool {
  return kind == .INT16 || kind == .UINT16;
}

kind_uses_int8 :: (kind: IR_SPV_Gen_Type) -> bool {
  return kind == .INT8 || kind == .UINT8;
}

kind_uses_float16 :: (kind: IR_SPV_Gen_Type) -> bool {
  return kind == .FLOAT16;
}

state_uses_int64 :: (s: *IR_SPV_Gen_State) -> bool {
  if s.const_i64.count > 0 || s.const_u64.count > 0 return true;
  for s.locals if kind_uses_int64(it.type) return true;
  for s.local_arrays if kind_uses_int64(it.element_type) return true;
  for s.global_const_arrays if kind_uses_int64(it.element_type) return true;
  for s.local_structs for it.fields if kind_uses_int64(it.type) return true;
  for s.buffers {
    if kind_uses_int64(it.element_kind) return true;
    for it.fields if kind_uses_int64(it.type) return true;
  }
  for s.uniform_blocks for it.fields if kind_uses_int64(it.type) return true;
  for s.input_vars if kind_uses_int64(it.type) return true;
  for s.output_vars if kind_uses_int64(it.type) return true;
  return false;
}

state_uses_int16 :: (s: *IR_SPV_Gen_State) -> bool {
  if s.const_u16.count > 0 || s.const_i16.count > 0 return true;
  for s.function_constants if it.type == .U16 || it.type == .S16 return true;
  for s.locals if kind_uses_int16(it.type) return true;
  for s.local_arrays if kind_uses_int16(it.element_type) return true;
  for s.global_const_arrays if kind_uses_int16(it.element_type) return true;
  for s.local_structs for it.fields if kind_uses_int16(it.type) return true;
  for s.buffers {
    if kind_uses_int16(it.element_kind) return true;
    for it.fields if kind_uses_int16(it.type) return true;
  }
  for s.uniform_blocks for it.fields if kind_uses_int16(it.type) return true;
  for s.input_vars if kind_uses_int16(it.type) return true;
  for s.output_vars if kind_uses_int16(it.type) return true;
  return false;
}

state_uses_int8 :: (s: *IR_SPV_Gen_State) -> bool {
  if s.const_u8.count > 0 || s.const_i8.count > 0 return true;
  for s.function_constants if it.type == .U8 || it.type == .S8 return true;
  for s.locals if kind_uses_int8(it.type) return true;
  for s.local_arrays if kind_uses_int8(it.element_type) return true;
  for s.global_const_arrays if kind_uses_int8(it.element_type) return true;
  for s.local_structs for it.fields if kind_uses_int8(it.type) return true;
  for s.buffers {
    if kind_uses_int8(it.element_kind) return true;
    for it.fields if kind_uses_int8(it.type) return true;
  }
  for s.uniform_blocks for it.fields if kind_uses_int8(it.type) return true;
  for s.input_vars if kind_uses_int8(it.type) return true;
  for s.output_vars if kind_uses_int8(it.type) return true;
  return false;
}

state_uses_storage_buffer_int16 :: (s: *IR_SPV_Gen_State) -> bool {
  for s.buffers {
    if kind_uses_int16(it.element_kind) return true;
    for it.fields if kind_uses_int16(it.type) return true;
  }
  return false;
}

state_uses_storage_buffer_int8 :: (s: *IR_SPV_Gen_State) -> bool {
  for s.buffers {
    if kind_uses_int8(it.element_kind) return true;
    for it.fields if kind_uses_int8(it.type) return true;
  }
  return false;
}

promote_integral_kind :: (a: IR_SPV_Gen_Type, b: IR_SPV_Gen_Type) -> IR_SPV_Gen_Type {
  assert(is_integral_kind(a));
  assert(is_integral_kind(b));
  if a == b return a;
  if a == .INT64 || b == .INT64 return .INT64;
  if a == .UINT64 || b == .UINT64 {
    if is_signed_integral_kind(a) || is_signed_integral_kind(b) return .INT64;
    return .UINT64;
  }
  a_bytes := byte_size_of_kind(a);
  b_bytes := byte_size_of_kind(b);
  max_bytes := max(a_bytes, b_bytes);
  signed := is_signed_integral_kind(a) || is_signed_integral_kind(b);
  if max_bytes <= 1 return ifx signed then .INT8 else .UINT8;
  if max_bytes <= 2 return ifx signed then .INT16 else .UINT16;
  if signed return .INT;
  return .UINT;
}

spv_append_capabilities :: (sb: *String_Builder, state: *IR_SPV_Gen_State, use_physical_storage := false) {
  assert(sb != null);
  assert(state != null);
  append(sb, "               OpCapability Shader\n");
  append(sb, "               OpCapability Int8\n");
  append(sb, "               OpCapability Int16\n");
  if state_uses_int64(state) append(sb, "               OpCapability Int64\n");
  if state_uses_storage_buffer_int8(state) append(sb, "               OpCapability StorageBuffer8BitAccess\n");
  if state_uses_storage_buffer_int16(state) append(sb, "               OpCapability StorageBuffer16BitAccess\n");
  append(sb, "               OpCapability Float16\n");
  if state.uses_write_2d || state.uses_write_3d append(sb, "               OpCapability StorageImageWriteWithoutFormat\n");
  if use_physical_storage append(sb, "               OpCapability PhysicalStorageBufferAddresses\n");
}

spv_append_common_type_decls :: (sb: *String_Builder, state: *IR_SPV_Gen_State, storage_class: string) {
  uses_int8 := state_uses_int8(state);
  uses_int16 := state_uses_int16(state);
  print_to_builder(sb, "% = OpTypeVoid\n", id_text(state.id_void));
  print_to_builder(sb, "% = OpTypeFunction %\n", id_text(state.id_fn_void), id_text(state.id_void));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypeInt 8 0\n", id_text(state.id_uint8));
    print_to_builder(sb, "% = OpTypeInt 8 1\n", id_text(state.id_int8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypeInt 16 0\n", id_text(state.id_uint16));
    print_to_builder(sb, "% = OpTypeInt 16 1\n", id_text(state.id_int16));
  }
  print_to_builder(sb, "% = OpTypeInt 32 0\n", id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypeInt 32 1\n", id_text(state.id_int));
  print_to_builder(sb, "% = OpTypeInt 64 1\n", id_text(state.id_int64));
  print_to_builder(sb, "% = OpTypeInt 64 0\n", id_text(state.id_uint64));
  print_to_builder(sb, "% = OpTypeFloat 16\n", id_text(state.id_half));
  print_to_builder(sb, "% = OpTypeFloat 32\n", id_text(state.id_float));
  print_to_builder(sb, "% = OpTypeVector % 2\n", id_text(state.id_float2), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypeVector % 3\n", id_text(state.id_float3), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypeVector % 4\n", id_text(state.id_float4), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypeMatrix % 2\n", id_text(state.id_float2x2), id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypeMatrix % 3\n", id_text(state.id_float3x3), id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypeMatrix % 4\n", id_text(state.id_float4x4), id_text(state.id_float4));
  print_to_builder(sb, "% = OpTypeBool\n", id_text(state.id_bool));
  print_to_builder(sb, "% = OpConstantTrue %\n", id_text(state.id_bool_true), id_text(state.id_bool));
  print_to_builder(sb, "% = OpConstantFalse %\n", id_text(state.id_bool_false), id_text(state.id_bool));
  print_to_builder(sb, "% = OpTypeVector % 3\n", id_text(state.id_v3uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypeVector % 2\n", id_text(state.id_v2uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_v3uint), id_text(state.id_v3uint));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_uint8), id_text(state.id_uint8));
    print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_int8), id_text(state.id_int8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_uint16), id_text(state.id_uint16));
    print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_int16), id_text(state.id_int16));
  }
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_half), id_text(state.id_half));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float2), id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float3), id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypePointer Input %\n", id_text(state.id_ptr_input_float4), id_text(state.id_float4));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_uint8), id_text(state.id_uint8));
    print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_int8), id_text(state.id_int8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_uint16), id_text(state.id_uint16));
    print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_int16), id_text(state.id_int16));
  }
  print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float2), id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float3), id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypePointer Output %\n", id_text(state.id_ptr_output_float4), id_text(state.id_float4));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int8), id_text(state.id_int8));
    print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint8), id_text(state.id_uint8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int16), id_text(state.id_int16));
    print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint16), id_text(state.id_uint16));
  }
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int), id_text(state.id_int));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_int64), id_text(state.id_int64));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_uint64), id_text(state.id_uint64));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_half), id_text(state.id_half));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float2), id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float3), id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float4), id_text(state.id_float4));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float2x2), id_text(state.id_float2x2));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float3x3), id_text(state.id_float3x3));
  print_to_builder(sb, "% = OpTypePointer Uniform %\n", id_text(state.id_ptr_uniform_float4x4), id_text(state.id_float4x4));
  print_to_builder(sb, "% = OpTypeRuntimeArray %\n", id_text(state.id_runtimearr_uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypeStruct %\n", id_text(state.id_buffer_struct), id_text(state.id_runtimearr_uint));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_buffer_struct), storage_class, id_text(state.id_buffer_struct));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int8), storage_class, id_text(state.id_int8));
    print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint8), storage_class, id_text(state.id_uint8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int16), storage_class, id_text(state.id_int16));
    print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint16), storage_class, id_text(state.id_uint16));
  }
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int), storage_class, id_text(state.id_int));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint), storage_class, id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_int64), storage_class, id_text(state.id_int64));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_uint64), storage_class, id_text(state.id_uint64));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_half), storage_class, id_text(state.id_half));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float), storage_class, id_text(state.id_float));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float2), storage_class, id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float3), storage_class, id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float4), storage_class, id_text(state.id_float4));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float2x2), storage_class, id_text(state.id_float2x2));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float3x3), storage_class, id_text(state.id_float3x3));
  print_to_builder(sb, "% = OpTypePointer % %\n", id_text(state.id_ptr_storage_float4x4), storage_class, id_text(state.id_float4x4));
  if uses_int8 {
    print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int8), id_text(state.id_int8));
    print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint8), id_text(state.id_uint8));
  }
  if uses_int16 {
    print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int16), id_text(state.id_int16));
    print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint16), id_text(state.id_uint16));
  }
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int), id_text(state.id_int));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint), id_text(state.id_uint));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_int64), id_text(state.id_int64));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_uint64), id_text(state.id_uint64));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_half), id_text(state.id_half));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float), id_text(state.id_float));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2), id_text(state.id_float2));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float3), id_text(state.id_float3));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float4), id_text(state.id_float4));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float2x2), id_text(state.id_float2x2));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float3x3), id_text(state.id_float3x3));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_float4x4), id_text(state.id_float4x4));
  print_to_builder(sb, "% = OpTypePointer Function %\n", id_text(state.id_ptr_func_bool), id_text(state.id_bool));
}

spv_append_numeric_constants :: (sb: *String_Builder, state: *IR_SPV_Gen_State) {
  if state_uses_int8(state) for state.const_u8 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint8), it.value);
  if state_uses_int8(state) for state.const_i8 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_int8), it.value);
  if state_uses_int16(state) for state.const_u16 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint16), it.value);
  if state_uses_int16(state) for state.const_i16 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_int16), it.value);
  for state.const_u32 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint), it.value);
  for state.const_i32 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_int), it.value);
  for state.const_i64 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_int64), it.value);
  for state.const_u64 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_uint64), it.value);
  for state.const_f16 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_half), it.text);
  for state.const_f32 print_to_builder(sb, "% = OpConstant % %\n", id_text(it.id), id_text(state.id_float), it.text);
}

spv_append_null_constants :: (sb: *String_Builder, state: *IR_SPV_Gen_State) {
  for state.const_null print_to_builder(sb, "% = OpConstantNull %\n", id_text(it.id), id_text(it.type_id));
}

spv_append_global_const_array_decls :: (sb: *String_Builder, state: *IR_SPV_Gen_State) {
  for state.global_const_arrays {
    elem_type_id := type_id_from_kind(state, it.element_type);
    print_to_builder(sb, "% = OpTypeArray % %\n", id_text(it.array_type_id), id_text(elem_type_id), id_text(it.count_const_id));
    print_to_builder(sb, "% = OpTypePointer Private %\n", id_text(it.ptr_private_array_type_id), id_text(it.array_type_id));
    print_to_builder(sb, "% = OpTypePointer Private %\n", id_text(it.ptr_private_elem_type_id), id_text(elem_type_id));
  }
  for state.global_const_arrays {
    print_to_builder(sb, "% = OpConstantComposite %", id_text(it.composite_const_id), id_text(it.array_type_id));
    for it.element_const_ids append(sb, tprint(" %", id_text(it)));
    append(sb, "\n");
    print_to_builder(sb, "% = OpVariable % Private %\n", id_text(it.var_id), id_text(it.ptr_private_array_type_id), id_text(it.composite_const_id));
  }
}

spv_module_append_capabilities_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State, use_physical_storage := false) {
  assert(m != null);
  assert(state != null);
  spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_SHADER);
  spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_INT8);
  spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_INT16);
  if state_uses_int64(state) spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_INT64);
  if state_uses_storage_buffer_int8(state) spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_STORAGE_BUFFER8_BIT_ACCESS);
  if state_uses_storage_buffer_int16(state) spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_STORAGE_BUFFER16_BIT_ACCESS);
  spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_FLOAT16);
  if state.uses_write_2d || state.uses_write_3d {
    spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT);
  }
  if use_physical_storage {
    spv_module_append_words(m, .CAPABILITIES, SPV_OP_CAPABILITY, SPV_CAPABILITY_PHYSICAL_STORAGE_BUFFER_ADDRESSES);
  }
}

spv_module_append_common_type_decls_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State, storage_class: u32) {
  assert(m != null);
  assert(state != null);
  uses_int8 := state_uses_int8(state);
  uses_int16 := state_uses_int16(state);
  section: SPV_Section = .TYPES_CONSTANTS_GLOBALS;
  spv_module_append_words(m, section, SPV_OP_TYPE_VOID, cast(u32) state.id_void);
  spv_module_append_words(m, section, SPV_OP_TYPE_FUNCTION, cast(u32) state.id_fn_void, cast(u32) state.id_void);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_uint8, 8, 0);
    spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_int8, 8, 1);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_uint16, 16, 0);
    spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_int16, 16, 1);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_uint, 32, 0);
  spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_int, 32, 1);
  spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_int64, 64, 1);
  spv_module_append_words(m, section, SPV_OP_TYPE_INT, cast(u32) state.id_uint64, 64, 0);
  spv_module_append_words(m, section, SPV_OP_TYPE_FLOAT, cast(u32) state.id_half, 16);
  spv_module_append_words(m, section, SPV_OP_TYPE_FLOAT, cast(u32) state.id_float, 32);
  spv_module_append_words(m, section, SPV_OP_TYPE_VECTOR, cast(u32) state.id_float2, cast(u32) state.id_float, 2);
  spv_module_append_words(m, section, SPV_OP_TYPE_VECTOR, cast(u32) state.id_float3, cast(u32) state.id_float, 3);
  spv_module_append_words(m, section, SPV_OP_TYPE_VECTOR, cast(u32) state.id_float4, cast(u32) state.id_float, 4);
  spv_module_append_words(m, section, SPV_OP_TYPE_MATRIX, cast(u32) state.id_float2x2, cast(u32) state.id_float2, 2);
  spv_module_append_words(m, section, SPV_OP_TYPE_MATRIX, cast(u32) state.id_float3x3, cast(u32) state.id_float3, 3);
  spv_module_append_words(m, section, SPV_OP_TYPE_MATRIX, cast(u32) state.id_float4x4, cast(u32) state.id_float4, 4);
  spv_module_append_words(m, section, SPV_OP_TYPE_BOOL, cast(u32) state.id_bool);
  spv_module_append_words(m, section, SPV_OP_CONSTANT_TRUE, cast(u32) state.id_bool, cast(u32) state.id_bool_true);
  spv_module_append_words(m, section, SPV_OP_CONSTANT_FALSE, cast(u32) state.id_bool, cast(u32) state.id_bool_false);
  spv_module_append_words(m, section, SPV_OP_TYPE_VECTOR, cast(u32) state.id_v3uint, cast(u32) state.id_uint, 3);
  spv_module_append_words(m, section, SPV_OP_TYPE_VECTOR, cast(u32) state.id_v2uint, cast(u32) state.id_uint, 2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_v3uint, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_v3uint);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_uint8, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_uint8);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_int8, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_int8);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_uint16, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_uint16);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_int16, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_int16);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_uint, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_half, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_half);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_float, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_float);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_float2, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_float2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_float3, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_float3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_input_float4, SPV_STORAGE_CLASS_INPUT, cast(u32) state.id_float4);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_uint8, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_uint8);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_int8, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_int8);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_uint16, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_uint16);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_int16, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_int16);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_float, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_float2, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_float3, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_output_float4, SPV_STORAGE_CLASS_OUTPUT, cast(u32) state.id_float4);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_int8, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_int8);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_uint8, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_uint8);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_int16, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_int16);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_uint16, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_uint16);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_int, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_int);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_uint, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_int64, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_int64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_uint64, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_uint64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_half, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_half);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float2, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float3, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float4, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float4);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float2x2, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float2x2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float3x3, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float3x3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_uniform_float4x4, SPV_STORAGE_CLASS_UNIFORM, cast(u32) state.id_float4x4);
  spv_module_append_words(m, section, SPV_OP_TYPE_RUNTIME_ARRAY, cast(u32) state.id_runtimearr_uint, cast(u32) state.id_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_STRUCT, cast(u32) state.id_buffer_struct, cast(u32) state.id_runtimearr_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_buffer_struct, storage_class, cast(u32) state.id_buffer_struct);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_int8, storage_class, cast(u32) state.id_int8);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_uint8, storage_class, cast(u32) state.id_uint8);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_int16, storage_class, cast(u32) state.id_int16);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_uint16, storage_class, cast(u32) state.id_uint16);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_int, storage_class, cast(u32) state.id_int);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_uint, storage_class, cast(u32) state.id_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_int64, storage_class, cast(u32) state.id_int64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_uint64, storage_class, cast(u32) state.id_uint64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_half, storage_class, cast(u32) state.id_half);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float, storage_class, cast(u32) state.id_float);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float2, storage_class, cast(u32) state.id_float2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float3, storage_class, cast(u32) state.id_float3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float4, storage_class, cast(u32) state.id_float4);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float2x2, storage_class, cast(u32) state.id_float2x2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float3x3, storage_class, cast(u32) state.id_float3x3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_storage_float4x4, storage_class, cast(u32) state.id_float4x4);
  if uses_int8 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_int8, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_int8);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_uint8, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_uint8);
  }
  if uses_int16 {
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_int16, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_int16);
    spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_uint16, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_uint16);
  }
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_int, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_int);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_uint, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_uint);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_int64, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_int64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_uint64, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_uint64);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_half, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_half);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float2, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float3, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float4, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float4);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float2x2, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float2x2);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float3x3, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float3x3);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_float4x4, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_float4x4);
  spv_module_append_words(m, section, SPV_OP_TYPE_POINTER, cast(u32) state.id_ptr_func_bool, SPV_STORAGE_CLASS_FUNCTION, cast(u32) state.id_bool);
}

spv_module_append_null_constants_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State) {
  assert(m != null);
  assert(state != null);
  for state.const_null {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT_NULL, cast(u32) it.type_id, cast(u32) it.id);
  }
}

spv_module_append_numeric_constants_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State) {
  assert(m != null);
  assert(state != null);
  if state_uses_int8(state) for state.const_u8 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_uint8, cast(u32) it.id, cast(u32) it.value);
  }
  if state_uses_int8(state) for state.const_i8 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_int8, cast(u32) it.id, cast(u32) cast(u8) it.value);
  }
  if state_uses_int16(state) for state.const_u16 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_uint16, cast(u32) it.id, cast(u32) it.value);
  }
  if state_uses_int16(state) for state.const_i16 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_int16, cast(u32) it.id, cast(u32) cast(u16) it.value);
  }
  for state.const_u32 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_uint, cast(u32) it.id, it.value);
  }
  for state.const_i32 {
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_int, cast(u32) it.id, cast(u32) it.value);
  }
  for state.const_i64 {
    if it.id <= 0 {
      assert(false, "SPIR-V binary backend: invalid int64 constant id % for value %.", it.id, it.value);
    }
    bits := cast(u64) it.value;
    type_id := cast(u32) state.id_int64;
    const_id := cast(u32) it.id;
    low_word := cast,no_check(u32) (bits & cast(u64) 0xFFFF_FFFF);
    high_word := cast,no_check(u32) ((bits >> 32) & cast(u64) 0xFFFF_FFFF);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, type_id, const_id, low_word, high_word);
  }
  for state.const_u64 {
    if it.id <= 0 {
      assert(false, "SPIR-V binary backend: invalid uint64 constant id % for value %.", it.id, it.value);
    }
    type_id := cast(u32) state.id_uint64;
    const_id := cast(u32) it.id;
    low_word := cast,no_check(u32) (it.value & cast(u64) 0xFFFF_FFFF);
    high_word := cast,no_check(u32) ((it.value >> 32) & cast(u64) 0xFFFF_FFFF);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, type_id, const_id, low_word, high_word);
  }
  for state.const_f16 {
    value, value_ok, remainder := string_to_float(it.text);
    assert(value_ok && remainder.count == 0);
    half := F16.float32_to_float16(value);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_half, cast(u32) it.id, cast(u32) cast(u16) half);
  }
  for state.const_f32 {
    value, value_ok, remainder := string_to_float(it.text);
    assert(value_ok && remainder.count == 0);
    bits := (.*) cast(*u32) *value;
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_CONSTANT, cast(u32) state.id_float, cast(u32) it.id, bits);
  }
}

spv_module_append_global_const_array_decls_binary :: (m: *SPV_Module, state: *IR_SPV_Gen_State) {
  assert(m != null);
  assert(state != null);
  for state.global_const_arrays {
    elem_type_id := cast(u32) type_id_from_kind(state, it.element_type);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_ARRAY, cast(u32) it.array_type_id, elem_type_id, cast(u32) it.count_const_id);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_private_array_type_id, SPV_STORAGE_CLASS_PRIVATE, cast(u32) it.array_type_id);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_TYPE_POINTER, cast(u32) it.ptr_private_elem_type_id, SPV_STORAGE_CLASS_PRIVATE, elem_type_id);
  }
  for state.global_const_arrays {
    inst: SPV_Inst;
    inst.opcode = SPV_OP_CONSTANT_COMPOSITE;
    array_add(*inst.words, cast(u32) it.array_type_id, cast(u32) it.composite_const_id);
    for it.element_const_ids array_add(*inst.words, cast(u32) it);
    spv_module_append_inst(m, .TYPES_CONSTANTS_GLOBALS, inst);
    spv_module_append_words(m, .TYPES_CONSTANTS_GLOBALS, SPV_OP_VARIABLE, cast(u32) it.ptr_private_array_type_id, cast(u32) it.var_id, SPV_STORAGE_CLASS_PRIVATE, cast(u32) it.composite_const_id);
  }
}
