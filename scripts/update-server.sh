#!/bin/bash
set -e

STEAMCMD_DIR="/server/steamcmd"
INSTALL_DIR="/server/install"
APP_ID=298740

echo "=== Updating Space Engineers Dedicated Server (App ID: $APP_ID) ==="

"$STEAMCMD_DIR/steamcmd.sh" \
    +force_install_dir "$INSTALL_DIR" \
    +login anonymous \
    +app_update "$APP_ID" validate \
    +quit

echo "=== Server update complete ==="
