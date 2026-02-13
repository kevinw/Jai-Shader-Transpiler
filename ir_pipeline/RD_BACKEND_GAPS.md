# RD Backend Gaps (Discovered While Building `app_peel_reaction_diffusion`)

This file tracks real gaps found while getting the reaction-diffusion prototype working end-to-end.

## Active blockers

1. Pair linking fails when stages use different addressing models.
- Error from `spirv-link`: `Conflicting addressing models: PhysicalStorageBuffer64 vs Logical`.
- Trigger: vertex stage with pointer-ABI root arg while fragment stage lowered to logical path.
- Current behavior: fail early with explicit ABI mismatch diagnostic; link-time diagnostics also include per-stage memory models.

2. Pair stage interfaces can still fail if vertex/fragment semantics diverge in unsupported ways.
- Historically observed runtime error: fragment input `user(locn1)` mismatched vertex output.
- Current behavior now fail-fasts before SPIR-V emission with an explicit stage-interface mismatch diagnostic (type + semantic/name checks after builtin filtering).
- Remaining risk: some legacy semantic aliases may still need explicit policy decisions.

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

5. Pair interface mismatch diagnostics were too late (`spirv-link`) and opaque.
- Fix: pre-link vertex/fragment stage-interface validator in pair SPIR-V path.
- Behavior: fail-fast with field index + type/semantic/name details.
- Coverage: existing pair tests remain green and legacy tiles/vulkan examples validate through the new path.

## Next pass after RD is running

- Add minimal failing tests for each remaining active item above in transpiler headless suite.
- Fix in this order: (1) addressing model policy unification for pairs, then remaining semantic-alias policy cleanups.
