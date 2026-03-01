//
// Tests basic Jai -> compute shader compilation across various test cases by
// running them on the GPU and CPU and comparing results.
// 

ALL_TEST_FUNCTIONS :: (struct { name: string; type: enum { Bare; Table; Boids; Vec3; Vec4; Vec4Box; }; }).[
  {"simple", .Bare},
  {"loop", .Bare},
  {"locals", .Bare},
  {"return_value", .Bare},
  {"with_function", .Bare},
  {"with_using", .Bare},
  {"while_break", .Bare},
  {"with_continue", .Bare},
  {"with_switch", .Bare},
  {"compound_assign", .Bare},
  {"defer_assign", .Bare},
  {"defer_block", .Bare},
  {"defer_break", .Bare},
  {"defer_continue", .Bare},
  {"defer_switch_through", .Bare},
  {"matrix_math", .Bare},
  {"intrinsics", .Bare},
  {"float4_component_lvalue", .Bare},
  {"local_array_literal_read", .Bare},
  {"local_array_write_then_read", .Bare},
  {"bool_and_or", .Bare},
  {"bool_temp_chain", .Bare},
  {"switch_sparse", .Bare},
  {"nested_switch_in_loop", .Bare},
  {"switch_through_chain", .Bare},
  {"nested_while_continue_break", .Bare},
  {"intrinsic_mod_float", .Bare},
  {"intrinsic_smoothstep", .Bare},
  {"intrinsic_pow", .Bare},
  {"vector_scalar_mix", .Bare},
  {"helper_return_member_on_call", .Bare},
  {"helper_return_assign_local", .Bare},
  {"helper_void_call_statement", .Bare},
  {"helper_void_nested_return", .Bare},
  {"helper_void_switch_return", .Bare},
  {"local_float3_array_roundtrip", .Bare},
  {"helper_float3_array_arg", .Bare},
  {"buffer_struct_copy_temp", .Boids},
  {"unary_not_bool", .Bare},
  {"unary_bit_not", .Bare},
  {"float4_swizzle_xy", .Bare},
  {"matrix_ctor_mul", .Bare},
  {"using_inside_nested_block", .Bare},
  {"while_false_initially", .Bare},
  {"matrix_mul_builtin", .Bare},
  {"for_descending", .Bare},
  {"cast_chain", .Bare},
  {"int64_arithmetic", .Bare},
  {"subscript_compound_assign", .Bare},
  {"member_chain_compound_assign", .Boids},
  {"switch_default_only", .Bare},
  {"switch_without_default", .Bare},
  {"helper_multiple_returns", .Bare},
  {"early_return_in_nested_if", .Bare},
  {"int64_bitwise_mix", .Bare},
  {"local_struct_using_update", .Bare},
  {"vector_component_swap", .Boids},
  {"matrix_reassign_chain", .Bare},
  {"thread_id_y_component", .Bare},
  {"thread_id_renamed_field", .Bare},
  {"group_thread_id_renamed_field", .Bare},
  {"group_id_renamed_field", .Bare},
  {"group_index_renamed_field", .Bare},
  {"global_constants_subscript", .Bare},
  {"local_float3_components", .Bare},
  {"wrap_helper_constants", .Bare},
  {"wrap_xy_cell_index", .Bare},
  {"float_constant_division", .Bare},
  {"float16_roundtrip", .Bare},
  {"local_array_index_expression", .Bare},
  {"for_continue_break_mix", .Bare},
  {"switch_through_default", .Bare},
  {"bool_int_chain", .Bare},
  {"inner_shadow_reassign", .Bare},
  {"helper_bool_select", .Bare},
  {"struct_constructor_named_out_of_order", .Bare},
  {"struct_copy_then_mutate", .Bare},
  {"nested_struct_constructor_named", .Bare},
  {"nested_loop_continue_break", .Bare},
  {"table_local_array_mix", .Table},
  {"table_switch_bit_mix", .Table},
  {"table_subscript_index_expr", .Table},
  {"table_helper_index_chain", .Table},
  {"boid_copy_modify_writeback", .Boids},
  {"boid_component_compound_chain", .Boids},
  {"boid_constructor_from_members", .Boids},
  {"boid_struct_temp_roundtrip", .Boids},
  {"matrix_vector_reassign", .Bare},
  {"vector3_scalar_mix_floor", .Bare},
  {"helper_pointer_table_arg", .Table},
  {"boid_nested_shorthand_constructor", .Boids},
  {"helper_if_prelude", .Bare},
  {"helper_nested_if_prelude", .Bare},
  {"struct_helper_if_prelude", .Bare},
  {"ifx_select_expr", .Bare},
  {"ifx_lazy_branch_side_effects", .Bare},
  {"pointer_alias_same_buffer", .Bare},
  {"vector_component_write_order", .Boids},
  {"nested_array_struct_chain", .Boids},
  {"using_shadow_member_write", .Bare},
  {"signed_unsigned_shift_compare", .Bare},
  {"int64_loop_cast_mod", .Bare},
  {"matrix_ctor_scalar_chain", .Bare},
  {"helper_vector_return_swizzle", .Bare},
  {"defer_continue_return_nested", .Bare},
  {"switch_dense_sparse_through_default", .Bare},
  {"local_fixed_array_complex_index", .Bare},
  {"short_circuit_helper_side_effects", .Bare},
  {"global_constant_index_fold", .Bare},
  {"nested_struct_copy_partial_mutate", .Bare},
  {"thread_id_all_components", .Bare},
  {"boid_component_write_hazard", .Boids},
  {"table_dynamic_index_chain", .Table},
  {"helper_matrix_vector_chain", .Bare},
  {"for_switch_break_continue_mix", .Bare},
  {"for_local_array_iteration_value", .Bare},
  {"for_local_array_it", .Bare},
  {"struct_of_array_roundtrip", .Bare},
  {"table_rotate_sum", .Table},
  {"boid_pairwise_mix", .Boids},
  {"nested_defer_loop", .Bare},
  {"helper_matrix_rebuild", .Bare},
  {"subscript_compound_mix", .Table},
  {"switch_table_dynamic", .Table},
  {"using_helper_nested_struct", .Bare},
  {"short_circuit_nested_calls", .Bare},
  {"ifx_nested_chain", .Bare},
  {"boid_ifx_component_choose", .Boids},
  {"same_width_signed_casts", .Bare},
  {"nested_struct_helper_arg_copy", .Bare},
  {"scalar_helper_if_return_chain", .Bare},
  {"pointer_alias_from_member_expr", .Bare},
  {"shaderfuncs_normalize_mix_clamp", .Bare},
  {"shaderfuncs_saturate", .Bare},
  {"shaderfuncs_lerp", .Bare},
  {"shaderfuncs_reflect", .Bare},
  {"shaderfuncs_step_smoothstep_mod_fract", .Bare},
  {"shaderfuncs_degrees_radians_chain", .Bare},
  {"tuple_destructure_compound_decl", .Bare},
  {"tuple_destructure_helper_calls", .Bare},
  {"call_arg_implicit_cast_to_s64", .Bare},
  {"shaderfuncs_vector_mix_clamp", .Bare},
  {"shaderfuncs_vector_step_smoothstep_mod", .Bare},
  {"vector_negate", .Bare},
  {"helper_nested_call", .Bare},
  {"struct_constructor_from_member_expr", .Boids},
  {"nested_local_struct_field_access", .Bare},
  {"edge_gap_70_helper_struct_named_constructor_arg", .Bare},
  {"edge_gap_71_switch_signed_condition", .Bare},
  {"edge_gap_72_helper_pointer_alias_arg", .Table},
  
  {"nested", .Table},
  {"bitwise", .Table},
  {"using_helper", .Table},
  
  {"vector_index", .Boids},
  {"access_chain", .Boids},
  {"helper_struct_chain", .Boids},
  {"helper_struct_direct_assign", .Boids},
  {"raw_vec3_buffer_component_write", .Vec3},
  {"raw_vec4_buffer_component_write", .Vec4},
  {"struct_vec4_field_write", .Vec4Box},
  {"struct_buffer_element_constructor_assign", .Vec4Box},
  {"terrain_tetra_inside_outside_signature", .Bare},
  {"helper_scalar_arg_shadow_capture", .Bare},
  
  {"inner_proc", .Bare},
];

ELEMENT_COUNT :: 64;

Compute_Boid_State :: struct {
  pos: Vector2;
  vel: Vector2;
}

Compute_Vec4_Box :: struct {
  v: Vector4;
}

Compute_Table_Kind :: enum {
  U32;
  BOID_STATE;
  VEC3;
  VEC4;
  VEC4_BOX;
}

Compute_Semantics_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
  #overlay (thread_id) dispatch_xyz: UVector3; @thread_position_in_grid
  group_thread_id: UVector3; @thread_position_in_threadgroup
  #overlay (group_thread_id) local_tid: UVector3; @thread_position_in_threadgroup
  group_id: UVector3; @threadgroup_position_in_grid
  #overlay (group_id) workgroup_xyz: UVector3; @threadgroup_position_in_grid
  group_index: u32; @thread_index_in_threadgroup
  #overlay (group_index) local_index: u32; @thread_index_in_threadgroup
}

compute_bindless_write_2d :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 2 || thread_id.y >= 2 return;

  texture_index := values[0];
  color := Vector4.{1.0, 0.0, 0.0, 1.0};
  if thread_id.x == 1 color = Vector4.{0.0, 1.0, 0.0, 1.0};
  if thread_id.y == 1 color.z = 1.0;
  write_2d(texture_index, thread_id.x, thread_id.y, color);
} @compute_shader

simple :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    v := values[thread_id.x];
    if (thread_id.x % 2) == 0 {
      using thread_id;
      values[x] = v * 3 + 1;
    } else {
      values[thread_id.x] = v * 5 + 7;
    }
  }
} @compute_shader

loop :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    base := values[thread_id.x];
    acc: u32 = 0;
    for 0..4 {
      acc += thread_id.x + 1;
      acc += 1;
    }
    values[thread_id.x] = base + acc;
  }
} @compute_shader

nested :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    base := values[idx];
    tweak := table[idx % 8];

    if (idx % 3) == 0 {
      for 0..1 {
        base += tweak + 1;
      }
    } else {
      if (idx % 2) == 0 {
        base += tweak;
      } else {
        base += tweak * 2;
      }
    }

    values[idx] = base;
  }
} @compute_shader

locals :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    base := values[idx];
    t0 := base + idx;
    t1 := t0 * 2;
    t2 := t1 - (idx % 5);
    values[idx] = t2;
  }
} @compute_shader

return_value :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;

  idx := thread_id.x;
  sum: u32 = 0;
  for i: 0..3 {
    ii := cast(u32) i;
    if (ii % 2) == 0 {
      sum += idx + ii;
    } else {
      sum += 1;
    }
  }
  values[idx] = values[idx] + sum;
} @compute_shader

compute_semantics_helper_twist :: (x: u32, y: u32) -> u32 {
  t := x * 3 + y;
  return t + (y + 1) * 2;
}

with_function :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    values[idx] = compute_semantics_helper_twist(values[idx], idx);
  }
} @compute_shader

bitwise :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    a := values[idx];
    b := table[idx];
    mask := (a & 15) << 1;
    mixed := (a ^ b) | mask;
    shr := b >> (idx % 3);
    values[idx] = mixed + shr;
  }
} @compute_shader

