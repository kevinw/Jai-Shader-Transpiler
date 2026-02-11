# IR TODO

## Goal
Track missing/partial IR lowering coverage needed for reliable Jai -> IR -> Slang -> Metal/Vulkan behavior.

## Status Legend
- `todo`: not implemented
- `partial`: implemented for a narrow subset
- `done`: covered by lowering + tests

## Compute
- `done` Basic declarations/assignments.
- `done` `if/else` control flow.
- `done` `for` loops (including reverse flag path in lowering).
- `done` Multi-buffer pointer args (`RWStructuredBuffer<T>` mapping).
- `done` Runtime semantics tests (branching, loops, nested control flow + second buffer).
- `done` Basic cast expressions (`cast(...)`) lowering in expression emission.
- `todo` Broader cast coverage (compound/nested casts and edge type forms).
- `done` Basic helper-function call dependencies (called compute helpers emitted ahead of `ComputeMain`).
- `todo` Helper-function coverage expansion (recursive/nested helper graphs, wider type coverage).
- `todo` More statement kinds (`while`, `switch/case`, break/continue behavior tests).
- `todo` Robust integer type-cast behavior across signed/unsigned paths.
- `done` Bitwise operator coverage in IR expression lowering (`^`, `&`, `|`, shifts) with runtime semantics test.

## Vertex/Fragment
- `done` Basic interface lowering (input/output structs + semantics).
- `done` Basic output assignments from body.
- `done` Pair emission to single Metal source.
- `partial` Local data-flow (supports simple expression chains, not full dependency/liveness model).
- `todo` Function-call lowering for body expressions.
- `todo` Struct literal edge cases (named/positional mixed forms in more paths).
- `todo` Matrix/vector operation breadth (swizzles, matrix constructors/mults, builtins).
- `todo` More robust uniform/local variable handling for complex shaders.
- `todo` Shared helper/function prototype emission strategy across stages (Jai order-independence vs C-like declaration order).

## Semantics Mapping
- `done` Vertex/fragment basics in current tests.
- `done` Compute thread builtin mapping (`thread_position_in_grid` -> `SV_DispatchThreadID`).
- `todo` Additional compute builtins in runtime tests (`group/threadgroup` variants).
- `todo` Extended stage semantic compatibility checks in tests.

## Diagnostics / Negative Tests
- `todo` Explicit failing tests for unsupported constructs (with clear diagnostics).
- `todo` `#overlay` negative tests in IR path.
- `todo` Pointer/array unsupported-form diagnostics where fallback should happen.

## Pipeline / Infrastructure
- `done` Fast headless IR compile tests.
- `done` Fast headless compute runtime semantics tests.
- `todo` Expand IR-path gating to be capability-driven per feature rather than broad subset text.
- `todo` Vulkan GLSL IR runtime equivalence harness (after Metal path matures).
