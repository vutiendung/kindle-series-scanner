#!/bin/sh
# Kindle Series Scanner - Diagnose cc.db

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

LUA_BIN="${LUA_BIN:-lua}"
"$LUA_BIN" src/main.lua diagnose
