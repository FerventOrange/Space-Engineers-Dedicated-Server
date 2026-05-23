#!/bin/bash
set -e

STEAMCMD_DIR="/server/steamcmd"
INSTALL_DIR="/server/install"
APP_ID=298740

if [ -z "$STEAM_USER" ] || [ -z "$STEAM_PASS" ]; then
    echo "ERROR: STEAM_USER and STEAM_PASS are required (App 298740 does not support anonymous login)"
    exit 1
fi

echo "=== Updating Space Engineers Dedicated Server (App ID: $APP_ID) ==="

"$STEAMCMD_DIR/steamcmd.sh" \
    +force_install_dir "$INSTALL_DIR" \
    +login "$STEAM_USER" "$STEAM_PASS" \
    +app_update "$APP_ID" validate \
    +quit

echo "=== Server update complete ==="
