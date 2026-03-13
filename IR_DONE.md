# IR / SPIR-V Completed Items

This file tracks IR/SPIR-V backend limitations that were implemented and verified.

## Ordered Backend Simplification Plan (1-9)
Status: Completed (March 1, 2026). Remaining ordered item is tracked in `IR_TODO.md` (#10).
- 1) Builtin semantics are first-class in IR:
  - Added typed builtin refs on `IR_Expr`/input builtin mapping and removed ad hoc builtin shape fallbacks in SPIR-V member emission.
- 2) Compute backend split into analysis + emit:
  - Added explicit compute analysis pass (bound/resource expansion/builtin usage flags) and made emit consume analyzed state.
- 3) Reduced stringly SPIR-V assembly for common op forms:
  - Added typed helper emitters for common forms (`OpAccessChain`, `OpLoad`, common `OpExtInst`) and migrated core call sites.
- 4) Centralized conversion/coercion policy:
  - Added single scalar conversion helper and routed `coerce_to_kind`/`coerce_to_float` through it.
- 5) Normalized declaration default initialization:
  - Added one local declaration default-initializer path and reused it for scalar and fixed-array declarations.
- 6) Added pre-emission IR invariant validation:
  - Added lightweight IR validator for builtin provenance and control-flow expression traversal before backend emission.
  - Preserved Jai default-zero declaration semantics unless explicitly uninitialized (`---` / `.IS_UNINITIALIZED`).
- 7) Reduced semantic dependence on member text:
  - Added typed member-access provenance (`IR_Member_Access_Kind`) in IR lowering and switched backend component/swizzle decisions to typed metadata.
- 8) Resource/buffer classification moved to dedicated module:
  - Extracted classification/expansion logic into `ir_pipeline/spv_resource_classification.jai`.
- 9) Backend file split by domain continued:
  - Extracted invariant domain into `ir_pipeline/spv_invariants.jai` and kept coordinator flow thinner.

## Next Simplification / Robustness Pass (1-8)
Status: Completed (March 1, 2026).
- 1) Removed remaining call-dispatch semantic dependence on raw callee text in backend hot paths:
  - Added typed builtin call-kind analysis consumption in backend builtin usage scanning.
- 2) Split lvalue lowering domain:
  - Moved lvalue pointer/storage lowering helpers to `ir_pipeline/spv_lvalue_lowering.jai`.
- 3) Added typed call metadata in IR:
  - Added `IR_Call_Target_Kind` + `IR_Call_Builtin_Kind` metadata and threaded lowering/backend dispatch through typed call identity.
- 4) Added explicit graphics backend analysis pass:
  - Added `spv_analyze_graphics_shader` and moved graphics resource/builtin planning out of emit-time discovery.
- 5) Expanded invariant validation for typed member/call consistency:
  - Added call-target/builtin coherence checks in invariant validation.
- 6) Centralized vector component/swizzle bounds policy:
  - Introduced shared vector component range validation helper used across expression and lvalue paths.
- 7) Hardened headless cleanup under transient filesystem races:
  - Updated `test_runner.jai` cleanup command path to avoid flaky remove failures.
- 8) Added focused headless robustness coverage:
  - Enabled `edge_gap_70_helper_struct_named_constructor_arg` and `edge_gap_72_helper_pointer_alias_arg` in compute semantics.
  - Added graphics semantics nested resource-container case (`graphics_nested_resource_container`).

## 22) Member access on vector-returning function calls
Status: Fixed (March 2, 2026) for SPIR-V helper-call vector results.
- Symptom before:
  - `SPIR-V backend: member access on non-struct call return 'float4'.`
- Implemented:
  - Added shared vector-member extractor in SPIR-V backend (`x/y/z/w`, `xy`, `xyz`).
  - Extended `.MEMBER` call lowering to accept helper return kinds `float2/float3/float4` and emit component/swatch extraction directly.
  - Reused the same extractor for other vector-member paths to keep behavior consistent.
- Regression coverage:
  - Added `ir_headless_fragment_call_member_main` in `headless_ir/ir_headless_runner.jai`.
  - Validates generated SPIR-V includes vector component extraction for call-result member access.

## 21) Storage-buffer member/swizzle access on indexed expressions
Status: Fixed (March 2, 2026) for indexed struct-field component/swizzle reads.
- Symptom before:
  - `SPIR-V backend: unsupported member expression 'payload[0].xyz'.`
