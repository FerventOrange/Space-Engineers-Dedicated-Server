#!/bin/bash
set -e

# Ensure volume mount directories exist and fix ownership (Docker creates them as root)
mkdir -p /server/install /server/world /server/config /server/backups /server/mods /home/steam/Steam

# Non-recursive chown on all top-level dirs (fast, always needed)
chown steam:steam /server/install /server/world /server/config /server/backups /server/mods /home/steam/Steam

# Recursive chown only on small config/data dirs
chown -R steam:steam /server/config /server/backups /server/mods

# Recursive chown on large dirs only if empty (first run)
if [ -z "$(ls -A /server/install 2>/dev/null)" ]; then
    chown -R steam:steam /server/install
fi
if [ -z "$(ls -A /home/steam/Steam 2>/dev/null)" ]; then
    chown -R steam:steam /home/steam/Steam
fi

# Drop to steam user and run entrypoint
exec gosu steam /server/entrypoint.sh "$@"
