#import "Basic";
#import "File";
#import "String";
#import "Metal";
#import "Objective_C";
#import "Compiler";

#import,file "../module.jai";

ELEMENT_COUNT :: 64;
UVector3 :: struct { x, y, z: u32; }
Vector2 :: struct { x, y: float; }

Compute_Boid_State :: struct {
  pos: Vector2;
  vel: Vector2;
}

Compute_Table_Kind :: enum {
  U32;
  BOID_STATE;
}

g_device: *MTLDevice;
g_queue: *MTLCommandQueue;
g_compile_options: *MTLCompileOptions;

Compute_Semantics_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
}

compute_semantics_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_loop_shader :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    base := values[thread_id.x];
    acc: u32 = 0;
    for 0..4 {
      acc += thread_id.x + 1;
    }
    values[thread_id.x] = base + acc;
  }
} @compute_shader

compute_semantics_nested_shader :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
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

compute_semantics_locals_shader :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    base := values[idx];
    t0 := base + idx;
    t1 := t0 * 2;
    t2 := t1 - (idx % 5);
    values[idx] = t2;
  }
} @compute_shader

compute_semantics_return_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_helper_shader :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    values[idx] = compute_semantics_helper_twist(values[idx], idx);
  }
} @compute_shader

compute_semantics_bitwise_shader :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
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

compute_semantics_using_shader :: (in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_using_helper_step :: (input: Using_Helper_Params) -> u32 {
  using input;
  return base + delta * 2;
}

compute_semantics_using_helper_shader :: (using in: Compute_Semantics_In, values: *u32, table: *u32) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    p := Using_Helper_Params.{values[idx], table[idx % 8]};
    values[idx] = compute_semantics_using_helper_step(p);
  }
} @compute_shader

compute_semantics_while_break_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_continue_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_switch_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_compound_assign_shader :: (using in: Compute_Semantics_In, values: *u32) {
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

compute_semantics_vector_index_shader :: (using in: Compute_Semantics_In, values: *u32, boids: *Compute_Boid_State) {
  if thread_id.x < 64 {
    idx := thread_id.x;
    b := boids[idx];
    nx := b.pos.x + b.vel.x * 2.0;
    ny := b.pos.y + b.vel.y * 2.0;
    boids[idx].pos = Vector2.{nx, ny};
    values[idx] = cast(u32) ((nx + ny) * 10.0);
  }
} @compute_shader

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

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_contains :: (source: string, pattern: string, where: string) {
  ok, _ := contains(source, pattern);
  if !ok fail("Expected '%' in %", pattern, where);
}

run_compute_case_impl :: (source: string, case_name: string, cpu_shader_proc: $F, proc_name: string, $WITH_TABLE := false, $TABLE_TYPE: Type = u32, $TABLE_KIND := Compute_Table_Kind.U32) {
  suffix := ifx WITH_TABLE then " (table)" else "";
  log("[IR][compute] Running case '%' with %%", case_name, proc_name, suffix);
  error: *NSError = null;
  lib_compute := MTLDevice.newLibraryWithSource_options_error(g_device, NSString.getTempString(source), g_compile_options, *error);
  if log_nserror("Failed to compile compute shader library", error) || !lib_compute {
    if !lib_compute && error == null fail("Failed to compile compute shader library");
    fail("Compute source compilation failed");
  }
  defer release(lib_compute);

  fn_compute := cast(*MTLFunction) MTLLibrary.newFunctionWithName(lib_compute, NSString.getTempString("ComputeMain"));
  if !fn_compute fail("Failed to find compute entry point 'ComputeMain'");
  defer release(fn_compute);

  error = null;
  pipeline_compute := MTLDevice.newComputePipelineStateWithFunction_error(g_device, xx fn_compute, *error);
  if log_nserror("Failed to create compute pipeline", error) || !pipeline_compute {
    if !pipeline_compute && error == null fail("Failed to create compute pipeline");
    fail("Compute pipeline creation failed");
  }
  defer release(pipeline_compute);

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
  #if WITH_TABLE {
    run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data, table_data.data);
  } else {
    run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data);
  }

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

  for 0..ELEMENT_COUNT-1 {
    if gpu_values[it] != expected[it] {
      fail("[%] compute semantics mismatch at %: GPU=% CPU=%", case_name, it, gpu_values[it], expected[it]);
    }
  }
  log("[IR][compute] Passed case '%' with %%", case_name, proc_name, suffix);
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

