#!/bin/bash
set -eo pipefail

INSTALL_DIR="/server/install"
CONFIG_DIR="/server/config"
WORLD_DIR="${WORLD_DIR:-/server/world}"
TEMPLATE_DIR="/server/config-templates"
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-6}"
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
SERVER_PID=""
BACKUP_PID=""

# --- Cleanup tracking ---
CLEANUP_FILES=()
cleanup() {
    for f in "${CLEANUP_FILES[@]}"; do
        rm -f "$f"
    done
}
trap cleanup EXIT

# --- Helper functions ---
validate_positive_integer() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -eq 0 ]; then
        echo "ERROR: $name must be a positive integer, got: $value"
        exit 1
    fi
}

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

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    echo "$s"
}

# --- Input validation ---
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

export MAX_BACKUP_SAVES="${MAX_BACKUP_SAVES:-28}"
if ! [[ "$MAX_BACKUP_SAVES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: MAX_BACKUP_SAVES must be a non-negative integer, got: $MAX_BACKUP_SAVES"
    exit 1
fi

BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
validate_positive_integer "BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_DAYS"

# Validate multipliers
export INVENTORY_SIZE_MULTIPLIER="${INVENTORY_SIZE_MULTIPLIER:-10}"
export BLOCKS_INVENTORY_SIZE_MULTIPLIER="${BLOCKS_INVENTORY_SIZE_MULTIPLIER:-10}"
export ASSEMBLER_SPEED_MULTIPLIER="${ASSEMBLER_SPEED_MULTIPLIER:-10}"
export ASSEMBLER_EFFICIENCY_MULTIPLIER="${ASSEMBLER_EFFICIENCY_MULTIPLIER:-10}"
export REFINERY_SPEED_MULTIPLIER="${REFINERY_SPEED_MULTIPLIER:-10}"
export WELDER_SPEED_MULTIPLIER="${WELDER_SPEED_MULTIPLIER:-5}"
export GRINDER_SPEED_MULTIPLIER="${GRINDER_SPEED_MULTIPLIER:-5}"
export HARVEST_RATIO_MULTIPLIER="${HARVEST_RATIO_MULTIPLIER:-5}"

validate_positive_integer "INVENTORY_SIZE_MULTIPLIER" "$INVENTORY_SIZE_MULTIPLIER"
validate_positive_integer "BLOCKS_INVENTORY_SIZE_MULTIPLIER" "$BLOCKS_INVENTORY_SIZE_MULTIPLIER"
validate_positive_integer "ASSEMBLER_SPEED_MULTIPLIER" "$ASSEMBLER_SPEED_MULTIPLIER"
validate_positive_integer "ASSEMBLER_EFFICIENCY_MULTIPLIER" "$ASSEMBLER_EFFICIENCY_MULTIPLIER"
validate_positive_integer "REFINERY_SPEED_MULTIPLIER" "$REFINERY_SPEED_MULTIPLIER"
validate_positive_integer "WELDER_SPEED_MULTIPLIER" "$WELDER_SPEED_MULTIPLIER"
validate_positive_integer "GRINDER_SPEED_MULTIPLIER" "$GRINDER_SPEED_MULTIPLIER"
validate_positive_integer "HARVEST_RATIO_MULTIPLIER" "$HARVEST_RATIO_MULTIPLIER"

# Graceful shutdown handler
shutdown_handler() {
    echo "=== Received shutdown signal ==="
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Stopping server process group (PID: $SERVER_PID)..."
        # Kill the entire process group (xvfb-run + wine + SE server)
        kill -TERM -- -"$SERVER_PID" 2>/dev/null || kill -TERM "$SERVER_PID" 2>/dev/null
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

    # XML-escape user-facing strings before template substitution
    export SERVER_NAME
    SERVER_NAME="$(xml_escape "${SERVER_NAME:-Space Engineers Server}")"
    export WORLD_NAME
    WORLD_NAME="${WORLD_NAME:-Star System}"
    if [[ "$WORLD_NAME" =~ [^a-zA-Z0-9\ _.-] ]]; then
        echo "WARNING: WORLD_NAME contains characters that may cause path issues: $WORLD_NAME"
    fi
    WORLD_NAME="$(xml_escape "$WORLD_NAME")"

    # Apply envsubst for simple vars, write to temp file
    TMP_CONFIG=$(mktemp)
    CLEANUP_FILES+=("$TMP_CONFIG" "${TMP_CONFIG}.tmp")
    envsubst '${SERVER_NAME} ${WORLD_NAME} ${SERVER_PORT} ${MAX_BACKUP_SAVES} ${INVENTORY_SIZE_MULTIPLIER} ${BLOCKS_INVENTORY_SIZE_MULTIPLIER} ${ASSEMBLER_SPEED_MULTIPLIER} ${ASSEMBLER_EFFICIENCY_MULTIPLIER} ${REFINERY_SPEED_MULTIPLIER} ${WELDER_SPEED_MULTIPLIER} ${GRINDER_SPEED_MULTIPLIER} ${HARVEST_RATIO_MULTIPLIER}' \
        < "$TEMPLATE_DIR/SpaceEngineers-Dedicated.cfg.template" \
        > "$TMP_CONFIG"

    # Inject admin IDs using sed with temp file (avoids awk special-character issues)
    if [ -n "$ADMIN_XML" ]; then
        ADMIN_TMP=$(mktemp)
        CLEANUP_FILES+=("$ADMIN_TMP")
        printf '%s' "$ADMIN_XML" > "$ADMIN_TMP"
        sed -i "/<!-- ADMIN_IDS_PLACEHOLDER -->/{ r $ADMIN_TMP
d }" "$TMP_CONFIG"
    else
        sed -i '/<!-- ADMIN_IDS_PLACEHOLDER -->/d' "$TMP_CONFIG"
    fi

    # Inject mod items using sed with temp file
    if [ -n "$MODS_XML" ]; then
        MODS_TMP=$(mktemp)
        CLEANUP_FILES+=("$MODS_TMP")
        printf '%s' "$MODS_XML" > "$MODS_TMP"
        sed -i "/<!-- MODS_PLACEHOLDER -->/{ r $MODS_TMP
d }" "$TMP_CONFIG"
    else
        sed -i '/<!-- MODS_PLACEHOLDER -->/d' "$TMP_CONFIG"
    fi

    mv "$TMP_CONFIG" "$CONFIG_FILE"
    echo "Config written to $CONFIG_FILE"
fi

# Download Workshop mods if MODS env var is set (single SteamCMD session via runscript)
if [ -n "$MODS" ]; then
    echo "=== Downloading Workshop mods ==="
    IFS=',' read -ra MOD_IDS <<< "$MODS"

    # Build SteamCMD runscript to avoid exposing credentials on command line
    STEAM_SCRIPT=$(mktemp)
    CLEANUP_FILES+=("$STEAM_SCRIPT")
    chmod 600 "$STEAM_SCRIPT"
    {
        echo "force_install_dir /home/steam/Steam"
        echo "login $STEAM_USER $STEAM_PASS"
        for MOD_ID in "${MOD_IDS[@]}"; do
            MOD_ID=$(echo "$MOD_ID" | tr -d ' ')
            echo "  - Mod: $MOD_ID" >&2
            echo "workshop_download_item 244850 $MOD_ID"
        done
        echo "quit"
    } > "$STEAM_SCRIPT"

    /server/steamcmd/steamcmd.sh +runscript "$STEAM_SCRIPT" || echo "Warning: Some mods may have failed to download"
    rm -f "$STEAM_SCRIPT"

    echo "=== Mod download complete ==="
fi

# Start background backup loop (if enabled)
if [ "$BACKUP_ENABLED" = "true" ]; then
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
else
    echo "=== Backups disabled ==="
fi

# Redirect SE saves to the world volume
# SE saves to {-path}/Saves/{WorldName}/ — symlink Saves -> world volume
if [ ! -L "$CONFIG_DIR/Saves" ]; then
    rm -rf "$CONFIG_DIR/Saves"
    ln -sfn "$WORLD_DIR" "$CONFIG_DIR/Saves"
fi

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

# Enable job control so backgrounded process becomes process group leader
set -m
xvfb-run wine "$SERVER_EXE" \
    -console \
    -path "$WIN_CONFIG_DIR" &
SERVER_PID=$!

echo "=== Server started (PID: $SERVER_PID) ==="

# Wait for server process and capture real exit code
set +e
wait "$SERVER_PID"
EXIT_CODE=$?
set -e

# Clean up backup loop
if [ -n "$BACKUP_PID" ] && kill -0 "$BACKUP_PID" 2>/dev/null; then
    kill "$BACKUP_PID" 2>/dev/null || true
fi

echo "=== Server exited with code: $EXIT_CODE ==="