with_using :: (in: Compute_Semantics_In, values: *u32) {
  using in;
  if thread_id.x < 64 {
    idx := thread_id.x;
    values[idx] = values[idx] + idx + 1;
  }
} @compute_shader

Using_Helper_Params :: struct {
  base: u32;
  delta: u32;
}

using_helper_step :: (input: Using_Helper_Params) -> u32 {
  using input;
  return base + delta * 2;
}

using_helper :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    p := Using_Helper_Params.{values[idx], table[idx % 8]};
    values[idx] = using_helper_step(p);
  }
} @compute_shader

while_break :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  j: u32 = 0;
  while true {
    if j >= 6 break;
    acc += idx + j;
    j += 1;
  }
  values[idx] = values[idx] + acc;
} @compute_shader

with_continue :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  j: u32 = 0;
  while j < 8 {
    if (j % 2) == 1 {
      j += 1;
      continue;
    }
    acc += idx + j;
    j += 1;
  }
  values[idx] = values[idx] + acc;
} @compute_shader

with_switch :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 4 == {
    case 0;
      v += 10;
      #through;
    case 1;
      v += 3;
    case 2;
      v += 20;
    case;
      v += 30;
  }
  values[idx] = v;
} @compute_shader

compound_assign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  v += idx;
  v *= 2;
  v -= 3;
  v |= 1;
  v &= 255;
  values[idx] = v;
} @compute_shader

defer_assign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  foo := values[idx];
  defer values[idx] = foo;
  defer foo = 42;
  foo = foo + idx + 1;
} @compute_shader

defer_block :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  foo: u32 = 1;
  bar: u32 = 10;
  defer {
    foo *= 42;
    bar -= 1;
    values[idx] = foo + bar;
  }
  foo = idx + 2;
  bar = idx + 3;
  if (idx % 2) == 0 return;
  values[idx] += 777;
} @compute_shader

defer_break :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  i: u32 = 0;
  while i < 6 {
    defer acc += 1;
    if i == 3 break;
    acc += i;
    i += 1;
  }
  values[idx] = values[idx] + acc;
} @compute_shader

defer_continue :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  outer: u32 = 0;
  j: u32 = 0;
  while j < 4 {
    defer outer += 100;
    inner: u32 = 0;
    k: u32 = 0;
    while k < 4 {
      defer inner += 1;
      if k == 1 {
        k += 1;
        continue;
      }
      if k == 3 break;
      inner += 10;
      k += 1;
    }
    outer += inner;
    j += 1;
  }
  values[idx] = values[idx] + outer;
} @compute_shader

defer_switch_through :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v: u32 = 0;
  if idx % 4 == {
    case 0;
      defer v += 100;
      v += 1;
      #through;
    case 1;
      defer v += 10;
      v += 2;
    case 2;
      defer v += 20;
      v += 3;
    case;
      defer v += 30;
      v += 4;
  }
  values[idx] = values[idx] + v;
} @compute_shader

vector_index :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    b := boids[idx];
    nx := b.pos.x + b.vel.x * 2.0;
    ny := b.pos.y + b.vel.y * 2.0;
    boids[idx].pos = Vector2.{nx, ny};
    values[idx] = cast(u32) ((nx + ny) * 10.0);
  }
} @compute_shader

access_chain :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    boids[idx].pos.x = boids[idx].pos.x + boids[idx].vel.x;
    boids[idx].pos.y = boids[idx].pos.y + boids[idx].vel.y;
    using boids[idx].pos;
    values[idx] = cast(u32) ((x * 8.0) + (y * 4.0));
  }
} @compute_shader

boid_advance :: (state: Compute_Boid_State, scale: float) -> Compute_Boid_State {
  out := state;
  out.pos.x = state.pos.x + state.vel.x * scale;
  out.pos.y = state.pos.y + state.vel.y * scale;
  return out;
}

helper_struct_chain :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    next := boid_advance(boids[idx], 2.0);
    boids[idx] = next;
    values[idx] = cast(u32) (boid_advance(boids[idx], 1.0).pos.x +
                             boid_advance(boids[idx], 1.0).pos.y);
  }
} @compute_shader

helper_struct_direct_assign :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    boids[idx] = boid_advance(boids[idx], 2.0);
    values[idx] = cast(u32) (boids[idx].pos.x + boids[idx].pos.y);
  }
} @compute_shader

raw_vec3_buffer_component_write :: (using in: Compute_Semantics_In, values: *u32, table: *Vector3) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := table[idx];
  table[idx].x = v.x + 0.5;
  table[idx].z = table[idx].x + table[idx].y + cast(float) (idx % 5) * 0.25;
  out := table[idx].x + table[idx].z;
  values[idx] = cast(u32) floor(out * 13.0) + idx;
} @compute_shader

raw_vec4_buffer_component_write :: (using in: Compute_Semantics_In, values: *u32, table: *Vector4) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := table[idx];
  table[idx].x = v.x + 1.0;
  table[idx].z = table[idx].x + table[idx].y + cast(float) (idx % 3);
  out := table[idx].z + table[idx].w;
  values[idx] = cast(u32) floor(out * 10.0) + idx;
} @compute_shader

struct_vec4_field_write :: (using in: Compute_Semantics_In, values: *u32, table: *Compute_Vec4_Box) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := table[idx];
  b.v = b.v + Vector4.{0.25, 0.5, 0.75, 1.0};
  b.v.w = b.v.x + b.v.y + b.v.z + 0.5;
  table[idx].v = b.v;
  values[idx] = cast(u32) floor(table[idx].v.w * 9.0 + b.v.x * 3.0) + idx;
} @compute_shader

struct_buffer_element_constructor_assign :: (using in: Compute_Semantics_In, values: *u32, table: *Compute_Vec4_Box) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := table[idx].v;
  table[idx] = Compute_Vec4_Box.{
    v = .{
      x = v.x + 0.2,
      y = v.y + 0.4,
      z = v.z + 0.6,
      w = v.x + v.y + v.z + 0.8,
    },
  };
  values[idx] = cast(u32) floor(table[idx].v.w * 11.0 + table[idx].v.x * 5.0) + idx;
} @compute_shader

matrix_math :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    m := Matrix2.{2.0, 1.0, -1.0, 3.0};
    v := Vector2.{cast(float) (idx % 8), cast(float) ((idx * 3) % 7)};
    r := m * v;
    values[idx] = cast(u32) (r.x * 4.0 + r.y * 2.0 + 17.0);
  }
} @compute_shader

intrinsics :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    x := cast(float) (idx % 16);
    a := floor(x * 0.5);
    b := min(max(x - 3.0, 0.0), 5.0);
    c := abs(x - 7.0);
    d := sqrt((x + 1.0) * (x + 1.0));
    e := sin(0.0) + cos(0.0);
    // Avoid integer-boundary flakiness from tiny trig precision differences across CPU/GPU.
    values[idx] = cast(u32) floor(a + b + c + d + e + 0.5);
  }
} @compute_shader

// Edge-case shaders for IR/backend parity coverage.
Edge_U32_Pair :: struct {
  a: u32;
  b: u32;
}

Edge_Nested_Local :: struct {
  pair: Edge_U32_Pair;
  z: u32;
}

Edge_Array4_U32 :: struct {
  values: [4]u32;
}

Edge_Array_Struct_Item :: struct {
  p: Edge_U32_Pair;
}

Edge_Struct_With_Array :: struct {
  slots: [4]u32;
}

EDGE_GLOBAL_BIAS :: cast(u32) 13;

edge_global_lut_value :: (i: u32) -> u32 {
  x := i % 8;
  out: u32 = 0;
  if x == 0 out = 7;
  else if x == 1 out = 3;
  else if x == 2 out = 5;
  else if x == 3 out = 1;
  else if x == 4 out = 6;
  else if x == 5 out = 2;
  else if x == 6 out = 4;
  else out = 0;
  return out;
}

edge_make_pair :: (x: u32, y: u32) -> Edge_U32_Pair {
  return Edge_U32_Pair.{x, y};
}

bool_and_or :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := (idx % 2) == 0;
  b := (idx % 3) == 0;
  if a && !b values[idx] += 11;
  else if a || b values[idx] += 5;
  else values[idx] += 1;
} @compute_shader

unary_not_bool :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  if !(idx == 7) values[idx] += 2;
} @compute_shader

unary_bit_not :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = ~values[idx];
} @compute_shader

switch_sparse :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 9 == {
    case 1; v += 100;
    case 4; v += 40;
    case 7; v += 7;
    case;   v += 1;
  }
  values[idx] = v;
} @compute_shader

switch_through_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 5 == {
    case 0;
      v += 1;
      #through;
    case 1;
      v += 2;
      #through;
    case 2;
      v += 4;
    case;
      v += 8;
  }
  values[idx] = v;
} @compute_shader

nested_while_continue_break :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  j: u32 = 0;
  acc: u32 = 0;
  while true {
    if j >= 10 break;
    if (j % 3) == 0 {
      j += 1;
      continue;
    }
    acc += j;
    j += 1;
  }
  values[idx] += acc;
} @compute_shader

local_array_literal_read :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [4]u32 = .[2, 4, 8, 16];
  values[idx] += lut[idx % 4];
} @compute_shader

local_array_write_then_read :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [4]u32;
  lut[0] = idx + 1;
  lut[1] = idx + 2;
  lut[2] = idx + 3;
  lut[3] = idx + 4;
  values[idx] = lut[(idx + 1) % 4];
} @compute_shader

float2_component_compound :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector2.{cast(float) idx, 1.0};
  v.x += 2.0;
  v.y *= 3.0;
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

float4_component_lvalue :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector4.{1.0, 2.0, 3.0, 4.0};
  v.x = v.x + cast(float) idx;
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

float4_swizzle_xy :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector4.{cast(float) idx, cast(float) (idx + 1), 9.0, 10.0};
  xy := v.xy;
  values[idx] = cast(u32) (xy.x + xy.y);
} @compute_shader

matrix_ctor_mul :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{1.0, 2.0, 3.0, 4.0};
  p := m * Vector2.{cast(float) idx, 1.0};
  values[idx] = cast(u32) (p.x + p.y);
} @compute_shader

matrix_mul_builtin :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{2.0, 0.0, 0.0, 2.0};
  p := m * Vector2.{cast(float) idx, 0.5};
  values[idx] = cast(u32) p.x;
} @compute_shader

intrinsic_mod_float :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (idx + 5);
  values[idx] = cast(u32) fmod_cycling(x, 3.5);
} @compute_shader

intrinsic_smoothstep :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (idx % 10) / 9.0;
  y := saturate((x - 0.2) / 0.6);
  values[idx] = cast(u32) floor(y * 255.0);
} @compute_shader

intrinsic_pow :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  y := pow(2.0, cast(float) (idx % 6));
  values[idx] = cast(u32) y;
} @compute_shader

helper_return_member_on_call :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = edge_make_pair(idx, idx + 9).b;
} @compute_shader

helper_return_assign_local :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := edge_make_pair(idx + 1, idx + 2);
  values[idx] = p.a + p.b;
} @compute_shader

nested_local_struct_field_access :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  n := Edge_Nested_Local.{pair = Edge_U32_Pair.{idx + 3, idx + 4}, z = 5};
  values[idx] = n.pair.a + n.pair.b + n.z;
} @compute_shader

