# CLAUDE.md - Minecraft Server Management Suite

## Commands

### Fabric Server Management

- **Start Server**: `./tools/server-start.sh`
- **Install/Update Fabric**: `./tools/mod-updates.sh install-fabric [version]`
- **Update Mods**: `./tools/mod-updates.sh ferium`

### Backup & Snapshots

- **Backup (tar)**: `./tools/backup.sh backup [all|world|config|mods]`
- **List Backups**: `./tools/backup.sh list`
- **Restore Backup**: `./tools/backup.sh restore <file>`
- **Btrfs Snapshot**: `./tools/backup.sh snapshot [source] [name]`
- **List Snapshots**: `./tools/backup.sh snapshot-list`
- **Restore Snapshot**: `./tools/backup.sh snapshot-restore <name>`

### Systemd Service (NEW)

- **Create Service**: `./tools/systemd-service.sh create`
- **Create Infrarust Proxy Service**: `./tools/systemd-service.sh create-infrarust [dir] [user]`
- **Enable Service**: `./tools/systemd-service.sh enable`
- **Start Service**: `./tools/systemd-service.sh start`
- **Stop Service**: `./tools/systemd-service.sh stop`
- **View Status**: `./tools/systemd-service.sh status`
- **View Logs**: `./tools/systemd-service.sh logs [lines]`

### Monitoring & Maintenance

- **Monitor**: `./tools/monitor.sh [status|watch|alert]`
- **Log Maintenance**: `./tools/logrotate.sh maintenance`

### Proxy & Tunneling

- **Setup lazymc**: `./tools/prepare.sh lazymc-install`
- **Generate lazymc config**: `./tools/prepare.sh lazymc-config`
- **Manage lazymc**: `./tools/server-start.sh lazymc [start|stop|restart|status|logs|follow]`
- **Start server with lazymc**: `ENABLE_LAZYMC=true ./tools/server-start.sh`

## Code Style & Standards

- **Shell**: Bash 5.0+. Shebang `#!/usr/bin/env bash`.
- **Shared Library**: All scripts MUST source `tools/common.sh` for common functions (output formatting, command detection, memory calculations, etc.).
- **Strict Mode**: Provided by `tools/common.sh` - no need to redefine in individual scripts.
- **Formatting**: 2-space indent. No tabs. Strip trailing whitespace.
- **Variables**: `snake_case` for locals, `SCREAMING_SNAKE` for globals/exports. Quote all variables unless intentional splitting.
- **Output**: Use `printf` over `echo`. Use `print_header`, `print_success`, `print_error`, `print_info` from `tools/common.sh`.
- **Loops**: Prefer `while IFS= read -r` or `mapfile` over `for` loops on command output.
- **Conditions**: Use `[[ ... ]]` over `[ ... ]`. Use `(( ... ))` for arithmetic.
- **Functions**: Define as `func_name() { ... }`. Use `local` variables. Return values via `printf` capture or global refs if necessary.

## Tech Stack

- **Core**: Bash Scripts (Management, Automation, Monitoring).
- **Runtime**: Java 21+ (GraalVM Enterprise/Community or Eclipse Temurin).
- **Server**: Fabric Loader + Minecraft Java Edition.
- **Proxy/Tunnel**: Playit.gg, Infrarust, lazymc (auto sleep/wake).
- **Geyser**: Bedrock/Java interoperability.
- **Backup**: tar-based backups + Btrfs snapshots (optional).

## Tool Preferences

- **JSON**: `jaq` > `jq`.
- **Download**: `aria2c` > `curl` > `wget`.
- **Search**: `rg` (ripgrep) > `grep`.
- **Optimization**: `oxipng`, `optipng`, `jpegoptim` (via workflows).

## Directory Structure

- `tools/`: All operational scripts (server management, backup, monitor, watchdog, logs, systemd).
- `lib/`: Shared shell library (`common.sh`) with reusable functions.
- `minecraft/`: Minecraft-specific data directory.
  - `config/`: Mod configurations (ServerCore, Geyser, etc.).
  - `backups/`: Storage for compressed world/config archives.
    - `worlds/`: Tar-based world backups
    - `configs/`: Tar-based config backups
    - `btrfs-snapshots/`: Btrfs snapshots (if filesystem supports)
  - `server.properties`: Minecraft server configuration.
  - `packsquash.toml`: Resource pack optimization config.
- `docs/`: Documentation and JVM flag references.
- `.github/`: CI/CD workflows, issue templates, AI instructions.
