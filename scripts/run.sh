#!/usr/bin/env bash
# Rebuilds and launches Resize.app, replacing any running copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pkill -x Resize || true
APP="$("$ROOT/scripts/bundle.sh" "${1:-debug}")"
open "$APP"
