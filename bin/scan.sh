#!/bin/sh
# Kindle Series Scanner - Scan and Sync Action

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

if command -v lua >/dev/null 2>&1; then
    LUA_BIN="lua"
elif command -v luajit >/dev/null 2>&1; then
    LUA_BIN="luajit"
elif [ -f "/usr/bin/lua" ]; then
    LUA_BIN="/usr/bin/lua"
else
    LUA_BIN="lua"
fi

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8  "==================================="
    eips 3 10 "  Kindle Series Scanner"
    eips 3 12 "  Scanning library for series..."
    eips 3 14 "==================================="
fi

# Stop Content Catalog daemon before database update
stop com.lab126.ccat 2>/dev/null

"$LUA_BIN" src/main.lua scan --eips >> /tmp/kindle-series-scanner.log 2>&1

# Restart Content Catalog daemon and Kindle framework
start com.lab126.ccat 2>/dev/null

if command -v eips >/dev/null 2>&1; then
    eips 3 16 "  Scan complete! Restarting framework..."
fi

restart framework
