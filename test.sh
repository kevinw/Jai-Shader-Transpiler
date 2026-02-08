#!/usr/bin/env bash
set -euo pipefail
export MTL_DEBUG_LAYER=1
jai -quiet test_runner.jai +Autorun