- Implemented:
  - Added explicit `.MEMBER` lowering path for `subscript.field.member` over storage buffers.
  - Loads the indexed field and applies shared vector-member extraction (`x/y/z/w`, `xy`, `xyz`) consistently.
- Regression coverage:
  - Added `ir_headless_compute_alias_layout_main` with indexed nested-field component reads/writes.

## 20) Subscript on casted storage pointer expression
Status: Fixed (March 2, 2026).
- Symptom before:
  - `SPIR-V backend: unknown subscript base '*float4(state)'.`
- Implemented:
  - Unified struct-buffer field pointer base resolution on `resolve_buffer_name_from_expr(...)`, which handles cast/unary/member forms.
  - Applied the same resolution in struct declaration subscript initializers.
- Regression coverage:
  - Added `ir_headless_compute_casted_struct_subscript_main` using casted storage-pointer subscript bases.

## 19) Helper pointer args with fixed-array storage buffer pointees
Status: Fixed (March 2, 2026) in inline helper binding.
- Symptom before:
  - `SPIR-V backend: helper '...' pointer arg 'state' has unsupported pointee kind FIXED_ARRAY.`
- Implemented:
  - Extended pointer-arg binding to recognize pointer-to-fixed-array pointees and validate against source buffer element kind/struct.
  - Preserved subscript-based base-index aliasing for pointer args.
- Regression coverage:
  - Added `ir_headless_helper_fixed_array_x` + `ir_headless_compute_fixed_array_pointer_helper_main`.

## 12) Storage-buffer wrapper struct field layout/type aliasing (`TM_Float4`-style)
Status: Fixed (March 2, 2026) for layout/type emission of simple float wrapper structs.
- Symptom before:
  - `SPIR-V generic backend: buffer struct '...' field '...' has unsupported layout type 'TM_Float4'.`
- Implemented:
  - Added layout-specific type mapping that resolves simple struct aliases (single float/vector field or 2/3/4 float-field wrappers) to backend vector/scalar kinds during buffer layout planning.
  - Kept regular type mapping untouched outside layout path.
- Regression coverage:
  - Added `ir_headless_compute_alias_layout_main` in `headless_ir/ir_headless_runner.jai` with nested alias fields in storage buffers.
  - Validates transpilation/Metal compile for alias-layout compute path.
- Additional follow-up (March 2, 2026):
  - Added nested struct buffer-element local copy support for alias wrappers during:
    - local struct declaration initialization from `buffer[idx]`
    - struct-buffer assignment from local structs with nested wrapper fields
    - helper struct-arg binding from buffer subscripts
  - Implemented shared alias pack/unpack helpers to map between local nested wrapper structs and backend vector/scalar storage field kinds.

## 23) `exp` intrinsic call support in SPIR-V backend expression lowering
Status: Fixed (March 1, 2026).
- Symptom:
  - `SPIR-V backend: unsupported call target 'exp'.`
- Where hit:
  - `src/apps/shaders/flux_shader.jai` while adding exponential distance fog in fragment shading.
- Implemented:
  - Added typed builtin kind support for `exp` in IR lowering/backend call classification.
  - Mapped `exp` to `GLSL.std.450 Exp` in SPIR-V emission.
  - Added compute semantics regression coverage (`intrinsic_exp`).

## 24) Graphics parameter blocks nested-struct layout in struct-buffer path
Status: Fixed (March 3, 2026).
- Symptom before:
  - `SPIR-V generic backend: buffer struct '...' field '...' has unsupported layout type '...'.`
- Implemented:
  - Added nested-field flattening in struct-buffer layout planning for true nested structs, while preserving simple struct aliases (e.g. vector wrapper aliases) as scalar/vector fields.
  - Added member-path field resolution for flattened names in graphics expression/lvalue lowering (e.g. `params.core.mix_gain`).
  - Added recursive local-struct initialization from struct-buffer subscripts so nested local copies work with flattened field paths.
- Regression coverage:
  - Added `ir_headless_fragment_nested_params_main` in `headless_ir/ir_headless_runner.jai`.

## 25) Casted pointer alias indexing against graphics parameter buffers
Status: Fixed (March 3, 2026) for casted fixed-array reinterpret access.
- Symptom before:
  - Casted reinterpret subscript paths in graphics parameter buffers were brittle and failed to resolve buffer roots/types.