main :: () {
  _ = get_transpiled(.METAL, compute_semantics_shader);
  _ = get_transpiled(.METAL, compute_semantics_loop_shader);
  _ = get_transpiled(.METAL, compute_semantics_nested_shader);
  _ = get_transpiled(.METAL, compute_semantics_locals_shader);
  _ = get_transpiled(.METAL, compute_semantics_return_shader);
  _ = get_transpiled(.METAL, compute_semantics_helper_shader);
  _ = get_transpiled(.METAL, compute_semantics_bitwise_shader);
  _ = get_transpiled(.METAL, compute_semantics_using_shader);
  _ = get_transpiled(.METAL, compute_semantics_using_helper_shader);
  _ = get_transpiled(.METAL, compute_semantics_while_break_shader);
  _ = get_transpiled(.METAL, compute_semantics_continue_shader);
  _ = get_transpiled(.METAL, compute_semantics_switch_shader);
  _ = get_transpiled(.METAL, compute_semantics_compound_assign_shader);
  _ = get_transpiled(.METAL, compute_semantics_vector_index_shader);

  compute_source := get_transpiled(.METAL, compute_semantics_shader);
  loop_source := get_transpiled(.METAL, compute_semantics_loop_shader);
  nested_source := get_transpiled(.METAL, compute_semantics_nested_shader);
  locals_source := get_transpiled(.METAL, compute_semantics_locals_shader);
  ret_source := get_transpiled(.METAL, compute_semantics_return_shader);
  helper_source := get_transpiled(.METAL, compute_semantics_helper_shader);
  bitwise_source := get_transpiled(.METAL, compute_semantics_bitwise_shader);
  using_source := get_transpiled(.METAL, compute_semantics_using_shader);
  using_helper_source := get_transpiled(.METAL, compute_semantics_using_helper_shader);
  while_break_source := get_transpiled(.METAL, compute_semantics_while_break_shader);
  continue_source := get_transpiled(.METAL, compute_semantics_continue_shader);
  switch_source := get_transpiled(.METAL, compute_semantics_switch_shader);
  compound_assign_source := get_transpiled(.METAL, compute_semantics_compound_assign_shader);
  vector_index_source := get_transpiled(.METAL, compute_semantics_vector_index_shader);

  ir_slang_path := ".build/ir_slang/compute_semantics_shader_comp.slang";
  ir_slang_source, ir_slang_ok := read_entire_file(ir_slang_path);
  if !ir_slang_ok fail("Could not read %", ir_slang_path);
  check_contains(ir_slang_source, "generated_by_ir_pipeline", "compute IR slang output");
  check_contains(ir_slang_source, "[shader(\"compute\")]", "compute IR slang output");

  loop_ir_slang_path := ".build/ir_slang/compute_semantics_loop_shader_comp.slang";
  loop_ir_slang_source, loop_ir_ok := read_entire_file(loop_ir_slang_path);
  if !loop_ir_ok fail("Could not read %", loop_ir_slang_path);
  check_contains(loop_ir_slang_source, "generated_by_ir_pipeline", "compute loop IR slang output");
  check_contains(loop_ir_slang_source, "for (", "compute loop IR slang output");

  nested_ir_slang_path := ".build/ir_slang/compute_semantics_nested_shader_comp.slang";
  nested_ir_slang_source, nested_ir_ok := read_entire_file(nested_ir_slang_path);
  if !nested_ir_ok fail("Could not read %", nested_ir_slang_path);
  check_contains(nested_ir_slang_source, "generated_by_ir_pipeline", "compute nested IR slang output");
  check_contains(nested_ir_slang_source, "table[", "compute nested IR slang output");
  check_contains(nested_ir_slang_source, "if (", "compute nested IR slang output");

  locals_ir_slang_path := ".build/ir_slang/compute_semantics_locals_shader_comp.slang";
  locals_ir_slang_source, locals_ir_ok := read_entire_file(locals_ir_slang_path);
  if !locals_ir_ok fail("Could not read %", locals_ir_slang_path);
  check_contains(locals_ir_slang_source, "generated_by_ir_pipeline", "compute locals IR slang output");
  check_contains(locals_ir_slang_source, "t0", "compute locals IR slang output");
  check_contains(locals_ir_slang_source, "t1", "compute locals IR slang output");

  ret_ir_slang_path := ".build/ir_slang/compute_semantics_return_shader_comp.slang";
  ret_ir_slang_source, ret_ir_ok := read_entire_file(ret_ir_slang_path);
  if !ret_ir_ok fail("Could not read %", ret_ir_slang_path);
  check_contains(ret_ir_slang_source, "generated_by_ir_pipeline", "compute return IR slang output");
  check_contains(ret_ir_slang_source, "return;", "compute return IR slang output");
  check_contains(ret_ir_slang_source, "for (", "compute return IR slang output");

  helper_ir_slang_path := ".build/ir_slang/compute_semantics_helper_shader_comp.slang";
  helper_ir_slang_source, helper_ir_ok := read_entire_file(helper_ir_slang_path);
  if !helper_ir_ok fail("Could not read %", helper_ir_slang_path);
  check_contains(helper_ir_slang_source, "generated_by_ir_pipeline", "compute helper IR slang output");
  check_contains(helper_ir_slang_source, "compute_semantics_helper_twist", "compute helper IR slang output");

  bitwise_ir_slang_path := ".build/ir_slang/compute_semantics_bitwise_shader_comp.slang";
  bitwise_ir_slang_source, bitwise_ir_ok := read_entire_file(bitwise_ir_slang_path);
  if !bitwise_ir_ok fail("Could not read %", bitwise_ir_slang_path);
  check_contains(bitwise_ir_slang_source, "generated_by_ir_pipeline", "compute bitwise IR slang output");
  check_contains(bitwise_ir_slang_source, "^", "compute bitwise IR slang output");
  check_contains(bitwise_ir_slang_source, "&", "compute bitwise IR slang output");
  check_contains(bitwise_ir_slang_source, "|", "compute bitwise IR slang output");
  check_contains(bitwise_ir_slang_source, "<<", "compute bitwise IR slang output");
  check_contains(bitwise_ir_slang_source, ">>", "compute bitwise IR slang output");

  using_ir_slang_path := ".build/ir_slang/compute_semantics_using_shader_comp.slang";
  using_ir_slang_source, using_ir_ok := read_entire_file(using_ir_slang_path);
  if !using_ir_ok fail("Could not read %", using_ir_slang_path);
  check_contains(using_ir_slang_source, "generated_by_ir_pipeline", "compute using IR slang output");
  check_contains(using_ir_slang_source, "input.thread_id", "compute using IR slang output");

  using_helper_ir_slang_path := ".build/ir_slang/compute_semantics_using_helper_shader_comp.slang";
  using_helper_ir_slang_source, using_helper_ir_ok := read_entire_file(using_helper_ir_slang_path);
  if !using_helper_ir_ok fail("Could not read %", using_helper_ir_slang_path);
  check_contains(using_helper_ir_slang_source, "generated_by_ir_pipeline", "compute helper using IR slang output");
  check_contains(using_helper_ir_slang_source, "compute_semantics_using_helper_step", "compute helper using IR slang output");
  check_contains(using_helper_ir_slang_source, "input.base", "compute helper using IR slang output");

  while_break_ir_slang_path := ".build/ir_slang/compute_semantics_while_break_shader_comp.slang";
  while_break_ir_slang_source, while_break_ir_ok := read_entire_file(while_break_ir_slang_path);
  if !while_break_ir_ok fail("Could not read %", while_break_ir_slang_path);
  check_contains(while_break_ir_slang_source, "generated_by_ir_pipeline", "compute while/break IR slang output");
  check_contains(while_break_ir_slang_source, "while (", "compute while/break IR slang output");
  check_contains(while_break_ir_slang_source, "break;", "compute while/break IR slang output");

  continue_ir_slang_path := ".build/ir_slang/compute_semantics_continue_shader_comp.slang";
  continue_ir_slang_source, continue_ir_ok := read_entire_file(continue_ir_slang_path);
  if !continue_ir_ok fail("Could not read %", continue_ir_slang_path);
  check_contains(continue_ir_slang_source, "generated_by_ir_pipeline", "compute continue IR slang output");
  check_contains(continue_ir_slang_source, "while (", "compute continue IR slang output");
  check_contains(continue_ir_slang_source, "continue;", "compute continue IR slang output");

  switch_ir_slang_path := ".build/ir_slang/compute_semantics_switch_shader_comp.slang";
  switch_ir_slang_source, switch_ir_ok := read_entire_file(switch_ir_slang_path);
  if !switch_ir_ok fail("Could not read %", switch_ir_slang_path);
  check_contains(switch_ir_slang_source, "generated_by_ir_pipeline", "compute switch IR slang output");
  check_contains(switch_ir_slang_source, "switch (", "compute switch IR slang output");
  check_contains(switch_ir_slang_source, "case 0", "compute switch IR slang output");
  check_contains(switch_ir_slang_source, "default", "compute switch IR slang output");
  check_contains(switch_ir_slang_source, "break;", "compute switch IR slang output");

  compound_assign_ir_slang_path := ".build/ir_slang/compute_semantics_compound_assign_shader_comp.slang";
  compound_assign_ir_slang_source, compound_assign_ir_ok := read_entire_file(compound_assign_ir_slang_path);
  if !compound_assign_ir_ok fail("Could not read %", compound_assign_ir_slang_path);
  check_contains(compound_assign_ir_slang_source, "generated_by_ir_pipeline", "compute compound-assign IR slang output");
  check_contains(compound_assign_ir_slang_source, "+=", "compute compound-assign IR slang output");
  check_contains(compound_assign_ir_slang_source, "*=", "compute compound-assign IR slang output");
  check_contains(compound_assign_ir_slang_source, "-=", "compute compound-assign IR slang output");
  check_contains(compound_assign_ir_slang_source, "|=", "compute compound-assign IR slang output");
  check_contains(compound_assign_ir_slang_source, "&=", "compute compound-assign IR slang output");

  vector_index_ir_slang_path := ".build/ir_slang/compute_semantics_vector_index_shader_comp.slang";
  vector_index_ir_slang_source, vector_index_ir_ok := read_entire_file(vector_index_ir_slang_path);
  if !vector_index_ir_ok fail("Could not read %", vector_index_ir_slang_path);
  check_contains(vector_index_ir_slang_source, "generated_by_ir_pipeline", "compute vector/index IR slang output");
  check_contains(vector_index_ir_slang_source, "boids[idx]", "compute vector/index IR slang output");
  check_contains(vector_index_ir_slang_source, ".pos.x", "compute vector/index IR slang output");
  check_contains(vector_index_ir_slang_source, "struct Compute_Boid_State", "compute vector/index IR slang output");
  check_contains(vector_index_ir_slang_source, "float2 pos", "compute vector/index IR slang output");

  init_objective_c();
  init_metal();

  g_device = cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !g_device fail("Failed to get default Metal device");
  defer release(g_device);

  g_queue = MTLDevice.newCommandQueue(g_device);
  if !g_queue fail("Failed to create Metal command queue");
  defer release(g_queue);

  g_compile_options = objc_init(objc_alloc(MTLCompileOptions));
  if !g_compile_options fail("Failed to create MTLCompileOptions");
  defer release(g_compile_options);

  run_compute_case(compute_source, "branch", compute_semantics_shader);
  run_compute_case(loop_source, "loop", compute_semantics_loop_shader);
  run_compute_case_with_table(nested_source, "nested", compute_semantics_nested_shader);
  run_compute_case(locals_source, "locals", compute_semantics_locals_shader);
  run_compute_case(ret_source, "return", compute_semantics_return_shader);
  run_compute_case(helper_source, "helper", compute_semantics_helper_shader);
  run_compute_case_with_table(bitwise_source, "bitwise", compute_semantics_bitwise_shader);
  run_compute_case(using_source, "using", compute_semantics_using_shader);
  run_compute_case_with_table(using_helper_source, "using-helper", compute_semantics_using_helper_shader);
  run_compute_case(while_break_source, "while-break", compute_semantics_while_break_shader);
  run_compute_case(continue_source, "continue", compute_semantics_continue_shader);
  run_compute_case(switch_source, "switch", compute_semantics_switch_shader);
  run_compute_case(compound_assign_source, "compound-assign", compute_semantics_compound_assign_shader);
  run_compute_case_with_boid_table(vector_index_source, "vector-index", compute_semantics_vector_index_shader);
  log("IR compute semantics test passed (GPU output matches CPU reference for % elements).", ELEMENT_COUNT);
}