using_inside_nested_block :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  {
    using thread_id;
    values[x] = values[x] + 1;
  }
} @compute_shader

for_descending :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  i: u32 = 5;
  while true {
    acc += i;
    if i == 0 break;
    i -= 1;
  }
  values[idx] += acc;
} @compute_shader

for_local_array_it :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  acc: u32 = 99;
  for u32.[1, 2, 3, 4, thread_id.x] acc += it;
} @compute_shader

for_local_array_iteration_value :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [4]u32 = .[idx + 1, idx + 2, idx + 3, idx + 4];
  acc: u32 = 0;
  for v: lut {
    acc += v;
  }
  values[idx] = acc + idx;
} @compute_shader

bool_temp_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := (idx % 2) == 0;
  b := (idx % 4) == 0;
  c := (idx % 8) == 0;
  pass := (a && b) || c;
  if pass values[idx] += 9;
} @compute_shader

nested_switch_in_loop :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  for 0..2 {
    if (idx + cast(u32) it) % 3 == {
      case 0; v += 1;
      case 1; v += 2;
      case;   v += 3;
    }
  }
  values[idx] = v;
} @compute_shader

cast_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := cast(float) idx;
  b := cast(u32) (a * 1.5);
  values[idx] = b + 3;
} @compute_shader

vector_scalar_mix :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector2.{cast(float) idx, 2.0};
  v = v * 2.0 + Vector2.{1.0, 1.0};
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

vector_negate :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := -Vector2.{cast(float) idx, 3.0};
  values[idx] = cast(u32) abs(v.x) + cast(u32) abs(v.y);
} @compute_shader

helper_nested_call :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = edge_make_pair(edge_make_pair(idx, idx + 1).a, idx + 2).b;
} @compute_shader

struct_constructor_from_member_expr :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_U32_Pair.{cast(u32) boids[idx].pos.x, cast(u32) boids[idx].vel.y};
  values[idx] = p.a + p.b;
} @compute_shader

buffer_struct_copy_temp :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  c := b;
  values[idx] = cast(u32) (c.pos.x + c.pos.y + c.vel.x + c.vel.y);
} @compute_shader

while_false_initially :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  j: u32 = 5;
  while j < 3 {
    values[idx] += j;
    j += 1;
  }
  values[idx] += 1;
} @compute_shader

int64_arithmetic :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx_u := thread_id.x;
  idx := cast(int) idx_u;
  v: int = (idx * cast(int) 3) - cast(int) 91;
  if v < 0 v = -v;
  values[idx_u] = cast(u32) (v + cast(int) 17);
} @compute_shader

subscript_compound_assign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] += idx;
  values[idx] ^= (idx << 1);
  values[idx] &= 1023;
} @compute_shader

member_chain_compound_assign :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  boids[idx].vel.x += 0.5;
  boids[idx].vel.y *= 1.25;
  boids[idx].pos.x += boids[idx].vel.x;
  boids[idx].pos.y += boids[idx].vel.y;
  values[idx] = cast(u32) (boids[idx].pos.x * 8.0 + boids[idx].pos.y * 4.0);
} @compute_shader

switch_default_only :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 5 == {
    case;
      v += 77;
  }
  values[idx] = v;
} @compute_shader

switch_without_default :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 4 == {
    case 1; v += 11;
    case 3; v += 33;
  }
  values[idx] = v;
} @compute_shader

helper_pick_value :: (x: u32) -> u32 {
  if x < 10 return x + 100;
  if x < 20 return x + 200;
  return x + 300;
}

helper_multiple_returns :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = helper_pick_value(idx % 30);
} @compute_shader

early_return_in_nested_if :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  if (idx % 3) == 0 {
    if (idx % 2) == 0 return;
    values[idx] += 9;
    return;
  }
  values[idx] += 4;
} @compute_shader

int64_bitwise_mix :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx_u := thread_id.x;
  x := cast(int) idx_u;
  v: int = (x << cast(int) 2) | cast(int) 7;
  v = v ^ cast(int) 13;
  if (v & cast(int) 1) != 0 v += cast(int) 5;
  values[idx_u] = cast(u32) (v & cast(int) 1023);
} @compute_shader

Edge_Local_Params :: struct {
  a: u32;
  b: u32;
}

local_struct_using_update :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_Local_Params.{a = values[idx], b = idx + 3};
  using p;
  a += b;
  b += 2;
  values[idx] = a + b;
} @compute_shader

vector_component_swap :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  tx := b.pos.x;
  b.pos.x = b.pos.y;
  b.pos.y = tx;
  boids[idx] = b;
  values[idx] = cast(u32) (b.pos.x * 10.0 + b.pos.y * 2.0);
} @compute_shader

matrix_reassign_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{1.0, 0.0, 0.0, 1.0};
  r0 := m * Vector2.{cast(float) idx, 1.0};
  m = Matrix2.{2.0, 1.0, 0.0, 1.0};
  r1 := m * r0;
  values[idx] = cast(u32) (r1.x + r1.y);
} @compute_shader

thread_id_y_component :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  values[thread_id.x] = values[thread_id.x] + thread_id.y + 1;
} @compute_shader

thread_id_renamed_field :: (using in: Compute_Semantics_In, values: *u32) {
  if dispatch_xyz.x >= 64 return;
  values[dispatch_xyz.x] = values[dispatch_xyz.x] + dispatch_xyz.y + dispatch_xyz.z + 3;
} @compute_shader

group_thread_id_renamed_field :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  values[thread_id.x] = values[thread_id.x] + local_tid.x + local_tid.y + local_tid.z + 5;
} @compute_shader

group_id_renamed_field :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  values[thread_id.x] = values[thread_id.x] + workgroup_xyz.x + workgroup_xyz.y + workgroup_xyz.z + 7;
} @compute_shader

group_index_renamed_field :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  values[thread_id.x] = values[thread_id.x] + local_index + 9;
} @compute_shader

EDGE_CONST_MUL :: 5;
EDGE_CONST_ADD :: 11;

global_constants_subscript :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  values[thread_id.x] = values[thread_id.x] * EDGE_CONST_MUL + EDGE_CONST_ADD;
} @compute_shader

local_float3_components :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  t := cast(float) (idx % 5);
  v := Vector3.{1.0 + t, 2.0, 3.0};
  v.y += 4.0;
  v.z = v.z * 2.0;
  values[idx] = cast(u32) (v.x + v.y + v.z);
} @compute_shader

EDGE_WRAP_WIDTH :: 8;

edge_wrap_left_const :: (x: u32) -> u32 {
  if x == 0 return EDGE_WRAP_WIDTH - 1;
  return x - 1;
}

edge_wrap_right_const :: (x: u32) -> u32 {
  n := x + 1;
  if n >= EDGE_WRAP_WIDTH return 0;
  return n;
}

wrap_helper_constants :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  x := thread_id.x % EDGE_WRAP_WIDTH;
  l := edge_wrap_left_const(x);
  r := edge_wrap_right_const(x);
  values[thread_id.x] = x * 100 + l * 10 + r;
} @compute_shader

edge_wrap_up_const :: (y: u32) -> u32 {
  if y == 0 return EDGE_WRAP_WIDTH - 1;
  return y - 1;
}

edge_wrap_down_const :: (y: u32) -> u32 {
  n := y + 1;
  if n >= EDGE_WRAP_WIDTH return 0;
  return n;
}

edge_cell_index_const :: (x: u32, y: u32) -> u32 {
  return y * EDGE_WRAP_WIDTH + x;
}

wrap_xy_cell_index :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := idx % EDGE_WRAP_WIDTH;
  y := idx / EDGE_WRAP_WIDTH;

  left_x := edge_wrap_left_const(x);
  right_x := edge_wrap_right_const(x);
  up_y := edge_wrap_up_const(y);
  down_y := edge_wrap_down_const(y);

  l := edge_cell_index_const(left_x, y);
  r := edge_cell_index_const(right_x, y);
  u := edge_cell_index_const(x, up_y);
  d := edge_cell_index_const(x, down_y);

  values[idx] = l + r * 64 + u * 4096 + d * 262144;
} @compute_shader

EDGE_FLOAT_DT :: 1.0 / 60.0;

float_constant_division :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := cast(float) (idx + 1) * EDGE_FLOAT_DT * 120.0;
  values[idx] = cast(u32) (v * 1000.0);
} @compute_shader

float16_roundtrip :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := (idx * 3 + 5) % 29;
  h: Float16 = cast(Float16) base;
  back := cast(float) h;
  values[idx] = cast(u32) (back * 7.0 + 1.0);
} @compute_shader

local_array_index_expression :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [8]u32;
  for 0..7 {
    ii := cast(u32) it;
    lut[it] = idx + ii * 3 + 1;
  }
  j := ((idx % 3) * 2 + 1) % 8;
  values[idx] = lut[j];
} @compute_shader

for_continue_break_mix :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  for 0..15 {
    i := cast(u32) it;
    if (i % 5) == 0 continue;
    acc += i;
    if i >= (idx % 7 + 6) break;
  }
  values[idx] += acc;
} @compute_shader

switch_through_default :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 6 == {
    case 0;
      v += 2;
      #through;
    case 1;
      v += 3;
      #through;
    case;
      v += 5;
  }
  values[idx] = v;
} @compute_shader

bool_int_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := ((idx & 1) == 0);
  b := ((idx % 5) == 2);
  c := ((idx % 7) < 3);
  pass := (a && c) || (!a && b);
  if pass values[idx] += 19;
  else values[idx] += 4;
} @compute_shader

inner_shadow_reassign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := values[idx];
  {
    x := idx + 11;
    values[idx] = x;
  }
  values[idx] += x & 7;
} @compute_shader

helper_select :: (a: u32, b: u32, take_a: bool) -> u32 {
  if take_a return a;
  return b;
}

helper_bool_select :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  choose_left := (idx % 3) == 0;
  values[idx] = helper_select(values[idx], idx * 9 + 1, choose_left);
} @compute_shader

struct_constructor_named_out_of_order :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_U32_Pair.{b = idx + 30, a = idx + 5};
  values[idx] = p.a * 2 + p.b;
} @compute_shader

struct_copy_then_mutate :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := Edge_U32_Pair.{idx + 1, idx + 2};
  b := a;
  b.a += 10;
  b.b += 20;
  values[idx] = a.a + a.b + b.a + b.b;
} @compute_shader

nested_struct_constructor_named :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  n := Edge_Nested_Local.{z = 13, pair = Edge_U32_Pair.{b = idx + 4, a = idx + 3}};
  values[idx] = n.pair.a + n.pair.b + n.z;
} @compute_shader

nested_loop_continue_break :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  outer: u32 = 0;
  while outer < 5 {
    inner: u32 = 0;
    while inner < 7 {
      if inner == (idx % 4) {
        inner += 1;
        continue;
      }
      if inner >= 5 break;
      acc += outer * 10 + inner;
      inner += 1;
    }
    outer += 1;
  }
  values[idx] += acc;
} @compute_shader

table_local_array_mix :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  local: [4]u32;
  local[0] = table[idx % 8];
  local[1] = table[(idx + 1) % 8];
  local[2] = table[(idx + 2) % 8];
  local[3] = table[(idx + 3) % 8];
  values[idx] = values[idx] + local[idx % 4] + local[(idx + 2) % 4];
} @compute_shader

