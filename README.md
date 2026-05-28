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
| `WORLD_NAME` | `Star System` | World/save name (see [Custom Maps](#custom-maps)) |
| `SERVER_PORT` | `27016` | Game port (UDP) |
| `ADMIN_IDS` | *(empty)* | Comma-separated Steam64 IDs for admin access |
| `MODS` | *(empty)* | Comma-separated Steam Workshop mod IDs |
| `AUTO_UPDATE` | `true` | Update SE server on every container start |
| `BACKUP_INTERVAL_HOURS` | `6` | Hours between automatic world backups |
| `BACKUP_RETENTION_DAYS` | `7` | Number of days to keep backup files before automatic deletion |
| `MAX_BACKUP_SAVES` | `28` | Max in-game backup saves retained by the server |
| `WORLD_DIR` | `/server/world` | World save directory inside the container |
| `BACKUP_DIR` | `/server/backups` | Backup directory inside the container |
| `INVENTORY_SIZE_MULTIPLIER` | `10` | Player inventory size multiplier |
| `BLOCKS_INVENTORY_SIZE_MULTIPLIER` | `10` | Block inventory size multiplier (cargo containers, etc.) |
| `ASSEMBLER_SPEED_MULTIPLIER` | `10` | Assembler crafting speed multiplier |
| `ASSEMBLER_EFFICIENCY_MULTIPLIER` | `10` | Assembler material efficiency multiplier |
| `REFINERY_SPEED_MULTIPLIER` | `10` | Refinery processing speed multiplier |
| `WELDER_SPEED_MULTIPLIER` | `5` | Welder speed multiplier |
| `GRINDER_SPEED_MULTIPLIER` | `5` | Grinder speed multiplier |
| `HARVEST_RATIO_MULTIPLIER` | `5` | Ore yield from mining multiplier |

Example `.env` file:

```env
STEAM_USER=your_steam_username
STEAM_PASS=your_steam_password
SERVER_NAME=My SE Server
WORLD_NAME=Star System
SERVER_PORT=27016
ADMIN_IDS=76561198000000001,76561198000000002
MODS=754173702,857053359
BACKUP_RETENTION_DAYS=14
INVENTORY_SIZE_MULTIPLIER=10
REFINERY_SPEED_MULTIPLIER=10
HARVEST_RATIO_MULTIPLIER=5
```

> **Note:** Multiplier env vars are only applied during **initial config generation** (first run). To change multipliers on an existing world, see [Changing Game Settings](#changing-game-settings-multipliers-etc).

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

The server config is generated on first run at `data/config/SpaceEngineers-Dedicated.cfg`. This file controls initial server settings (name, port, admins). After the first run you can edit it directly; changes take effect on restart.

To regenerate the config from the template (losing any manual edits):

```bash
rm data/config/SpaceEngineers-Dedicated.cfg
docker compose restart
```

### Changing Game Settings (Multipliers, etc.)

**Important:** SE stores session settings in the **world save**, not the server config. Once a world exists, the server config is only used for initial world creation. To change gameplay settings like multipliers:

1. Stop the server: `docker compose stop`
2. Edit **both** save files in `world/<WorldName>/`:
   - `Sandbox.sbc` — the world checkpoint
   - `Sandbox_config.sbc` — **this file overrides `Sandbox.sbc`** and is what SE actually reads
3. Start the server: `docker compose up -d`

Common settings in `Sandbox_config.sbc`:

```xml
<InventorySizeMultiplier>10</InventorySizeMultiplier>
<BlocksInventorySizeMultiplier>10</BlocksInventorySizeMultiplier>
<AssemblerSpeedMultiplier>10</AssemblerSpeedMultiplier>
<AssemblerEfficiencyMultiplier>10</AssemblerEfficiencyMultiplier>
<RefinerySpeedMultiplier>10</RefinerySpeedMultiplier>
<WelderSpeedMultiplier>5</WelderSpeedMultiplier>
<GrinderSpeedMultiplier>5</GrinderSpeedMultiplier>
<HarvestRatioMultiplier>5</HarvestRatioMultiplier>
```

**You must edit the files while the server is stopped.** If you edit them while the server is running, SE will overwrite your changes when it auto-saves or shuts down.

### Custom Maps

The `WORLD_NAME` must match one of SE's built-in premade worlds **exactly** (including spaces). On first run, SE copies the premade world from `Content/CustomWorlds/<WORLD_NAME>` into the save directory. If the name doesn't match, the server will crash with a "world not found" error.

Available premade worlds:

- `Star System` (default)
- `Easy Start 1`
- `Easy Start 2`
- `Lone Survivor`
- `Crashed Red Ship`
- `Two Platforms`
- `Asteroids`
- `Empty World`

To use a custom/uploaded world instead of a premade one:

1. Set `WORLD_NAME` to `Star System` (or any valid premade name) for the initial run
2. Let the server create the world and then stop it
3. Replace the contents of `world/<WorldName>/` with your custom world files
4. Restart the server

> **Warning:** Using a non-existent world name (e.g., `StarSystem` instead of `Star System`) will cause the container to crash-loop on startup.

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
tar -xzf data/backups/world_backup_20250101_120000.tar.gz -C world/
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

Mods are downloaded on container start via SteamCMD into the Steam library path (`/home/steam/Steam/steamapps/workshop/`). Mods are also added to the server config XML automatically when the config is first generated.

### How Mods Load

1. **SteamCMD** pre-downloads mod files on container start (reliable)
2. **SE's internal Steam client** verifies/downloads mods when loading the world (can be unreliable in Wine)

For SE to load mods, they must be listed in **both** the server config and the world save files:
- `data/config/SpaceEngineers-Dedicated.cfg` — `<Mods>` section (generated from `MODS` env var on first run)
- `world/<WorldName>/Sandbox.sbc` — `<Mods>` section
- `world/<WorldName>/Sandbox_config.sbc` — `<Mods>` section (overrides Sandbox.sbc)

### Adding Mods to an Existing World

If you add mods after world creation, you need to manually add them to `Sandbox_config.sbc` and `Sandbox.sbc`:

```xml
<Mods>
  <ModItem FriendlyName="" Name="754173702.sbm">
    <PublishedFileId>754173702</PublishedFileId>
    <PublishedServiceName>Steam</PublishedServiceName>
  </ModItem>
</Mods>
```

### Legacy Mods (Known Issue)

Some older Steam Workshop mods use a legacy UGC download format (`manifest: -1` in the workshop ACF). SE's internal Steam client **cannot reliably download these mods** in a Wine/Docker environment — they will timeout and crash the server in a loop.

To identify legacy mods, check the workshop manifest after SteamCMD downloads them:

```bash
docker exec se-server grep -B1 '"manifest".*"-1"' \
  /home/steam/Steam/steamapps/workshop/appworkshop_244850.acf
```

**Workaround:** Remove legacy mods from the `MODS` env var and from both `Sandbox.sbc`/`Sandbox_config.sbc`. The server will load successfully with the remaining mods.

## Ports

| Port | Protocol | Description |
|---|---|---|
| `SERVER_PORT` (default 27016) | UDP | Game server port |

The port mapping in `docker-compose.yml` uses `${SERVER_PORT}` so the host port and container port always match. This is important because SE advertises the internal port to Steam — if the host and container ports differ, players cannot connect.

### Port Forwarding

For external access, forward the `SERVER_PORT` (UDP) on your router to your server's LAN IP. **The external port, router forwarding port, and `SERVER_PORT` must all match.**

Example with `SERVER_PORT=27020`:
- Router: forward UDP 27020 → `<server-LAN-IP>`:27020
- Players connect to: `your.domain:27020`

> **Important:** Ensure the port forward is **UDP**, not TCP. SE uses UDP exclusively for game traffic.

## Data Persistence

Persistent data is split between `data/` and `world/`:

```
world/                # World save files (at repo root for easy access)
└── Star System/
    ├── Sandbox.sbc
    ├── Sandbox_config.sbc   ← SE reads settings from here
    └── ...

data/
├── config/          # Server configuration
├── backups/         # World backups (timestamped tar.gz)
├── mods/            # Downloaded Workshop mods (legacy path)
├── server-install/  # SE dedicated server binaries (cached)
└── steam-cache/     # Steam auth session + workshop downloads
```

Both directories are git-ignored and persist across container rebuilds.

### Volume Mounts

| Host Path | Container Path | Purpose |
|---|---|---|
| `./world` | `/server/world` | World save files |
| `./data/config` | `/server/config` | Server configuration |
| `./data/backups` | `/server/backups` | World backup archives |
| `./data/mods` | `/server/mods` | Downloaded Workshop mods (legacy) |
| `./data/server-install` | `/server/install` | SE server binaries |
| `./data/steam-cache` | `/home/steam/Steam` | Steam auth cache, workshop downloads |
| `./init.sh` | `/server/init.sh` | Init script (bind-mounted) |
| `./entrypoint.sh` | `/server/entrypoint.sh` | Entrypoint script (bind-mounted) |
| `./scripts` | `/server/scripts` | Utility scripts (bind-mounted) |
| `./config` | `/server/config-templates` | Config templates (bind-mounted) |

Scripts are bind-mounted from the project root so that changes take effect immediately on container restart without requiring an image rebuild.

### World Save Symlink

SE saves worlds to `{-path}/Saves/{WorldName}/`. The entrypoint creates a symlink:

```
/server/config/Saves → /server/world
```

This redirects SE's save path into the `./world` volume on the host.

## Container Security

The `docker-compose.yml` includes several security hardening measures:

| Setting | Value | Purpose |
|---|---|---|
| `security_opt` | `no-new-privileges:true` | Prevents processes from gaining additional privileges via setuid/setgid |
| `memory` | `8G` | Caps container memory usage |
| `cpus` | `2.0` | Caps container CPU usage (adjust to match your host) |
| `pids_limit` | `256` | Limits the number of processes to prevent fork bombs |
| `stop_grace_period` | `120s` | Allows time for the server to save and shut down cleanly |

## Reproducible Builds

The Dockerfile pins external dependencies to specific versions for reproducible builds:

- **Winetricks** is pinned to release `20260125` via the `WINETRICKS_TAG` build argument. To update, change the `ARG WINETRICKS_TAG` value in the Dockerfile and rebuild.
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

### Server won't start

Check logs with `docker compose logs`. Common causes:

- **Wine/.NET issues:** May require a full image rebuild (`docker compose build --no-cache`). The `dotnet48` winetricks install is the most fragile step.
- **"World not found" or premade world error:** The `WORLD_NAME` must match an SE premade world exactly (e.g., `Star System` with a space, not `StarSystem`). If wrong, delete `data/config/SpaceEngineers-Dedicated.cfg` and restart.

### New `.env` variables not taking effect after an update

If you pull a project update that adds new environment variables to `docker-compose.yml` (e.g., `SERVER_PASSWORD`), a plain `docker compose restart` won't pick them up — it reuses the existing container definition. You must recreate the container:

```bash
docker compose down && docker compose up -d
```

### Settings changes not taking effect

SE loads session settings from `world/<WorldName>/Sandbox_config.sbc`, **not** from `SpaceEngineers-Dedicated.cfg`. You must:

1. **Stop the server first** — if you edit files while running, SE overwrites them on save/shutdown
2. **Edit `Sandbox_config.sbc`** (this is the file that matters)
3. **Also edit `Sandbox.sbc`** for consistency (SE may fall back to it)

### Config not regenerating after .env changes

The server config (`SpaceEngineers-Dedicated.cfg`) is only generated if the file doesn't exist. If you change `.env` values like `WORLD_NAME` or `SERVER_PORT`, you must delete the config to trigger regeneration:

```bash
docker compose stop
rm data/config/SpaceEngineers-Dedicated.cfg
docker compose up -d
```

### Players can't connect

- **Port mismatch:** `SERVER_PORT` in `.env`, the Docker port mapping, and the router port forward must all use the **same port number**. SE advertises the internal port to Steam, so mismatched ports (e.g., external 27020 → internal 27016) will not work.
- **UDP not enabled:** Ensure your router port forward is **UDP**, not TCP.
- **Docker listening on wrong port:** After changing `SERVER_PORT`, verify with `ss -ulnp | grep <port>` that Docker is actually listening on the new port. You may need `docker compose down && docker compose up -d` (not just restart) for port changes to take effect.

### Mods not loading

- Mods must be listed in `Sandbox_config.sbc` and `Sandbox.sbc` `<Mods>` sections, not just in `.env`.
- Adding `MODS` to `.env` only affects the **initial** config generation and SteamCMD pre-download. For an existing world, you must manually add mods to the save files.
- **Crash loop from mod timeouts:** SE's internal Steam client may fail to download certain mods in Wine. Check `docker compose logs | grep "Mod failed"`. Legacy-format mods (see [Legacy Mods](#legacy-mods-known-issue)) are the most common cause.

### Steam Guard prompt on every start

Ensure `./data/steam-cache` is mapped as a volume (check `docker-compose.yml`). The directory must persist between runs.

### Docker Compose v5 compatibility

- `pids_limit` must be under `deploy.resources.limits.pids`, not as a top-level service key.
- `cpus` must not exceed the host's actual CPU count or Docker will reject the compose file.

### Performance issues

Adjust `MaxPlayers`, `ViewDistance`, `SyncDistance`, and PCU limits in `Sandbox_config.sbc`. The container is limited to 8 GB memory and 2 CPUs by default; adjust `deploy.resources.limits` in `docker-compose.yml` if needed.

### Shutdown takes too long

The 120-second grace period should be sufficient. If the server hangs, Docker will force-kill it after this period.
