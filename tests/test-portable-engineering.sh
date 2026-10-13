#!/usr/bin/env bash
# Deterministic portable package checks. Bash 3.2 compatible.
BASH=/bin/bash
set -eu
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 -c 'import sys, yaml; assert sys.version_info >= (3, 9)' || {
  echo 'FAIL: Python 3.9+ and PyYAML are required; no dependency installation attempted.' >&2
  exit 1
}
python3 -m unittest discover -s "$ENGINE_DIR/modules/engineering/tests" -p 'test_*.py' -v
