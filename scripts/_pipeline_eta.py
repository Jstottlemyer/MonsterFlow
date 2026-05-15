#!/usr/bin/env python3
"""
_pipeline_eta.py — pipeline ETA helper (v0.14 fallback-only)

CLI contract:
  python3 scripts/_pipeline_eta.py --gate <name> [--feature <slug>]

Returns hardcoded default ETA in seconds on stdout.
Exit 0 always.

v0.14: hardcoded defaults only. No real-data / rankings-history code path.
Real-data ETA is a v0.15 BACKLOG item (pipeline-eta-from-timing-data).
"""

import argparse
import sys

# Hardcoded defaults (seconds). v0.14 ships only this table.
_DEFAULTS = {
    "spec": 480,         # ~8 min
    "spec-review": 360,  # ~6 min
    "blueprint": 180,    # ~3 min
    "check": 300,        # ~5 min
    "build": 900,        # ~15 min
}

_UNKNOWN_FALLBACK = 300  # median, per spec


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Return ETA in seconds for a pipeline gate.",
        add_help=True,
    )
    parser.add_argument(
        "--gate",
        required=True,
        help="Gate name (spec, spec-review, blueprint, check, build)",
    )
    parser.add_argument(
        "--feature",
        default=None,
        help="Feature slug (accepted but unused in v0.14; real-data ETA is v0.15)",
    )
    args = parser.parse_args()

    eta = _DEFAULTS.get(args.gate, _UNKNOWN_FALLBACK)
    print(eta)
    sys.exit(0)


if __name__ == "__main__":
    main()
