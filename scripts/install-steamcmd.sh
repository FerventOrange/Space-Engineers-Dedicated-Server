#!/bin/bash
set -e

STEAMCMD_DIR="/server/steamcmd"

echo "=== Installing SteamCMD ==="

mkdir -p "$STEAMCMD_DIR"
cd "$STEAMCMD_DIR"

# Download to file first, then verify integrity before extraction.
# Checksum pinning is not feasible because Valve auto-updates the tarball
# without versioning, so the hash changes without notice.
TARBALL="steamcmd_linux.tar.gz"
curl -fsSL -o "$TARBALL" https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

if ! gzip -t "$TARBALL"; then
    echo "ERROR: Downloaded SteamCMD archive is corrupt"
    rm -f "$TARBALL"
    exit 1
fi

tar xzf "$TARBALL"
rm -f "$TARBALL"

echo "=== Running initial SteamCMD update ==="
./steamcmd.sh +quit || true

echo "=== SteamCMD installed ==="