- Implemented:
  - Hardened identifier/member root normalization for cast-shaped buffer expressions.
  - Added struct-buffer reinterpret constant-subscript lowering for casted access patterns, including array-field slot mapping within struct-backed parameter buffers.
  - Kept regular typed-field access paths unchanged.
- Regression coverage:
  - Added `ir_headless_fragment_casted_fixed_alias_params_main` in `headless_ir/ir_headless_runner.jai`.

## 26) BOOL <-> integer conversion support in SPIR-V coercion
Status: Fixed (March 3, 2026).
- Symptom before:
  - `SPIR-V backend: unsupported conversion from BOOL to UINT.`
- Implemented:
  - Added explicit BOOL -> INT/UINT/INT64/UINT64 lowering via `OpSelect` (1/0 constants).
  - Added INT/UINT/INT64/UINT64 -> BOOL lowering via non-zero comparisons.
  - Added FLOAT/FLOAT16 -> BOOL lowering via ordered non-zero compare.
- Regression coverage:
  - Added bool-cast usage in `ir_headless_fragment_nested_params_main` and SPIR-V text assertion for `OpSelect`.

## 27) Field/member access normalization for non-trivial roots
Status: Fixed (March 13, 2026).
- Symptom before:
  - Member access could fail or route through the wrong backend path when the root was not a plain identifier, for example:
    - nested resource-param access like `data.p.texture_index`
    - zero-deref/root-pointer forms like `params[0].core.mix_gain`
    - mixed chains with subscript + field + vector component
- Implemented:
  - Replaced ad hoc recursive text recovery with one normalized access-chain path in the SPIR-V backend.
  - Reused the normalized path for:
    - member-path reconstruction
    - buffer-prefix resolution
    - local nested-struct field traversal
    - lvalue field/component access
  - Preserved the old zero-deref normalization so pointer-root parameter-buffer forms still resolve correctly.
- Regression coverage:
  - Added compute semantics cases:
    - `nested_local_member_expr_chain`
    - `nested_boid_member_chain`
  - Existing graphics headless regression `ir_headless_fragment_nested_params_main` continues to validate `params[0].core.mix_gain`.

## 28) Local shader structs with storage-buffer pointer fields
Status: Fixed (March 13, 2026).
- Symptom before:
  - Local struct declarations with pointer fields failed during backend lowering, for example:
    - `SPIR-V backend: local struct '...' field 'values' has unsupported type '*uint'.`
- Implemented:
  - Added support for pointer-typed local struct fields by storing them as buffer-alias metadata instead of function-memory scalar values.
  - Extended struct initialization/copy paths and helper pointer-arg binding to preserve that alias information.
  - Reused the alias metadata in subscript/lvalue lowering so expressions like `params.nested.values[idx]` work the same as direct buffer aliases.
- Regression coverage:
  - Added compute semantics case `nested_pointer_field_from_local_struct`.

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
Status: Fixed (March 1, 2026) for nested runtime helper procs; nested `#expand` procs now produce an explicit diagnostic.
- Symptom:
  - `IR lowering: unsupported declaration type for '<inner_proc_name>'.`
- Where hit:
  - Declaring a helper proc inside another shader proc body (example regression: `inner_proc` in `compute_semantics_runner.jai`).
- Implemented:
  - `ir_shared` statement lowering now recognizes declaration nodes whose expression is a nested procedure and treats them as helper declarations instead of value declarations.
  - Added explicit IR diagnostic when nested proc declaration has an `expand` note:
    - `IR lowering: nested proc '<name>' marked #expand is unsupported`
  - Extended SPIR-V inline helper pointer-arg binding and buffer aliasing for subscript-based pointer args (e.g. `*values[idx]`) so nested helper calls can mutate the correct storage element.
  - Added unary pointer-deref fallback in IR unary lowering for pointer-typed operands (`*`), and SPIR-V unary deref load/lvalue support in helper lowering.
- Verification:
  - `jai -quiet headless_ir/build_ir_compute_semantics.jai` passes (includes `inner_proc`).
  - `jai -quiet build.jai - -run_tests` passes.

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

## 11) Helper pointer arguments can now target local scalar lvalues in compute helper inlining
Status: Fixed (March 1, 2026) for local scalar/vector lvalue pointer args.
- Symptom before:
  - `SPIR-V backend: helper '<name>' pointer arg '<arg>' expected storage buffer identifier, got '<local>'.`
