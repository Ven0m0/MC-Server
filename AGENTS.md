# AI Agent Instructions for MC-Server

> **Context for AI Assistants:** This document provides comprehensive guidance for working with the MC-Server repository. Read this before making changes or answering questions about the codebase.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Tech Stack](#tech-stack)
3. [Repository Structure](#repository-structure)
4. [Development Workflows](#development-workflows)
5. [Code Conventions](#code-conventions)
6. [Dependencies](#dependencies)
7. [Common Tasks](#common-tasks)
8. [Configuration Files](#configuration-files)

---

## Project Overview

**MC-Server** is a production-ready Minecraft Fabric server management suite built entirely in Bash. It provides comprehensive automation for server lifecycle management, backups, monitoring, optimization, and deployment.

### Key Features

- **Automated Server Management** - Start, stop, monitor, and maintain Minecraft servers
- **Multi-Strategy Backups** - Tar archives, Rustic deduplication, Btrfs snapshots
- **Performance Optimization** - GraalVM support, JVM tuning, resource pack optimization
- **Cross-Platform Play** - GeyserMC + Floodgate for Bedrock/Java interoperability
- **Production Deployment** - Systemd services, socket activation, security hardening
- **Comprehensive Monitoring** - Health checks, TPS tracking, error detection, resource usage
- **Automated Maintenance** - Log rotation, world optimization, mod updates, backups
- **Public Hosting** - Playit.gg and Infrarust proxy integration

### Server Specifications

- **Minecraft Version:** 1.21.5 (Fabric)
- **Java Version:** 21+ (GraalVM Enterprise/Community or Eclipse Temurin)
- **Bash Version:** 5.0+ required
- **Modding Framework:** Fabric Loader
- **Primary Mods:** ServerCore, GeyserMC, Floodgate, Cesium, performance optimizations

---

## Tech Stack

### Languages & Frameworks

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Server Scripts** | Bash | 5.0+ | All automation and management |
| **Game Runtime** | Java | 21+ | Minecraft server execution |
| **Modding Framework** | Fabric Loader | Latest | Server-side modifications |
| **Config Formats** | YAML, JSON, TOML, Properties | - | Server and mod configuration |

### Core Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| **mise** | Tool version management | Via `mise.toml` |
| **Ferium** | Minecraft mod manager | Auto-downloaded |
| **Rustic** | Backup utility (Rust) | Via mise/cargo |
| **PackSquash** | Resource pack optimizer | Via mise/cargo |
| **ChunkCleaner** | World optimization | Via mise/ubi |
| **lazymc** | Auto-sleep proxy | Optional |
| **Playit.gg/Infrarust** | Public tunneling | Optional |

### CI/CD & Quality Assurance

- **GitHub Actions** - Automated workflows for linting, image optimization, dependency updates
- **MegaLinter** - Multi-language linting (Bash, YAML, JSON, Markdown)
- **ShellCheck** - Bash script static analysis
- **Dependabot** - Automated dependency updates
- **PackSquash** - Resource pack validation and optimization

---

## Repository Structure

### Directory Layout

```
MC-Server/
├── @tools/                          # Server management scripts (13 files)
│   ├── @backup.sh                   # Backup creation/restoration (tar, rustic, btrfs)
│   ├── @common.sh                   # Shared utility functions (logging, colors)
│   ├── @logrotate.sh                # Log file rotation and maintenance
│   ├── @mc-client.sh                # Minecraft server console interface
│   ├── @mod-updates.sh              # Fabric installation and mod updates
│   ├── @monitor.sh                  # Server health monitoring and metrics
│   ├── @prepare.sh                  # Initial server setup (EULA, directories)
│   ├── @rcon.sh                     # RCON client for remote commands
│   ├── @server-start.sh             # Server startup with JVM optimization
│   ├── @systemd-service.sh          # Systemd service creation and management
│   ├── @watchdog.sh                 # Auto-restart on crashes
│   ├── @world-optimize.sh           # World pruning and optimization
│   └── systemd/                     # Systemd unit templates
│       ├── minecraft@.service       # Main server service template
│       ├── minecraft@.socket        # Socket activation template
│       ├── minecraft-backup.service # Backup automation service
│       └── minecraft.sudoers        # Sudo permissions config
│
├── minecraft/                       # Minecraft server data
│   ├── backups/                     # Backup storage
│   │   ├── worlds/                  # Tar archives of worlds
│   │   ├── configs/                 # Configuration backups
│   │   ├── rustic/                  # Rustic deduplicated backups
│   │   └── btrfs-snapshots/         # Btrfs COW snapshots
│   ├── config/                      # Mod and plugin configurations
│   │   ├── servercore/              # ServerCore optimization configs
│   │   ├── Geyser-Fabric/           # GeyserMC Bedrock bridge
│   │   ├── floodgate/               # Floodgate authentication
│   │   └── [20+ mod configs]
│   ├── mods/                        # Fabric mod JAR files
│   ├── worlds/                      # World data directories
│   └── logs/                        # Server and mod logs
│
├── @docs/                           # Documentation
│   ├── @SETUP.md                    # Comprehensive setup guide
│   ├── @TROUBLESHOOTING.md          # Common issues and solutions
│   ├── @HOSTING.md                  # Public hosting configuration
│   ├── Flags.txt                    # JVM optimization flags reference
│   ├── mods.txt                     # Complete installed mod list
│   └── mods-links.txt               # Mod download links
│
├── .github/                         # GitHub configuration
│   ├── workflows/                   # CI/CD pipelines
│   │   ├── @mega-linter.yml         # Code quality automation
│   │   ├── image-optimization.yml   # Image compression
│   │   ├── packsquash.yml           # Resource pack optimization
│   │   └── automerge-dependabot.yml # Automated dependency merging
│   ├── instructions/                # AI assistant context files
│   │   ├── claude.md                # Claude-specific instructions
│   │   ├── gemini.md                # Gemini-specific instructions
│   │   └── copilot.md               # GitHub Copilot rules
│   └── dependabot.yml               # Dependency update configuration
│
├── .config/                         # Application configurations
│   └── lazymc/                      # Lazymc proxy settings
│
├── @README.md                       # Main project documentation (539 lines)
├── @TODO.md                         # Development roadmap and feature backlog
├── @CREDITS.md                      # Third-party component attribution
├── @mise.toml                       # Tool versioning and installation
├── @server.toml                     # Minecraft server configuration (mcman)
├── @.editorconfig                   # Code formatting standards
├── @.megalinter.yml                 # Linting configuration
├── @.shellcheckrc                   # Bash linting rules
├── @.gitignore                      # Git exclusions
└── @.gitattributes                  # Git file handling
```

### Key File Purposes

| File | Lines | Purpose |
|------|-------|---------|
| `@tools/server-start.sh` | ~300 | Main server launcher with JVM optimization |
| `@tools/backup.sh` | ~400 | Multi-strategy backup and restore |
| `@tools/monitor.sh` | ~350 | Health monitoring and metrics |
| `@tools/mod-updates.sh` | ~250 | Fabric and mod management |
| `@tools/common.sh` | ~150 | Shared utility library |
| `@README.md` | 539 | Complete project documentation |
| `@docs/SETUP.md` | ~150 | Step-by-step setup guide |
| `@.megalinter.yml` | ~100 | Comprehensive linting config |

---

## Development Workflows

### Setup

**Prerequisites:**
```bash
# System requirements
- Bash 5.0+
- Java 21+ (GraalVM or Temurin)
- curl/wget for downloads
- jq/jaq for JSON parsing (optional)
- aria2c for parallel downloads (optional)
```

**Initial Setup:**
```bash
# 1. Clone repository
git clone https://github.com/Ven0m0/MC-Server.git
cd MC-Server

# 2. Run initial preparation
./tools/prepare.sh

# 3. Install Fabric server
./tools/mod-updates.sh install-fabric

# 4. Install tools via mise
mise install

# 5. Start server
./tools/server-start.sh
```

### Build Process

**Server Installation:**
```bash
# Install latest Fabric
./tools/mod-updates.sh install-fabric

# Install specific version
./tools/mod-updates.sh install-fabric 1.21.5

# Update mods via Ferium
./tools/mod-updates.sh ferium
```

**JVM Optimization:**
- Server automatically detects JVM type (GraalVM vs. standard JDK)
- Applies optimized flags from `@docs/Flags.txt`
- Configures G1GC, huge pages, GameMode integration
- See `@tools/server-start.sh:150-250` for flag logic

### Testing

**Automated Testing (GitHub Actions):**
```bash
# Runs on push to main/claude/* branches
- ShellCheck validation of all .sh files
- YAML/JSON/TOML syntax validation
- Markdown linting
- Image optimization
- Resource pack validation

# Local testing
mega-linter --flavor bash  # Run MegaLinter locally
shellcheck tools/*.sh      # Check Bash scripts
```

**Manual Testing:**
```bash
# Syntax check all scripts
for f in tools/*.sh; do bash -n "$f"; done

# Check server status
./tools/monitor.sh status

# Test backup creation
./tools/backup.sh backup test-backup

# Verify systemd service
./tools/systemd-service.sh validate
```

### Deployment

**Systemd Service Deployment:**
```bash
# Create and enable service
./tools/systemd-service.sh create
./tools/systemd-service.sh enable
./tools/systemd-service.sh start

# With proxy (Playit.gg or Infrarust)
./tools/systemd-service.sh create-infrarust
./tools/systemd-service.sh create-playit
```

**Manual Deployment:**
```bash
# Start in screen/tmux
screen -dmS minecraft bash -c "cd /path/to/MC-Server && ./tools/server-start.sh"

# Attach to console
./tools/mc-client.sh attach

# With watchdog (auto-restart)
screen -dmS watchdog bash -c "cd /path/to/MC-Server && ./tools/watchdog.sh monitor"
```

**Automated Maintenance (Cron):**
```bash
# Daily backup at 4 AM
0 4 * * * cd /path/to/MC-Server && ./tools/backup.sh backup all

# Weekly log rotation (Sunday 3 AM)
0 3 * * 0 cd /path/to/MC-Server && ./tools/logrotate.sh maintenance

# Monthly world optimization (1st of month, 2 AM)
0 2 1 * * cd /path/to/MC-Server && ./tools/world-optimize.sh --chunks unused --backup
```

---

## Code Conventions

### Bash Standards

**Script Template:**
```bash
#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'

# Source common library
source "${PWD}/tools/common.sh"

# Configuration with defaults
: "${VAR_NAME:=default_value}"

# Main functionality
main() {
  local var_name="value"
  # Implementation
}

main "$@"
```

**Formatting Rules (from `@.editorconfig`):**
| Rule | Value |
|------|-------|
| **Indentation** | 2 spaces (never tabs) |
| **Line Endings** | LF (Unix) |
| **Max Line Length** | 120 characters |
| **Charset** | UTF-8 |
| **Trailing Whitespace** | Trim |
| **Final Newline** | Insert |

**Naming Conventions:**
```bash
# Local variables (function scope)
local backup_dir="/path"
local max_retries=3

# Global/exported variables
export BACKUP_DIR="/path"
export MAX_RETRIES=3

# Functions
function_name() { ... }
complex_function_with_underscores() { ... }
```

**Required Patterns:**
```bash
# Conditionals: Use [[ ]] not [ ]
[[ -f "$file" ]] && echo "exists"

# Arithmetic: Use (( )) not expr
(( count++ ))

# Loops: Prefer while read over for
while IFS= read -r line; do
  echo "$line"
done < file.txt

# Array iteration
mapfile -t array < <(command)
for item in "${array[@]}"; do
  echo "$item"
done
```

**Forbidden Patterns:**
```bash
# DON'T parse ls output
for file in $(ls); do  # WRONG

# DON'T use eval
eval "$command"  # WRONG - security risk

# DON'T use backticks
result=`command`  # WRONG - use $() instead

# DON'T leave variables unquoted
rm -rf $dir/*  # WRONG - use "$dir"
```

**Output Functions (from `@tools/common.sh`):**
```bash
print_header "Installing Fabric"     # Blue "==> Installing Fabric"
print_success "Server started"       # Green "✓ Server started"
print_error "Failed to start"        # Red "✗ Failed to start" (stderr)
print_info "Checking status"         # Yellow "→ Checking status"
```

**Error Handling:**
```bash
# Strict mode (required in all scripts)
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Explicit error checking
if ! command; then
  print_error "Command failed"
  exit 1
fi

# Cleanup on exit
trap 'cleanup_function' EXIT
```

### ShellCheck Compliance

**Enabled Rules (from `@.shellcheckrc`):**
```bash
# All rules enabled by default
enable=all

# Warnings as errors
severity=warning

# Bash-specific checks
shell=bash
```

**Common ShellCheck Fixes:**
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals
- Declare variables as `local` in functions
- Use `$()` instead of backticks
- Check command existence: `command -v program >/dev/null 2>&1`

---

## Dependencies

### Core Runtime

| Dependency | Version | Required | Purpose |
|------------|---------|----------|---------|
| **Bash** | 5.0+ | Yes | Shell interpreter |
| **Java** | 21+ | Yes | Minecraft server runtime |
| **curl/wget** | Any | Yes | HTTP downloads |
| **tar/gzip** | Any | Yes | Archive handling |
| **jq/jaq** | Latest | Recommended | JSON parsing |
| **aria2c** | Latest | Optional | Parallel downloads |

### External Tools (Auto-Installed)

**Via mise (`@mise.toml`):**
```toml
[tools]
"cargo:https://github.com/ComunidadAylas/PackSquash" = "latest"
"ubi:zeroBzeroT/ChunkCleaner" = "latest"
"cargo:rustic-rs" = "latest"
```

**Via Scripts:**
- **Fabric Loader** - Downloaded by `mod-updates.sh`
- **Ferium** - Auto-downloaded for mod management
- **lazymc** - Optional, for auto-sleep proxy
- **Playit.gg** - Optional, for public tunneling
- **Infrarust** - Optional, alternative proxy

### Minecraft Mods

**Performance Optimization:**
- ServerCore - Core performance tweaks
- Cesium - Rendering optimization
- Neruina - Crash prevention
- Krypton - Network optimization
- Lithium - General performance

**Cross-Platform:**
- GeyserMC - Bedrock/Java bridge
- Floodgate - Bedrock authentication

**Full list:** See `@docs/mods.txt` (50+ mods)

### Dependency Management

**Update Process:**
```bash
# Update mods via Ferium
./tools/mod-updates.sh ferium

# Update mise tools
mise upgrade

# Update GitHub Actions (via Dependabot)
# Automatically creates PRs for outdated actions
```

**Version Pinning:**
- Minecraft version: `@server.toml` (mcman config)
- Fabric Loader: `@server.toml`
- Java: `mise.toml` (optional)
- Mods: Ferium profile (`minecraft/config/ferium.json`)

---

## Common Tasks

### Server Operations

**Start/Stop:**
```bash
# Start server (with optimization)
./tools/server-start.sh

# Start with lazymc proxy
./tools/server-start.sh --proxy lazymc

# Start with Infrarust proxy
./tools/server-start.sh --proxy infrarust

# Stop server (via RCON or console)
./tools/rcon.sh stop
./tools/mc-client.sh send stop

# Force stop
pkill -INT -f minecraft_server
```

**Console Management:**
```bash
# Attach to console
./tools/mc-client.sh attach

# Send command
./tools/mc-client.sh send "say Hello"

# Send RCON command
./tools/rcon.sh "whitelist add PlayerName"
```

**Monitoring:**
```bash
# Full status report
./tools/monitor.sh status

# Continuous monitoring
./tools/monitor.sh watch

# Health check (for scripts)
./tools/monitor.sh alert
```

### Backup & Recovery

**Create Backups:**
```bash
# Tar archive backup
./tools/backup.sh backup my-backup

# Rustic deduplicated backup
./tools/backup.sh backup --rustic

# Btrfs snapshot
./tools/backup.sh backup --btrfs

# Backup everything (worlds + configs)
./tools/backup.sh backup all
```

**Restore Backups:**
```bash
# List available backups
./tools/backup.sh list

# Restore tar backup
./tools/backup.sh restore backup-name.tar.gz

# Restore Rustic snapshot
./tools/backup.sh restore --rustic snapshot-id

# Restore Btrfs snapshot
./tools/backup.sh restore --btrfs snapshot-name
```

### Maintenance

**Log Management:**
```bash
# Rotate logs
./tools/logrotate.sh rotate

# Clean old logs (keep last 7 days)
./tools/logrotate.sh clean

# Full maintenance
./tools/logrotate.sh maintenance
```

**World Optimization:**
```bash
# Remove unused chunks
./tools/world-optimize.sh --chunks unused

# Optimize with backup
./tools/world-optimize.sh --chunks unused --backup

# Prune specific world
./tools/world-optimize.sh --world world_the_nether --chunks unused
```

**Mod Updates:**
```bash
# Update all mods via Ferium
./tools/mod-updates.sh ferium

# Install new Fabric version
./tools/mod-updates.sh install-fabric 1.21.5

# Download specific mod (manual)
cd minecraft/mods && wget https://example.com/mod.jar
```

### Development

**Linting & Formatting:**
```bash
# Run MegaLinter on all files
mega-linter --flavor bash

# Check specific script
shellcheck tools/backup.sh

# Format with shfmt
shfmt -w -i 2 -bn tools/*.sh
```

**Testing:**
```bash
# Syntax check all scripts
for f in tools/*.sh; do bash -n "$f" || echo "Error in $f"; done

# Dry-run backup
./tools/backup.sh backup test --dry-run

# Test systemd service creation
./tools/systemd-service.sh validate
```

**Adding New Scripts:**
```bash
# 1. Create script in tools/
cat > tools/new-script.sh << 'EOF'
#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
source "${PWD}/tools/common.sh"

main() {
  print_header "New Script"
  # Implementation
}

main "$@"
EOF

# 2. Make executable
chmod +x tools/new-script.sh

# 3. Test syntax
bash -n tools/new-script.sh

# 4. Run ShellCheck
shellcheck tools/new-script.sh

# 5. Document in README.md
```

---

## Configuration Files

### Core Configurations

**Server Management:**
| File | Format | Purpose |
|------|--------|---------|
| `@mise.toml` | TOML | Tool installation and versioning |
| `@server.toml` | TOML | Minecraft server config (mcman) |
| `minecraft/server.properties` | Properties | Java server settings |
| `.config/lazymc/lazymc.toml` | TOML | Auto-sleep proxy config |

**Code Quality:**
| File | Format | Purpose |
|------|--------|---------|
| `@.editorconfig` | INI | Universal editor settings |
| `@.megalinter.yml` | YAML | Multi-language linting |
| `@.shellcheckrc` | RC | Bash linting rules |
| `.github/workflows/mega-linter.yml` | YAML | CI linting automation |

**Mod Configurations:**
| Path | Files | Purpose |
|------|-------|---------|
| `minecraft/config/servercore/` | `config.yml`, `optimizations.yml` | Performance tuning |
| `minecraft/config/Geyser-Fabric/` | `config.yml` | Bedrock bridge settings |
| `minecraft/config/floodgate/` | `config.yml` | Bedrock authentication |
| `minecraft/config/` | 20+ JSON/YAML files | Per-mod settings |

**Git & CI/CD:**
| File | Format | Purpose |
|------|--------|---------|
| `.gitignore` | Text | Exclusions |
| `.gitattributes` | Text | File handling |
| `.github/dependabot.yml` | YAML | Dependency automation |
| `.github/workflows/*.yml` | YAML | CI/CD pipelines |

### Environment Variables

**Server Configuration:**
```bash
# Server memory (default: 4G)
export MAX_MEMORY="8G"

# Backup directory (default: minecraft/backups)
export BACKUP_DIR="/custom/path"

# Max backups to keep (default: 7)
export MAX_BACKUPS=14

# RCON settings
export RCON_HOST="localhost"
export RCON_PORT=25575
export RCON_PASSWORD="password"
```

**Proxy Configuration:**
```bash
# Use lazymc proxy
export USE_LAZYMC=true

# Use Infrarust proxy
export USE_INFRARUST=true

# Use Playit.gg tunnel
export USE_PLAYIT=true
```

**Development:**
```bash
# Enable debug output
export DEBUG=true

# Dry-run mode (no destructive actions)
export DRY_RUN=true
```

---

## AI Assistant Guidelines

### When Editing Code

1. **Always read files first** - Use Read tool before Edit/Write
2. **Preserve existing patterns** - Match the codebase style
3. **Follow Bash conventions** - 2-space indent, strict mode, quoting
4. **Run ShellCheck mentally** - Quote vars, use `[[ ]]`, avoid backticks
5. **Minimize changes** - Edit existing files, don't create new ones unnecessarily
6. **Use common.sh functions** - `print_header`, `print_success`, etc.
7. **Test syntax** - Ensure valid Bash with `bash -n script.sh`

### When Answering Questions

1. **Reference specific files** - Use `@filename:line` format
2. **Check documentation first** - Review `@README.md`, `@docs/SETUP.md`
3. **Provide context** - Explain why, not just what
4. **Include examples** - Show actual commands from the codebase
5. **Link to sources** - Reference relevant files and line numbers

### When Implementing Features

1. **Read TODO.md** - Check if feature is already planned
2. **Follow existing patterns** - Look at similar implementations
3. **Update documentation** - Modify `@README.md` if needed
4. **Add to TODO.md** - Document future enhancements
5. **Test thoroughly** - Verify syntax and logic

### File Reference Format

When referencing code, use this format for easy navigation:
```
The backup function is defined in tools/backup.sh:45
Server startup logic is in tools/server-start.sh:150-250
JVM flags are documented in docs/Flags.txt:10-30
```

---

## Project Maintenance

### Regular Updates

**Weekly:**
- Run `./tools/mod-updates.sh ferium` - Update mods
- Check `./tools/monitor.sh status` - Verify health
- Review `minecraft/logs/latest.log` - Check for errors

**Monthly:**
- Run `./tools/world-optimize.sh` - Prune unused chunks
- Update Java version if available
- Review and close completed TODO.md items

**Quarterly:**
- Update Minecraft version (test in staging first)
- Review and update documentation
- Audit backup retention policies

### Contributing

**Before Submitting PRs:**
1. Run `mega-linter --flavor bash` locally
2. Ensure all scripts pass `shellcheck`
3. Test changes manually
4. Update `@README.md` if adding features
5. Add entry to `@TODO.md` if applicable
6. Check `.github/workflows/` for CI requirements

**Commit Message Format:**
```
feat: Add new backup compression options
fix: Resolve RCON timeout issues
docs: Update SETUP.md with Java 22 instructions
chore: Update dependencies via Dependabot
```

---

## Troubleshooting

**Common Issues:**
| Problem | Solution | Reference |
|---------|----------|-----------|
| Server won't start | Check Java version, EULA acceptance | `@docs/TROUBLESHOOTING.md` |
| Backup fails | Verify disk space, permissions | `tools/backup.sh` logs |
| Mods not loading | Check Fabric version compatibility | `@docs/mods.txt` |
| RCON timeout | Verify port, password in `server.properties` | `@docs/SETUP.md` |

**Debug Mode:**
```bash
# Enable verbose logging
export DEBUG=true
./tools/server-start.sh

# Check systemd service logs
journalctl -u minecraft@default -f

# Monitor in real-time
./tools/monitor.sh watch
```

**Getting Help:**
- Review `@README.md` - Comprehensive feature documentation
- Check `@docs/SETUP.md` - Step-by-step setup guide
- Read `@docs/TROUBLESHOOTING.md` - Common issues and solutions
- Examine `@TODO.md` - Known issues and planned features
- Check GitHub Issues - Community discussions

---

## Quick Reference

**Essential Commands:**
```bash
./tools/prepare.sh                    # Initial setup
./tools/mod-updates.sh install-fabric # Install server
./tools/server-start.sh              # Start server
./tools/mc-client.sh attach          # Open console
./tools/monitor.sh status            # Check health
./tools/backup.sh backup all         # Create backup
./tools/logrotate.sh maintenance     # Clean logs
./tools/world-optimize.sh            # Optimize world
```

**Key Files:**
- `@tools/server-start.sh` - Server launcher
- `@tools/backup.sh` - Backup/restore
- `@tools/monitor.sh` - Health monitoring
- `@README.md` - Main documentation
- `@server.toml` - Server configuration

**Documentation:**
- Setup: `@docs/SETUP.md`
- Troubleshooting: `@docs/TROUBLESHOOTING.md`
- Hosting: `@docs/HOSTING.md`
- JVM Flags: `@docs/Flags.txt`
- Mod List: `@docs/mods.txt`

---

**Last Updated:** 2026-02-10 (Auto-generated for AI assistants)