table_switch_bit_mix :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := values[idx];
  t := table[idx % 8];
  if idx % 4 == {
    case 0; base ^= t;
    case 1; base |= (t << 1);
    case 2; base &= (t | 255);
    case;   base += t;
  }
  values[idx] = base;
} @compute_shader

table_subscript_index_expr :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := (idx * 3 + 1) % 8;
  i1 := (idx * 5 + 2) % 8;
  values[idx] = values[idx] + table[i0] * 2 + table[i1];
} @compute_shader

table_helper_index :: (i: u32, add: u32) -> u32 {
  return (i * 3 + add) % 8;
}

table_helper_index_chain :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := table_helper_index(idx, 1);
  i1 := table_helper_index(idx + 1, 2);
  values[idx] = values[idx] + table[i0] + table[i1] * 2;
} @compute_shader

boid_copy_modify_writeback :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  b.pos.x += b.vel.x * 3.0;
  b.pos.y += b.vel.y * 2.0;
  boids[idx] = b;
  values[idx] = cast(u32) (b.pos.x * 4.0 + b.pos.y * 6.0);
} @compute_shader

boid_component_compound_chain :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  boids[idx].vel.x *= 1.5;
  boids[idx].vel.y += 0.25;
  boids[idx].pos.x += boids[idx].vel.x;
  boids[idx].pos.y += boids[idx].vel.y;
  values[idx] = cast(u32) (boids[idx].pos.x * 5.0 + boids[idx].pos.y * 3.0);
} @compute_shader

boid_constructor_from_members :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  src := boids[idx];
  next := Compute_Boid_State.{
    pos = Vector2.{src.pos.x + src.vel.x, src.pos.y + src.vel.y},
    vel = Vector2.{src.vel.y, src.vel.x},
  };
  boids[idx] = next;
  values[idx] = cast(u32) (next.pos.x * 2.0 + next.pos.y * 2.0 + next.vel.x * 10.0);
} @compute_shader

boid_struct_temp_roundtrip :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := boids[idx];
  b := a;
  b.pos.x = a.pos.y + a.vel.x;
  b.pos.y = a.pos.x + a.vel.y;
  boids[idx] = b;
  values[idx] = cast(u32) (b.pos.x * 7.0 + b.pos.y * 2.0);
} @compute_shader

matrix_vector_reassign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{1.0, 2.0, 3.0, 4.0};
  v := Vector2.{cast(float) (idx % 6), cast(float) (idx % 4)};
  r0 := m * v;
  m = Matrix2.{0.5, 0.0, 0.0, 2.0};
  r1 := m * r0;
  values[idx] = cast(u32) (r1.x * 3.0 + r1.y);
} @compute_shader

vector3_scalar_mix_floor :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  t := cast(float) (idx % 9);
  v := Vector3.{t + 0.25, t * 0.5 + 1.0, 8.0 - t * 0.25};
  v = v * 1.5 + Vector3.{0.5, 1.5, 2.5};
  values[idx] = cast(u32) floor(v.x + v.y + v.z);
} @compute_shader

pointer_table_mix_helper :: (table: *u32, idx: u32) -> u32 {
  a := table[idx % 8];
  b := table[(idx + 3) % 8];
  return a + b * 2;
}

helper_pointer_table_arg :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = values[idx] + pointer_table_mix_helper(table, idx);
} @compute_shader

boid_nested_shorthand_constructor :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  src := boids[idx];
  next := Compute_Boid_State.{
    pos = .{x = src.pos.x + src.vel.x, y = src.pos.y + src.vel.y},
    vel = .{x = src.vel.y, y = src.vel.x},
  };
  boids[idx] = next;
  values[idx] = cast(u32) (next.pos.x * 2.0 + next.pos.y * 2.0 + next.vel.x * 10.0);
} @compute_shader

helper_if_prelude_return :: (x: u32) -> u32 {
  if (x & 1) == 0 {
    t := x * 3 + 2;
    return t + 5;
  }
  return x + 11;
}

helper_if_prelude :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = helper_if_prelude_return(values[idx] + idx);
} @compute_shader

helper_nested_if_prelude_return :: (x: u32) -> u32 {
  if (x % 5) < 3 {
    base := x * 2 + 1;
    if (base & 1) == 0 {
      tweak := base + 7;
      return tweak;
    }
    return base + 9;
  }
  return x + 13;
}

helper_nested_if_prelude :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = helper_nested_if_prelude_return(values[idx] + idx * 2);
} @compute_shader

Edge_Case_72_Pair :: struct {
  a: u32;
  b: u32;
}

helper_struct_if_prelude_return :: (x: u32) -> Edge_Case_72_Pair {
  if (x % 2) == 0 {
    base := x + 2;
    return Edge_Case_72_Pair.{a = base * 2, b = base + 3};
  }
  return Edge_Case_72_Pair.{a = x + 5, b = x + 7};
}

struct_helper_if_prelude :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := helper_struct_if_prelude_return(values[idx] + idx);
  values[idx] = p.a + p.b * 2;
} @compute_shader

ifx_select_helper :: (cond: bool, a: u32, b: u32) -> u32 {
  return ifx cond then a else b;
}

ifx_select_expr :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;

  idx := thread_id.x;
  base := values[idx];

  picked := ifx (idx % 2) == 0 then base + idx else base + 7;
  out: u32 = 0;
  out = ifx (base % 3) == 0 then picked * 2 else picked + 5;
  values[idx] = ifx (idx % 5) == 0 then ifx_select_helper(true, out, base) else ifx_select_helper(false, out, base);
} @compute_shader

ifx_then_side_effect :: (values: *u32, idx: u32) -> u32 {
  values[idx] += 100;
  return values[idx];
}

ifx_else_side_effect :: (values: *u32, idx: u32) -> u32 {
  values[idx] += 7;
  return values[idx];
}

ifx_lazy_branch_side_effects :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  selected := ifx (idx & 1) == 0 then ifx_then_side_effect(values, idx) else ifx_else_side_effect(values, idx);
  suffix := ifx (idx & 1) == 0 then cast(u32) 1 else cast(u32) 2;
  values[idx] = selected + suffix;
} @compute_shader

alias_read :: (values: *u32, idx: u32) -> u32 {
  return values[idx];
}

pointer_alias_same_buffer :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = values[idx] + idx + 3;
  values[idx] = alias_read(values, idx) * 2 + 1;
} @compute_shader

vector_component_write_order :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  boids[idx].pos.x = boids[idx].pos.x + boids[idx].vel.x;
  boids[idx].pos.y = boids[idx].pos.x + boids[idx].vel.y;
  values[idx] = cast(u32) (boids[idx].pos.x * 3.0 + boids[idx].pos.y * 5.0);
} @compute_shader

nested_array_struct_chain :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := (idx + 1) % 64;
  i1 := (idx * 3 + 7) % 64;
  i2 := (i0 + cast(u32) boids[i1].pos.x) % 64;
  values[idx] = cast(u32) (boids[i0].pos.x * 2.0 + boids[i1].vel.y * 8.0 + boids[i2].vel.x * 4.0);
} @compute_shader

using_shadow_member_write :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_U32_Pair.{a = idx + 2, b = idx + 7};
  using p;
  values[idx] = a + b;
  {
    inner := idx + 33;
    values[idx] += inner;
  }
  values[idx] += a;
} @compute_shader

signed_unsigned_shift_compare :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  si := cast(s64) (values[idx] & 255);
  ui := cast(s64) idx;
  shifted := cast(u32) si >> (idx % 3);
  if si < ui {
    values[idx] = shifted + 11;
  } else {
    values[idx] = shifted + 3;
  }
} @compute_shader

int64_loop_cast_mod :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := cast(s64) thread_id.x;
  acc: s64 = 0;
  for i: 0..4 {
    ii := cast(s64) i;
    acc += (idx + 1) * (ii + 3);
  }
  values[thread_id.x] = cast(u32) (acc & 255);
} @compute_shader

matrix_ctor_scalar_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := 1.0 + cast(float) (idx % 3);
  b := 0.5 + cast(float) (idx % 5) * 0.25;
  c := 2.0 + cast(float) (idx % 7) * 0.125;
  d := 1.0;
  m := Matrix2.{a, b, c, d};
  v := Vector2.{cast(float) (idx % 4), cast(float) (idx % 6)};
  r := m * v;
  values[idx] = cast(u32) floor(r.x + r.y + 0.5);
} @compute_shader

helper_make_vec4 :: (x: float) -> Vector4 {
  return Vector4.{x + 1.0, x * 0.5 + 2.0, x * 0.25 + 3.0, 1.0};
}

helper_add_bias_void :: (values: *u32, idx: u32, bias: u32) {
  values[idx] += bias;
}

helper_void_call_statement :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := values[idx];
  helper_add_bias_void(values, idx, (idx % 5) + 3);
  values[idx] = values[idx] + base * 2 + 1;
} @compute_shader

helper_add_with_nested_return :: (values: *u32, idx: u32) {
  values[idx] += 2;
  if (idx % 4) == 0 {
    return;
  }

  i: u32 = 0;
  while i < 3 {
    if i == (idx % 3) {
      values[idx] += 5;
      return;
    }
    values[idx] += i + 1;
    i += 1;
  }

  values[idx] += 11;
}

helper_void_nested_return :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := values[idx];
  helper_add_with_nested_return(values, idx);
  values[idx] = values[idx] + base * 3 + 7;
} @compute_shader

helper_add_with_switch_return :: (values: *u32, idx: u32) {
  values[idx] += 1;
  if idx % 5 == {
    case 0;
      values[idx] += 40;
      return;
    case 1;
      values[idx] += 30;
      #through;
    case 2;
      values[idx] += 20;
      return;
    case;
      values[idx] += 10;
  }
  values[idx] += 3;
}

helper_void_switch_return :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := values[idx];
  helper_add_with_switch_return(values, idx);
  values[idx] = values[idx] + base * 4 + 5;
} @compute_shader

local_float3_array_roundtrip :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a: [4]Vector3;
  a[0] = .{1.0, 2.0, 3.0};
  a[1] = .{4.0, 5.0, 6.0};
  a[2] = .{7.0, 8.0, 9.0};
  a[3] = .{10.0, 11.0, 12.0};
  j0 := idx % 4;
  j1 := (idx + 1) % 4;
  v := a[j0] + a[j1] * 0.5;
  values[idx] = cast(u32) floor(v.x * 5.0 + v.y * 3.0 + v.z * 2.0 + cast(float) idx);
} @compute_shader

helper_float3_array_arg_inner :: (arr: [4]Vector3, idx: u32) -> u32 {
  a := arr[idx % 4];
  b := arr[(idx + 2) % 4];
  v := a * 0.75 + b * 0.25;
  return cast(u32) floor(v.x * 7.0 + v.y * 5.0 + v.z * 3.0 + cast(float) idx);
}

helper_float3_array_arg :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a: [4]Vector3;
  a[0] = .{2.0, 4.0, 6.0};
  a[1] = .{8.0, 10.0, 12.0};
  a[2] = .{14.0, 16.0, 18.0};
  a[3] = .{20.0, 22.0, 24.0};
  values[idx] = helper_float3_array_arg_inner(a, idx);
} @compute_shader

