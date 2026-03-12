# IR / SPIR-V TODOs

This file tracks concrete IR/SPIR-V backend limitations that are still open.
Completed items were moved to `IR_DONE.md`.

Direction note:
- Incrementally prefer carrying richer Compiler AST/type information through lowering where practical, instead of encoding behavior through hardcoded strings and mirrored IR type/operator tables. Start by removing string-sentinel decisions (for example `"<operator_not_supported>"` checks) in favor of typed operator handling.
- Prefer Compiler module enums/nodes (`Operator_Type`, `Code_Node` forms, `Type_Info`) over duplicated string encodings whenever the data stays in-compiler-pass.

## Next Simplification Pass
1. Expand focused headless semantics coverage for robustness.
- Add one case per builtin alias pattern and coercion edge (`f16/f32/int`).
- Add one case per key pointer/lvalue/resource shape to catch regressions early.

## High Impact

## 1) SPIR-V backend lacks production-ready `f16`/`half` buffer/type path
- Symptom:
  - No reliable end-to-end `half` (`f16`) compute storage path is available in the current IR -> SPIR-V -> backend flow for this terrain workload.
- Where hit:
  - Terrain meshing/compaction memory planning wanted to cut arena bandwidth/size by moving positions/normals to `f16`.
- Current workaround:
  - Keep density/mesh buffers as `float` (`f32`) everywhere.
- Current status:
  - Initial scalar `Float16`/`half` path is now wired for local values/casts in compute semantics (typed IR `F16`, SPIR-V `OpTypeFloat 16`, capability gating, and basic coercions).
- Desired fix:
  - Map Jai `Float16` to a proper 16-bit GPU float type.
  - Add explicit `f16` type lowering and capability/extension emission in the SPIR-V backend.
  - Validate cross-backend codegen and ABI layout for `half` storage buffers, including transpiler regression tests.

## 2) Hard-fail compile-time validation is missing for host-vs-shader struct ABI alignment mismatches
- Symptom:
  - Runtime-only rendering failures can occur when host-side struct layout (Jai) diverges from shader-side ABI layout, for example `Vector3` 12-byte host layout vs MSL `float3` 16-byte alignment rules in constant/device buffers.
- Where hit:
  - Brickmap raw-Metal path after moving to 3D atlas resources; params buffer fields were misread until shader structs used packed vector fields.
- Current workaround:
  - Manually mirror/pack shader structs (for example `packed_float3`) and validate by runtime rendering checks.
- Desired fix:
  - Add compile-time ABI checks that compare generated/reflected host layout against target shader layout rules and fail the build on mismatch.
  - Error output should name the struct/field, expected offset/align/stride, actual host values, and a concrete fix hint (`packed_*`, explicit padding, or layout-safe type substitution).

## 3) Structured-buffer element layout/alignment is fragile for non-16-byte strides
- Symptom:
  - `spirv-opt` rejects generated SPIR-V with block-layout errors such as: `array with stride 44 not satisfying alignment to 16`.
- Where hit:
  - Structured buffer element `Tetris_Block_Instance` (2x `vec2` + `vec4` + scalar tail fields) generated a 44-byte stride.
- Current workaround:
  - Add explicit padding field(s) to force a 16-byte-aligned struct stride (`48` bytes here).
- Desired fix:
  - Backend should enforce/validate target block layout proactively and/or auto-pad reflected struct layout for storage buffers so misaligned host-side structs fail early with actionable diagnostics.

## 4) Graphics physical-pointer roots still fail for large host-blittable structs nested behind root pointers
- Symptom:
  - Pair shader lowering reaches `spirv-opt` block-layout failures for generated physical-storage wrappers, for example:
    - `Structure ... Block for variable in PhysicalStorageBuffer ... array with stride ... not satisfying alignment to 16`
- Where hit:
  - `brickmap` attempt to switch from the direct `Brickmap_Params` ABI to a cleaner `Brickmap_Render_Data { params: *Brickmap_Params; state: *Brickmap_State; }` graphics root.
- Current workaround:
  - Keep the render path on the direct params buffer ABI and mirror any GPU-owned state needed by the fragment shader into that params buffer.
