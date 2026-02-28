# IR / SPIR-V TODOs Found While Porting Terrain Meshing Compute

This file captures concrete IR/SPIR-V backend limitations that are still open.
Completed items were moved to `IR_DONE.md`.

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
