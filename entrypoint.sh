#!/bin/bash
set -e

INSTALL_DIR="/server/install"
CONFIG_DIR="/server/config"
WORLD_DIR="/server/world"
TEMPLATE_DIR="/server/config-templates"
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-6}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
SERVER_PID=""
BACKUP_PID=""

# Graceful shutdown handler
shutdown_handler() {
    echo "=== Received shutdown signal ==="
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill -TERM "$SERVER_PID"
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -n "$BACKUP_PID" ] && kill -0 "$BACKUP_PID" 2>/dev/null; then
        kill "$BACKUP_PID" 2>/dev/null || true
    fi
    echo "=== Server stopped ==="
    exit 0
}
trap shutdown_handler SIGTERM SIGINT

# Auto-update server
if [ "$AUTO_UPDATE" = "true" ]; then
    echo "=== Auto-update enabled ==="
    /server/scripts/update-server.sh
else
    echo "=== Auto-update disabled ==="
    if [ ! -f "$INSTALL_DIR/DedicatedServer64/SpaceEngineersDedicated.exe" ]; then
        echo "Server not installed, running initial install..."
        /server/scripts/update-server.sh
    fi
fi

# Apply config template if no config exists
CONFIG_FILE="$CONFIG_DIR/SpaceEngineers-Dedicated.cfg"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "=== Applying default server configuration ==="

    # Build admin list XML
    ADMIN_XML=""
    if [ -n "$ADMIN_IDS" ]; then
        IFS=',' read -ra AIDS <<< "$ADMIN_IDS"
        for AID in "${AIDS[@]}"; do
            AID=$(echo "$AID" | tr -d ' ')
            ADMIN_XML="${ADMIN_XML}    <unsignedLong>${AID}</unsignedLong>\n"
        done
    fi

    # Build mods list XML
    MODS_XML=""
    if [ -n "$MODS" ]; then
        IFS=',' read -ra MIDS <<< "$MODS"
        for MID in "${MIDS[@]}"; do
            MID=$(echo "$MID" | tr -d ' ')
            MODS_XML="${MODS_XML}    <ModItem>\n      <Name>${MID}.sbm</Name>\n      <PublishedFileId>${MID}</PublishedFileId>\n    </ModItem>\n"
        done
    fi

    export SERVER_NAME="${SERVER_NAME:-Space Engineers Server}"
    export WORLD_NAME="${WORLD_NAME:-Star System}"
    export SERVER_PORT="${SERVER_PORT:-27016}"
    export ADMIN_XML
    export MODS_XML

    # Apply envsubst for simple vars, then inject admin/mods XML
    envsubst '${SERVER_NAME} ${WORLD_NAME} ${SERVER_PORT}' \
        < "$TEMPLATE_DIR/SpaceEngineers-Dedicated.cfg.template" \
        | sed "s|</Administrators>|${ADMIN_XML}</Administrators>|" \
        | sed "s|</Mods>|${MODS_XML}</Mods>|" \
        > "$CONFIG_FILE"

    echo "Config written to $CONFIG_FILE"
fi

# Download Workshop mods if MODS env var is set
if [ -n "$MODS" ]; then
    echo "=== Downloading Workshop mods ==="
    IFS=',' read -ra MOD_IDS <<< "$MODS"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID=$(echo "$MOD_ID" | tr -d ' ')
        echo "Downloading mod: $MOD_ID"
        /server/steamcmd/steamcmd.sh \
            +force_install_dir /server/mods \
            +login anonymous \
            +workshop_download_item 244850 "$MOD_ID" \
            +quit || echo "Warning: Failed to download mod $MOD_ID (may require auth)"
    done
    echo "=== Mod download complete ==="
fi

# Start background backup loop
backup_loop() {
    local interval=$((BACKUP_INTERVAL_HOURS * 3600))
    while true; do
        sleep "$interval"
        echo "=== Running scheduled backup ==="
        /server/scripts/backup.sh || echo "Warning: Backup failed"
    done
}
backup_loop &
BACKUP_PID=$!
echo "=== Backup loop started (every ${BACKUP_INTERVAL_HOURS}h, PID: $BACKUP_PID) ==="

# Find the server executable
SERVER_EXE="$INSTALL_DIR/DedicatedServer64/SpaceEngineersDedicated.exe"
if [ ! -f "$SERVER_EXE" ]; then
    echo "ERROR: Server executable not found at $SERVER_EXE"
    echo "Contents of $INSTALL_DIR:"
    ls -la "$INSTALL_DIR/" 2>/dev/null || echo "(empty)"
    exit 1
fi

# Launch Space Engineers Dedicated Server via Wine
echo "=== Starting Space Engineers Dedicated Server ==="
echo "Server Name: ${SERVER_NAME:-Space Engineers Server}"
echo "World Name: ${WORLD_NAME:-Star System}"
echo "Port: ${SERVER_PORT:-27016}/udp"

export WINEPREFIX=/home/steam/.wine
export WINEARCH=win64
export WINEDEBUG=-all

xvfb-run wine "$SERVER_EXE" \
    -console \
    -path "$CONFIG_DIR" &
SERVER_PID=$!

echo "=== Server started (PID: $SERVER_PID) ==="

# Wait for server process
wait "$SERVER_PID"
