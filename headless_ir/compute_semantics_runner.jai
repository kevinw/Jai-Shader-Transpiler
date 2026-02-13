//
// Tests basic Jai -> compute shader compilation across various test cases by
// running them on the GPU and CPU and comparing results.
// 

ALL_TEST_FUNCTIONS :: (struct { name: string; type: enum { Bare; Table; Boids; }; }).[
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
  {"edge_case_10_float4_component_lvalue", .Bare},
  {"edge_case_07_local_array_literal_read", .Bare},
  {"edge_case_08_local_array_write_then_read", .Bare},
  {"edge_case_01_bool_and_or", .Bare},
  {"edge_case_22_bool_temp_chain", .Bare},
  {"edge_case_04_switch_sparse", .Bare},
  {"edge_case_23_nested_switch_in_loop", .Bare},
  {"edge_case_05_switch_through_chain", .Bare},
  {"edge_case_06_nested_while_continue_break", .Bare},
  {"edge_case_14_intrinsic_mod_float", .Bare},
  {"edge_case_15_intrinsic_smoothstep", .Bare},
  {"edge_case_16_intrinsic_pow", .Bare},
  {"edge_case_25_vector_scalar_mix", .Bare},
  {"edge_case_17_helper_return_member_on_call", .Bare},
  {"edge_case_18_helper_return_assign_local", .Bare},
  {"edge_case_29_buffer_struct_copy_temp", .Boids},
  {"edge_case_02_unary_not_bool", .Bare},
  {"edge_case_03_unary_bit_not", .Bare},
  {"edge_case_11_float4_swizzle_xy", .Bare},
  {"edge_case_12_matrix_ctor_mul", .Bare},
  {"edge_case_20_using_inside_nested_block", .Bare},
  {"edge_case_30_while_false_initially", .Bare},
  {"edge_case_13_matrix_mul_builtin", .Bare},
  {"edge_case_21_for_descending", .Bare},
  {"edge_case_24_cast_chain", .Bare},
  {"edge_case_31_int64_arithmetic", .Bare},
  {"edge_case_32_subscript_compound_assign", .Bare},
  {"edge_case_33_member_chain_compound_assign", .Boids},
  {"edge_case_34_switch_default_only", .Bare},
  {"edge_case_35_switch_without_default", .Bare},
  {"edge_case_36_helper_multiple_returns", .Bare},
  {"edge_case_37_early_return_in_nested_if", .Bare},
  {"edge_case_38_int64_bitwise_mix", .Bare},
  {"edge_case_39_local_struct_using_update", .Bare},
  {"edge_case_40_vector_component_swap", .Boids},
  {"edge_case_41_matrix_reassign_chain", .Bare},
  {"edge_case_26_vector_negate", .Bare},
  {"edge_case_27_helper_nested_call", .Bare},
  {"edge_case_28_struct_constructor_from_member_expr", .Boids},
  {"edge_case_19_nested_local_struct_field_access", .Bare},
  
  {"nested", .Table},
  {"bitwise", .Table},
  {"using_helper", .Table},
  
  {"vector_index", .Boids},
  {"access_chain", .Boids},
  {"helper_struct_chain", .Boids},
  {"helper_struct_direct_assign", .Boids},
];

ELEMENT_COUNT :: 64;
UVector3 :: struct { x, y, z: u32; }

Compute_Boid_State :: struct {
  pos: Vector2;
  vel: Vector2;
}

Compute_Table_Kind :: enum {
  U32;
  BOID_STATE;
}

Compute_Semantics_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
}

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

// Exploratory edge-case shaders. Intentionally not added to ALL_TEST_FUNCTIONS yet.
Edge_U32_Pair :: struct {
  a: u32;
  b: u32;
}

Edge_Nested_Local :: struct {
  pair: Edge_U32_Pair;
  z: u32;
}

edge_make_pair :: (x: u32, y: u32) -> Edge_U32_Pair {
  return Edge_U32_Pair.{x, y};
}

edge_case_01_bool_and_or :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := (idx % 2) == 0;
  b := (idx % 3) == 0;
  if a && !b values[idx] += 11;
  else if a || b values[idx] += 5;
  else values[idx] += 1;
} @compute_shader

edge_case_02_unary_not_bool :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  if !(idx == 7) values[idx] += 2;
} @compute_shader

edge_case_03_unary_bit_not :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = ~values[idx];
} @compute_shader

edge_case_04_switch_sparse :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_05_switch_through_chain :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_06_nested_while_continue_break :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_07_local_array_literal_read :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [4]u32 = .[2, 4, 8, 16];
  values[idx] += lut[idx % 4];
} @compute_shader

edge_case_08_local_array_write_then_read :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  lut: [4]u32;
  lut[0] = idx + 1;
  lut[1] = idx + 2;
  lut[2] = idx + 3;
  lut[3] = idx + 4;
  values[idx] = lut[(idx + 1) % 4];
} @compute_shader

