#!/usr/bin/env bash
set -euo pipefail
jai -quiet headless_ir/build_ir_compute_semantics.jai - -use_ir_pipeline -use_spirv_backend -use_direct_spirv_text
