#!/bin/bash
set -e

# Ensure volume mount directories exist and fix ownership (Docker creates them as root)
mkdir -p /server/install /server/world /server/config /server/backups /server/mods /home/steam/Steam
chown -R steam:steam /server/install /server/world /server/config /server/backups /server/mods /home/steam/Steam

# Drop to steam user and run entrypoint
exec gosu steam /server/entrypoint.sh "$@"