- Implemented:
  - Extended inline helper pointer-arg binding to accept local lvalue sources (e.g. `*tmp`) in addition to storage-buffer identifiers/subscripts.
  - Added local pointer-arg aliasing path and unary `*` lvalue support for helper pointer identifiers backed by local pointers.
- Regression coverage:
  - `helper_local_pointer_scalar_arg`
  - `helper_local_pointer_float_arg`
- Verification:
  - `jai -quiet build.jai - -run_tests` passes.

## 18) Typed-first SPIR-V backend simplification (string-heuristic reduction)
Status: In large part fixed (March 1, 2026) across backend hot paths; remaining small cleanup is tracked in `IR_TODO.md` #18.
- Implemented:
  - Added typed expression result provenance (`IR_Expr.result_type`) and moved key SPIR-V type decisions to typed metadata.
  - Removed broad backend reliance on legacy pointer/type-name mirrors for resource classification and physical-pointer graphics traversal.
  - Migrated helper struct-arg/return matching and struct constructor/init checks to typed struct metadata first.
  - Removed now-unused string-parser helpers that previously inferred semantics from wrapper text.
  - Removed remaining SPIR-V type-name parser fallbacks (`expr_type_from_decl` / fixed-array type-name parsing family); backend type decisions now use `IR_Type` metadata.
  - Removed remaining IR mirror fields used by backends (`pointer_*`, `original_type_name`, field/arg `type_name`, function `return_type_name`, stmt `decl_type_name`, compute-buffer `element_type_name`) and rewired callsites to typed `IR_Type`.
  - Simplified lowering helpers to typed side-effect collectors (no more string wrapper synthesis when the return text is unused), and centralized typed name selection through one shared utility.
  - Removed the legacy `"<operator_not_supported>"` sentinel TODO path from active codepaths; operator handling now uses explicit success/failure flow.
  - Tightened compute builtin note matching from substring scans to normalized exact-name matching (optional `@` prefix / call-style suffix normalization).
  - Removed origin-node-based struct-init type fallback in SPIR-V local struct init; constructor type matching now depends on lowered typed result metadata only.
  - Replaced member-path buffer resolution fallbacks that previously depended on reconstructed expression text with structural IR member-chain resolution.
  - Switched thread-id branch-pattern matching and storage-buffer lvalue classification from expression-text reconstruction to structural member-path matching.
  - Removed dead SPIR-V decl-alias type parser tables/helpers (`SPV_DECL_ALIASES`, `expr_type_from_decl`) that were no longer referenced after typed lowering migration.
  - Added initial scalar `Float16`/`half` lowering path through IR -> SPIR-V (typed `F16` kind, `OpTypeFloat 16`, `Float16` capability gating, and cast/coercion support via `OpFConvert`/`OpConvert*ToF`) with compute semantics coverage.
  - Removed compute thread builtin dependence on hardcoded identifier text (`thread_id.x` style): lowering now tags builtin provenance/components on IR expressions, and SPIR-V backend dispatch-thread handling consumes those tags.
- Outcome:
  - Backend semantics now primarily come from lowered type metadata instead of reconstructed strings, with narrow compatibility fallbacks only where lowering completeness is still being finished.


## 41) Transpiled shader cache invalidation can reuse stale backend output after source/transpiler changes
- Symptom:
  - Shader edits can appear to "do nothing" because previously cached transpiled backend output is reused.
  - Behavior can look like backend miscompile even when source is fixed, until cache is manually busted.
- Where hit:
  - Brickmap shader/debug iterations while validating fragment/control-flow fixes against emitted Metal.
- Current workaround:
  - Manually clear cache or bump cache-version key.
- Desired fix:
  - Make cache keys content-addressed by effective inputs (shader source, backend, transpiler codegen-relevant version/feature fingerprint).
  - Ensure transpiler/backend changes invalidate prior cached outputs automatically without manual version bumps.
  - Add a regression check that recompiles after source mutation and asserts emitted backend text changes.

