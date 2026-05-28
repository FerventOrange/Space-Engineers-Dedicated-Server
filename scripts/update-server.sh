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

# Let SteamCMD self-update first so it doesn't restart mid-login
echo "--- Checking for SteamCMD updates ---"
"$STEAMCMD_DIR/steamcmd.sh" +quit || true

echo "--- Downloading/updating SE server ---"

# Use runscript to avoid exposing credentials on the command line
STEAM_SCRIPT=$(mktemp)
chmod 600 "$STEAM_SCRIPT"
cat > "$STEAM_SCRIPT" <<SCRIPT
@sSteamCmdForcePlatformType windows
force_install_dir $INSTALL_DIR
login $STEAM_USER $STEAM_PASS
app_update $APP_ID validate
quit
SCRIPT

"$STEAMCMD_DIR/steamcmd.sh" +runscript "$STEAM_SCRIPT"
rm -f "$STEAM_SCRIPT"

echo "=== Server update complete ==="
