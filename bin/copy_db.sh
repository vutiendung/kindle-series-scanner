#!/bin/sh
# Force copy /var/local/cc.db to /mnt/us/cc.db (accessible via USB)
EXT_DIR="/mnt/us/extensions/kindle-series-scanner"

if [ ! -d "$EXT_DIR" ]; then
    EXT_DIR="$(dirname "$(dirname "$0")")"
fi

cd "$EXT_DIR" || exit 1

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 3 8 "  Kindle Series Scanner"
    eips 3 10 "  Copying cc.db to /mnt/us..."
fi

# Force copy cc.db to /mnt/us/cc.db and sync disk
cp -f /var/local/cc.db /mnt/us/cc.db 2>/dev/null
sync

if [ -f "/mnt/us/cc.db" ]; then
    if command -v eips >/dev/null 2>&1; then
        eips 3 12 "  Success! Saved to:"
        eips 3 14 "  /mnt/us/cc.db"
    fi
    echo "[INFO] Successfully copied /var/local/cc.db to /mnt/us/cc.db"
else
    # Fallback via Lua CLI
    lua src/main.lua export --eips
fi

sleep 2