helper_vector_return_swizzle :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := helper_make_vec4(cast(float) (idx % 9));
  xy := v.xy;
  values[idx] = cast(u32) floor(xy.x * 2.0 + xy.y + v.z);
} @compute_shader

defer_continue_return_nested :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  i: u32 = 0;
  while i < 6 {
    defer acc += 1;
    if i == (idx % 3) {
      i += 1;
      continue;
    }
    if i == 5 && (idx % 11) == 0 {
      values[idx] = acc + 77;
      return;
    }
    acc += i * 2 + 1;
    i += 1;
  }
  values[idx] += acc;
} @compute_shader

switch_dense_sparse_through_default :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 8 == {
    case 0;
      v += 2;
      #through;
    case 1; v += 4;
    case 3; v += 9;
    case 6;
      v += 1;
      #through;
    case;
      v += 7;
  }
  values[idx] = v;
} @compute_shader

local_fixed_array_complex_index :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a: [8]u32;
  for i: 0..7 a[i] = cast(u32) (i * 3 + 1);
  i0 := (idx * 5 + 3) % 8;
  i1 := (idx * 7 + 1) % 8;
  values[idx] = values[idx] + a[i0] * 2 + a[i1];
} @compute_shader

mark_true :: (values: *u32, idx: u32) -> bool {
  values[idx] += 100;
  return true;
}

mark_false :: (values: *u32, idx: u32) -> bool {
  values[idx] += 7;
  return false;
}

short_circuit_helper_side_effects :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  even := (idx & 1) == 0;
  first := even && mark_true(values, idx);
  second := !even || mark_false(values, idx);
  if first values[idx] += 1;
  if second values[idx] += 2;
} @compute_shader

global_constant_index_fold :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := (idx * 3 + EDGE_GLOBAL_BIAS) % 8;
  i1 := (edge_global_lut_value(i0) + idx) % 8;
  values[idx] = values[idx] + edge_global_lut_value(i0) * 2 + edge_global_lut_value(i1);
} @compute_shader

nested_struct_copy_partial_mutate :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := Edge_Nested_Local.{pair = Edge_U32_Pair.{a = idx + 1, b = idx + 2}, z = idx + 3};
  next := base;
  next.pair.b += 9;
  values[idx] = base.pair.a + base.pair.b + next.pair.b + next.z;
} @compute_shader

thread_id_all_components :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  mixed_id := thread_id.x + thread_id.y * 7 + thread_id.z * 13;
  values[idx] = values[idx] + mixed_id + 1;
} @compute_shader

boid_component_write_hazard :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  boids[idx].pos.y = boids[idx].pos.x + boids[idx].vel.y;
  boids[idx].pos.x = boids[idx].pos.y + boids[idx].vel.x;
  values[idx] = cast(u32) (boids[idx].pos.x * 4.0 + boids[idx].pos.y * 3.0);
} @compute_shader

table_dynamic_index_chain :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := table[idx % 8] % 8;
  i1 := table[(idx + 3) % 8] % 8;
  i2 := (i0 + i1 + idx) % 8;
  values[idx] = values[idx] + table[i0] + table[i1] * 2 + table[i2];
} @compute_shader

make_matrix :: (s: float, b: float) -> Matrix2 {
  return Matrix2.{s, b, 0.0, s + 1.0};
}

helper_matrix_vector_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := make_matrix(cast(float) (idx % 4) + 1.0, 0.25);
  v := Vector2.{cast(float) (idx % 5), cast(float) (idx % 3)};
  r := m * v;
  values[idx] = cast(u32) floor(r.x + r.y + 0.25);
} @compute_shader

for_switch_break_continue_mix :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  for i: 0..7 {
    ii := cast(u32) i;
    if ii == (idx % 5) continue;
    if ii % 6 == {
      case 0; acc += ii + 1;
      case 1; acc += ii + 3;
      case 4; acc += 9;
      case;
        acc += 2;
    }
  }
  values[idx] = values[idx] + acc;
} @compute_shader

struct_of_array_roundtrip :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a: [4]u32;
  a[0] = idx + 1;
  a[1] = idx + 3;
  a[2] = idx + 5;
  a[3] = idx + 7;
  b: [4]u32;
  b[0] = a[0];
  b[1] = a[1];
  b[2] = a[2];
  b[3] = a[3];
  b[(idx + 2) % 4] += 9;
  values[idx] = a[idx % 4] + b[(idx + 2) % 4];
} @compute_shader

table_rotate_sum :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := idx % 8;
  i1 := (i0 + 3) % 8;
  i2 := (i1 + 3) % 8;
  v := table[i0] + table[i1] * 2 + table[i2] * 3;
  values[idx] = values[idx] + v;
} @compute_shader

boid_pairwise_mix :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := boids[idx];
  b := boids[idx];
  out := Compute_Boid_State.{
    pos = .{x = a.pos.x + b.vel.x, y = a.pos.y + b.vel.y},
    vel = .{x = b.pos.x - a.vel.x, y = b.pos.y - a.vel.y},
  };
  boids[idx] = out;
  values[idx] = cast(u32) (out.pos.x * 2.0 + out.pos.y * 3.0 + out.vel.x * 4.0 + out.vel.y * 5.0);
} @compute_shader

nested_defer_loop :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  acc: u32 = 0;
  i: u32 = 0;
  while i < 5 {
    defer acc += 1;
    j: u32 = 0;
    while j < 4 {
      defer acc += 2;
      if j == (idx % 3) {
        j += 1;
        continue;
      }
      acc += i + j;
      if j == 3 break;
      j += 1;
    }
    i += 1;
  }
  values[idx] = values[idx] + acc;
} @compute_shader

matrix_rebuild_helper :: (k: float) -> Matrix2 {
  return Matrix2.{k, 1.0 - k * 0.25, k * 0.5, k + 1.0};
}

helper_matrix_rebuild :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  k := cast(float) (idx % 6) * 0.25 + 0.5;
  m0 := matrix_rebuild_helper(k);
  m1 := matrix_rebuild_helper(k + 0.25);
  v := Vector2.{cast(float) (idx % 5), cast(float) (idx % 7)};
  r0 := m0 * v;
  r1 := m1 * r0;
  values[idx] = cast(u32) floor(r1.x + r1.y + 0.5);
} @compute_shader

subscript_compound_mix :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i0 := idx % 8;
  i1 := (idx + 1) % 8;
  tmp: [2]u32;
  tmp[0] = table[i0];
  tmp[1] = table[i1];
  tmp[0] += values[idx] & 15;
  tmp[1] ^= tmp[0];
  values[idx] = values[idx] + tmp[0] + tmp[1];
} @compute_shader

switch_table_dynamic :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  key := table[idx % 8] % 6;
  if key == {
    case 0; v += 3;
    case 2; v += 7;
    case 4; v += 11;
    case;   v += 1;
  }
  values[idx] = v;
} @compute_shader

Edge_Using_Box :: struct {
  a: u32;
  b: u32;
  bias: u32;
}

using_helper_inner :: (box: Edge_Using_Box) -> u32 {
  using box;
  return a + b + bias;
}

using_helper_nested_struct :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := Edge_Using_Box.{a = idx + 2, b = idx + 5, bias = idx % 7};
  values[idx] = values[idx] + using_helper_inner(b);
} @compute_shader

call_true :: (values: *u32, idx: u32) -> bool {
  values[idx] += 9;
  return true;
}

call_false :: (values: *u32, idx: u32) -> bool {
  values[idx] += 4;
  return false;
}

short_circuit_nested_calls :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  even := (idx & 1) == 0;
  pass := (even && call_true(values, idx)) || (!even && call_false(values, idx));
  if pass values[idx] += 2;
  else values[idx] += 1;
} @compute_shader

ifx_nested_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := ifx (idx % 2) == 0 then values[idx] + 3 else values[idx] + 5;
  b := ifx (idx % 3) == 0 then a * 2 else a + 7;
  c := ifx (idx % 5) == 0 then b + idx else b - (idx % 7);
  values[idx] = c;
} @compute_shader

boid_ifx_component_choose :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  choose_x := (idx & 1) == 0;
  px := ifx choose_x then b.pos.x + b.vel.x else b.pos.y + b.vel.y;
  py := ifx choose_x then b.pos.y - b.vel.x else b.pos.x - b.vel.y;
  boids[idx].pos = .{x = px, y = py};
  values[idx] = cast(u32) (px * 4.0 + py * 6.0);
} @compute_shader

same_width_signed_casts :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  raw := values[idx] & 0x7FFF_FFFF;
  as_s32 := cast(s32) raw;
  back_u32 := cast(u32) as_s32;
  as_s64 := cast(s64) back_u32;
  as_u64 := cast(u64) as_s64;
  values[idx] = cast(u32) (as_u64 & cast(u64) 0xFFFF) + cast(u32) (back_u32 & 31);
} @compute_shader

Edge_Using_Box_Nested :: struct {
  pair: Edge_U32_Pair;
  bias: u32;
}

nested_struct_helper_arg_copy_inner :: (box: Edge_Using_Box_Nested) -> u32 {
  using box;
  return pair.a + pair.b + bias;
}

nested_struct_helper_arg_copy :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  box := Edge_Using_Box_Nested.{pair = .{a = idx + 2, b = idx + 5}, bias = idx % 7};
  values[idx] = values[idx] + nested_struct_helper_arg_copy_inner(box);
} @compute_shader

scalar_helper_if_return_chain_inner :: (x: u32) -> u32 {
  base := x * 3 + 1;
  if (x & 1) == 0 {
    return base + 7;
  }
  return base + 2;
}

scalar_helper_if_return_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = scalar_helper_if_return_chain_inner(values[idx] + idx);
} @compute_shader

Edge_Case_108_Params :: struct {
  values: *u32;
}

pointer_alias_from_member_expr :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  params := Edge_Case_108_Params.{values = values};
  alias := params.values;
  alias[idx] = alias[idx] + idx + 9;
  alias[idx] = alias_read(alias, idx) * 3 + 2;
} @compute_shader

shaderfuncs_normalize_mix_clamp :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := cast(float) ((values[idx] % 97) + 1);
  v := Vector2.{base * 0.03125 + 0.25, cast(float) (idx % 11) * 0.125 + 0.5};
  n := normalize(v);
  t_raw := cast(float) ((idx * 13) % 170) * 0.01 - 0.25;
  t := clamp(t_raw, 0.0, 1.0);
  m := mix(n.x, n.y + 0.125, t);
  values[idx] = cast(u32) (m * 1000.0 + n.x * 173.0 + n.y * 211.0 + t * 37.0);
} @compute_shader

shaderfuncs_saturate :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (idx % 17) * 0.17 - 0.85;
  s := saturate(x);
  values[idx] = cast(u32) floor(s * 257.0 + x * x * 91.0);
} @compute_shader

shaderfuncs_lerp :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  t := cast(float) (idx % 11) / 10.0;
  a := cast(float) (values[idx] % 23) * 0.1;
  b := a + 2.75;
  ls := lerp(a, b, t);
  values[idx] = cast(u32) floor(ls * 311.0 + t * 97.0 + a * 13.0);
} @compute_shader

