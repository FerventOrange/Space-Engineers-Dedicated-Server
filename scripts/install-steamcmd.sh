#!/bin/bash
set -e

STEAMCMD_DIR="/server/steamcmd"

echo "=== Installing SteamCMD ==="

mkdir -p "$STEAMCMD_DIR"
cd "$STEAMCMD_DIR"

curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xzf -

echo "=== Running initial SteamCMD update ==="
./steamcmd.sh +quit || true

echo "=== SteamCMD installed ==="
