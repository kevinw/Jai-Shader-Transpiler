#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"/..
jai -quiet headless_ir/build_ir_headless.jai -