shaderfuncs_reflect :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  i := normalize(Vector3.{
    cast(float) (idx % 9) * 0.17 - 0.68,
    cast(float) ((idx + 3) % 7) * 0.21 - 0.52,
    -1.0,
  });
  n := normalize(Vector3.{0.25, 0.95, 0.1});
  r := reflect(i, n);
  values[idx] = cast(u32) floor((r.x * 0.5 + 0.5) * 89.0 +
                                (r.y * 0.5 + 0.5) * 149.0 +
                                (r.z * 0.5 + 0.5) * 211.0);
} @compute_shader

shaderfuncs_step_smoothstep_mod_fract :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (values[idx] % 43) * 0.12 + cast(float) (idx % 7) * 0.07;
  wrapped := mod(x + 2.75, 1.6);
  frac_part := fract(x * 0.73);
  s := step(0.65, wrapped);
  sm := smoothstep(0.20, 1.15, wrapped + frac_part * 0.3);
  values[idx] = cast(u32) (wrapped * 137.0 + frac_part * 71.0 + s * 23.0 + sm * 89.0);
} @compute_shader

shaderfuncs_degrees_radians_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  deg := 15.0 + cast(float) (idx % 12) * 7.5;
  rad := radians(deg);
  back_deg := degrees(rad);
  sm := smoothstep(0.0, 180.0, back_deg);
  values[idx] = cast(u32) (back_deg * 3.0 + sm * 101.0);
} @compute_shader

tuple_destructure_compound_decl :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := values[idx];
  a, b := x + 3, x * 5 + 11;
  values[idx] = (a ^ b) + idx;
} @compute_shader

tuple_helper_a :: (x: u32) -> u32 {
  return x * 3 + 7;
}

tuple_helper_b :: (x: u32) -> u32 {
  return x ^ 19;
}

tuple_destructure_helper_calls :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a, b := tuple_helper_a(idx), tuple_helper_b(values[idx]);
  values[idx] = a + b * 5 + idx;
} @compute_shader

pair_mix :: (a: s64, b: s64) -> u32 {
  x := a * 13 + b * 29;
  if x < 0 x = -x;
  return cast(u32) x;
}

call_arg_implicit_cast_to_s64 :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := idx % 11;
  y := idx / 11;
  a := pair_mix(cast(s64) x - 1, y + 7);
  b := pair_mix(cast(s64) y + 2, x + 13);
  values[idx] = a * 17 + b * 31 + idx;
} @compute_shader

shaderfuncs_vector_mix_clamp :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  base := Vector3.{
    cast(float) (values[idx] % 41) * 0.041 + 0.11,
    cast(float) (idx % 29) * 0.033 + 0.07,
    cast(float) ((values[idx] + idx) % 37) * 0.027 + 0.03,
  };
  hot := Vector3.{0.93, 0.62, 0.28};
  t_scalar := cast(float) (idx % 17) * 0.05;
  t_vec := Vector3.{0.2, 0.45, 0.8};
  mixed_scalar := mix(base, hot, t_scalar);
  mixed := mix(mixed_scalar, hot, t_vec);
  bounded := clamp(mixed, 0.08, 0.91);
  bounded = clamp(bounded, Vector3.{0.10, 0.12, 0.06}, Vector3.{0.88, 0.83, 0.79});
  values[idx] = cast(u32) (bounded.x * 173.0 + bounded.y * 257.0 + bounded.z * 311.0 + cast(float) idx * 1.5);
} @compute_shader

shaderfuncs_vector_step_smoothstep_mod :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector3.{
    cast(float) (values[idx] % 53) * 0.041,
    cast(float) (idx % 31) * 0.036,
    cast(float) ((values[idx] + idx) % 47) * 0.029,
  };
  wrapped := mod(v * 1.37 + Vector3.{0.11, 0.53, 0.89}, 1.25);
  st := step(0.45, wrapped);
  sm := smoothstep(0.20, 0.95, wrapped);
  values[idx] = cast(u32) (wrapped.x * 101.0 + wrapped.y * 113.0 + wrapped.z * 127.0 +
                           st.x * 19.0 + st.y * 23.0 + st.z * 29.0 +
                           sm.x * 31.0 + sm.y * 37.0 + sm.z * 41.0);
} @compute_shader

// Gap probes (not in ALL_TEST_FUNCTIONS yet):
// - Edge helper struct constructor args with named-field form.
// - Switch condition typing for signed integer values.
// - Helper pointer args passed through local pointer aliases.

edge_gap_helper_sum_pair :: (p: Edge_U32_Pair) -> u32 {
  return p.a + p.b * 3;
}

edge_gap_70_helper_struct_named_constructor_arg :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_U32_Pair.{b = idx + 2, a = idx + 1};
  values[idx] = edge_gap_helper_sum_pair(p);
} @compute_shader

edge_gap_71_switch_signed_condition :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx_u := thread_id.x;
  idx := cast(int) idx_u;
  v := values[idx_u];
  if idx % cast(int) 4 == {
    case 0; v += 10;
    case 1; v += 20;
    case;   v += 30;
  }
  values[idx_u] = v;
} @compute_shader

edge_gap_72_helper_pointer_alias_arg :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  t := table;
  values[idx] = values[idx] + pointer_table_mix_helper(t, idx);
} @compute_shader

terrain_tetra_hash_edge :: (h: u32, a: u32, b: u32) -> u32 {
  e := (a << 2) | (b & 3);
  return (h ^ e) * 16777619;
}

terrain_tetra_getd :: (i: u32, d0: float, d1: float, d2: float, d3: float) -> float {
  if i == 0 return d0;
  if i == 1 return d1;
  if i == 2 return d2;
  return d3;
}

terrain_tetra_candidate_signature :: (d0: float, d1: float, d2: float, d3: float) -> u32 {
  inside: [4]u32;
  outside: [4]u32;
  inside_count: u32 = 0;
  outside_count: u32 = 0;

  if d0 < 0.0 { inside[inside_count] = 0; inside_count += 1; } else { outside[outside_count] = 0; outside_count += 1; }
  if d1 < 0.0 { inside[inside_count] = 1; inside_count += 1; } else { outside[outside_count] = 1; outside_count += 1; }
  if d2 < 0.0 { inside[inside_count] = 2; inside_count += 1; } else { outside[outside_count] = 2; outside_count += 1; }
  if d3 < 0.0 { inside[inside_count] = 3; inside_count += 1; } else { outside[outside_count] = 3; outside_count += 1; }

  if inside_count == 0 || inside_count == 4 return 0;

  h: u32 = 2166136261;
  if inside_count == 1 {
    i0 := inside[0];
    o0 := outside[0];
    o1 := outside[1];
    o2 := outside[2];
    _ = terrain_tetra_getd(i0, d0, d1, d2, d3);
    _ = terrain_tetra_getd(o0, d0, d1, d2, d3);
    _ = terrain_tetra_getd(o1, d0, d1, d2, d3);
    _ = terrain_tetra_getd(o2, d0, d1, d2, d3);
    h = terrain_tetra_hash_edge(h, i0, o0);
    h = terrain_tetra_hash_edge(h, i0, o1);
    h = terrain_tetra_hash_edge(h, i0, o2);
    return h;
  }

  if inside_count == 3 {
    o0 := outside[0];
    i0 := inside[0];
    i1 := inside[1];
    i2 := inside[2];
    _ = terrain_tetra_getd(o0, d0, d1, d2, d3);
    _ = terrain_tetra_getd(i0, d0, d1, d2, d3);
    _ = terrain_tetra_getd(i1, d0, d1, d2, d3);
    _ = terrain_tetra_getd(i2, d0, d1, d2, d3);
    h = terrain_tetra_hash_edge(h, o0, i0);
    h = terrain_tetra_hash_edge(h, o0, i2);
    h = terrain_tetra_hash_edge(h, o0, i1);
    return h;
  }

  i0 := inside[0];
  i1 := inside[1];
  o0 := outside[0];
  o1 := outside[1];
  _ = terrain_tetra_getd(i0, d0, d1, d2, d3);
  _ = terrain_tetra_getd(i1, d0, d1, d2, d3);
  _ = terrain_tetra_getd(o0, d0, d1, d2, d3);
  _ = terrain_tetra_getd(o1, d0, d1, d2, d3);

  h = terrain_tetra_hash_edge(h, i0, o0);
  h = terrain_tetra_hash_edge(h, i1, o0);
  h = terrain_tetra_hash_edge(h, i1, o1);
  h = terrain_tetra_hash_edge(h, i0, o0);
  h = terrain_tetra_hash_edge(h, i1, o1);
  h = terrain_tetra_hash_edge(h, i0, o1);
  return h;
}

terrain_tetra_ref_signature :: (mask: u32) -> u32 {
  h: u32 = 2166136261;

  if mask == 0 || mask == 15 return 0;
  if mask == 1  { h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 0, 2); h = terrain_tetra_hash_edge(h, 0, 3); return h; }
  if mask == 2  { h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 1, 2); h = terrain_tetra_hash_edge(h, 1, 3); return h; }
  if mask == 4  { h = terrain_tetra_hash_edge(h, 2, 0); h = terrain_tetra_hash_edge(h, 2, 1); h = terrain_tetra_hash_edge(h, 2, 3); return h; }
  if mask == 8  { h = terrain_tetra_hash_edge(h, 3, 0); h = terrain_tetra_hash_edge(h, 3, 1); h = terrain_tetra_hash_edge(h, 3, 2); return h; }
  if mask == 14 { h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 0, 3); h = terrain_tetra_hash_edge(h, 0, 2); return h; }
  if mask == 13 { h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 1, 3); h = terrain_tetra_hash_edge(h, 1, 2); return h; }
  if mask == 11 { h = terrain_tetra_hash_edge(h, 2, 0); h = terrain_tetra_hash_edge(h, 2, 3); h = terrain_tetra_hash_edge(h, 2, 1); return h; }
  if mask == 7  { h = terrain_tetra_hash_edge(h, 3, 0); h = terrain_tetra_hash_edge(h, 3, 2); h = terrain_tetra_hash_edge(h, 3, 1); return h; }
  if mask == 3  { h = terrain_tetra_hash_edge(h, 0, 2); h = terrain_tetra_hash_edge(h, 1, 2); h = terrain_tetra_hash_edge(h, 1, 3); h = terrain_tetra_hash_edge(h, 0, 2); h = terrain_tetra_hash_edge(h, 1, 3); h = terrain_tetra_hash_edge(h, 0, 3); return h; }
  if mask == 5  { h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 2, 1); h = terrain_tetra_hash_edge(h, 2, 3); h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 2, 3); h = terrain_tetra_hash_edge(h, 0, 3); return h; }
  if mask == 6  { h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 2, 0); h = terrain_tetra_hash_edge(h, 2, 3); h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 2, 3); h = terrain_tetra_hash_edge(h, 1, 3); return h; }
  if mask == 9  { h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 3, 1); h = terrain_tetra_hash_edge(h, 3, 2); h = terrain_tetra_hash_edge(h, 0, 1); h = terrain_tetra_hash_edge(h, 3, 2); h = terrain_tetra_hash_edge(h, 0, 2); return h; }
  if mask == 10 { h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 3, 0); h = terrain_tetra_hash_edge(h, 3, 2); h = terrain_tetra_hash_edge(h, 1, 0); h = terrain_tetra_hash_edge(h, 3, 2); h = terrain_tetra_hash_edge(h, 1, 2); return h; }
  if mask == 12 { h = terrain_tetra_hash_edge(h, 2, 0); h = terrain_tetra_hash_edge(h, 3, 0); h = terrain_tetra_hash_edge(h, 3, 1); h = terrain_tetra_hash_edge(h, 2, 0); h = terrain_tetra_hash_edge(h, 3, 1); h = terrain_tetra_hash_edge(h, 2, 1); return h; }
  return 0;
}

