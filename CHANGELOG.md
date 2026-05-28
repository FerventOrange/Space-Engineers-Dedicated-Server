# Changelog

All notable changes to the Space Engineers Dedicated Server Docker project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Dockerfile with Wine, SteamCMD, and .NET Framework on Debian Bookworm for running the SE dedicated server via Wine (`9cd18f1`)
- docker-compose.yml with volume mounts and environment-driven configuration (`9cd18f1`)
- Auto-update on container restart via SteamCMD (`9cd18f1`)
- Scheduled world backups every 6 hours with 7-day retention (`9cd18f1`)
- Backup and restore scripts for world save management (`9cd18f1`)
- Steam Workshop mod support via MODS environment variable (`9cd18f1`)
- XML config template with envsubst placeholders for server configuration (`9cd18f1`)
- Graceful shutdown handling via SIGTERM trap (`9cd18f1`)
- HEALTHCHECK in Dockerfile using pgrep for the server process (`0bdc1b8`)
- Input validation for ADMIN_IDS, MODS (numeric only), BACKUP_INTERVAL_HOURS (positive int), and SERVER_PORT (valid range) (`0bdc1b8`)
- stop_grace_period (120s) in docker-compose to prevent SIGKILL during world save (`0bdc1b8`)
- .env added to .gitignore to prevent accidental secret commits (`0bdc1b8`)
- MAX_BACKUP_SAVES as a configurable environment variable, defaulting to 5 (`55f989c`)
- Steam credential support via STEAM_USER/STEAM_PASS environment variables, since App 298740 does not support anonymous download (`bf1e4e2`)
- PremadeCheckpointPath for new world creation so the server can find built-in world templates (`dbf4a0c`)
- Volume mount for Steam auth cache (./data/steam-cache) so Steam Guard codes persist across container restarts (`82d5c86`)
- BACKUP_RETENTION_DAYS environment variable for configurable backup retention (`37c73f5`)
- `SERVER_PASSWORD` environment variable for server password protection; when set, the password is injected into the SE config before every launch so the engine hashes it on startup (`074c465`)
- Resource limits in docker-compose: 8G memory, 4 CPUs, 256 pids limit (`37c73f5`)
- no-new-privileges security option in docker-compose (`37c73f5`)
- Process group management via setsid for clean SIGTERM propagation to Wine (`37c73f5`)

### Changed

- Switch from WineHQ Wine 11 to Debian Wine 8 packages to resolve kernel32.dll load failure caused by Wine 11 WoW64 architecture changes (`052984a`)
- Use wineboot directly instead of wine wineboot (`052984a`)
- Reorder Dockerfile layers to copy runtime scripts after expensive Wine/dotnet/vcrun build layers, preventing script changes from invalidating cached layers (`9634d62`)
- Batch all mod downloads into a single SteamCMD session instead of one process per mod, dramatically improving download speed with many mods (`6ee94d4`)
- Bind-mount init.sh from host to avoid image rebuilds for script changes (`82d5c86`)
- Pin winetricks to release tag 20240105 for supply chain safety (`37c73f5`)
- Use bash array for WORKSHOP_ARGS in entrypoint.sh to prevent word-splitting (`37c73f5`)
- Kill entire process group in shutdown handler and capture real exit code (`37c73f5`)
- Add set -e to init.sh for fail-fast behavior and mkdir -p to ensure volume directories exist (`37c73f5`)
- Add -maxdepth 1 to find in backup.sh to prevent recursive descent during retention cleanup (`37c73f5`)

### Fixed

- Dockerfile build failures due to missing xauth, gettext-base, and procps packages (`052984a`)
- XML injection: replace sed with awk using placeholder comments to produce well-formed XML (`0bdc1b8`)
- Self-closing `<Mods />` and `<Banned />` tags that prevented XML injection from matching (`0bdc1b8`)
- Remove set -e from entrypoint to prevent silent exit on server crash (`0bdc1b8`)
- Convert config path to Windows path via winepath for Wine compatibility (`0bdc1b8`)
- README restore procedure (docker exec cannot run on stopped containers) (`0bdc1b8`)
- SteamCMD losing credentials after self-update restart by running a separate +quit invocation first (`b011428`)
- SteamCMD downloading Linux binaries instead of Windows depots by forcing platform type with @sSteamCmdForcePlatformType windows (`ce1109b`)
- Root-owned volume mounts preventing SteamCMD writes by adding init.sh wrapper with gosu for permission fixing (`d19879c`)
- SE server failing with "Cannot start new world - Premade world not found" when PremadeCheckpointPath was missing (`dbf4a0c`)

### Security

- Path traversal protection and running-server check in restore.sh (`0bdc1b8`)
- Reject absolute paths and '..' in restore.sh input, resolve BACKUP_DIR with realpath before path containment check (`37c73f5`)
- Temp file cleanup trap in entrypoint.sh (`37c73f5`)
