# Slang Repro: Graphics Params Lowered Through Uninitialized `KernelContext`

This repro demonstrates a problematic Metal lowering pattern for graphics entry points that take either:

- `ParameterBlock<Params>`
- `Params*`

Both cases produce a wrapper `[[vertex]] VertexMain(...)` that does not expose resource parameters, while an internal `KernelContext_*` is created and passed to the lowered implementation.

The lowered implementation reads through pointers in `KernelContext_*`, but the wrapper never initializes them.

## Run

```bash
./show-bug.sh
```

## What to look for

In generated `.metal`:

1. A `struct KernelContext_*` containing resource pointers.
2. A lowered `VertexMain_0(..., KernelContext_* thread* ...)`.
3. A wrapper `[[vertex]] VertexMain(...)` with only builtin vertex inputs (no resource params).
4. A local `thread KernelContext_* kernelContext_*;` passed to `VertexMain_0(...)` without initialization.

