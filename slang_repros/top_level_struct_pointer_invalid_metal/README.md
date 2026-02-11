# Slang Repro: Top-Level Struct Pointer Params Emit Invalid Metal

This repro demonstrates that top-level graphics entry parameters of type `Struct*` (where the struct contains resource fields) can lower to invalid Metal pointer types.

Observed invalid output pattern:

- Emitted entry parameters like:
  - `float device* device* ...`
- Metal compile errors:
  - `invalid type 'device float *device *' for buffer declaration`

## Run

```bash
./show-bug.sh
```

The script:
1. Compiles the Slang file to Metal.
2. Runs `xcrun metal -fsyntax-only` on emitted output.
3. Prints the key failing lines and diagnostic.

