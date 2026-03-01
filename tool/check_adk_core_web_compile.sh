#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[adk_core] running web compile smoke..."
dart compile js tool/smoke/adk_core_web_smoke.dart -o /tmp/adk_core_smoke.js

echo "[adk_core] web compile smoke passed."
