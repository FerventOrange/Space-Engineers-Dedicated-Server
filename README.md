# Space Engineers Dedicated Server (Linux Docker)

Docker-based Space Engineers dedicated server running on Linux via Wine. Includes auto-update on restart, scheduled world backups, and Steam Workshop mod support.

## Quick Start

```bash
git clone <repo-url>
cd Space-Engineers-Server
docker compose up -d
```

The first run will build the image (installing Wine, SteamCMD, .NET Framework) and then download the SE dedicated server files. This initial setup takes a while due to .NET installation.

## Environment Variables

Set these in a `.env` file or pass them to `docker compose`:

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `Space Engineers Server` | Server name shown in server browser |
| `WORLD_NAME` | `Star System` | World/save name |
| `SERVER_PORT` | `27016` | Game port (UDP) |
| `ADMIN_IDS` | *(empty)* | Comma-separated Steam64 IDs for admin access |
| `MODS` | *(empty)* | Comma-separated Steam Workshop mod IDs |
| `AUTO_UPDATE` | `true` | Update SE server on every container start |
| `BACKUP_INTERVAL_HOURS` | `6` | Hours between automatic world backups |

Example `.env` file:

```env
SERVER_NAME=My SE Server
WORLD_NAME=Star System
ADMIN_IDS=76561198000000001,76561198000000002
MODS=754173702,857053359
```

## Server Management

### Starting / Stopping

```bash
docker compose up -d      # Start (auto-updates SE on start)
docker compose stop        # Stop gracefully
docker compose restart     # Restart (triggers auto-update)
docker compose logs -f     # View live logs
```

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

The server creates automatic world backups every 6 hours (configurable via `BACKUP_INTERVAL_HOURS`). Backups older than 7 days are automatically deleted.

### Manual Backup

```bash
docker exec se-server /server/scripts/backup.sh
```

### Listing Backups

```bash
docker exec se-server /server/scripts/restore.sh
```

### Restoring a Backup

```bash
docker compose stop
docker exec se-server /server/scripts/restore.sh world_backup_20250101_120000.tar.gz
docker compose start
```

Backups are stored in `data/backups/` and can also be accessed directly from the host.

## Mods

Set the `MODS` environment variable with comma-separated Steam Workshop IDs:

```env
MODS=754173702,857053359
```

Mods are downloaded on container start via SteamCMD. Some mods may require Steam authentication and might fail to download with anonymous login.

Mods are also added to the server config XML automatically when the config is first generated.

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
└── server-install/  # SE dedicated server binaries (cached)
```

This directory is git-ignored and persists across container rebuilds.

## Rebuilding the Image

If you need to rebuild (e.g., after Dockerfile changes):

```bash
docker compose build --no-cache
docker compose up -d
```

The server binaries in `data/server-install/` are preserved across rebuilds, so SteamCMD only needs to validate rather than re-download everything.

## Troubleshooting

- **Server won't start:** Check logs with `docker compose logs`. Wine/.NET issues may require a full rebuild.
- **Mod download fails:** Some mods require Steam authentication. Try downloading them manually.
- **Performance issues:** Adjust `MaxPlayers`, `ViewDistance`, `SyncDistance`, and PCU limits in the config file.
- **Port conflicts:** Change `SERVER_PORT` and update the port mapping in `docker-compose.yml`.
