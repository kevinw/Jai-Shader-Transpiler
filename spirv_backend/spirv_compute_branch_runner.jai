#import "Basic";
#import "File";
#import "Metal";
#import "Objective_C";
Process :: #import "Process";
String :: #import "String";

#import,file "../module.jai";

ELEMENT_COUNT :: 64;
TOOL_TIMEOUT_MS :: 7000;
SPIRV_OUT_DIR :: ".build/spirv_backend";

UVector3 :: struct { x, y, z: u32; }

Compute_Semantics_In :: struct {
  thread_id: UVector3; @thread_position_in_grid
}

compute_branch_shader :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 64 {
    v := values[thread_id.x];
    if (thread_id.x % 2) == 0 {
      values[thread_id.x] = v * 3 + 1;
    } else {
      values[thread_id.x] = v * 5 + 7;
    }
  }
} @compute_shader

compute_branch_shader_alt :: (using in: Compute_Semantics_In, values: *u32) {
  if thread_id.x < 32 {
    v := values[thread_id.x];
    if (thread_id.x % 3) == 1 {
      values[thread_id.x] = v * 2 + 9;
    } else {
      values[thread_id.x] = v * 7 + 11;
    }
  }
} @compute_shader

compute_min_shader :: (using in: Compute_Semantics_In, values: *u32) {
  idx := thread_id.x;
  values[idx] = values[idx] + 1;
} @compute_shader

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_contains :: (source: string, pattern: string, where: string) {
  ok, _ := String.contains(source, pattern);
  if !ok fail("Expected '%' in %", pattern, where);
}

check_spvasm_is_generic :: (shader_name: string) {
  spvasm_path := tprint(".build/ir_intermediate/%_comp.spvasm", shader_name);
  source, ok := read_entire_file(spvasm_path);
  if !ok fail("Could not read generated SPIR-V text at %", spvasm_path);
  check_contains(source, "Generator: Jai Shader Transpiler IR SPIR-V generic backend; 1", spvasm_path);
}

run_command_checked :: (description: string, args: [] string) {
  command := Process.get_quoted_command_string(args);
  result, output, error, timeout_reached := Process.run_command(..args, timeout_ms=TOOL_TIMEOUT_MS);

  if timeout_reached {
    fail("% timed out after %ms: %", description, TOOL_TIMEOUT_MS, command);
  }
  if result.type == .FAILED_TO_LAUNCH {
    fail("% failed to launch: %", description, command);
  }
  if result.type != .EXITED || result.exit_code != 0 {
    if output.count > 0 log_error("[%] stdout:\n%", description, output);
    if error.count > 0 log_error("[%] stderr:\n%", description, error);
    fail("% failed with exit code %: %", description, result.exit_code, command);
  }
}

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