edge_case_09_float2_component_compound :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector2.{cast(float) idx, 1.0};
  v.x += 2.0;
  v.y *= 3.0;
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

edge_case_10_float4_component_lvalue :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector4.{1.0, 2.0, 3.0, 4.0};
  v.x = v.x + cast(float) idx;
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

edge_case_11_float4_swizzle_xy :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector4.{cast(float) idx, cast(float) (idx + 1), 9.0, 10.0};
  xy := v.xy;
  values[idx] = cast(u32) (xy.x + xy.y);
} @compute_shader

edge_case_12_matrix_ctor_mul :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{1.0, 2.0, 3.0, 4.0};
  p := m * Vector2.{cast(float) idx, 1.0};
  values[idx] = cast(u32) (p.x + p.y);
} @compute_shader

edge_case_13_matrix_mul_builtin :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{2.0, 0.0, 0.0, 2.0};
  p := m * Vector2.{cast(float) idx, 0.5};
  values[idx] = cast(u32) p.x;
} @compute_shader

edge_case_14_intrinsic_mod_float :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (idx + 5);
  values[idx] = cast(u32) fmod_cycling(x, 3.5);
} @compute_shader

edge_case_15_intrinsic_smoothstep :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  x := cast(float) (idx % 10) / 9.0;
  y := saturate((x - 0.2) / 0.6);
  values[idx] = cast(u32) floor(y * 255.0);
} @compute_shader

edge_case_16_intrinsic_pow :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  y := pow(2.0, cast(float) (idx % 6));
  values[idx] = cast(u32) y;
} @compute_shader

edge_case_17_helper_return_member_on_call :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = edge_make_pair(idx, idx + 9).b;
} @compute_shader

edge_case_18_helper_return_assign_local :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := edge_make_pair(idx + 1, idx + 2);
  values[idx] = p.a + p.b;
} @compute_shader

edge_case_19_nested_local_struct_field_access :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  n := Edge_Nested_Local.{pair = Edge_U32_Pair.{idx + 3, idx + 4}, z = 5};
  values[idx] = n.pair.a + n.pair.b + n.z;
} @compute_shader

edge_case_20_using_inside_nested_block :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  {
    using thread_id;
    values[x] = values[x] + 1;
  }
} @compute_shader

edge_case_21_for_descending :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_22_bool_temp_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := (idx % 2) == 0;
  b := (idx % 4) == 0;
  c := (idx % 8) == 0;
  pass := (a && b) || c;
  if pass values[idx] += 9;
} @compute_shader

edge_case_23_nested_switch_in_loop :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_24_cast_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  a := cast(float) idx;
  b := cast(u32) (a * 1.5);
  values[idx] = b + 3;
} @compute_shader

edge_case_25_vector_scalar_mix :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := Vector2.{cast(float) idx, 2.0};
  v = v * 2.0 + Vector2.{1.0, 1.0};
  values[idx] = cast(u32) (v.x + v.y);
} @compute_shader

edge_case_26_vector_negate :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := -Vector2.{cast(float) idx, 3.0};
  values[idx] = cast(u32) abs(v.x) + cast(u32) abs(v.y);
} @compute_shader

edge_case_27_helper_nested_call :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = edge_make_pair(edge_make_pair(idx, idx + 1).a, idx + 2).b;
} @compute_shader

edge_case_28_struct_constructor_from_member_expr :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_U32_Pair.{cast(u32) boids[idx].pos.x, cast(u32) boids[idx].vel.y};
  values[idx] = p.a + p.b;
} @compute_shader

edge_case_29_buffer_struct_copy_temp :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  c := b;
  values[idx] = cast(u32) (c.pos.x + c.pos.y + c.vel.x + c.vel.y);
} @compute_shader

edge_case_30_while_false_initially :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  j: u32 = 5;
  while j < 3 {
    values[idx] += j;
    j += 1;
  }
  values[idx] += 1;
} @compute_shader

edge_case_31_int64_arithmetic :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx_u := thread_id.x;
  idx := cast(int) idx_u;
  v: int = (idx * cast(int) 3) - cast(int) 91;
  if v < 0 v = -v;
  values[idx_u] = cast(u32) (v + cast(int) 17);
} @compute_shader

edge_case_32_subscript_compound_assign :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] += idx;
  values[idx] ^= (idx << 1);
  values[idx] &= 1023;
} @compute_shader

edge_case_33_member_chain_compound_assign :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  boids[idx].vel.x += 0.5;
  boids[idx].vel.y *= 1.25;
  boids[idx].pos.x += boids[idx].vel.x;
  boids[idx].pos.y += boids[idx].vel.y;
  values[idx] = cast(u32) (boids[idx].pos.x * 8.0 + boids[idx].pos.y * 4.0);
} @compute_shader

edge_case_34_switch_default_only :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 5 == {
    case;
      v += 77;
  }
  values[idx] = v;
} @compute_shader

