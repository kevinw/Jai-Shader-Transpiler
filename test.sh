#!/usr/bin/env bash
set -euo pipefail
jai -quiet build.jai - -output_shaders -run_tests
