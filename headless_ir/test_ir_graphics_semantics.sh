#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
jai -quiet ${SCRIPT_DIR}/build_ir_graphics_semantics.jai -
