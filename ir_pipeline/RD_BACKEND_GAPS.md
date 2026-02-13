# RD Backend Gaps (Discovered While Building `app_peel_reaction_diffusion`)

This file tracks real gaps found while getting the reaction-diffusion prototype working end-to-end.

## Active blockers

1. Pair linking fails when stages use different addressing models.
- Error from `spirv-link`: `Conflicting addressing models: PhysicalStorageBuffer64 vs Logical`.
- Trigger: vertex stage with pointer-ABI root arg while fragment stage lowered to logical path.
- Current behavior: fail with explicit per-stage memory-model diagnostic in pair path.

2. Pair Metal output can still be brittle when stages are lowered independently.
- Historically observed runtime error: fragment input `user(locn1)` mismatched vertex output.
- Recent fix covers one concrete source (`@position` semantic being treated as non-builtin in fragment stage).
- Remaining risk: other semantic/location edge-cases may still exist.

## Resolved in this pass

1. Graphics SPIR-V backend rejected integer division (`/`) for integer kinds.
- Error was: `SPIR-V backend: unsupported integer binary op '/' for kind UINT.`
- Fix: add integer division emission (`OpUDiv`/`OpSDiv`) in `emit_int_binary_op`.
- Coverage: headless graphics tests now include uint-division vertex-only and uint-division pair outputs.

2. Compute IR lowering rejected pointer-to-struct root args.
- Error was: `IR lowering(compute): could not lower struct type 'RD_Compute_Params' for argument 'data'`.
- Fixes:
  - use pointer-aware struct lowering in compute IR lowering.
  - expand compute resource-root structs into concrete compute buffers before SPIR-V init.
- Coverage: headless compute root-struct tests now include single-pointer and ping-pong (`src`/`dst`) root structs.

3. Fragment `POSITION` semantic could consume user varying location.
- Symptom: potential varying location drift between vertex and fragment.
- Fix: map fragment semantic `POSITION` to FragCoord builtin handling.
- Coverage: headless pair test added for `@position` + color varying pass-through.

4. Compute thread-id component member access beyond `.x`.
- Error was: `SPIR-V backend: unsupported member expression 'input.thread_id'`.
- Fix: add component load emission for `thread_id.{x,y,z}` / `input.thread_id.{x,y,z}`.
- Coverage: compute semantics test `edge_case_42_thread_id_y_component`.

## Next pass after RD is running

- Add minimal failing tests for each remaining active item above in transpiler headless suite.
- Fix in this order: (2) broader stage varying/location consistency, (1) addressing model policy unification for pairs.
