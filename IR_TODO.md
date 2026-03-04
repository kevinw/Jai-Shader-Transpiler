# IR / SPIR-V TODOs 

This file captures concrete IR/SPIR-V backend limitations that are still open.
Completed items were moved to `IR_DONE.md`.

Direction note:
- Incrementally prefer carrying richer Compiler AST/type information through lowering where practical, instead of encoding behavior through hardcoded strings and mirrored IR type/operator tables. Start by removing string-sentinel decisions (for example `"<operator_not_supported>"` checks) in favor of typed operator handling.
- Prefer Compiler module enums/nodes (`Operator_Type`, `Code_Node` forms, `Type_Info`) over duplicated string encodings whenever the data stays in-compiler-pass.

## Ordered Backend Simplification Plan
10. Expand focused headless semantics coverage for robustness.
- Add one case per builtin alias pattern and coercion edge (`f16/f32/int`).
- Add one case per key pointer/lvalue/resource shape to catch regressions early.

## 27) Graphics cast reinterpret still relies on weak type metadata for raw pointer casts
- Symptom:
  - Some casted graphics reinterpret expressions can still surface unknown-result-type failures when IR does not carry complete cast/subscript type metadata.
- Where hit:
  - Direct raw-pointer cast patterns like `cast(*Vector4) params` in fragment parameter-buffer paths.
- Current workaround:
  - Prefer fixed-array reinterpret casts (`cast(*[N] Vector4) params`) or typed field access.
- Desired fix:
  - Thread explicit cast target type info through IR expression lowering for cast/subscript nodes in graphics paths.
  - Remove text-based fallback type inference in SPIR-V reinterpret lowering once typed metadata is available.

## 28) Function-typed local declarations are unsupported in IR lowering
- Symptom:
  - `IR lowering: unsupported typed declaration info for '<local_name>'`.
- Where hit:
  - Shader helper alias patterns inside function bodies, e.g. local declarations like `project := some_helper; project(...)`.
- Current workaround:
  - Call helpers directly, or use global compile-time aliases that lower as direct helper identifiers.
- Desired fix:
  - Add IR declaration/lvalue support for procedure-typed locals (or explicit rejection earlier with targeted diagnostic and suggestion).
  - Add a focused headless regression covering local helper alias call sites once supported.

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

## 13) Resource-container argument cannot mix buffers with scalar/uniform fields
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
  - Support mixed resource+uniform payloads in one argument container (or a first-class root-constants/params channel in the IR ABI) so compute kernels do not need artificial split structs.

## 14) SPIR-V backend lacks production-ready `f16`/`half` buffer/type path
- Symptom:
  - No reliable end-to-end `half` (`f16`) compute storage path available in the current IR -> SPIR-V -> backend flow for this terrain workload.
- Where hit:
  - Terrain meshing/compaction memory planning (wanted to cut arena bandwidth/size by moving positions/normals to f16).
- Current workaround:
  - Keep density/mesh buffers as `float` (`f32`) everywhere.
- Current status:
  - Initial scalar `Float16`/`half` path is now wired for local values/casts in compute semantics (typed IR `F16`, SPIR-V `OpTypeFloat 16`, capability gating, and basic coercions).
- Desired fix:
  - Map "Float16" Jai module type Float16 to proper 16 bit float in the gpu
  - Add explicit `f16` type lowering and capability/extension emission in SPIR-V backend.
  - Validate cross-backend codegen and ABI layout for `half` storage buffers, including transpiler regression tests.

## 17) Builtin-note detection still relies on note text parsing
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

## 18) IR still duplicates some frontend shape that can be referenced directly during lowering
- Symptom:
  - Several lowering paths reconstruct semantics from IR text fields (`expr.text`, type-name text) instead of carrying direct provenance.
- Where hit:
  - Constructor/type classification and some helper-call lowering paths in IR/SPIR-V backend.
- Desired fix:
  - Incrementally add provenance handles for in-pass use (for example original `Code_Node`/resolved declaration/type handles) where this removes string heuristics.
  - Keep backend portability by retaining final normalized IR fields, but stop using text as the primary semantic key.
- Status:
  - Active. Major typed-first backend simplification work has landed; see `IR_DONE.md` for completed milestones.
  - Remaining work: remove the last semantic dependencies on `expr.text` / `*_type_name` in backend decision paths.

## 29) Integer fragment varyings can fail output-pointer typing in SPIR-V backend
- Symptom:
  - Pair shader lowering can fail with: `SPIR-V backend: missing output pointer type for field '<field>'` when passing integer varyings (e.g. `u32 flags`) from vertex to fragment.
- Where hit:
  - New Tetris pair shader (`src/apps/shaders/tetris_shader.jai`) when carrying per-instance flags through vertex output.
- Current workaround:
  - Carry the varying as `float`, cast back to integer in fragment.
- Desired fix:
  - Ensure integer varyings in stage I/O structs always produce valid pointer/result types in SPIR-V text backend, including interpolation/storage decorations as needed.

## 30) Structured-buffer element layout/alignment is fragile for non-16-byte strides
- Symptom:
  - `spirv-opt` rejects generated SPIR-V with block-layout errors such as: `array with stride 44 not satisfying alignment to 16`.
- Where hit:
  - Structured buffer element `Tetris_Block_Instance` (2x vec2 + vec4 + scalar tail fields) generated a 44-byte stride.
- Current workaround:
  - Add explicit padding field(s) to force 16-byte-aligned struct stride (`48` bytes here).
- Desired fix:
  - Backend should enforce/validate target block layout proactively and/or auto-pad reflected struct layout for storage buffers so misaligned host-side structs fail early with actionable diagnostics.

## 31) Shader-side `normalize` overload resolution still trips host pointer-style forms
- Symptom:
  - Shader lowering emits `SPIR-V backend: normalize expects 1 arg.` in contexts that pick or preserve host-style overload forms.
- Where hit:
  - Tetris shader normal computation in pair shader path.
- Current workaround:
  - Use explicit local normalize helper (`len2/sqrt/inv`) in shader code.
- Desired fix:
  - Route shader lowering through unambiguous value-vector normalize lowering (or improve overload filtering/diagnostics so host pointer-style forms never leak into shader IR paths).

## 32) Vector `min`/`max` lowering can mis-type element-wise expressions
- Symptom:
  - Pair shader lowering can fail with: `SPIR-V backend: unsupported conversion from FLOAT3 to FLOAT.`
- Where hit:
  - Raytracer shader AABB slab intersection when using vector element-wise forms:
    - `tmin3 := min(t0, t1)`
    - `tmax3 := max(t0, t1)`
- Current workaround:
  - Expand to explicit per-component scalar comparisons (`ifx` / scalar `min`/`max`) before scalar reductions.
- Desired fix:
  - Ensure vector `min`/`max` builtins preserve vector result typing through IR + SPIR-V lowering (including overload selection and temporary type propagation), so element-wise vector ops don’t degrade to scalar conversion paths.
