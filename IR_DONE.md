# IR / SPIR-V Completed Items

This file tracks IR/SPIR-V backend limitations that were implemented and verified.

## 1) Helper procs with `void` return are not supported in compute lowering
Status: Fixed (February 28, 2026) for statement-level void helper calls with side effects.
- Symptom:
  - `SPIR-V backend: helper 'tm_mesh_tetra' has unsupported return type 'void'.`
- Where hit:
  - Compute shader helpers that mutate via pointer/out params and return nothing.
- Current workaround:
  - Rewrote helpers to return values (`u32` threaded state) instead of `void`.
- Implemented:
  - Added statement-level inlining for `void` helpers in SPIR-V backend call lowering.
  - Added inline helper return-context handling so nested `return;` in control flow unwinds safely during inlining.
  - Added regression coverage in `compute_semantics_runner` (`helper_void_call_statement`, `helper_void_nested_return`).

## 2) Local vector array lowering (`float3[4]`, etc.) fails
Status: Fixed (February 28, 2026) for fixed-size local scalar/vector arrays and helper fixed-array args in compute lowering.
- Symptom:
  - `SPIR-V backend: unknown local struct type 'float3[4]'.`
- Where hit:
  - Local temporary arrays in compute helpers (`[4]Vector3`, `[4]float`) used for tetra staging.
- Implemented:
  - Added/validated fixed-size local array lowering for scalar/vector element kinds in compute path.
  - Added fixed-array helper-arg binding in SPIR-V inline helper lowering (copy from local array identifiers and array literals).
  - Added test coverage in `compute_semantics_runner`:
    - `local_float3_array_roundtrip`
    - `helper_float3_array_arg`

## 5) Storage buffer alignment issue for `Vector3` arrays in SPIR-V validation
Status: Addressed (February 28, 2026) by adopting scalar block layout assumptions for Vulkan validation/layout.
- Symptom:
  - `spirv-val ... stride 12 not satisfying alignment to 16` for StorageBuffer array member.
- Where hit:
  - Compute output buffers typed as `*Vector3`.
- Implemented:
  - Switched SPIR-V validation to scalar block layout mode (`spirv-val --scalar-block-layout`).
  - Updated storage-struct field/stride packing to a CPU-blittable scalar-layout ABI.
  - Added compute semantics coverage for raw `*Vector3` storage buffers (`raw_vec3_buffer_component_write`).
- Current ABI assumption:
  - Vulkan targets are assumed to support scalar block layout.
  - CPU and GPU storage data are expected to be directly blittable under that layout contract (no per-dispatch repacking).

## 6) Compute buffer params must be struct-buffer compatible
Status: Fixed (February 28, 2026) for raw scalar/vector storage buffers in compute path.
- Symptom:
  - `SPIR-V backend: buffer 'positions' is not a struct buffer.`
- Where hit:
  - Pointer parameters to non-struct element types for storage buffers.
- Implemented:
  - Added raw vector-buffer component lvalue fallback for subscript member writes (e.g. `table[idx].x = ...` where `table: *Vector4`).
  - Kept direct non-struct subscript load/store path for scalar/vector buffers and validated with compute semantics.
  - Added regression coverage in `compute_semantics_runner`: `raw_vec4_buffer_component_write`.

## 7) Struct buffer field type coverage gaps (e.g. `Vector4` field)
Status: Fixed (February 28, 2026) for float vector fields including `Vector4`.
- Symptom:
  - `SPIR-V backend: unsupported struct buffer field type for 'positions.v'.`
- Where hit:
  - Struct buffer field declared as builtin vector type.
- Implemented:
  - Added storage-pointer type support for `float4` in SPIR-V type mapping (`PTR_STORAGE_FLOAT4` / `id_ptr_storage_float4`).
  - Updated struct-buffer layout packing to align vector fields/stride correctly for validation.
  - Added regression coverage in `compute_semantics_runner`: `struct_vec4_field_write`.

## 8) Struct assignment into storage buffer elements is unsupported
Status: Fixed (February 28, 2026) for constructor/helper/local-struct RHS in compute path.
- Symptom:
  - `SPIR-V backend: unsupported struct buffer assignment rhs 'TM_Float4(...)'.`
- Where hit:
  - Writing full struct literals into storage buffer elements.
- Implemented:
  - Added struct-buffer assignment lowering for constructor RHS:
    - `buffer[idx] = StructType.{...};`
  - Existing helper-call/local-struct RHS support remains.
  - Added regression coverage in `compute_semantics_runner`:
    - `struct_buffer_element_constructor_assign`

## 10) Compute correctness mismatch in helper-heavy tetra logic
Status: Fixed (February 28, 2026) for compute helper return-chain lowering.
- Symptom:
  - GPU and CPU diverged for identical tetra-style helper code, causing terrain meshing artifacts.
  - Repro failure:
    - `[FAIL] mismatch in 'terrain_tetra_inside_outside_signature' at index 2: GPU=2147483650 CPU=2484802686`
- Where hit:
  - `headless_ir/compute_semantics_runner.jai` case `terrain_tetra_inside_outside_signature`
  - `modules/Terrain_Mesh_Compute/shaders/terrain_mesh_compute_shader.jai` terrain compute flow.
- Root cause:
  - SPIR-V helper return-chain lowering for `if` branches evaluated both branches eagerly, then selected, instead of preserving branch control flow.
- Implemented:
  - Reworked helper return-chain `if` lowering in `ir_pipeline/spirv_text_backend.jai` to emit real branch/merge control flow and load the chosen result.
  - Added null-constant tracking/emission and function-local variable initialization plumbing (`OpConstantNull`) in:
    - `ir_pipeline/spirv_text_backend.jai`
    - `ir_pipeline/spv_types.jai`
    - `ir_pipeline/spirv_text_backend_emitters.jai`
- Verification:
  - `bash headless_ir/test_ir_compute_semantics.sh` passes with the new regression case.
  - `jai modules/Jai-Shader-Transpiler/build.jai - -run_tests` passes.
