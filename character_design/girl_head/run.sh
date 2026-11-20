#!/usr/bin/env bash
# Interactive studio for the procedural android girl head.
set -euo pipefail
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:10}"
godot --path . "$@"