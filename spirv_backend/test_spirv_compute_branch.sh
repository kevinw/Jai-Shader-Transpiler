#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
jai -quiet spirv_backend/build_spirv_compute_branch.jai - -norun
