# mcctl Integration Guide

This repository includes an integrated and modernized version of [Kraftland/mcctl](https://github.com/Kraftland/mcctl) for managing Paper and Spigot Minecraft servers.

## Overview

The mcctl integration provides Paper/Spigot server management capabilities alongside the existing Fabric-focused tooling. The original mcctl has been refactored to follow modern bash practices and integrate seamlessly with this repository's architecture.

## New Tools

### 1. `tools/mcctl.sh` - Paper/Spigot Server Management

Provides commands for building, updating, and managing Paper/Spigot servers and their plugins.

#### Server Commands

```bash
# Build Paper server (latest or specific version)
./tools/mcctl.sh build-paper 1.21.1

# Build Spigot server
./tools/mcctl.sh build-spigot latest

# Initialize new server directory
./tools/mcctl.sh init

# Accept EULA
./tools/mcctl.sh accept-eula
```

#### Plugin Management

```bash
# Update a specific plugin
./tools/mcctl.sh update geyser
./tools/mcctl.sh update viaversion
./tools/mcctl.sh update protocollib

# Update all common plugins
./tools/mcctl.sh update-all
```

#### Supported Plugins

- **viaversion** - Protocol compatibility (cross-version support)
- **viabackwards** - Backwards protocol support
- **multilogin** - Multiple authentication backends
- **floodgate** - Bedrock edition support (without Xbox auth)
- **geyser** - Bedrock/Java crossplay
- **protocollib** - Packet manipulation library
- **vault** - Permissions/economy/chat API
- **luckperms** - Advanced permissions management
- **griefprevention** - Land protection plugin

### 2. `tools/systemd-service.sh` - Systemd Integration

Manage your Minecraft server as a systemd service for automatic startup and easy management.

#### Setup

```bash
# Create systemd service
sudo ./tools/systemd-service.sh create

# Enable auto-start on boot
sudo ./tools/systemd-service.sh enable

# Start the service
sudo ./tools/systemd-service.sh start
```

#### Management

```bash
# Check service status
./tools/systemd-service.sh status

# View logs
./tools/systemd-service.sh logs 100

# Follow logs in real-time
./tools/systemd-service.sh follow

# Stop service
sudo ./tools/systemd-service.sh stop

# Restart service
sudo ./tools/systemd-service.sh restart

# Remove service
sudo ./tools/systemd-service.sh remove
```

#### Features

- **Auto-start**: Server starts automatically on boot
- **Auto-restart**: Automatically restarts on crashes
- **Resource limits**: CPU and memory limits for safety
- **Security hardening**: PrivateTmp, ProtectSystem, NoNewPrivileges
- **Logging**: Full integration with systemd journal (`journalctl`)

### 3. Enhanced `tools/backup.sh` - Btrfs Snapshot Support

The backup tool now supports instant Btrfs snapshots in addition to traditional tar-based backups.

#### Tar Backups (Works on all filesystems)

```bash
# Full backup
./tools/backup.sh backup

# Backup specific components
./tools/backup.sh backup world
./tools/backup.sh backup config
./tools/backup.sh backup mods

# List backups
./tools/backup.sh list

# Restore backup
./tools/backup.sh restore backups/worlds/world_20250119_120000.tar.gz
```

#### Btrfs Snapshots (Requires Btrfs filesystem)

```bash
# Create snapshot
./tools/backup.sh snapshot

# Create named snapshot
./tools/backup.sh snapshot ./world my-backup

# List snapshots
./tools/backup.sh snapshot-list

# Restore snapshot
./tools/backup.sh snapshot-restore my-backup

# Delete snapshot
./tools/backup.sh snapshot-delete old-backup
```

#### Btrfs Benefits

- **Instant**: Snapshots are created in milliseconds
- **Space-efficient**: Only stores changed data (copy-on-write)
- **Atomic**: Snapshot is always consistent
- **Scalable**: Hundreds of snapshots with minimal overhead

## Integration with Existing Tools

### Fabric + Paper/Spigot Side-by-Side

You can run both Fabric and Paper/Spigot servers from the same repository:

```bash
# Fabric workflow
./scripts/mcdl.sh 1.21.1              # Download Fabric
./scripts/mod-updates.sh full-update  # Update mods
./scripts/server-start.sh             # Start Fabric server

# Paper workflow
./tools/mcctl.sh build-paper 1.21.1   # Download Paper
./tools/mcctl.sh update-all           # Update plugins
./scripts/server-start.sh             # Start Paper server
```

The `server-start.sh` script automatically detects the server jar and applies appropriate JVM flags.

### Backup Strategy

Combine tar backups and Btrfs snapshots for optimal protection:

```bash
# Daily: Quick Btrfs snapshot (if available)
./tools/backup.sh snapshot

# Weekly: Full tar backup for off-site storage
./tools/backup.sh backup

# Before major changes: Named snapshot
./tools/backup.sh snapshot ./world pre-update-$(date +%Y%m%d)
```

### Systemd + lazymc

For the ultimate setup, combine systemd service with lazymc for auto-sleep:

```bash
# Setup lazymc
./scripts/lazymc-setup.sh install

# Create systemd service that starts lazymc instead
./tools/systemd-service.sh create ./tools/lazymc.sh start

# Enable auto-start
sudo ./tools/systemd-service.sh enable
```

## Migration from Original mcctl

If you were using the original Kraftland/mcctl, here's what changed:

### Differences

| Original mcctl | Integrated mcctl |
|----------------|------------------|
| Monolithic 1500-line script | Modular, ~500 lines |
| Uses `echo` | Uses `printf` for consistency |
| Global variables | Local scoped variables |
| Mixed coding styles | Strict mode, consistent style |
| Includes systemd code | Separated to `systemd-service.sh` |
| Screen session management | Use systemd or tmux instead |
| Email reporting | Planned for future release |

### What's Preserved

- ✅ Paper/Spigot building
- ✅ Plugin updates (all major plugins)
- ✅ EULA acceptance
- ✅ Btrfs snapshot support
- ✅ Systemd service creation

### What's Different

- ❌ No built-in screen session management (use systemd instead)
- ❌ No email reporting (may be added later)
- ❌ No BuildTools for Spigot compilation (uses pre-built jars)
- ❌ No Windows/macOS support (Linux only, as before)

## Requirements

### Core Requirements

- **Bash**: 5.0+
- **Java**: 21+ (GraalVM or Eclipse Temurin recommended)
- **Git**: For version detection
- **JSON processor**: `jaq` (preferred) or `jq`

### Download Tools (one of)

- `aria2c` (recommended - fastest, parallel downloads)
- `curl` (fallback)
- `wget` (fallback)

### Optional

- **btrfs-progs**: For Btrfs snapshot support
- **sudo**: For systemd service management
- **systemd**: For service integration

## Examples

### Complete Paper Server Setup

```bash
# 1. Initialize server
./tools/mcctl.sh init

# 2. Build Paper
./tools/mcctl.sh build-paper 1.21.1

# 3. Install plugins
./tools/mcctl.sh update geyser
./tools/mcctl.sh update floodgate
./tools/mcctl.sh update viaversion
./tools/mcctl.sh update luckperms

# 4. Configure systemd service
sudo ./tools/systemd-service.sh create
sudo ./tools/systemd-service.sh enable

# 5. Start server
sudo ./tools/systemd-service.sh start

# 6. Monitor
./tools/systemd-service.sh follow
```

### Automated Backup Workflow

```bash
#!/bin/bash
# backup-cron.sh - Run via cron

cd /opt/minecraft

# Stop server gracefully
systemctl stop minecraft-server

# Create snapshots if on Btrfs
if ./tools/backup.sh snapshot 2>/dev/null; then
  echo "Btrfs snapshot created"
else
  # Fallback to tar backup
  ./tools/backup.sh backup
fi

# Start server
systemctl start minecraft-server

# Cleanup old backups
./tools/backup.sh cleanup
```

Add to crontab:
```
0 3 * * * /opt/minecraft/backup-cron.sh
```

## Troubleshooting

### "No JSON processor found"

Install jaq or jq:
```bash
# Arch Linux
sudo pacman -S jq

# Ubuntu/Debian
sudo apt install jq

# Preferred: Install jaq (faster)
cargo install jaq
```

### "Failed to create snapshot (root access required)"

Btrfs snapshots require root permissions:
```bash
# Use sudo
sudo ./tools/backup.sh snapshot

# Or add yourself to disk group (less secure)
sudo usermod -aG disk $USER
```

### "Service not found"

Create the service first:
```bash
sudo ./tools/systemd-service.sh create
```

### Paper build download fails

Try specifying a specific build number, or check your internet connection:
```bash
# The script will automatically try older builds
./tools/mcctl.sh build-paper 1.21.1
```

## Credits

- **Original mcctl**: [Kraftland/mcctl](https://github.com/Kraftland/mcctl)
- **Integration & Modernization**: MC-Server Project
- **License**: GPL-3.0 (inherited from original mcctl)

## Support

For issues specific to the integration:
- Open an issue in this repository

For general mcctl questions:
- See the [original mcctl repository](https://github.com/Kraftland/mcctl)

For Minecraft server help:
- [PaperMC Documentation](https://docs.papermc.io/)
- [Spigot Documentation](https://www.spigotmc.org/wiki/)
