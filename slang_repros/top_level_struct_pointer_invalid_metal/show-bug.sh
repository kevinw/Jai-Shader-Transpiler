#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v slangc >/dev/null 2>&1; then
  echo "error: slangc not found in PATH"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found in PATH (macOS repro script)"
  exit 1
fi

OUT_DIR=".out"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

SRC="top_level_struct_pointer.slang"
METAL_OUT="$OUT_DIR/top_level_struct_pointer.metal"
METAL_ERR="$OUT_DIR/metal_errors.txt"

echo "=== slang -> metal ==="
slangc "$SRC" -target metal -line-directive-mode none -o "$METAL_OUT"

echo "--- key suspicious types in generated metal ---"
rg -n "device\\* device\\*|\\[\\[vertex\\]\\]|\\[\\[fragment\\]\\]" "$METAL_OUT" || true

echo "=== metal syntax check (expected failure) ==="
set +e
xcrun -sdk macosx metal -fsyntax-only -c "$METAL_OUT" 2>"$METAL_ERR"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "unexpected: metal syntax check succeeded"
  echo "generated file: $METAL_OUT"
  exit 1
fi

echo "metal failed as expected with exit code $status"
echo "--- diagnostic excerpt ---"
sed -n '1,80p' "$METAL_ERR"

echo
echo "Repro complete."
echo "Generated file: $METAL_OUT"
echo "Compiler errors: $METAL_ERR"