run_cpu_compute_dispatch :: (shader_proc: $F, values: *u32) #expand {
  assert(values != null);
  for 0..ELEMENT_COUNT-1 {
    `in := Compute_Semantics_In.{thread_id = .{x = cast(u32) it, y = 0, z = 0}};
    shader_proc(in, values);
  }
}

run_metal_compute_and_compare :: (metal_source_path: string, metal_source: string, case_name: string, $cpu_shader_proc: $F) {
  init_objective_c();
  init_metal();

  device := cast(*MTLDevice) MTLCreateSystemDefaultDevice();
  if !device fail("Failed to get default Metal device");
  defer release(device);

  queue := MTLDevice.newCommandQueue(device);
  if !queue fail("Failed to create Metal command queue");
  defer release(queue);

  compile_options := objc_init(objc_alloc(MTLCompileOptions));
  if !compile_options fail("Failed to create MTLCompileOptions");
  defer release(compile_options);

  error: *NSError = null;
  library := MTLDevice.newLibraryWithSource_options_error(device, NSString.getTempString(metal_source), compile_options, *error);
  if log_nserror("Failed to compile generated Metal source", error) || !library {
    fail("Metal source compile failed for %", metal_source_path);
  }
  defer release(library);

  fn_compute := cast(*MTLFunction) MTLLibrary.newFunctionWithName(library, NSString.getTempString("ComputeMain"));
  if !fn_compute fail("Failed to find compute entry point 'ComputeMain' in %", metal_source_path);
  defer release(fn_compute);

  error = null;
  pipeline := MTLDevice.newComputePipelineStateWithFunction_error(device, xx fn_compute, *error);
  if log_nserror("Failed to create compute pipeline", error) || !pipeline {
    fail("Compute pipeline creation failed");
  }
  defer release(pipeline);

  buffer_size := cast(NSUInteger) (ELEMENT_COUNT * size_of(u32));
  values_buffer := MTLDevice.newBufferWithLength_options(device, buffer_size, .MTLResourceStorageModeShared);
  if !values_buffer fail("Failed to create values buffer");
  defer release(values_buffer);

  gpu_values := cast(*u32) MTLBuffer.contents(values_buffer);
  if !gpu_values fail("MTLBuffer.contents returned null");

  expected: [ELEMENT_COUNT] u32;
  for 0..ELEMENT_COUNT-1 {
    seed := cast(u32) (it * 17 + 3);
    gpu_values[it] = seed;
    expected[it] = seed;
  }
  run_cpu_compute_dispatch(cpu_shader_proc, expected.data);

  command_buffer := MTLCommandQueue.commandBuffer(queue);
  if !command_buffer fail("Failed to create command buffer");
  encoder := MTLCommandBuffer.computeCommandEncoder(command_buffer);
  if !encoder fail("Failed to create compute encoder");

  MTLComputeCommandEncoder.setComputePipelineState(encoder, xx pipeline);
  MTLComputeCommandEncoder.setBuffer_offset_atIndex(encoder, xx values_buffer, 0, 0);
  MTLComputeCommandEncoder.dispatchThreads_threadsPerThreadgroup(encoder, MTLSizeMake(ELEMENT_COUNT, 1, 1), MTLSizeMake(ELEMENT_COUNT, 1, 1));
  MTLCommandEncoder.endEncoding(cast(*MTLCommandEncoder) encoder);
  MTLCommandBuffer.commit(command_buffer);
  MTLCommandBuffer.waitUntilCompleted(command_buffer);

  for 0..ELEMENT_COUNT-1 {
    if gpu_values[it] != expected[it] {
      fail("[%] GPU mismatch at %: got %, expected %", case_name, it, gpu_values[it], expected[it]);
    }
  }
}

main :: () {
  if !make_directory_if_it_does_not_exist(SPIRV_OUT_DIR, recursive=true) {
    fail("Could not create %", SPIRV_OUT_DIR);
  }

  // Case: branch
  {
    case_name :: "branch";
    metal_path := tprint("%/%_metal.comp.metal", SPIRV_OUT_DIR, case_name);
    vulkan_glsl_path := tprint("%/%_vk.comp.glsl", SPIRV_OUT_DIR, case_name);
    air_path := tprint("%/%_metal.comp.air", SPIRV_OUT_DIR, case_name);

    metal_source := get_transpiled(.METAL, compute_branch_shader);
    vulkan_glsl_source := get_transpiled(.VULKAN_GLSL, compute_branch_shader);
    check_spvasm_is_generic("compute_branch_shader");

    if !write_entire_file(metal_path, metal_source) fail("Could not write %", metal_path);
    if !write_entire_file(vulkan_glsl_path, vulkan_glsl_source) fail("Could not write %", vulkan_glsl_path);

    run_command_checked(tprint("[%] Compile generated Metal source", case_name),
      .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", metal_path, "-o", air_path]);
    run_command_checked(tprint("[%] Compile generated Vulkan GLSL", case_name),
      .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", "comp", vulkan_glsl_path]);

    run_metal_compute_and_compare(metal_path, metal_source, case_name, compute_branch_shader);
  }

  // Case: branch_alt (different constants to validate parameterized SPIR-V text emission).
  {
    case_name :: "branch_alt";
    metal_path := tprint("%/%_metal.comp.metal", SPIRV_OUT_DIR, case_name);
    vulkan_glsl_path := tprint("%/%_vk.comp.glsl", SPIRV_OUT_DIR, case_name);
    air_path := tprint("%/%_metal.comp.air", SPIRV_OUT_DIR, case_name);

    metal_source := get_transpiled(.METAL, compute_branch_shader_alt);
    vulkan_glsl_source := get_transpiled(.VULKAN_GLSL, compute_branch_shader_alt);
    check_spvasm_is_generic("compute_branch_shader_alt");

    if !write_entire_file(metal_path, metal_source) fail("Could not write %", metal_path);
    if !write_entire_file(vulkan_glsl_path, vulkan_glsl_source) fail("Could not write %", vulkan_glsl_path);

    run_command_checked(tprint("[%] Compile generated Metal source", case_name),
      .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", metal_path, "-o", air_path]);
    run_command_checked(tprint("[%] Compile generated Vulkan GLSL", case_name),
      .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", "comp", vulkan_glsl_path]);

    run_metal_compute_and_compare(metal_path, metal_source, case_name, compute_branch_shader_alt);
  }

  // Case: min (smallest shape, no branches).
  {
    case_name :: "min";
    metal_path := tprint("%/%_metal.comp.metal", SPIRV_OUT_DIR, case_name);
    vulkan_glsl_path := tprint("%/%_vk.comp.glsl", SPIRV_OUT_DIR, case_name);
    air_path := tprint("%/%_metal.comp.air", SPIRV_OUT_DIR, case_name);

    metal_source := get_transpiled(.METAL, compute_min_shader);
    vulkan_glsl_source := get_transpiled(.VULKAN_GLSL, compute_min_shader);
    check_spvasm_is_generic("compute_min_shader");

    if !write_entire_file(metal_path, metal_source) fail("Could not write %", metal_path);
    if !write_entire_file(vulkan_glsl_path, vulkan_glsl_source) fail("Could not write %", vulkan_glsl_path);

    run_command_checked(tprint("[%] Compile generated Metal source", case_name),
      .["xcrun", "-sdk", "macosx", "metal", "-std=metal3.0", "-c", metal_path, "-o", air_path]);
    run_command_checked(tprint("[%] Compile generated Vulkan GLSL", case_name),
      .["glslangValidator", "-V", "--target-env", "vulkan1.2", "-S", "comp", vulkan_glsl_path]);

    run_metal_compute_and_compare(metal_path, metal_source, case_name, compute_min_shader);
  }

  log("[SPIR-V][compute] Passed plugin path: Jai -> IR -> SPIR-V -> spirv-cross -> Metal/GLSL + GPU match.");
}
