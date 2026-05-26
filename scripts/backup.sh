#!/bin/bash
set -e

WORLD_DIR="/server/world"
BACKUP_DIR="/server/backups"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/world_backup_${TIMESTAMP}.tar.gz"

if [ ! -d "$WORLD_DIR" ] || [ -z "$(ls -A "$WORLD_DIR" 2>/dev/null)" ]; then
    echo "No world data found in $WORLD_DIR, skipping backup."
    exit 0
fi

mkdir -p "$BACKUP_DIR"

echo "=== Creating backup: $BACKUP_FILE ==="
tar -czf "$BACKUP_FILE" -C "$WORLD_DIR" .
echo "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

# Clean up old backups
echo "=== Removing backups older than ${RETENTION_DAYS} days ==="
find "$BACKUP_DIR" -maxdepth 1 -name "world_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete -print
echo "=== Backup complete ==="
