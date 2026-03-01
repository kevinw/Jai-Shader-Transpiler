# IR / SPIR-V TODOs 

This file captures concrete IR/SPIR-V backend limitations that are still open.
Completed items were moved to `IR_DONE.md`.

Direction note:
- Incrementally prefer carrying richer Compiler AST/type information through lowering where practical, instead of encoding behavior through hardcoded strings and mirrored IR type/operator tables. Start by removing string-sentinel decisions (for example `"<operator_not_supported>"` checks) in favor of typed operator handling.

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

## 11) Helper pointer arguments cannot target local variables in shader IR
- Symptom at compile time:
  - `SPIR-V backend: helper 'tm_emit_vertex' pointer arg 'out_count' must be a buffer identifier.`
- Where hit:
  - Attempted robust emission pattern in terrain compute shader:
    - `tm_emit_vertex(..., out_count: *u32, ...)` with `*count` where `count` is local.
- Current workaround:
  - Keep counter flow in return values (`out_count = tm_emit_vertex(...)`) instead of pointer mutation helpers.
- Desired fix:
  - Clarify this as an explicit language/IR restriction in diagnostics/docs, and/or
  - Support pointer-to-function-local arguments for simple scalar mutation in helper calls.

## 12) Storage-buffer struct fields cannot be nested struct types (layout/type emission gap)
- Symptom at compile time:
  - `SPIR-V backend mode failed for shader 'terrain_apply_brush_compute' (Compute).`
  - `SPIR-V backend: SPIR-V generic backend: buffer struct 'TM_Brush_Command' field 'center_radius' has unsupported layout type 'TM_Float4'.`
- Where hit:
  - Compute buffer element struct:
    - `TM_Brush_Command :: struct { center_radius: TM_Float4; delta_pad: TM_Float4; }`
- Current workaround:
  - Flattened buffer element structs to scalar fields:
    - `center_x, center_y, center_z, radius, delta, ...pad...`
- Desired fix:
  - Add storage-buffer layout/type support for nested named struct fields when leaf field types are already supported scalars/vectors.
  - Emit a targeted diagnostic that suggests flattening as a temporary workaround when unsupported.

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
- Desired fix:
  - Map "Float16" Jai module type Float16 to proper 16 bit float in the gpu
  - Add explicit `f16` type lowering and capability/extension emission in SPIR-V backend.
  - Validate cross-backend codegen and ABI layout for `half` storage buffers, including transpiler regression tests.