terrain_tetra_inside_outside_signature :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  mask := idx & 15;

  d0 := ifx (mask & 1) != 0 then -1.0 else +1.0;
  d1 := ifx (mask & 2) != 0 then -1.0 else +1.0;
  d2 := ifx (mask & 4) != 0 then -1.0 else +1.0;
  d3 := ifx (mask & 8) != 0 then -1.0 else +1.0;

  candidate := terrain_tetra_candidate_signature(d0, d1, d2, d3);
  reference := terrain_tetra_ref_signature(mask);
  if candidate != reference {
    values[idx] = 0x80000000 | idx;
    return;
  }
  values[idx] = values[idx] + candidate + 1;
} @compute_shader

helper_scalar_arg_shadow_sig :: (d0: u32, d1: u32, d2: u32, d3: u32) -> u32 {
  // Distinct weights make accidental argument aliasing obvious.
  return d0 + d1 * 11 + d2 * 101 + d3 * 1009;
}

helper_scalar_arg_shadow_capture :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;

  d0 := values[idx] & 7;
  d1 := idx + 3;
  d5 := idx * 5 + 1;
  d6 := idx * 9 + 2;

  // Third call arg intentionally references d1 while second helper arg is named d1.
  // Broken inline arg binding can incorrectly capture d1 <- d5 here.
  sig := helper_scalar_arg_shadow_sig(d0, d5, d1, d6);
  values[idx] = values[idx] + sig + 1;
} @compute_shader

inner_proc :: (using in: Compute_Semantics_In, values: *u32) {
    if thread_id.x >= ELEMENT_COUNT return;
    
    inner_example_proc :: (val: *u32) {
        val.* += 55;
    }
    
    idx := thread_id.x;
    values[idx] = idx;
    inner_example_proc(*values[idx]);
} @compute_shader

run_cpu_compute_dispatch :: (thread_count: s64, shader_proc: $F, values: *u32) #expand {
  for 0..thread_count-1 {
    `in := Compute_Semantics_In.{
      thread_id = .{x = cast(u32) it, y = 0, z = 0},
      group_thread_id = .{x = cast(u32) it, y = 0, z = 0},
      group_id = .{x = 0, y = 0, z = 0},
      group_index = cast(u32) it,
    };
    shader_proc(in, values);
  }
}

run_cpu_compute_dispatch :: (thread_count: s64, shader_proc: $F, values: *u32, table: *$T) #expand {
  for 0..thread_count-1 {
    `in := Compute_Semantics_In.{
      thread_id = .{x = cast(u32) it, y = 0, z = 0},
      group_thread_id = .{x = cast(u32) it, y = 0, z = 0},
      group_id = .{x = 0, y = 0, z = 0},
      group_index = cast(u32) it,
    };
    shader_proc(in, values, table);
  }
}

Compute_Case_Timings :: struct {
  compile_s: float64;
  pipeline_s: float64;
  gpu_setup_s: float64;
  dispatch_wait_s: float64;
  cpu_s: float64;
  compare_s: float64;
  total_s: float64;
}

Compute_Timing_Totals :: struct {
  case_count: s64;
  compile_s: float64;
  pipeline_s: float64;
  gpu_setup_s: float64;
  dispatch_wait_s: float64;
  cpu_s: float64;
  compare_s: float64;
  total_s: float64;
}

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_contains :: (source: string, pattern: string, where: string) {
  ok, _ := contains(source, pattern);
  if !ok fail("Expected '%' in %", pattern, where);
}

check_contains_any :: (source: string, p0: string, p1: string, where: string) {
  ok0, _ := contains(source, p0);
  ok1, _ := contains(source, p1);
  if !ok0 && !ok1 fail("Expected either '%' or '%' in %", p0, p1, where);
}

check_rgba8_pixel :: (pixels: [] u8, width: s64, x: s64, y: s64, r: u8, g: u8, b: u8, a: u8) {
  offset := (y * width + x) * 4;
  if offset + 3 >= pixels.count fail("Readback index out of range for pixel (%,%).", x, y);
  if pixels[offset + 0] != r || pixels[offset + 1] != g || pixels[offset + 2] != b || pixels[offset + 3] != a {
    fail("Unexpected pixel (%,%): got (% % % %), expected (% % % %).",
         x, y,
         pixels[offset + 0], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3],
         r, g, b, a);
  }
}

run_compute_case_impl :: (source: string, case_name: string, cpu_shader_proc: $F, proc_name: string, $WITH_TABLE := false, $TABLE_TYPE: Type = u32, $TABLE_KIND := Compute_Table_Kind.U32) {
  case_start := current_time_monotonic();
  timings: Compute_Case_Timings;
  suffix := ifx WITH_TABLE then " (table)" else "";
  //log("[IR][compute] Running case '%'", case_name, proc_name, suffix);
  error: *NSError = null;
  t0 := current_time_monotonic();
  lib_compute := MTLDevice.newLibraryWithSource_options_error(g_device, NSString.getTempString(source), g_compile_options, *error);
  timings.compile_s = to_float64_seconds(current_time_monotonic() - t0);
  if log_nserror("Failed to compile compute shader library", error) || !lib_compute {
    if !lib_compute && error == null fail("Failed to compile compute shader library: %", case_name);
    fail("Compute source compilation failed: %", case_name);
  }
  defer release(lib_compute);

  fn_compute := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_compute, NSString.getTempString("ComputeMain"));
  if !fn_compute fail("Failed to find compute entry point 'ComputeMain': %", case_name);
  defer release(fn_compute);

  error = null;
  t0 = current_time_monotonic();
  pipeline_compute := MTLDevice.newComputePipelineStateWithFunction_error(g_device, xx fn_compute, *error);
  timings.pipeline_s = to_float64_seconds(current_time_monotonic() - t0);
  if log_nserror("Failed to create compute pipeline", error) || !pipeline_compute {
    if !pipeline_compute && error == null fail("Failed to create compute pipeline");
    fail("Compute pipeline creation failed '%'", case_name);
  }
  defer release(pipeline_compute);

  t0 = current_time_monotonic();
  buffer_size := cast(NSUInteger) (ELEMENT_COUNT * size_of(u32));
  out_buffer := MTLDevice.newBufferWithLength_options(g_device, buffer_size, .MTLResourceStorageModeShared);
  if !out_buffer fail("Failed to create shared output buffer");
  defer release(out_buffer);

  table_buffer: *MTLBuffer = null;
  table_size := cast(NSUInteger) 0;
  #if WITH_TABLE {
    table_size = cast(NSUInteger) (ELEMENT_COUNT * size_of(TABLE_TYPE));
    table_buffer = MTLDevice.newBufferWithLength_options(g_device, table_size, .MTLResourceStorageModeShared);
    if !table_buffer fail("Failed to create shared table buffer");
    defer release(table_buffer);
  }

  gpu_values := cast(*u32) MTLBuffer.contents(out_buffer);
  if !gpu_values fail("MTLBuffer.contents returned null");

  gpu_table: *TABLE_TYPE = null;
  #if WITH_TABLE {
    gpu_table = cast(*TABLE_TYPE) MTLBuffer.contents(table_buffer);
    if !gpu_table fail("MTLBuffer.contents returned null");
  }

  expected: [ELEMENT_COUNT] u32;
  table_data: [ELEMENT_COUNT] TABLE_TYPE;
  for 0..ELEMENT_COUNT-1 {
    seed := ifx WITH_TABLE then cast(u32) (it * 11 + 9) else cast(u32) (it * 17 + 3);
    gpu_values[it] = seed;
    expected[it] = seed;
    #if WITH_TABLE {
      #if TABLE_KIND == .U32 {
        table_seed := cast(u32) (it * 7 + 3);
        gpu_table[it] = cast(TABLE_TYPE) table_seed;
        table_data[it] = cast(TABLE_TYPE) table_seed;
      } else #if TABLE_KIND == .BOID_STATE {
        px := cast(float) it * 0.25;
        py := cast(float) it * 0.5;
        vx := cast(float) ((it % 5) + 1) * 0.1;
        vy := cast(float) ((it % 7) + 1) * 0.05;
        boid := Compute_Boid_State.{pos = .{x = px, y = py}, vel = .{x = vx, y = vy}};
        gpu_table[it] = cast(TABLE_TYPE) boid;
        table_data[it] = cast(TABLE_TYPE) boid;
      } else #if TABLE_KIND == .VEC3 {
        vec := Vector3.{
          cast(float) it * 0.09 + 0.35,
          cast(float) ((it % 7) + 2) * 0.19,
          cast(float) ((it % 11) + 1) * 0.14,
        };
        gpu_table[it] = cast(TABLE_TYPE) vec;
        table_data[it] = cast(TABLE_TYPE) vec;
      } else #if TABLE_KIND == .VEC4 {
        vec := Vector4.{
          cast(float) it * 0.11 + 0.5,
          cast(float) ((it % 7) + 1) * 0.23,
          cast(float) ((it % 9) + 2) * 0.17,
          cast(float) ((it % 5) + 3) * 0.19,
        };
        gpu_table[it] = cast(TABLE_TYPE) vec;
        table_data[it] = cast(TABLE_TYPE) vec;
      } else #if TABLE_KIND == .VEC4_BOX {
        box := Compute_Vec4_Box.{
          v = .{
            cast(float) it * 0.07 + 0.25,
            cast(float) ((it % 11) + 1) * 0.13,
            cast(float) ((it % 13) + 2) * 0.09,
            cast(float) ((it % 3) + 1) * 0.21,
          },
        };
        gpu_table[it] = cast(TABLE_TYPE) box;
        table_data[it] = cast(TABLE_TYPE) box;
      } else {
        #assert false;
      }
    }
  }
  timings.gpu_setup_s = to_float64_seconds(current_time_monotonic() - t0);

  t0 = current_time_monotonic();
  command_buffer := MTLCommandQueue.commandBuffer(g_queue);
  if !command_buffer fail("Failed to create compute command buffer");

  encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
  if !encoder fail("Failed to create compute command encoder");

  {
    using MTLComputeCommandEncoder;
    setComputePipelineState(encoder, xx pipeline_compute);
    setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
    #if WITH_TABLE setBuffer_offset_atIndex(encoder, xx table_buffer, 0, 1);
    threads_per_grid := MTLSizeMake(ELEMENT_COUNT, 1, 1);
    threads_per_group := MTLSizeMake(ELEMENT_COUNT, 1, 1);
    dispatchThreads_threadsPerThreadgroup(encoder, threads_per_grid, threads_per_group);
  }
  MTLCommandEncoder.endEncoding(cast(*MTLCommandEncoder) encoder);

  MTLCommandBuffer.commit(command_buffer);
  MTLCommandBuffer.waitUntilCompleted(command_buffer);
  timings.dispatch_wait_s = to_float64_seconds(current_time_monotonic() - t0);
  
  // Run the CPU version.
  t0 = current_time_monotonic();
  #if WITH_TABLE run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data, table_data.data);
  else           run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data);
  timings.cpu_s = to_float64_seconds(current_time_monotonic() - t0);
  
  // Compare
  t0 = current_time_monotonic();
  saw_gpu_non_zero, saw_cpu_non_zero: bool;
  for 0..ELEMENT_COUNT-1 {
    if gpu_values[it] != 0 saw_gpu_non_zero = true;
    if expected[it] != 0   saw_cpu_non_zero = true;
    if gpu_values[it] != expected[it] {
      fail("[FAIL] mismatch in '%' at index %: GPU=% CPU=%", case_name, it, gpu_values[it], expected[it]);
    }
  }
  
  // Sanity check
  if !saw_gpu_non_zero fail("Expected at least one GPU compute to return non-zero");
  if !saw_cpu_non_zero fail("Expected at least one CPU run to return non-zero");
  timings.compare_s = to_float64_seconds(current_time_monotonic() - t0);

  timings.total_s = to_float64_seconds(current_time_monotonic() - case_start);

  if TIMINGS_ENABLED {
    log("[timing] runtime case %: total=%s compile=%s pipeline=%s setup=%s dispatch=%s cpu=%s compare=%s", case_name, timings.total_s, timings.compile_s, timings.pipeline_s, timings.gpu_setup_s, timings.dispatch_wait_s, timings.cpu_s, timings.compare_s);
  }
  
  using g_compute_timing_totals;
  case_count += 1;
  compile_s += timings.compile_s;
  pipeline_s += timings.pipeline_s;
  gpu_setup_s += timings.gpu_setup_s;
  dispatch_wait_s += timings.dispatch_wait_s;
  cpu_s += timings.cpu_s;
  compare_s += timings.compare_s;
  total_s += timings.total_s;
  
  if VERBOSE_TEST_LOGGING log("[OK] %", case_name);
}

