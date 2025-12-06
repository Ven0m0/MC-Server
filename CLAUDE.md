# CLAUDE.md - Minecraft Server Management Suite

## Commands
- **Start Server**: `./scripts/server-start.sh`
- **Install/Update Fabric**: `./scripts/mcdl.sh [version]`
- **Update Mods**: `./scripts/mod-updates.sh upgrade`
- **Backup**: `./tools/backup.sh backup [all|world|config|mods]`
- **Monitor**: `./tools/monitor.sh [status|watch|alert]`
- **Log Maintenance**: `./tools/logrotate.sh maintenance`
- **Lint/Format Configs**: `./scripts/format-config.sh --mode [format|check|minify]`
- **Test**: `./scripts/test_common.sh`
- **Setup lazymc**: `./scripts/lazymc-setup.sh [install|config]`
- **Manage lazymc**: `./tools/lazymc.sh [start|stop|restart|status|logs|follow]`

## Code Style & Standards
- **Shell**: Bash 5.0+. Shebang `#!/usr/bin/env bash`.
- **Strict Mode**: Always use `set -euo pipefail`.
- **Formatting**: 2-space indent. No tabs. Strip trailing whitespace.
- **Variables**: `snake_case` for locals, `SCREAMING_SNAKE` for globals/exports. Quote all variables unless intentional splitting.
- **Output**: Use `printf` over `echo`.
- **Loops**: Prefer `while IFS= read -r` or `mapfile` over `for` loops on command output.
- **Conditions**: Use `[[ ... ]]` over `[ ... ]`. Use `(( ... ))` for arithmetic.
- **Functions**: Define as `func_name() { ... }`. Use `local` variables. Return values via `printf` capture or global refs if necessary.

## Tech Stack
- **Core**: Bash Scripts (Management, Automation, Monitoring).
- **Runtime**: Java 21+ (GraalVM Enterprise/Community or Eclipse Temurin).
- **Server**: Fabric Loader + Minecraft Java Edition.
- **Proxy/Tunnel**: Playit.gg, Infrarust, lazymc (auto sleep/wake).
- **Geyser**: Bedrock/Java interoperability.

## Tool Preferences
- **JSON**: `jaq` > `jq`.
- **Download**: `aria2c` > `curl` > `wget`.
- **Search**: `rg` (ripgrep) > `grep`.
- **Optimization**: `oxipng`, `optipng`, `jpegoptim` (via workflows).

## Directory Structure
- `scripts/`: Core logic (start, updates, install).
- `tools/`: Operational utilities (backup, monitor, watchdog, logs).
- `config/`: Plugin/Mod configurations (ServerCore, Geyser, etc.).
- `docs/`: Documentation and JVM flag references.
- `backups/`: Storage for compressed world/config archives.
- `.github/`: CI/CD workflows, issue templates, agent definitions.
