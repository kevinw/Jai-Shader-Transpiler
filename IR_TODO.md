# IR / SPIR-V TODOs Found While Porting Terrain Meshing Compute

This file captures concrete IR/SPIR-V backend limitations encountered during the terrain meshing compute port.

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

## 3) Nested local proc declarations are unsupported in IR lowering
- Symptom:
  - `IR lowering: unsupported declaration type for 'getp'.`
- Where hit:
  - Declaring helper procs inside another proc body.
- Current workaround:
  - Hoisted nested helper procs to module/file scope.
- Desired fix:
  - Either:
    1. Support nested local proc lowering, or
    2. Emit clearer diagnostic that nested procs are intentionally unsupported with actionable guidance.

## 4) Pointer-style `normalize(*v, fallback=...)` is not shader-IR compatible
- Symptom:
  - `SPIR-V backend: normalize expects 1 arg.`
- Where hit:
  - Using host-side Math API form (`normalize(*n, fallback=...)`) in shader code.
- Current workaround:
  - Replaced with explicit normalize math (`len2`, `sqrt`, fallback branch).
- Desired fix:
  - Optional: add shader-safe overload mapping for pointer-style convenience helpers, or
  - Improve diagnostics to explicitly call out host-only helper signatures.

## 5) Storage buffer alignment issue for `Vector3` arrays in SPIR-V validation
- Symptom:
  - `spirv-val ... stride 12 not satisfying alignment to 16` for StorageBuffer array member.
- Where hit:
  - Compute output buffers typed as `*Vector3`.
- Current workaround:
  - Switched to 16-byte entries (float4-like layout) for storage buffers.
- Desired fix:
  - Document/enforce std430-friendly layout rules in lowering.
  - Optionally auto-pad vector3 storage arrays or reject with targeted diagnostic earlier.

## 6) Compute buffer params must be struct-buffer compatible
- Symptom:
  - `SPIR-V backend: buffer 'positions' is not a struct buffer.`
- Where hit:
  - Pointer parameters to non-struct element types for storage buffers.
- Current workaround:
  - Wrapped data in struct element types.
- Desired fix:
  - Support raw scalar/vector storage buffers directly, or formalize/diagnose required buffer form clearly.

## 7) Struct buffer field type coverage gaps (e.g. `Vector4` field)
- Symptom:
  - `SPIR-V backend: unsupported struct buffer field type for 'positions.v'.`
- Where hit:
  - Struct buffer field declared as builtin vector type.
- Current workaround:
  - Replaced vector field with explicit scalar fields (`x,y,z,w`).
- Desired fix:
  - Extend struct-buffer field lowering to support vector field types (`Vector2/3/4`, integer vector variants as needed).

## 8) Struct assignment into storage buffer elements is unsupported
- Symptom:
  - `SPIR-V backend: unsupported struct buffer assignment rhs 'TM_Float4(...)'.`
- Where hit:
  - Writing full struct literals into storage buffer elements.
- Current workaround:
  - Wrote members individually (`.x/.y/.z/.w`) instead of struct assignment.
- Desired fix:
  - Support full struct write for storage buffer elements when field types are supported.
  - Or provide explicit diagnostic that only member-wise writes are supported.

## 9) Runtime integration edge: 4 compute buffers triggered Metal argument table assertion
- Symptom at runtime:
  - `bindingIndex (3) must not be higher than the maxBufferBindCount (3).`
- Where hit:
  - Dispatch path with 4 compute buffers for this shader.
- Current workaround:
  - Reduced shader/bindings to 3 buffers (encoded per-cell count in `positions[base].w`).
- Desired fix:
  - Verify `gpu_dispatch_buffers` / Metal backend binding limits and argument-table setup.
  - Confirm whether this is backend cap, descriptor layout mismatch, or IR-generated signature mismatch.
