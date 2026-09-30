#!/bin/sh
# Kindle Series Scanner - Restore cc.db

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8  "==================================="
    eips 3 10 "  Restoring cc.db..."
    eips 3 12 "  From /mnt/us/kindle_db_backup"
    eips 3 14 "==================================="
fi

LUA_BIN="${LUA_BIN:-lua}"
"$LUA_BIN" src/main.lua restore --eips >> /tmp/kindle-series-scanner.log 2>&1

if command -v eips >/dev/null 2>&1; then
    eips 3 16 "  Database restored! Restarting framework..."
fi

# Restart framework to reload cc.db into Kindle UI
restart framework
