#!/usr/bin/env bash
set -euo pipefail
export MTL_LOG_TO_STDERR=1
export MTL_DEBUG_LAYER=1
export MTL_LOG_LEVEL=MTLLogLevelDebug
export MTL_LOG_BUFFER_SIZE=2048
jai -quiet test_runner.jai +Autorun
