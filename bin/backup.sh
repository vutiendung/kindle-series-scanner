#!/bin/sh
# Kindle Series Scanner - Backup cc.db

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8  "==================================="
    eips 3 10 "  Backing up cc.db..."
    eips 3 12 "  To /mnt/us/kindle_db_backup"
    eips 3 14 "==================================="
fi

LUA_BIN="${LUA_BIN:-lua}"
"$LUA_BIN" src/main.lua backup --eips >> /tmp/kindle-series-scanner.log 2>&1

if command -v eips >/dev/null 2>&1; then
    eips 3 16 "  Database backup created!"
fi