edge_case_35_switch_without_default :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  v := values[idx];
  if idx % 4 == {
    case 1; v += 11;
    case 3; v += 33;
  }
  values[idx] = v;
} @compute_shader

edge_case_36_helper_pick_value :: (x: u32) -> u32 {
  if x < 10 return x + 100;
  if x < 20 return x + 200;
  return x + 300;
}

edge_case_36_helper_multiple_returns :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  values[idx] = edge_case_36_helper_pick_value(idx % 30);
} @compute_shader

edge_case_37_early_return_in_nested_if :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  if (idx % 3) == 0 {
    if (idx % 2) == 0 return;
    values[idx] += 9;
    return;
  }
  values[idx] += 4;
} @compute_shader

edge_case_38_int64_bitwise_mix :: (using in: Compute_Semantics_In, values: *u32) {
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

edge_case_39_local_struct_using_update :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  p := Edge_Local_Params.{a = values[idx], b = idx + 3};
  using p;
  a += b;
  b += 2;
  values[idx] = a + b;
} @compute_shader

edge_case_40_vector_component_swap :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  b := boids[idx];
  tx := b.pos.x;
  b.pos.x = b.pos.y;
  b.pos.y = tx;
  boids[idx] = b;
  values[idx] = cast(u32) (b.pos.x * 10.0 + b.pos.y * 2.0);
} @compute_shader

edge_case_41_matrix_reassign_chain :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x >= 64 return;
  idx := thread_id.x;
  m := Matrix2.{1.0, 0.0, 0.0, 1.0};
  r0 := m * Vector2.{cast(float) idx, 1.0};
  m = Matrix2.{2.0, 1.0, 0.0, 1.0};
  r1 := m * r0;
  values[idx] = cast(u32) (r1.x + r1.y);
} @compute_shader

run_cpu_compute_dispatch :: (thread_count: s64, shader_proc: $F, values: *u32) #expand {
  for 0..thread_count-1 {
    `in := Compute_Semantics_In.{thread_id = .{x = cast(u32) it, y = 0, z = 0}};
    shader_proc(in, values);
  }
}

run_cpu_compute_dispatch :: (thread_count: s64, shader_proc: $F, values: *u32, table: *$T) #expand {
  for 0..thread_count-1 {
    `in := Compute_Semantics_In.{thread_id = .{x = cast(u32) it, y = 0, z = 0}};
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

  MTLComputeCommandEncoder.setComputePipelineState(encoder, xx pipeline_compute);
  MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
  #if WITH_TABLE {
    MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx table_buffer, 0, 1);
  }
  threads_per_grid := MTLSizeMake(ELEMENT_COUNT, 1, 1);
  threads_per_group := MTLSizeMake(ELEMENT_COUNT, 1, 1);
  MTLComputeCommandEncoder.dispatchThreads_threadsPerThreadgroup(encoder, threads_per_grid, threads_per_group);
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
  g_compute_timing_totals.case_count += 1;
  g_compute_timing_totals.compile_s += timings.compile_s;
  g_compute_timing_totals.pipeline_s += timings.pipeline_s;
  g_compute_timing_totals.gpu_setup_s += timings.gpu_setup_s;
  g_compute_timing_totals.dispatch_wait_s += timings.dispatch_wait_s;
  g_compute_timing_totals.cpu_s += timings.cpu_s;
  g_compute_timing_totals.compare_s += timings.compare_s;
  g_compute_timing_totals.total_s += timings.total_s;
  
  log("[OK] %", case_name);
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

n :: ($proc: $F, call := #caller_code) #compile_time {
 return #run proc_name_from_caller_arg_compile_time(call, 0);
}

main :: () {
  for get_command_line_arguments() {
    if it == "-timings" TIMINGS_ENABLED = true;
  }
  init_objective_c();
  init_metal();

  g_device = cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  g_queue = MTLDevice.newCommandQueue(g_device);
  g_compile_options = objc_init(objc_alloc(MTLCompileOptions));
  run_gpu_cpu_tests();
}

run_gpu_cpu_tests :: () {
  g_compute_timing_totals = .{};
  log("Comparing CPU and GPU results for % functions...", ALL_TEST_FUNCTIONS.count);
  #insert #run -> string {
    sb: String_Builder;
    for ALL_TEST_FUNCTIONS {
      test_runner_func: string;
      if #complete it.type == {
      case .Bare;  test_runner_func = "run_compute_case";
      case .Table; test_runner_func = "run_compute_case_with_table";
      case .Boids; test_runner_func = "run_compute_case_with_boid_table";
      }
      append(*sb, tprint("%1(get_transpiled(.METAL, %2), \"%2\", %2);\n", test_runner_func, it.name));
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
  
  log("Passed % functions: (GPU output matches CPU for % elements each).", ALL_TEST_FUNCTIONS.count, ELEMENT_COUNT);
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
#import "Metal";
#import "Objective_C";
#import "Compiler";

#import,file "../module.jai";
