# RD Backend Gaps (Discovered While Building `app_peel_reaction_diffusion`)

This file tracks real gaps found while getting the reaction-diffusion prototype working end-to-end.

## Active blockers

1. Graphics SPIR-V backend rejects an integer division expression in pair shader path.
- Error: `SPIR-V backend: unsupported integer binary op '/' for kind UINT.`
- Seen while transpiling pair `rd_vertex_main` + `rd_fragment_main`.
- Notes: appears even after removing obvious uint division from vertex body; likely emitted/typed unexpectedly in lowering or expression typing.

2. Compute IR lowering rejects pointer-to-struct root argument in compute entry.
- Error: `IR lowering(compute): could not lower struct type 'RD_Compute_Params' for argument 'data'`.
- Current workaround: compute entry takes a direct buffer pointer (`state: *Vector2`) instead of a param-struct pointer.

3. Compute SPIR-V backend had `thread_id` member-expression mismatch in 2D compute form.
- Error: `SPIR-V backend: unsupported member expression 'input.thread_id'`.
- Current workaround: use 1D dispatch (`thread_id.x`) and linear indexing.

4. Pair linking fails when stages use different addressing models.
- Error from `spirv-link`: `Conflicting addressing models: PhysicalStorageBuffer64 vs Logical`.
- Trigger: vertex stage with pointer-ABI root arg while fragment stage lowered to logical path.
- Workaround used: make fragment also take pointer-root arg.

5. Pair Metal output can have mismatched user varyings from separate stage codegen.
- Runtime error: fragment input `user(locn1)` mismatched vertex output.
- This shows stage-interface assignment is still brittle in merged-pair output.

## Next pass after RD is running

- Add minimal failing tests for each item above in transpiler headless suite.
- Fix in this order: (2) compute struct-pointer arg, (3) compute thread_id member expression, (1) uint division typing/op support, (5) stage varying location consistency, (4) addressing model policy unification for pairs.