- Desired fix:
  - Make physical-pointer wrapper emission validate and emit legal block layout for pointed-to structs used from graphics roots, including large POD payloads with `Vector3` fields and fixed arrays.
  - Add a focused pair-shader regression once the wrapper stride/layout rules are corrected.

## 5) Storage-buffer struct fields cannot currently be arrays of user-defined structs
- Symptom:
  - Pair shader lowering fails for storage buffer payloads with array-of-struct fields, e.g.:
    - `buffer struct 'Brickmap_Params' field 'lod_info' array element type 'Brickmap_Lod_Info' is unsupported.`
    - `... field 'edits' array element type 'SDF_Edit' is unsupported.`
- Where hit:
  - New brickmap prototype (`src/apps/shaders/brickmap_shader.jai`) for clipmap LOD/edit/dirty queues in a single storage payload.
- Current workaround:
  - Flatten arrays of structs into parallel primitive/vector arrays (`u32`/`s32`/`float`/`Vector4`) and pack/unpack on CPU.
- Desired fix:
  - Add SPIR-V storage buffer type emission + access support for arrays of user-defined struct element types.
  - Include layout/stride validation diagnostics for nested/arrayed struct fields.

## 6) Storage-buffer struct-array support still does not cover whole-struct indexed loads/stores
- Symptom:
  - Backend rejects whole-struct lvalue access like:
    - `unknown lvalue subscript base 'queues.candidates'`
- Where hit:
  - `brickmap` work queues after moving from SoA buffers to `Brick_Request[]` storage-buffer arrays.
- Current workaround:
  - Use field-by-field indexed access (`queues.candidates[i].lod`, `...brick_x`, etc.) instead of whole-struct assignment/load.
- Desired fix:
  - Extend lvalue lowering/emission so indexed storage-buffer struct elements can be assigned/loaded as whole POD structs, not only by field.

## 7) Resource-container arguments cannot mix buffers with scalar/uniform fields
- Symptom at compile time:
  - `SPIR-V backend: resource-container arg 'resources' currently requires all fields to be StructuredBuffer/RWStructuredBuffer.`
- Where hit:
  - Terrain compact compute path wanted one root argument containing both:
    - storage buffers (`src_positions`, `dst_positions_f32`, ...)
    - per-dispatch scalar params (`origin`, `first_vertex`, `max_vertices`)
- Current workaround:
  - Split into two arguments:
    - pointer-only resource container (`TM_Compact_Resources`)
    - separate params buffer (`TM_Compact_Params`)
- Desired fix:
  - Support mixed resource+uniform payloads in one argument container, or add a first-class root-constants/params channel in the IR ABI, so compute kernels do not need artificial split structs.

## 8) Integer fragment varyings can fail output-pointer typing in the SPIR-V backend
- Symptom:
  - Pair shader lowering can fail with: `SPIR-V backend: missing output pointer type for field '<field>'` when passing integer varyings (for example `u32 flags`) from vertex to fragment.
- Where hit:
  - New Tetris pair shader (`src/apps/shaders/tetris_shader.jai`) when carrying per-instance flags through vertex output.
- Current workaround:
  - Carry the varying as `float`, cast back to integer in fragment.
- Desired fix:
  - Ensure integer varyings in stage I/O structs always produce valid pointer/result types in the SPIR-V text backend, including interpolation/storage decorations as needed.

## 9) Vector `min`/`max` lowering can still mis-type element-wise expressions
- Symptom:
  - Pair shader lowering can fail with: `SPIR-V backend: unsupported conversion from FLOAT3 to FLOAT.`
- Where hit:
  - Raytracer shader AABB slab intersection when using vector element-wise forms:
    - `tmin3 := min(t0, t1)`
    - `tmax3 := max(t0, t1)`
- Current workaround:
  - Expand to explicit per-component scalar comparisons (`ifx` / scalar `min`/`max`) before scalar reductions.
- Desired fix:
  - Ensure vector `min`/`max` builtins preserve vector result typing through IR + SPIR-V lowering, including overload selection and temporary type propagation, so element-wise vector ops do not degrade to scalar conversion paths.

## Medium Impact

## 10) Root-parameter helper lowering is fragile for nested pointer/resource-container access
- Symptom:
  - Helper lowering can fail with errors like:
    - `helper '...' pointer arg 'params' expected storage buffer identifier, got 'params'`
