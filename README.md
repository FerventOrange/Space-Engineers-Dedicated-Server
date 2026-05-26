# Space Engineers Dedicated Server (Linux Docker)

Docker-based Space Engineers dedicated server running on Linux via Wine. Includes auto-update on restart, scheduled world backups with configurable retention, Steam Workshop mod support, and container security hardening.

## Quick Start

```bash
git clone <repo-url>
cd Space-Engineers-Dedicated-Server
cp .env.example .env   # edit with your Steam credentials
```

### First-Time Steam Guard Authentication

App 298740 (SE Dedicated Server) requires a Steam account -- anonymous login is not supported. If your account has Steam Guard enabled, you need to authenticate once interactively:

```bash
# 1. Run the container in the foreground
docker compose run --rm se-server

# 2. When SteamCMD prompts for the Steam Guard code, enter it in the terminal

# 3. Once the server finishes starting, press Ctrl+C to stop it

# 4. Start the server in detached mode -- no Steam Guard prompt again
docker compose up -d
```

The Steam auth session is persisted in `./data/steam-cache`, so the Guard code is only needed once. Subsequent starts reuse the cached credentials automatically.

> **Tip:** A dedicated Steam account (separate from your personal account) is recommended for running the server.

## Environment Variables

Set these in a `.env` file or pass them to `docker compose`:

| Variable | Default | Description |
|---|---|---|
| `STEAM_USER` | *(required)* | Steam account username for SteamCMD |
| `STEAM_PASS` | *(required)* | Steam account password for SteamCMD |
| `SERVER_NAME` | `Space Engineers Server` | Server name shown in server browser |
| `WORLD_NAME` | `Star System` | World/save name |
| `SERVER_PORT` | `27016` | Game port (UDP) |
| `ADMIN_IDS` | *(empty)* | Comma-separated Steam64 IDs for admin access |
| `MODS` | *(empty)* | Comma-separated Steam Workshop mod IDs |
| `AUTO_UPDATE` | `true` | Update SE server on every container start |
| `BACKUP_INTERVAL_HOURS` | `6` | Hours between automatic world backups |
| `BACKUP_RETENTION_DAYS` | `7` | Number of days to keep backup files before automatic deletion |
| `MAX_BACKUP_SAVES` | `5` | Max in-game backup saves retained by the server |

Example `.env` file:

```env
STEAM_USER=your_steam_username
STEAM_PASS=your_steam_password
SERVER_NAME=My SE Server
WORLD_NAME=Star System
ADMIN_IDS=76561198000000001,76561198000000002
MODS=754173702,857053359
BACKUP_RETENTION_DAYS=14
```

## Server Management

### Starting / Stopping

```bash
docker compose up -d      # Start (auto-updates SE on start)
docker compose stop        # Stop gracefully (120s grace period)
docker compose restart     # Restart (triggers auto-update)
docker compose logs -f     # View live logs
```

The container is configured with a 120-second stop grace period (`stop_grace_period: 120s`) to allow the server to save and shut down cleanly. The entrypoint uses process group management (`setsid`) so that the entire process tree (xvfb-run, Wine, and the SE server) receives the stop signal and shuts down together.

### Updating the Server

The server auto-updates every time the container starts (when `AUTO_UPDATE=true`). To manually trigger an update:

```bash
docker compose restart
```

### Server Configuration

The server config is generated on first run at `data/config/SpaceEngineers-Dedicated.cfg`. After the first run, edit this file directly to customize game settings. Changes take effect on restart.

To regenerate the config from the template (losing any manual edits):

```bash
rm data/config/SpaceEngineers-Dedicated.cfg
docker compose restart
```

## Backups

### Automatic Backups

The server creates automatic world backups every 6 hours (configurable via `BACKUP_INTERVAL_HOURS`). Backups older than the configured retention period are automatically deleted (configurable via `BACKUP_RETENTION_DAYS`, default 7 days).

### Manual Backup

```bash
docker exec se-server /server/scripts/backup.sh
```

### Listing Backups

```bash
docker exec se-server /server/scripts/restore.sh
```

### Restoring a Backup

Restore directly from the host (the backup files are in `data/backups/`):

```bash
docker compose stop
# Extract backup into the world directory
tar -xzf data/backups/world_backup_20250101_120000.tar.gz -C data/world/
docker compose start
```

