# SPIR-V Backend Prototype

This directory contains the initial SPIR-V backend prototype:

- Compute-only scope (single canonical branch shader first)
- Plugin path: `get_transpiled(.METAL/.VULKAN_GLSL, ...)`
- Toolchain: `IR -> Slang SPIR-V emit -> spirv-val -> spirv-cross`
- Target checks:
  - Metal output compiles with `xcrun metal`
  - Vulkan GLSL output compiles with `glslangValidator`
  - Metal compute runtime output matches CPU reference for 64 elements

## Fast loop

```bash
/Users/kev/src/peel/modules/Jai-Shader-Transpiler/spirv_backend/test_spirv_compute_branch.sh
```

## Notes

- This is intentionally a small-surface bootstrap for compute.
- First case mirrors `compute_semantics_shader` behavior.
