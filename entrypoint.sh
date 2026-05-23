#!/bin/bash

INSTALL_DIR="/server/install"
CONFIG_DIR="/server/config"
WORLD_DIR="/server/world"
TEMPLATE_DIR="/server/config-templates"
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-6}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
SERVER_PID=""
BACKUP_PID=""

# --- Input validation ---
validate_numeric_list() {
    local name="$1" value="$2"
    if [ -n "$value" ]; then
        IFS=',' read -ra ITEMS <<< "$value"
        for ITEM in "${ITEMS[@]}"; do
            ITEM=$(echo "$ITEM" | tr -d ' ')
            if ! [[ "$ITEM" =~ ^[0-9]+$ ]]; then
                echo "ERROR: $name contains non-numeric value: $ITEM"
                exit 1
            fi
        done
    fi
}

validate_numeric_list "ADMIN_IDS" "$ADMIN_IDS"
validate_numeric_list "MODS" "$MODS"

if ! [[ "$BACKUP_INTERVAL_HOURS" =~ ^[0-9]+$ ]] || [ "$BACKUP_INTERVAL_HOURS" -eq 0 ]; then
    echo "ERROR: BACKUP_INTERVAL_HOURS must be a positive integer, got: $BACKUP_INTERVAL_HOURS"
    exit 1
fi

export SERVER_PORT="${SERVER_PORT:-27016}"
if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    echo "ERROR: SERVER_PORT must be a valid port number (1-65535), got: $SERVER_PORT"
    exit 1
fi

export MAX_BACKUP_SAVES="${MAX_BACKUP_SAVES:-5}"
if ! [[ "$MAX_BACKUP_SAVES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: MAX_BACKUP_SAVES must be a non-negative integer, got: $MAX_BACKUP_SAVES"
    exit 1
fi

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
    /server/scripts/update-server.sh || { echo "ERROR: Server update failed"; exit 1; }
else
    echo "=== Auto-update disabled ==="
    if [ ! -f "$INSTALL_DIR/DedicatedServer64/SpaceEngineersDedicated.exe" ]; then
        echo "Server not installed, running initial install..."
        /server/scripts/update-server.sh || { echo "ERROR: Server install failed"; exit 1; }
    fi
fi

# Apply config template if no config exists
CONFIG_FILE="$CONFIG_DIR/SpaceEngineers-Dedicated.cfg"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "=== Applying default server configuration ==="

    # Build admin list XML (using real newlines, not \n literals)
    ADMIN_XML=""
    if [ -n "$ADMIN_IDS" ]; then
        IFS=',' read -ra AIDS <<< "$ADMIN_IDS"
        for AID in "${AIDS[@]}"; do
            AID=$(echo "$AID" | tr -d ' ')
            printf -v ADMIN_XML '%s    <unsignedLong>%s</unsignedLong>\n' "$ADMIN_XML" "$AID"
        done
    fi

    # Build mods list XML (using real newlines, not \n literals)
    MODS_XML=""
    if [ -n "$MODS" ]; then
        IFS=',' read -ra MIDS <<< "$MODS"
        for MID in "${MIDS[@]}"; do
            MID=$(echo "$MID" | tr -d ' ')
            printf -v MODS_XML '%s    <ModItem>\n      <Name>%s.sbm</Name>\n      <PublishedFileId>%s</PublishedFileId>\n    </ModItem>\n' "$MODS_XML" "$MID" "$MID"
        done
    fi

    export SERVER_NAME="${SERVER_NAME:-Space Engineers Server}"
    export WORLD_NAME="${WORLD_NAME:-Star System}"
    export MAX_BACKUP_SAVES="${MAX_BACKUP_SAVES:-5}"

    # Apply envsubst for simple vars, write to temp file
    TMP_CONFIG=$(mktemp)
    envsubst '${SERVER_NAME} ${WORLD_NAME} ${SERVER_PORT} ${MAX_BACKUP_SAVES}' \
        < "$TEMPLATE_DIR/SpaceEngineers-Dedicated.cfg.template" \
        > "$TMP_CONFIG"

    # Inject admin IDs using awk (safe for multi-line content)
    if [ -n "$ADMIN_XML" ]; then
        awk -v xml="$ADMIN_XML" '{sub(/<!-- ADMIN_IDS_PLACEHOLDER -->/, xml)}1' \
            "$TMP_CONFIG" > "${TMP_CONFIG}.tmp" && mv "${TMP_CONFIG}.tmp" "$TMP_CONFIG"
    else
        grep -v '<!-- ADMIN_IDS_PLACEHOLDER -->' "$TMP_CONFIG" > "${TMP_CONFIG}.tmp" \
            && mv "${TMP_CONFIG}.tmp" "$TMP_CONFIG"
    fi

    # Inject mod items using awk (safe for multi-line content)
    if [ -n "$MODS_XML" ]; then
        awk -v xml="$MODS_XML" '{sub(/<!-- MODS_PLACEHOLDER -->/, xml)}1' \
            "$TMP_CONFIG" > "${TMP_CONFIG}.tmp" && mv "${TMP_CONFIG}.tmp" "$TMP_CONFIG"
    else
        grep -v '<!-- MODS_PLACEHOLDER -->' "$TMP_CONFIG" > "${TMP_CONFIG}.tmp" \
            && mv "${TMP_CONFIG}.tmp" "$TMP_CONFIG"
    fi

    mv "$TMP_CONFIG" "$CONFIG_FILE"
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
            +login "$STEAM_USER" "$STEAM_PASS" \
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
echo "Port: ${SERVER_PORT}/udp"

export WINEPREFIX=/home/steam/.wine
export WINEARCH=win64
export WINEDEBUG=-all

# Convert Linux path to Windows path for Wine
WIN_CONFIG_DIR=$(winepath -w "$CONFIG_DIR" 2>/dev/null || echo 'Z:\server\config')

xvfb-run wine "$SERVER_EXE" \
    -console \
    -path "$WIN_CONFIG_DIR" &
SERVER_PID=$!

echo "=== Server started (PID: $SERVER_PID) ==="

# Wait for server process (|| true prevents script exit on non-zero return)
wait "$SERVER_PID" || true
EXIT_CODE=$?

# Clean up backup loop
if [ -n "$BACKUP_PID" ] && kill -0 "$BACKUP_PID" 2>/dev/null; then
    kill "$BACKUP_PID" 2>/dev/null || true
fi

echo "=== Server exited with code: $EXIT_CODE ==="
