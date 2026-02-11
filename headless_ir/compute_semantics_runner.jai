#import "Basic";
#import "File";
#import "String";
#import "Metal";
#import "Objective_C";

#import,file "../module.jai";

ELEMENT_COUNT :: 64;
UVector3 :: struct { x, y, z: u32; }
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
      values[thread_id.x] = v * 3 + 1;
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

run_cpu_compute_dispatch :: (thread_count: s64, shader_proc: $F, values: *u32, table: *u32) #expand {
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

run_compute_case :: (source: string, case_name: string, cpu_shader_proc: $F) {
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

  gpu_values := cast(*u32) MTLBuffer.contents(out_buffer);
  if !gpu_values fail("MTLBuffer.contents returned null");

  expected: [ELEMENT_COUNT] u32;
  for 0..ELEMENT_COUNT-1 {
    seed := cast(u32) (it * 17 + 3);
    gpu_values[it] = seed;
    expected[it] = seed;
  }
  run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data);

  command_buffer := MTLCommandQueue.commandBuffer(g_queue);
  if !command_buffer fail("Failed to create compute command buffer");

  encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
  if !encoder fail("Failed to create compute command encoder");

  MTLComputeCommandEncoder.setComputePipelineState(encoder, xx pipeline_compute);
  MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
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
}

run_compute_case_with_table :: (source: string, case_name: string, cpu_shader_proc: $F) {
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

  table_buffer := MTLDevice.newBufferWithLength_options(g_device, buffer_size, .MTLResourceStorageModeShared);
  if !table_buffer fail("Failed to create shared table buffer");
  defer release(table_buffer);

  gpu_values := cast(*u32) MTLBuffer.contents(out_buffer);
  gpu_table := cast(*u32) MTLBuffer.contents(table_buffer);
  if !gpu_values || !gpu_table fail("MTLBuffer.contents returned null");

  expected: [ELEMENT_COUNT] u32;
  table_data: [ELEMENT_COUNT] u32;
  for 0..ELEMENT_COUNT-1 {
    seed := cast(u32) (it * 11 + 9);
    table_seed := cast(u32) (it * 7 + 3);
    gpu_values[it] = seed;
    expected[it] = seed;
    gpu_table[it] = table_seed;
    table_data[it] = table_seed;
  }
  run_cpu_compute_dispatch(expected.count, cpu_shader_proc, expected.data, table_data.data);

  command_buffer := MTLCommandQueue.commandBuffer(g_queue);
  if !command_buffer fail("Failed to create compute command buffer");

  encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
  if !encoder fail("Failed to create compute command encoder");

  MTLComputeCommandEncoder.setComputePipelineState(encoder, xx pipeline_compute);
  MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx out_buffer, 0, 0);
  MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx table_buffer, 0, 1);
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
}

main :: () {
  _ = get_transpiled(.METAL, compute_semantics_shader);
  _ = get_transpiled(.METAL, compute_semantics_loop_shader);
  _ = get_transpiled(.METAL, compute_semantics_nested_shader);
  _ = get_transpiled(.METAL, compute_semantics_locals_shader);
  _ = get_transpiled(.METAL, compute_semantics_return_shader);
  _ = get_transpiled(.METAL, compute_semantics_helper_shader);
  _ = get_transpiled(.METAL, compute_semantics_bitwise_shader);

  compute_source := get_transpiled(.METAL, compute_semantics_shader);
  loop_source := get_transpiled(.METAL, compute_semantics_loop_shader);
  nested_source := get_transpiled(.METAL, compute_semantics_nested_shader);
  locals_source := get_transpiled(.METAL, compute_semantics_locals_shader);
  ret_source := get_transpiled(.METAL, compute_semantics_return_shader);
  helper_source := get_transpiled(.METAL, compute_semantics_helper_shader);
  bitwise_source := get_transpiled(.METAL, compute_semantics_bitwise_shader);

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
  log("IR compute semantics test passed (GPU output matches CPU reference for % elements).", ELEMENT_COUNT);
}
