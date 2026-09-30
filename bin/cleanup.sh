#!/bin/sh
# Kindle Series Scanner - Cleanup empty series

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
    eips 3 10 "  Cleaning up empty series..."
fi

# Stop Content Catalog daemon before database update
stop com.lab126.ccat 2>/dev/null

"$LUA_BIN" src/main.lua cleanup --eips >> /mnt/us/kindle_series_scanner.log 2>&1

# Restart Content Catalog daemon and Kindle framework
start com.lab126.ccat 2>/dev/null

if command -v eips >/dev/null 2>&1; then
    eips 3 14 "  Cleanup complete! Restarting framework..."
fi

restart framework
