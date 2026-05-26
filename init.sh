#!/bin/bash
# Fix volume mount ownership (Docker creates them as root)
chown -R steam:steam /server/install /server/world /server/config /server/backups /server/mods /home/steam/Steam

# Drop to steam user and run entrypoint
exec gosu steam /server/entrypoint.sh "$@"
