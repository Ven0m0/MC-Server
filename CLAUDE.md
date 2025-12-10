# CLAUDE.md - Minecraft Server Management Suite

## Commands

### Fabric Server Management

- **Start Server**: `./tools/server-start.sh`
- **Install/Update Fabric**: `./tools/mod-updates.sh install-fabric [version]`
- **Update Mods**: `./tools/mod-updates.sh ferium`

### Paper/Spigot Server Management

- **Build Paper**: `./tools/mcctl.sh build-paper [version]`
- **Build Spigot**: `./tools/mcctl.sh build-spigot [version]`
- **Update Plugin**: `./tools/mcctl.sh update <plugin>`
- **Update All Plugins**: `./tools/mcctl.sh update-all`
- **Initialize Server**: `./tools/mcctl.sh init`
- **Accept EULA**: `./tools/mcctl.sh accept-eula`

**Supported Plugins**: viaversion, viabackwards, multilogin, floodgate, geyser, protocollib, vault, luckperms, griefprevention, freedomchat, deluxemenus, noencryption, craftgui, globalmarket

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
- **Lint/Format Configs**: `./tools/format-config.sh --mode [format|check|minify]`

### Proxy & Tunneling

- **Setup lazymc**: `./tools/prepare.sh lazymc-install`
- **Generate lazymc config**: `./tools/prepare.sh lazymc-config`
- **Manage lazymc**: `./tools/lazymc.sh [start|stop|restart|status|logs|follow]`

## Code Style & Standards

- **Shell**: Bash 5.0+. Shebang `#!/usr/bin/env bash`.
- **Shared Library**: All scripts MUST source `lib/common.sh` for common functions (output formatting, command detection, memory calculations, etc.).
- **Strict Mode**: Provided by `lib/common.sh` - no need to redefine in individual scripts.
- **Formatting**: 2-space indent. No tabs. Strip trailing whitespace.
- **Variables**: `snake_case` for locals, `SCREAMING_SNAKE` for globals/exports. Quote all variables unless intentional splitting.
- **Output**: Use `printf` over `echo`. Use `print_header`, `print_success`, `print_error`, `print_info` from `lib/common.sh`.
- **Loops**: Prefer `while IFS= read -r` or `mapfile` over `for` loops on command output.
- **Conditions**: Use `[[ ... ]]` over `[ ... ]`. Use `(( ... ))` for arithmetic.
- **Functions**: Define as `func_name() { ... }`. Use `local` variables. Return values via `printf` capture or global refs if necessary.

## Tech Stack

- **Core**: Bash Scripts (Management, Automation, Monitoring).
- **Runtime**: Java 21+ (GraalVM Enterprise/Community or Eclipse Temurin).
- **Server**:
  - Fabric Loader + Minecraft Java Edition (primary)
  - Paper/Spigot support via mcctl (integrated)
- **Proxy/Tunnel**: Playit.gg, Infrarust, lazymc (auto sleep/wake).
- **Geyser**: Bedrock/Java interoperability.
- **Backup**: tar-based backups + Btrfs snapshots (optional).

## Tool Preferences

- **JSON**: `jaq` > `jq`.
- **Download**: `aria2c` > `curl` > `wget`.
- **Search**: `rg` (ripgrep) > `grep`.
- **Optimization**: `oxipng`, `optipng`, `jpegoptim` (via workflows).

## Directory Structure

- `tools/`: All operational scripts (server management, backup, monitor, watchdog, logs, mcctl, systemd).
- `lib/`: Shared shell library (`common.sh`) with reusable functions.
- `config/`: Plugin/Mod configurations (ServerCore, Geyser, etc.).
- `docs/`: Documentation and JVM flag references.
- `backups/`: Storage for compressed world/config archives.
  - `worlds/`: Tar-based world backups
  - `configs/`: Tar-based config backups
  - `btrfs-snapshots/`: Btrfs snapshots (if filesystem supports)
- `plugins/`: Paper/Spigot plugins (when using mcctl).
- `.github/`: CI/CD workflows, issue templates, agent definitions.

## mcctl Integration

This repository includes an integrated version of [Kraftland/mcctl](https://github.com/Kraftland/mcctl) (v2.1.0-integrated, based on upstream v1.6-stable) for Paper/Spigot server management. The tool has been modernized to follow this repository's code standards:

- Modern bash with strict mode (`set -euo pipefail`)
- Consistent code style (2-space indent, snake_case)
- Modular design with clear separation of concerns
- Compatible with existing Fabric-focused tooling
- Extended plugin support (14 plugins including ViaVersion, Geyser, LuckPerms, and more)
- Proper GPL-3.0 license attribution (see CREDITS.md)

Use `./tools/mcctl.sh help` for Paper/Spigot commands.

**Original Author**: Kimiblock | **License**: GPL-3.0
