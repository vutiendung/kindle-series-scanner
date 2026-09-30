#!/bin/sh
# Kindle Series Scanner - Dry Run Preview

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8  "==================================="
    eips 3 10 "  Kindle Series Scanner"
    eips 3 12 "  Running Preview (Dry Run)..."
    eips 3 14 "==================================="
fi

LUA_BIN="${LUA_BIN:-lua}"
"$LUA_BIN" src/main.lua dry-run --eips >> /tmp/kindle-series-scanner.log 2>&1

if command -v eips >/dev/null 2>&1; then
    eips 3 16 "  Preview done. See log file."
fi
