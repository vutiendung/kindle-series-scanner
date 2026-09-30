#!/bin/sh
# Reset and delete ALL series from Kindle cc.db (Clean Slate)
EXT_DIR="/mnt/us/extensions/kindle-series-scanner"

if [ ! -d "$EXT_DIR" ]; then
    EXT_DIR="$(dirname "$(dirname "$0")")"
fi

cd "$EXT_DIR" || exit 1

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8 "  Kindle Series Scanner"
    eips 3 10 "  Resetting all series..."
fi

lua src/main.lua clean-all --eips

if command -v eips >/dev/null 2>&1; then
    eips 3 12 "  All series deleted!"
    eips 3 14 "  Restarting framework..."
    sleep 1
fi

restart framework
