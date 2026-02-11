#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v slangc >/dev/null 2>&1; then
  echo "error: slangc not found in PATH"
  exit 1
fi

OUT_DIR=".out"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

compile_one() {
  local src="$1"
  local base="${src%.slang}"
  local out="$OUT_DIR/$base.metal"

  echo "=== compiling $src ==="
  slangc "$src" \
    -entry VertexMain \
    -stage vertex \
    -target metal \
    -line-directive-mode none \
    -o "$out"

  echo "--- key lines ($out) ---"
  rg -n "struct KernelContext_|VertexMain_0\\(|\\[\\[vertex\\]\\]|thread KernelContext_" "$out" || true

  echo "--- top of file ($out) ---"
  sed -n '1,140p' "$out"
  echo
}

compile_one "paramblock_vertex.slang"
compile_one "pointer_vertex.slang"

echo "Repro complete. Inspect generated files in $OUT_DIR/."
echo "Bug signature: wrapper [[vertex]] entry has no resource params, but passes an uninitialized KernelContext_*."

