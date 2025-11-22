# 🎮 Minecraft Server Management Suite

A professional, production-ready Minecraft server management toolkit with
automated setup, comprehensive monitoring, backup solutions, and performance
optimization.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Fabric](https://img.shields.io/badge/Fabric-1.21.5-green.svg)](https://fabricmc.net/)
[![GraalVM](https://img.shields.io/badge/GraalVM-Optimized-orange.svg)](https://www.graalvm.org/)

## ✨ Features

- 🚀 **Automated Server Management** - One-command server setup and deployment
- 📊 **Real-time Monitoring** - Health checks, performance metrics, and player activity tracking
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
./scripts/mcdl.sh

# 3. Accept EULA and prepare server
./scripts/prepare.sh

# 4. Start the server
./scripts/server-start.sh
```

### Quick Operations

```bash
# Monitor server health
./tools/monitor.sh status

# Create backup
./tools/backup.sh backup

# Start watchdog (auto-restart on crash)
./tools/watchdog.sh monitor

# Rotate logs
./tools/logrotate.sh maintenance
```text

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
```text

### Optional Dependencies

```bash
# Fast parallel downloads
sudo apt install -y aria2

# JSON processing (choose one)
sudo apt install -y jq      # or
cargo install jaq

# Network utilities
sudo apt install -y netcat-openbsd
```text

## 🎮 Server Scripts

Located in `scripts/` directory:

### `server-start.sh`

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
./scripts/server-start.sh

# Use specific JDK
MC_JDK=graalvm ./scripts/server-start.sh
MC_JDK=temurin ./scripts/server-start.sh
```text

### `mcdl.sh`

Fabric server downloader and installer

**Usage:**

```bash
./scripts/mcdl.sh [version]    # Downloads specified version
./scripts/mcdl.sh              # Downloads latest version
```text

### `mod-updates.sh`

Comprehensive mod manager with Modrinth and CurseForge support

**Features:**

- Profile-based mod organization
- Automatic version compatibility checking
- Parallel mod downloading
- Configuration management

**Usage:**

```bash
# Create profile
./scripts/mod-updates.sh profile create my-mods 1.21.5 fabric ./mods

# Add mods
./scripts/mod-updates.sh add modrinth sodium
./scripts/mod-updates.sh add modrinth lithium

# Download/update all mods
./scripts/mod-updates.sh upgrade

# List mods
./scripts/mod-updates.sh list
```text

### `mc-client.sh`

Minecraft Java Edition client launcher

**Usage:**

```bash
./scripts/mc-client.sh 1.21.5 YourUsername
MC_DIR=/custom/path ./scripts/mc-client.sh 1.21.5 Player
```text

### `prepare.sh`

Initial server preparation (EULA acceptance, directory setup)

### `infrarust.sh`

Infrarust proxy tunnel configuration

## 🛠️ Management Tools

Located in `tools/` directory:

### `backup.sh` - Backup Management

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
./tools/backup.sh backup

# Backup specific components
./tools/backup.sh backup world
./tools/backup.sh backup config
./tools/backup.sh backup mods

# List backups
./tools/backup.sh list

# Restore backup
./tools/backup.sh restore backups/worlds/world_20250119_120000.tar.gz

# Clean old backups
./tools/backup.sh cleanup --max-backups 10
```text

**Automated Backups:**

```bash
# Add to crontab for daily backups at 4 AM
0 4 * * * cd /path/to/MC-Server && ./tools/backup.sh backup all
```text

### `monitor.sh` - Server Monitoring

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
./tools/monitor.sh status

# Continuous monitoring
./tools/monitor.sh watch

# Health check (for scripts)
./tools/monitor.sh alert

# View player activity
./tools/monitor.sh players

# Check errors
./tools/monitor.sh errors
```text

### `watchdog.sh` - Auto-Restart & Crash Recovery

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
./tools/watchdog.sh monitor

# Scheduled restart with 10-minute warning
./tools/watchdog.sh restart 600

# Immediate restart
./tools/watchdog.sh restart 0

# Start server
./tools/watchdog.sh start

# Stop server
./tools/watchdog.sh stop

# Check status
./tools/watchdog.sh status
```text

**Run as Background Service:**

```bash
# Using screen
screen -dmS watchdog bash -c "cd /path/to/MC-Server && ./tools/watchdog.sh monitor"

# Using tmux
tmux new-session -d -s watchdog "cd /path/to/MC-Server && ./tools/watchdog.sh monitor"
```text

### `logrotate.sh` - Log Management

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
./tools/logrotate.sh maintenance

# Rotate logs
./tools/logrotate.sh rotate

# Compress old logs
./tools/logrotate.sh compress

# Clean logs older than 14 days
./tools/logrotate.sh clean 14

# Show statistics
./tools/logrotate.sh stats

# View log
./tools/logrotate.sh view latest.log 100

# Search logs
./tools/logrotate.sh search "error" latest.log
```text

**Automated Log Rotation:**

```bash
# Add to crontab for weekly log maintenance
0 3 * * 0 cd /path/to/MC-Server && ./tools/logrotate.sh maintenance
```text

## ⚙️ Configuration

### Environment Variables

**Server Launcher (`server-start.sh`)**:

- `MC_JDK` - JDK selection: `graalvm` or `temurin` (default: auto-detect)
- `JAVA_GRAALVM` - Path to GraalVM installation
- `JAVA_TEMURIN` - Path to Temurin installation

**Client Launcher (`mc-client.sh`)**:

- `MC_DIR` - Minecraft directory (default: `~/.minecraft`)

**Mod Manager (`mod-updates.sh`)**:

- `XDG_CONFIG_HOME` - Config directory (default: `~/.config`)

### Server Properties

Edit `server.properties` to configure:

- Server port, IP binding
- Max players, view distance
- Game mode, difficulty
- World generation settings

### Plugin Configuration

All plugin configs are in `config/` directory:

- **ServerCore** (`config/servercore/`) - Performance optimization settings
- **Geyser** (`config/Geyser-Fabric/`) - Bedrock Edition support
- **Floodgate** (`config/floodgate/`) - Bedrock authentication
- And more...

## 📚 Documentation

Detailed documentation available in `docs/`:

- **[SETUP.md](docs/SETUP.md)** - Comprehensive setup guide
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[TOOLS.md](docs/TOOLS.md)** - Detailed tool documentation
- **[Flags.txt](docs/Flags.txt)** - JVM optimization flags reference
- **[mods.txt](docs/mods.txt)** - Complete list of installed mods

## 📁 Directory Structure

```text
MC-Server/
├── scripts/                    # Server management scripts
│   ├── server-start.sh         # Main server launcher
│   ├── mod-updates.sh          # Mod management
│   ├── mcdl.sh                 # Fabric downloader
│   ├── mc-client.sh            # Client launcher
│   ├── prepare.sh              # Initial setup
│   ├── infrarust.sh            # Proxy configuration
│   └── test_common.sh          # Tests
│
├── tools/                      # Management utilities
│   ├── backup.sh               # Backup automation
│   ├── monitor.sh              # Server monitoring
│   ├── watchdog.sh             # Auto-restart & crash recovery
│   └── logrotate.sh            # Log management
│
├── config/                     # Plugin configurations
│   ├── servercore/             # ServerCore settings
│   ├── Geyser-Fabric/          # Geyser configuration
│   ├── floodgate/              # Floodgate settings
│   └── ...                     # Other plugin configs
│
├── docs/                       # Documentation
│   ├── SETUP.md                # Setup guide
│   ├── TROUBLESHOOTING.md      # Troubleshooting guide
│   ├── TOOLS.md                # Tools documentation
│   ├── Flags.txt               # JVM flags reference
│   ├── mods.txt                # Mod list
│   └── TODO.md                 # Development TODO
│
├── backups/                    # Backup storage
│   ├── worlds/                 # World backups
│   └── configs/                # Config backups
│
├── lib/                        # Shared utilities
│   └── common.sh               # Common functions
│
├── .github/                    # GitHub configuration
│   ├── workflows/              # CI/CD pipelines
│   └── ISSUE_TEMPLATE/         # Issue templates
│
├── server.properties           # Minecraft server config
├── config.yaml                 # Infrarust config
├── gamemode.ini                # GameMode settings
└── README.md                   # This file
```text

## 🔧 Maintenance Tasks

### Daily

- Monitor server status: `./tools/monitor.sh status`
- Check for errors: `./tools/monitor.sh errors`

### Weekly

- Create backup: `./tools/backup.sh backup`
- Rotate logs: `./tools/logrotate.sh maintenance`
- Update mods: `./scripts/mod-updates.sh upgrade`

### Monthly

- Clean old backups: `./tools/backup.sh cleanup`
- Clean old logs: `./tools/logrotate.sh clean 30`
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
