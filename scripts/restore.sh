#!/bin/bash
set -e

WORLD_DIR="${WORLD_DIR:-/server/world}"
BACKUP_DIR="${BACKUP_DIR:-/server/backups}"

# If no argument, list available backups
if [ -z "$1" ]; then
    echo "=== Available backups ==="
    if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR"/world_backup_*.tar.gz 2>/dev/null)" ]; then
        ls -lh "$BACKUP_DIR"/world_backup_*.tar.gz | awk '{print $NF, $5}'
    else
        echo "No backups found in $BACKUP_DIR"
    fi
    echo ""
    echo "Usage: $0 <backup_filename>"
    echo "Example: $0 world_backup_20250101_120000.tar.gz"
    exit 0
fi

# Reject absolute paths or path traversal in the argument
if [[ "$1" == /* ]] || [[ "$1" == *..* ]]; then
    echo "Error: Invalid backup filename (must not contain absolute paths or '..')"
    exit 1
fi

RESOLVED_BACKUP_DIR="$(realpath "$BACKUP_DIR")"
BACKUP_FILE="$(realpath -m "$BACKUP_DIR/$1")"
if [[ "$BACKUP_FILE" != "$RESOLVED_BACKUP_DIR/"* ]]; then
    echo "Error: Invalid backup path (must be within $BACKUP_DIR)"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Check if the server is running
if pgrep -f SpaceEngineersDedicated.exe > /dev/null 2>&1; then
    echo "Error: The server is still running. Stop it first with 'docker compose stop'."
    exit 1
fi

echo "=== Restoring from: $BACKUP_FILE ==="
echo "WARNING: This will overwrite the current world data."

# Clear existing world data
rm -rf "${WORLD_DIR:?}"/*

# Extract backup
tar -xzf "$BACKUP_FILE" -C "$WORLD_DIR"

echo "=== Restore complete ==="
echo "Start the server to use the restored world."
