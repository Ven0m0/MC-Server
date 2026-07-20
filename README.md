# 🎮 Minecraft Server Management Suite

A professional, production-ready Minecraft server management toolkit with
automated setup, comprehensive monitoring, backup solutions, and performance
optimization.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Fabric](https://img.shields.io/badge/Fabric-1.21.5-green.svg)](https://fabricmc.net/)
[![GraalVM](https://img.shields.io/badge/GraalVM-Optimized-orange.svg)](https://www.graalvm.org/)

## ✨ Features

- 🚀 **Automated Server Management** - One-command server setup and deployment
- 📊 **Real-time Monitoring** - Health checks, performance metrics, and player
  activity tracking
- 💾 **Automated Backups** - Scheduled backups with rotation and compression
- 🔄 **Auto-Restart & Crash Recovery** - Watchdog service for maximum uptime
- 📝 **Log Management** - Automatic log rotation, compression, and archiving
- 🎯 **Cross-Platform Support** - Java + Bedrock Edition via Geyser
- ⚡ **Performance Optimized** - GraalVM support with tuned JVM flags
- 🔧 **Mod Management** - Profile-based mod organization and updates
- 🌐 **Public Hosting Ready** - Playit.gg and Infrarust proxy support

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Server Scripts](#server-scripts)
- [Management Tools](#management-tools)
- [Configuration](#configuration)
- [Documentation](#documentation)
- [Directory Structure](#directory-structure)

## 🚀 Quick Start

### Initial Setup

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd MC-Server

# 2. Download and install Fabric server
./tools/mod-updates.py install-fabric

# 3. Accept EULA and prepare server
./tools/prepare.py

# 4. Start the server
./tools/server-start.py
```

### Quick Operations

```bash
# Monitor server health
./tools/monitor.py status

# Create backup
./tools/backup.py backup

# Start watchdog (auto-restart on crash)
./tools/watchdog.py monitor

# Rotate logs
./tools/logrotate.py maintenance
```

## 📦 Installation

### System Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 11+, or similar)
- **RAM**: Minimum 4GB, Recommended 8GB+
- **Disk**: 10GB+ free space
- **Java**: Java 21+ (GraalVM recommended)

### Required Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y openjdk-21-jdk curl wget unzip screen

# Optional: Install GraalVM for better performance
# Download from https://www.graalvm.org/downloads/
```

### Optional Dependencies

```bash
# Fast parallel downloads
sudo apt install -y aria2

# JSON processing (choose one)
sudo apt install -y jq      # or
cargo install jaq

# Network utilities
sudo apt install -y netcat-openbsd
```

## 🎮 Server Scripts

Located in `tools/` directory:

### `server-start.py`

Main server launcher with advanced optimizations

**Features:**

- Auto-detection of CPU cores and RAM
- GraalVM or Eclipse Temurin JDK support
- Optimized G1GC garbage collection settings
- Transparent Huge Pages support
- GameMode integration for performance
- Playit.gg tunnel support

**Usage:**

```bash
./tools/server-start.py

# Use specific JDK
MC_JDK=graalvm ./tools/server-start.py
MC_JDK=temurin ./tools/server-start.py
```

### `mod-updates.py`

Fabric server installer and comprehensive mod management system

**Features:**

- Fabric server installation with version selection
- Ferium mod updates
- mc-repack mod compression
- GeyserConnect extension updates
- Full workflow automation

**Usage:**

```bash
# Install Fabric server
./tools/mod-updates.py install-fabric              # Latest stable
./tools/mod-updates.py install-fabric 1.21.5       # Specific version
./tools/mod-updates.py install-fabric 1.21.5 0.16.10  # With loader version

# Mod management
./tools/mod-updates.py ferium                      # Update mods via Ferium
./tools/mod-updates.py repack ./mods ./mods-repacked  # Repack mods
./tools/mod-updates.py geyser                      # Update GeyserConnect

# Full workflow
./tools/mod-updates.py full-update                 # Complete update cycle
```

### `mc-client.py`

Minecraft Java Edition client launcher

**Usage:**

```bash
./tools/mc-client.py 1.21.5 YourUsername
MC_DIR=/custom/path ./tools/mc-client.py 1.21.5 Player
```

### `prepare.py`

Initial server preparation (EULA acceptance, directory setup)

## 🛠️ Management Tools

Located in `tools/` directory:

### `backup.py` - Backup Management

Automated backup solution for worlds, configurations, and mods.

**Features:**

- Automated world backups with server notifications
- Configuration and mod backups
- Automatic backup rotation (keeps last N backups)
- Restore functionality
- Compression support

**Usage:**

```bash
# Full backup
./tools/backup.py backup

# Backup specific components
./tools/backup.py backup world
./tools/backup.py backup config
./tools/backup.py backup mods

# List backups
./tools/backup.py list

# Restore backup
./tools/backup.py restore minecraft/backups/worlds/world_20250119_120000.tar.gz

# Clean old backups
./tools/backup.py cleanup --max-backups 10
```

**Automated Backups:**

```bash
# Add to crontab for daily backups at 4 AM
0 4 * * * cd /path/to/MC-Server && ./tools/backup.py backup all
```

### `monitor.py` - Server Monitoring

Real-time server health monitoring and performance tracking.

**Features:**

- Process and port status checking
- Memory and CPU usage tracking
- Disk space monitoring
- Player activity tracking
- Error detection and reporting
- TPS monitoring (with Spark plugin)

**Usage:**

```bash
# Show status
./tools/monitor.py status

# Continuous monitoring
./tools/monitor.py watch

# Health check (for scripts)
./tools/monitor.py alert

# View player activity
./tools/monitor.py players

# Check errors
./tools/monitor.py errors
```

### `watchdog.py` - Auto-Restart & Crash Recovery

Automatic server monitoring with crash recovery and restart capabilities.

**Features:**

- Automatic restart on crashes
- Configurable restart attempts and cooldowns
- Emergency backup before restart
- Graceful shutdown handling
- Scheduled restarts with player warnings

**Usage:**

```bash
# Start watchdog monitor (run in screen/tmux)
./tools/watchdog.py monitor

# Scheduled restart with 10-minute warning
./tools/watchdog.py restart 600

# Immediate restart
./tools/watchdog.py restart 0

# Start server
./tools/watchdog.py start

# Stop server
./tools/watchdog.py stop

# Check status
./tools/watchdog.py status
```

**Run as Background Service:**

```bash
# Using screen
screen -dmS watchdog bash -c "cd /path/to/MC-Server && ./tools/watchdog.py monitor"

# Using tmux
tmux new-session -d -s watchdog "cd /path/to/MC-Server && ./tools/watchdog.py monitor"
```

### `logrotate.py` - Log Management

Automated log rotation, compression, and archiving.

**Features:**

- Automatic log rotation based on size
- Compression of old logs
- Age-based cleanup
- Archive size limiting
- Log viewing and searching

**Usage:**

```bash
# Full maintenance
./tools/logrotate.py maintenance

# Rotate logs
./tools/logrotate.py rotate

# Compress old logs
./tools/logrotate.py compress

# Clean logs older than 14 days
./tools/logrotate.py clean 14

# Show statistics
./tools/logrotate.py stats

# View log
./tools/logrotate.py view latest.log 100

# Search logs
./tools/logrotate.py search "error" latest.log
```

**Automated Log Rotation:**

```bash
# Add to crontab for weekly log maintenance
0 3 * * 0 cd /path/to/MC-Server && ./tools/logrotate.py maintenance
```

### `systemd-service.py` - Systemd Service Management

Create and manage systemd services for Minecraft server and Infrarust proxy.

**Features:**

- Automated systemd service creation
- Infrarust proxy service support
- Service lifecycle management (enable, start, stop, restart)
- Log viewing via journalctl
- Auto-start on boot support

**Usage:**

```bash
# Create Minecraft server service
./tools/systemd-service.py create

# Create Infrarust proxy service (installs infrarust if needed)
./tools/systemd-service.py create-infrarust /opt/infrarust minecraft

# Enable service (auto-start on boot)
./tools/systemd-service.py enable

# Start service
./tools/systemd-service.py start

# Stop service
./tools/systemd-service.py stop

# Restart service
./tools/systemd-service.py restart

# View status
./tools/systemd-service.py status

# View logs
./tools/systemd-service.py logs 100

# Follow logs in real-time
./tools/systemd-service.py follow
```

## ⚙️ Configuration

### Environment Variables

**Server Launcher (`server-start.py`)**:

- `MC_JDK` - JDK selection: `graalvm` or `temurin` (default: auto-detect)
- `JAVA_GRAALVM` - Path to GraalVM installation
- `JAVA_TEMURIN` - Path to Temurin installation

**Client Launcher (`mc-client.py`)**:

- `MC_DIR` - Minecraft directory (default: `~/.minecraft`)

**Mod Manager (`mod-updates.py`)**:

- `XDG_CONFIG_HOME` - Config directory (default: `~/.config`)

### Server Properties

Edit `server.properties` to configure:

- Server port, IP binding
- Max players, view distance
- Game mode, difficulty
- World generation settings

### Plugin Configuration

All plugin configs are in `minecraft/config/` directory:

- **ServerCore** (`minecraft/config/servercore/`) - Performance optimization settings
- **Geyser** (`minecraft/config/Geyser-Fabric/`) - Bedrock Edition support
- **Floodgate** (`minecraft/config/floodgate/`) - Bedrock authentication
- And more...

## 📚 Documentation

Detailed documentation available in `docs/`:

- **[SETUP.md](docs/SETUP.md)** - Comprehensive setup guide
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[TOOLS.md](docs/TOOLS.md)** - Detailed tool documentation
- **[OPTIMIZE-RESOURCEPACKS.md](docs/OPTIMIZE-RESOURCEPACKS.md)** - PackSquash resource pack optimization
- **[MOD-JAR-COMPRESSION.md](docs/MOD-JAR-COMPRESSION.md)** - mc-repack mod jar compression
- **[Flags.txt](docs/Flags.txt)** - JVM optimization flags reference
- **[mods.txt](docs/mods.txt)** - Complete list of installed mods

## 📁 Directory Structure

```
MC-Server/
├── tools/                      # All operational scripts
│   ├── server-start.py         # Main server launcher with lazymc support
│   ├── mod-updates.py          # Fabric installer & mod management
│   ├── mc-client.py            # Client launcher
│   ├── prepare.py              # Initial setup & lazymc installation
│   ├── backup.py               # Backup automation
│   ├── monitor.py              # Server monitoring
│   ├── watchdog.py             # Auto-restart & crash recovery
│   ├── logrotate.py            # Log management
│   ├── systemd-service.py      # Systemd service management
│   ├── rcon.py                 # RCON protocol handler
│   └── world-optimize.py       # World optimization
│
├── minecraft/                  # Minecraft-specific data
│   ├── config/                 # Plugin/mod configurations
│   │   ├── servercore/         # ServerCore settings
│   │   ├── Geyser-Fabric/      # Geyser configuration
│   │   ├── floodgate/          # Floodgate settings
│   │   ├── versions.py         # Mod version tracker
│   │   └── ...                 # Other plugin configs
│   ├── backups/                # Backup storage
│   │   ├── worlds/             # World backups
│   │   ├── configs/            # Config backups
│   │   └── btrfs-snapshots/    # Btrfs snapshots (if supported)
│   ├── server.properties       # Minecraft server config
│   └── packsquash.toml         # Resource pack optimization config
│
├── docs/                       # Documentation
│   ├── SETUP.md                # Setup guide
│   ├── TROUBLESHOOTING.md      # Troubleshooting guide
│   ├── Flags.txt               # JVM flags reference
│   ├── mods.txt                # Mod list
│   └── mods-links.txt          # Mod download links
│
├── lib/                        # Shared utilities
│   └── common.py               # Common functions
│
├── .github/                    # GitHub configuration
│   ├── workflows/              # CI/CD pipelines
│   ├── ISSUE_TEMPLATE/         # Issue templates
│   └── instructions/           # AI assistant context
│       ├── claude.md           # Claude AI instructions
│       ├── gemini.md           # Gemini AI instructions
│       └── copilot.md          # Copilot instructions
│
├── .config/                    # Application configs
│   └── rustic/                 # Rustic backup config
│
└── README.md                   # This file
```

## 🔧 Maintenance Tasks

### Daily

- Monitor server status: `./tools/monitor.py status`
- Check for errors: `./tools/monitor.py errors`

### Weekly

- Create backup: `./tools/backup.py backup`
- Rotate logs: `./tools/logrotate.py maintenance`
- Update mods: `./tools/mod-updates.py upgrade`

### Monthly

- Clean old backups: `./tools/backup.py cleanup`
- Clean old logs: `./tools/logrotate.py clean 30`
- Review server performance and adjust configs

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Fabric](https://fabricmc.net/) - Modding framework
- [Geyser](https://geysermc.org/) - Bedrock Edition support
- [ServerCore](https://modrinth.com/mod/servercore) - Performance optimization
- [Ferium](https://github.com/gorilla-devs/ferium) - Mod manager inspiration
- [GraalVM](https://www.graalvm.org/) - High-performance JVM

## 🔗 Useful Resources

- [Minecraft Server Optimization Guide](https://github.com/YouHaveTrouble/minecraft-optimization)
- [Fabric Mod List](https://fabricmc.net/use/mods/)
- [Modrinth](https://modrinth.com/) - Mod repository
- [Server Optimization Flags](docs/Flags.txt)

## 📞 Support

- 🐛 [Report Issues](../../issues)
- 💬 [Discussions](../../discussions)
- 📖 [Documentation](docs/)

---

**Note**: This is a production-ready server management suite. Always test changes in a development environment before applying to production servers.