proc_name_from_caller_arg_compile_time :: (call: Code, arg_index: s64) -> string {
  root, _ := compiler_get_nodes(call);
  if !root || root.kind != .PROCEDURE_CALL return "";
  pc := cast(*Code_Procedure_Call) root;
  if arg_index < 0 || arg_index >= pc.arguments_unsorted.count return "";
  arg := pc.arguments_unsorted[arg_index].expression;
  if !arg || arg.kind != .IDENT return "";
  return (cast(*Code_Ident) arg).name;
}

run_compute_case :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, false, u32, .U32);
}

run_compute_case_with_table :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, true, u32, .U32);
}

run_compute_case_with_boid_table :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, true, Compute_Boid_State, .BOID_STATE);
}

run_compute_case_with_vec3_table :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, true, Vector3, .VEC3);
}

run_compute_case_with_vec4_table :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, true, Vector4, .VEC4);
}

run_compute_case_with_vec4_box_table :: (source: string, case_name: string, $cpu_shader_proc: $F, call := #caller_code) #expand {
  proc_name := #run proc_name_from_caller_arg_compile_time(call, 2);
  if proc_name.count == 0 proc_name = "cpu_shader_proc";
  run_compute_case_impl(source, case_name, cpu_shader_proc, proc_name, true, Compute_Vec4_Box, .VEC4_BOX);
}

n :: ($proc: $F, call := #caller_code) #compile_time {
 return #run proc_name_from_caller_arg_compile_time(call, 0);
}

run_bindless_texture_write_case_metal :: () {
  metal_source := get_transpiled(.METAL, compute_bindless_write_2d);
  check_contains(metal_source, "kernel", "bindless compute write metal output");

  error: *NSError = null;
  lib_compute := MTLDevice.newLibraryWithSource_options_error(g_device, NSString.getTempString(metal_source), g_compile_options, *error);
  if log_nserror("Failed to compile bindless write compute shader library", error) || !lib_compute {
    if !lib_compute && error == null fail("Failed to compile bindless write compute shader library");
    fail("Bindless write compute source compilation failed");
  }
  defer release(lib_compute);

  fn_compute := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_compute, NSString.getTempString("ComputeMain"));
  if !fn_compute fail("Failed to find bindless write compute entry point 'ComputeMain'");
  defer release(fn_compute);

  error = null;
  pipeline_compute := MTLDevice.newComputePipelineStateWithFunction_error(g_device, xx fn_compute, *error);
  if log_nserror("Failed to create bindless write compute pipeline", error) || !pipeline_compute {
    if !pipeline_compute && error == null fail("Failed to create bindless write compute pipeline");
    fail("Bindless write compute pipeline creation failed");
  }
  defer release(pipeline_compute);

  out_buffer := MTLDevice.newBufferWithLength_options(g_device, cast(NSUInteger) (ELEMENT_COUNT * size_of(u32)), .MTLResourceStorageModeShared);
  if !out_buffer fail("Failed to create bindless write control buffer");
  defer release(out_buffer);
  control_values := cast(*u32) MTLBuffer.contents(out_buffer);
  if !control_values fail("MTLBuffer.contents returned null");

  make_output_texture :: () -> *MTLTexture {
    texture_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatRGBA8Unorm, 2, 2, NO);
    if !texture_desc fail("Failed to create bindless write texture descriptor");
    defer release(texture_desc);
    MTLTextureDescriptor.setUsage(texture_desc, .MTLTextureUsageShaderWrite | .MTLTextureUsageShaderRead);
    MTLTextureDescriptor.setStorageMode(texture_desc, .MTLStorageModeShared);
    texture := cast(*MTLTexture) MTLDevice.newTextureWithDescriptor(g_device, texture_desc);
    if !texture fail("Failed to create bindless write texture");
    return texture;
  }

  dispatch_write :: (control_values: *u32, out_buffer: *MTLBuffer, pipeline_compute: *MTLComputePipelineState, texture_index: u32, slot_1: *MTLTexture, slot_16: *MTLTexture) {
    control_values[0] = texture_index;
    command_buffer := MTLCommandQueue.commandBuffer(g_queue);
    if !command_buffer fail("Failed to create bindless write command buffer");
    encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
    if !encoder fail("Failed to create bindless write compute command encoder");
    {
      using MTLComputeCommandEncoder;
      setComputePipelineState(encoder, xx pipeline_compute);
      setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
      if slot_1 setTexture_atIndex(encoder, xx slot_1, 1);
      if slot_16 setTexture_atIndex(encoder, xx slot_16, 16);
      dispatchThreads_threadsPerThreadgroup(encoder, MTLSizeMake(2, 2, 1), MTLSizeMake(2, 2, 1));
    }
    MTLCommandEncoder.endEncoding(cast(*MTLCommandEncoder) encoder);
    MTLCommandBuffer.commit(command_buffer);
    MTLCommandBuffer.waitUntilCompleted(command_buffer);
  }

  validate_texture_pixels :: (texture: *MTLTexture) {
    bytes_per_row := cast(NSUInteger) 8;
    pixels := NewArray(cast(s64) (bytes_per_row * 2), u8);
    defer array_free(pixels);
    region := MTLRegionMake2D(0, 0, 2, 2);
    MTLTexture.getBytes_bytesPerRow_fromRegion_mipmapLevel(texture, pixels.data, bytes_per_row, region, 0);
    check_rgba8_pixel(pixels, 2, 0, 0, 255,   0,   0, 255);
    check_rgba8_pixel(pixels, 2, 1, 0,   0, 255,   0, 255);
    check_rgba8_pixel(pixels, 2, 0, 1, 255,   0, 255, 255);
    check_rgba8_pixel(pixels, 2, 1, 1,   0, 255, 255, 255);
  }

  base_texture := make_output_texture();
  defer release(base_texture);
  dispatch_write(control_values, out_buffer, pipeline_compute, 0, base_texture, null);
  validate_texture_pixels(base_texture);

  oob_texture := make_output_texture();
  defer release(oob_texture);
  dispatch_write(control_values, out_buffer, pipeline_compute, 999, null, oob_texture);
  validate_texture_pixels(oob_texture);

  log("[OK] compute_bindless_write_2d");
}

main :: () {
  for get_command_line_arguments() {
    if it == "-timings" TIMINGS_ENABLED = true;
    if it == "-verbose" VERBOSE_TEST_LOGGING = true;
  }
  init_objective_c();
  init_metal();

  g_device = cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  g_queue = MTLDevice.newCommandQueue(g_device);
  g_compile_options = objc_init(objc_alloc(MTLCompileOptions));
  MTLCompileOptions.setLanguageVersion(g_compile_options, .MTLLanguageVersion2_1);
  run_gpu_cpu_tests();
}

run_gpu_cpu_tests :: () {
  g_compute_timing_totals = .{};
  total_functions_run: int = 0;
  log("Comparing CPU and GPU results for % functions...", ALL_TEST_FUNCTIONS.count);
  #insert #run -> string {
    sb: String_Builder;
    for ALL_TEST_FUNCTIONS {
      test_runner_func: string;
      if #complete it.type == {
      case .Bare;    test_runner_func = "run_compute_case";
      case .Table;   test_runner_func = "run_compute_case_with_table";
      case .Boids;   test_runner_func = "run_compute_case_with_boid_table";
      case .Vec3;    test_runner_func = "run_compute_case_with_vec3_table";
      case .Vec4;    test_runner_func = "run_compute_case_with_vec4_table";
      case .Vec4Box; test_runner_func = "run_compute_case_with_vec4_box_table";
      }
      print_to_builder(*sb, "%1(get_transpiled(.METAL, %2), \"%2\", %2);\ntotal_functions_run += 1;\n", test_runner_func, it.name);
    }
    return builder_to_string(*sb);
  };

  if TIMINGS_ENABLED {
    avg := ifx g_compute_timing_totals.case_count > 0 then g_compute_timing_totals.total_s / cast(float64) g_compute_timing_totals.case_count else 0.0;
    log("[timing] runtime compute totals (% cases): total=%s avg=%s compile=%s pipeline=%s setup=%s dispatch=%s cpu=%s compare=%s",
      g_compute_timing_totals.case_count,
      g_compute_timing_totals.total_s,
      avg,
      g_compute_timing_totals.compile_s,
      g_compute_timing_totals.pipeline_s,
      g_compute_timing_totals.gpu_setup_s,
      g_compute_timing_totals.dispatch_wait_s,
      g_compute_timing_totals.cpu_s,
      g_compute_timing_totals.compare_s);
  }
  
  run_bindless_texture_write_case_metal();
  total_functions_run += 1;
  log("% tests passed: GPU output matches CPU.", total_functions_run);
}

g_device: *MTLDevice;
g_queue: *MTLCommandQueue;
g_compile_options: *MTLCompileOptions;
TIMINGS_ENABLED := false;
g_compute_timing_totals: Compute_Timing_Totals;

log_nserror :: (label: string, error: *NSError) -> bool {
  if !error return false;
  desc := NSError.localizedDescription(error);
  if desc {
    log_error("%: %", label, to_string(NSString.UTF8String(desc)));
  } else {
    log_error("% (NSError without localizedDescription)", label);
  }
  return true;
}

#import "Basic";
#import "String";
#import "Math";
#import "Float16";
#import "Metal";
#import "Objective_C";
#import "Compiler";

#import,file "../modules/ShaderFuncs/module.jai";
#import,file "../module.jai";

VERBOSE_TEST_LOGGING := false;
