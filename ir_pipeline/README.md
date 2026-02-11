# IR Pipeline Prototype (Slang Frontend)

This directory contains a parallel pipeline prototype for:

Jai -> IR -> Slang source -> target source

Current scope:
- Slang toolchain integration (direct target emission)
- Minimal Jai interface/body lowering to IR for a narrow vertex/fragment/compute subset
- Targets in scope: Metal + Vulkan GLSL (OpenGL is intentionally out of scope for this path)
- Fast headless IR compile tests
- No windowing/runtime rendering
- No SPIRV-Cross in the active IR path; Slang emits target source directly

Planned next steps:
1. Expand IR lowering from interface-only to function body lowering.
2. Add fragment and shader-pair IR lowering.
3. Expand type coverage and diagnostics for unsupported forms.
4. Add Vulkan GLSL checks to the same headless IR runner.

Current flag plumbing:
- `-slang_emit_line_directives` keeps Slang `#line` output enabled. Default is to omit line directives for cleaner generated Metal/GLSL source.
- Runtime behavior is partially switched:
  - Experimental IR path is enabled for a narrow safe subset (single-stage and paired Metal vertex/fragment shaders plus simple Metal compute shaders, with non-pointer/non-array interface types and simple body forms).
  - All other shaders fall back to the legacy backend path.

Fast loop:
- Run `/Users/kev/src/peel/modules/Jai-Shader-Transpiler/headless_ir/test_ir_headless.sh` for the focused greenfield IR path.
- This validates Jai -> IR -> Slang -> Metal for minimal headless vertex, fragment, and pair cases.
- Run `/Users/kev/src/peel/modules/Jai-Shader-Transpiler/headless_ir/test_ir_compute_semantics.sh` for a runtime compute semantics check (GPU result compared against CPU Jai reference with exact integer matching).
  - This script also asserts IR usage by checking the generated compute `.slang` file marker.
  - Current compute fixtures cover branching, `for`-loop lowering, and nested control flow with a second buffer.