## 42) Compute atomics now include subtract / exchange / compare-exchange for `u32`
Status: Fixed (March 8, 2026) for SPIR-V backend lowering and smoke coverage.
- Implemented:
  - Added shader builtins:
    - `atomic_sub_u32`
    - `atomic_exchange_u32`
    - `atomic_compare_exchange_u32`
  - Wired builtin recognition through:
    - `modules/ShaderFuncs/module.jai`
    - `ir_pipeline/public_structs.jai`
    - `ir_pipeline/ir_shared.jai`
    - `ir_pipeline/ir_lowering.jai`
    - `ir_pipeline/spirv_text_backend.jai`
  - Lowered `atomic_sub_u32` as atomic add of a two's-complement-negated `u32` value (`OpISub` + `OpAtomicIAdd`), since direct `OpAtomicISub` is not a valid SPIR-V instruction.
  - Added headless regression coverage in:
    - `headless_ir/ir_headless_runner.jai`
    - coverage asserts `OpAtomicIAdd`, `OpISub`, `OpAtomicExchange`, and `OpAtomicCompareExchange`
- Verification:
  - `jai -quiet modules/Jai-Shader-Transpiler/headless_ir/build_ir_headless.jai -`
  - `jai -quiet modules/Jai-Shader-Transpiler/build.jai - -run_tests`

## 43) `atomic_min_u32` / `atomic_max_u32` now lower reliably in the SPIR-V target path
Status: Fixed (March 8, 2026) via generated compare-exchange retry loops.
- Symptom before:
  - Transpilation could fail to produce target source for simple compute shaders that used `atomic_min_u32` or `atomic_max_u32`, even though the other `u32` atomic helpers succeeded.
- Implemented:
  - Replaced the fragile direct SPIR-V min/max lowering path with backend-generated CAS loops in `ir_pipeline/spirv_text_backend.jai`.
  - Preserved the shader-facing builtin API, so shader code still uses:
    - `atomic_min_u32`
    - `atomic_max_u32`
  - Expanded the focused headless atomics regression in `headless_ir/ir_headless_runner.jai` to cover:
    - `atomic_add_u32`
    - `atomic_sub_u32`
    - `atomic_exchange_u32`
    - `atomic_compare_exchange_u32`
    - `atomic_min_u32`
    - `atomic_max_u32`
  - Added regression assertions for the loop/CAS shape in generated SPIR-V and Vulkan GLSL output.
- Verification:
  - `jai -quiet modules/Jai-Shader-Transpiler/headless_ir/build_ir_headless.jai -`
  - `jai -quiet modules/Jai-Shader-Transpiler/build.jai - -run_tests`

## 44) Vector-valued helper math no longer mis-coerces through scalar float paths
Status: Fixed (March 12, 2026) for compact vector helper expressions and exact result-kind coercion.
- Symptom before:
  - Pair shader lowering could fail with diagnostics such as:
    - `SPIR-V backend: cannot coerce value type FLOAT2 to float3.`
    - `detail: SPIR-V backend: unsupported conversion from FLOAT2 to FLOAT.`
- Where hit:
  - `src/apps/shaders/raytracer_shader.jai` while adding animated floor-noise helpers using compact `Vector2` math, for example:
```jai
raytracer_noise2 :: (p: Vector2) -> float {
    cell := Vector2.{floor(p.x), floor(p.y)};
    local := Vector2.{frac(p.x), frac(p.y)};
    smooth := local * local * (Vector2.{3.0, 3.0} - local * 2.0);

    n00 := raytracer_hash2(cell.x, cell.y);
    n10 := raytracer_hash2(cell.x + 1.0, cell.y);
    n01 := raytracer_hash2(cell.x, cell.y + 1.0);
    n11 := raytracer_hash2(cell.x + 1.0, cell.y + 1.0);
    nx0 := n00 + (n10 - n00) * smooth.x;
    nx1 := n01 + (n11 - n01) * smooth.x;
    return nx0 + (nx1 - nx0) * smooth.y;
}
```
- Implemented:
  - Switched `coerce_to_expr_result_kind` to use exact-kind coercion so vector-typed expression result slots preserve `FLOAT2/3/4` instead of falling through scalar-only conversion.
  - Added compact float-vector constructor flattening in the SPIR-V backend, so vector constructors can consume vector/scalar component mixes without misrouting through scalar coercion.
  - Added compute semantics coverage in `headless_ir/compute_semantics_runner.jai`:
    - `vector2_noise_compact_chain`
  - Restored the compact vector form in `src/apps/shaders/raytracer_shader.jai` instead of keeping the scalar-expanded workaround.
- Verification:
  - `jai modules/Jai-Shader-Transpiler/headless_ir/build_ir_compute_semantics.jai`
  - `jai modules/Jai-Shader-Transpiler/headless_ir/build_ir_graphics_semantics.jai`
  - `jai build.jai - src/apps/raytracer.jai`
