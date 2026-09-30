#!/bin/sh
# Display the latest dry-run/scan log on Kindle e-ink screen

LOG="/tmp/kindle-series-scanner.log"
if [ ! -f "$LOG" ] && [ -f "/mnt/us/kindle_series_scanner.log" ]; then
    LOG="/mnt/us/kindle_series_scanner.log"
fi

if command -v eips >/dev/null 2>&1; then
    eips -c
    eips 1 1 "=== Kindle Series Scanner Log ==="
    
    if [ ! -f "$LOG" ]; then
        eips 1 3 "No log file found yet."
        exit 0
    fi

    # Display last 20 lines
    LINE_NUM=3
    tail -n 20 "$LOG" | while IFS= read -r line; do
        # Truncate line to 50 chars for eips display
        short_line=$(echo "$line" | cut -c1-50)
        eips 1 "$LINE_NUM" "$short_line"
        LINE_NUM=$((LINE_NUM + 1))
        if [ "$LINE_NUM" -gt 38 ]; then
            break
        fi
    done
else
    if [ -f "$LOG" ]; then
        tail -n 30 "$LOG"
    else
        echo "No log file found."
    fi
fi