- Where hit:
  - Brickmap helper sampling path with root `params` that contained resource pointers.
- Current workaround:
  - Use flat monolithic payload buffers and avoid nested pointer/resource-container indirection in helper-call chains.
- Desired fix:
  - Allow helper lowering to resolve and propagate root storage identifiers through nested pointer/resource-container expressions reliably.

## 11) Compute helper calls with storage-buffer pointer args plus atomic retry loops are still fragile
- Symptom:
  - Backend can reject otherwise-valid compute helper calls with:
    - `SPIR-V backend: unsupported call target '<helper_name>'`
- Where hit:
  - `brickmap` GPU atlas reuse path when classify tried to call:
    - `brickmap_pop_free_atlas_slot(queues)`
  - The helper body performed a compare-exchange retry loop against a storage-buffer counter and then indexed the storage buffer to fetch the popped slot.
- Current workaround:
  - Inline the CAS/pop logic directly in the compute entry point instead of routing it through a helper.
- Desired fix:
  - Make compute helper lowering robust for pointer-arg helpers that:
    - mutate storage buffers
    - contain loops / retry logic
    - use atomic compare-exchange and storage-buffer indexing in the same helper body
  - Add a focused compute regression for a helper-shaped GPU free-list pop path.

## 12) Helper return-shape support is incomplete (multi-return / local POD return structs)
- Symptom:
  - Fragment/helper lowering can fail when shader helpers return composite shapes used for debug/inspection paths, for example:
    - IR lowering helper-collection failure for tuple-style helper returns (`float, s32`).
    - `SPIR-V backend: unsupported declaration type '<Helper_Return_Struct>'` for local POD return structs.
- Where hit:
  - Brickmap cache debug instrumentation while adding sampled-distance + selected-LOD helper return in one call.
- Current workaround:
  - Keep helper returns scalar-only and split extra debug data into separate helper calls.
- Desired fix:
  - Add backend support for helper return tuples and/or POD local struct return/value propagation in shader IR lowering.
  - Add focused regressions for helper returns with `(scalar, scalar)` and simple local POD struct returns used in fragment shaders.

## 13) Temporary/local user-defined struct declarations in shader code are not broadly supported
- Symptom:
  - Backend can fail with unsupported declaration type errors for shader-local custom struct declarations/returns.
  - Recent repro in fragment helper path:
    - `SPIR-V backend: unsupported declaration type 'Brickmap_Cache_Sample'.`
- Where hit:
  - Brickmap cached-sample helper initially returned a custom struct (`dist`, `from_cache`).
- Current workaround:
  - Avoid custom local return structs in shader helpers; use scalar returns/arguments instead.
- Desired fix:
  - Support user-defined POD local structs in IR/SPIR-V expression/declaration lowering, including function return/value propagation.

## 14) Builtin call-result member access can mis-route through the helper path
- Symptom:
  - Backend can fail with helper-resolution diagnostics for builtin call results used with member access, e.g. `sample_3d(...).x`:
    - `SPIR-V backend: unknown helper 'sample_3d'`
- Where hit:
  - Brickmap fragment path after moving to 3D atlas sampling.
- Current workaround:
  - Keep expressions simple / avoid forms that trigger helper-only call-member paths; validate with headless regression.
- Desired fix:
  - In member access lowering, recognize builtin calls before helper lookup and route through builtin emission (`sample_2d`/`sample_3d`/etc.) consistently.
  - Add dedicated regression coverage for member access on builtin call results.

## 15) Graphics cast reinterpret still relies on weak type metadata for raw pointer casts
- Symptom:
  - Some casted graphics reinterpret expressions can still surface unknown-result-type failures when IR does not carry complete cast/subscript type metadata.
- Where hit:
  - Direct raw-pointer cast patterns like `cast(*Vector4) params` in fragment parameter-buffer paths.
- Current workaround:
  - Prefer fixed-array reinterpret casts (`cast(*[N] Vector4) params`) or typed field access.
- Desired fix:
  - Thread explicit cast target type info through IR expression lowering for cast/subscript nodes in graphics paths.
  - Remove text-based fallback type inference in SPIR-V reinterpret lowering once typed metadata is available.