Alternatively, use a temporary container with the same volumes:

```bash
docker compose stop
docker compose run --rm se-server /server/scripts/restore.sh world_backup_20250101_120000.tar.gz
docker compose start
```

Backups are stored in `data/backups/` and can also be accessed directly from the host.

## Mods

Set the `MODS` environment variable with comma-separated Steam Workshop IDs:

```env
MODS=754173702,857053359
```

Mods are downloaded on container start via SteamCMD using your Steam credentials. Mods are also added to the server config XML automatically when the config is first generated.

## Ports

| Port | Protocol | Description |
|---|---|---|
| 27016 | UDP | Game server port |

Ensure this port is forwarded in your firewall/router for external access. For a private server (direct connect only), port forwarding is still required but the server won't appear in the public server browser.

## Data Persistence

All persistent data is stored in the `data/` directory:

```
data/
├── world/           # World save files
├── config/          # Server configuration
├── backups/         # World backups (timestamped tar.gz)
├── mods/            # Downloaded Workshop mods
├── server-install/  # SE dedicated server binaries (cached)
└── steam-cache/     # Steam auth session cache (persists Steam Guard tokens)
```

This directory is git-ignored and persists across container rebuilds.

### Volume Mounts

The `docker-compose.yml` maps the following volumes:

| Host Path | Container Path | Purpose |
|---|---|---|
| `./data/world` | `/server/world` | World save files |
| `./data/config` | `/server/config` | Server configuration |
| `./data/backups` | `/server/backups` | World backup archives |
| `./data/mods` | `/server/mods` | Downloaded Workshop mods |
| `./data/server-install` | `/server/install` | SE server binaries |
| `./data/steam-cache` | `/home/steam/Steam` | Steam auth cache (Guard tokens, session data) |
| `./init.sh` | `/server/init.sh` | Init script (bind-mounted for easy updates) |

The `init.sh` script is bind-mounted from the project root so that changes to the init logic take effect immediately on the next container start without requiring an image rebuild.

## Container Security

The `docker-compose.yml` includes several security hardening measures:

| Setting | Value | Purpose |
|---|---|---|
| `security_opt` | `no-new-privileges:true` | Prevents processes from gaining additional privileges via setuid/setgid |
| `memory` | `8G` | Caps container memory usage |
| `cpus` | `4.0` | Caps container CPU usage |
| `pids_limit` | `256` | Limits the number of processes to prevent fork bombs |
| `stop_grace_period` | `120s` | Allows time for the server to save and shut down cleanly |

## Reproducible Builds

The Dockerfile pins external dependencies to specific versions for reproducible builds:

- **Winetricks** is pinned to release `20240105` via the `WINETRICKS_TAG` build argument. To update, change the `ARG WINETRICKS_TAG` value in the Dockerfile and rebuild.
- **Wine 8** (stable) is installed from Debian Bookworm repositories.
- **Base image** uses `debian:bookworm-slim`.

## Rebuilding the Image

If you need to rebuild (e.g., after Dockerfile changes):

```bash
docker compose build --no-cache
docker compose up -d
```

The server binaries in `data/server-install/` are preserved across rebuilds, so SteamCMD only needs to validate rather than re-download everything. The `init.sh` script is bind-mounted and does not require a rebuild when modified.

## Troubleshooting

- **Server won't start:** Check logs with `docker compose logs`. Wine/.NET issues may require a full rebuild.
- **Steam Guard prompt on every start:** Ensure `./data/steam-cache` is mapped as a volume (check `docker-compose.yml`). The directory must persist between runs.
- **Mod download fails:** Mods require Steam authentication. Verify your credentials are correct and that the mod IDs are valid.
- **Performance issues:** Adjust `MaxPlayers`, `ViewDistance`, `SyncDistance`, and PCU limits in the config file. The container is limited to 8 GB memory and 4 CPUs by default; adjust `deploy.resources.limits` in `docker-compose.yml` if needed.
- **Port conflicts:** Change `SERVER_PORT` and update the port mapping in `docker-compose.yml`.
- **Container hits PID limit:** The default `pids_limit` of 256 is generous for normal operation. If you see "cannot allocate" errors, increase it in `docker-compose.yml`.
- **Shutdown takes too long:** The 120-second grace period should be sufficient. If the server hangs, Docker will force-kill it after this period.