## 16) Some `cast(float)` code paths still fail with unsupported-cast diagnostics
- Symptom:
  - Backend can fail with:
    - `SPIR-V backend: unsupported cast target 'float'`
- Where hit:
  - Triggered by specific expression shapes in newer shader/debug code paths.
- Current workaround:
  - Simplify or reshape expressions to avoid the failing cast forms.
- Desired fix:
  - Normalize scalar cast-target parsing so `float` aliases map to the backend scalar float type in all expression contexts.
  - Add regression tests covering cast usage in call args, vector constructors, and intermediate local expressions.

## 17) `tan(...)` intrinsic is missing in SPIR-V backend call lowering
- Symptom:
  - Pair shader lowering fails with: `unsupported call target 'tan'`.
- Where hit:
  - Brickmap fragment ray setup used `tan(fov * 0.5)`.
- Current workaround:
  - Precompute `tan_half_fov` on CPU and pass it as a uniform field.
- Desired fix:
  - Add intrinsic lowering for `tan` scalar/vector overloads consistent with existing trig builtin support.

## 18) Function-typed local declarations are unsupported in IR lowering
- Symptom:
  - `IR lowering: unsupported typed declaration info for '<local_name>'`.
- Where hit:
  - Shader helper alias patterns inside function bodies, e.g. local declarations like `project := some_helper; project(...)`.
- Current workaround:
  - Call helpers directly, or use global compile-time aliases that lower as direct helper identifiers.
- Desired fix:
  - Add IR declaration/lvalue support for procedure-typed locals, or reject earlier with a targeted diagnostic and suggestion.
  - Add a focused headless regression covering local helper alias call sites once supported.

## Low Impact / Cleanup

## 19) Maintain identifier names in IR for better diagnostics and debugging
- Desired fix:
  - Preserve stable source-facing identifier names through more IR/debug paths so backend diagnostics and dumped IR are easier to read while debugging failures.

## 20) Builtin-note detection still relies on note text parsing
- Symptom:
  - Compute builtin mapping uses normalized exact note-name text matching instead of structured note/operator identity.
- Where hit:
  - `ir_pipeline/ir_lowering.jai` `compute_builtin_note_for_member`.
- Current constraint:
  - In this path we consume `Type_Info_Struct_Member.notes`, which is `[] string` in `Preload.jai`; structured `Code_Note` pointers are not currently carried through this ABI.
- Cost:
  - Even with strict name matching, text parsing can drift from compiler note semantics.
- Desired fix:
  - Thread source-declaration provenance for compute input members so lowering can read structured `Code_Note` info when available.
  - Emit diagnostics that include exact source note location/operator when unsupported.

## 21) IR still duplicates some frontend shape that can be referenced directly during lowering
- Symptom:
  - Several lowering paths reconstruct semantics from IR text fields (`expr.text`, type-name text) instead of carrying direct provenance.
- Where hit:
  - Constructor/type classification and some helper-call lowering paths in the IR/SPIR-V backend.
- Status:
  - Active. Major typed-first backend simplification work has landed; see `IR_DONE.md` for completed milestones.
- Desired fix:
  - Incrementally add provenance handles for in-pass use (for example original `Code_Node` / resolved declaration/type handles) where this removes string heuristics.
  - Keep backend portability by retaining final normalized IR fields, but stop using text as the primary semantic key.
  - Remove the last semantic dependencies on `expr.text` / `*_type_name` in backend decision paths.

## 22) Shader-side `normalize` still picks or preserves host pointer-style forms in some paths
- Symptom:
  - Shader lowering emits `SPIR-V backend: normalize expects 1 arg.` when a host-style form such as `normalize(*v, fallback=...)` leaks into shader IR paths.
- Where hit:
  - Tetris shader normal computation in pair shader path, and more generally when using the host-side Math API form in shader code.
- Current workaround:
  - Use explicit local normalize math (`len2`, `sqrt`, fallback branch`) or an unambiguous value-vector helper in shader code.
- Desired fix:
  - Route shader lowering through unambiguous value-vector normalize lowering, or improve overload filtering/diagnostics so host pointer-style forms never leak into shader IR paths.
