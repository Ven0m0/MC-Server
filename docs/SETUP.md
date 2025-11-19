# 📖 Minecraft Server Setup Guide

Complete step-by-step guide for setting up and configuring your Minecraft server.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Server Configuration](#server-configuration)
- [Performance Tuning](#performance-tuning)
- [Automation Setup](#automation-setup)
- [Security](#security)
- [Advanced Configuration](#advanced-configuration)

## Prerequisites

### System Requirements

**Minimum Requirements:**
- CPU: 2 cores
- RAM: 4GB
- Disk: 10GB free space
- OS: Linux (Ubuntu 20.04+, Debian 11+)
- Java: OpenJDK 21+

**Recommended Requirements:**
- CPU: 4+ cores
- RAM: 8GB+
- Disk: 20GB+ SSD
- OS: Ubuntu 22.04 LTS or Debian 12
- Java: GraalVM 21+ for best performance

### Install Dependencies

#### Ubuntu/Debian

```bash
# Update package list
sudo apt update

# Install required packages
sudo apt install -y openjdk-21-jdk curl wget unzip screen git

# Install optional tools
sudo apt install -y aria2 jq netcat-openbsd htop

# Install build tools (if compiling anything)
sudo apt install -y build-essential
```

#### Install GraalVM (Recommended)

```bash
# Download GraalVM
wget https://download.oracle.com/graalvm/21/latest/graalvm-jdk-21_linux-x64_bin.tar.gz

# Extract
tar -xzf graalvm-jdk-21_linux-x64_bin.tar.gz

# Move to /opt
sudo mv graalvm-jdk-21.* /opt/graalvm-21

# Set environment variable
export JAVA_GRAALVM=/opt/graalvm-21
echo 'export JAVA_GRAALVM=/opt/graalvm-21' >> ~/.bashrc
```

## Initial Setup

### 1. Clone Repository

```bash
# Clone the repository
git clone <your-repo-url>
cd MC-Server

# Make scripts executable (if not already)
chmod +x scripts/*.sh tools/*.sh
```

### 2. Download Fabric Server

```bash
# Download latest version
./scripts/mcdl.sh

# Or specify version
./scripts/mcdl.sh 1.21.5
```

This will download:
- Fabric loader
- Fabric installer
- Minecraft server JAR
- Launch script

### 3. Accept EULA and Prepare

```bash
./scripts/prepare.sh
```

This script:
- Accepts the Minecraft EULA
- Creates necessary directories
- Sets up initial configuration

### 4. First Server Start

```bash
./scripts/server-start.sh
```

First start will:
- Generate world
- Create configuration files
- Initialize all plugins

**Note**: First start takes 2-5 minutes depending on your hardware.

## Server Configuration

### Basic Server Properties

Edit `server.properties`:

```properties
# Server Network Settings
server-port=25565
server-ip=0.0.0.0
online-mode=true

# World Settings
level-name=world
level-type=minecraft\:normal
difficulty=normal
gamemode=survival

# Performance Settings
max-players=20
view-distance=12
simulation-distance=8

# Spawn Protection
spawn-protection=16
```

### Configure Geyser (Bedrock Support)

Edit `config/Geyser-Fabric/config.yml`:

```yaml
bedrock:
  # Port for Bedrock clients
  port: 19132
  # Address to bind to
  address: 0.0.0.0

remote:
  # Your Java server address
  address: auto
  port: 25565
  auth-type: floodgate
```

### Configure ServerCore (Performance)

Edit `config/servercore/config.yml`:

```yaml
# Dynamic Performance
dynamic:
  enabled: true
  target_mspt: 40

# Entity Activation Range
activation_range:
  enabled: true
  villager_work_immunity_after: 100
  villager_work_immunity_for: 100

# Mob Caps
mobcap:
  hostile: 70
  creature: 10
  ambient: 15
  axolotl: 5
  underground_water_creature: 5
  water_creature: 5
  water_ambient: 20
```

## Performance Tuning

### JVM Flags

The server uses optimized flags automatically. To customize:

Edit `scripts/server-start.sh` and modify the JVM_OPTS section:

```bash
# Memory settings (auto-calculated by default)
MIN_RAM="2G"
MAX_RAM="6G"

# Custom flags
CUSTOM_FLAGS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200"
```

For detailed flag explanations, see [Flags.txt](Flags.txt).

### System Optimization

#### Enable Transparent Huge Pages

```bash
# Temporary (until reboot)
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Permanent (add to /etc/rc.local or systemd service)
```

#### CPU Governor

```bash
# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

#### GameMode Integration

Install GameMode for automatic performance optimization:

```bash
sudo apt install -y gamemode
```

The server launcher will automatically use GameMode if available.

### Network Optimization

For better network performance:

```bash
# Increase network buffer sizes
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216

# Make permanent
echo "net.core.rmem_max=16777216" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max=16777216" | sudo tee -a /etc/sysctl.conf
```

## Automation Setup

### Automated Backups

#### Daily Backups (Cron)

```bash
# Edit crontab
crontab -e

# Add daily backup at 4 AM
0 4 * * * cd /path/to/MC-Server && ./tools/backup.sh backup all >> /var/log/mc-backup.log 2>&1

# Weekly full maintenance
0 3 * * 0 cd /path/to/MC-Server && ./tools/logrotate.sh maintenance >> /var/log/mc-logrotate.log 2>&1
```

### Watchdog Service (Auto-Restart)

#### Using Systemd

Create `/etc/systemd/system/minecraft-watchdog.service`:

```ini
[Unit]
Description=Minecraft Server Watchdog
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/path/to/MC-Server
ExecStart=/path/to/MC-Server/tools/watchdog.sh monitor
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minecraft-watchdog
sudo systemctl start minecraft-watchdog
```

#### Using Screen (Alternative)

```bash
# Start watchdog in screen
screen -dmS mc-watchdog bash -c "cd /path/to/MC-Server && ./tools/watchdog.sh monitor"

# Attach to view logs
screen -r mc-watchdog
```

### Monitoring Dashboard

Set up continuous monitoring:

```bash
# In a tmux/screen session
./tools/monitor.sh watch --interval 30
```

## Security

### Firewall Configuration

```bash
# Allow Minecraft ports
sudo ufw allow 25565/tcp  # Java Edition
sudo ufw allow 19132/udp  # Bedrock Edition

# Enable firewall
sudo ufw enable
```

### User Permissions

Run server as non-root user:

```bash
# Create dedicated user
sudo useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft

# Move server files
sudo mv MC-Server /opt/minecraft/
sudo chown -R minecraft:minecraft /opt/minecraft/

# Run as minecraft user
sudo -u minecraft bash
cd /opt/minecraft/MC-Server
./scripts/server-start.sh
```

### Whitelist Setup

Enable whitelist in `server.properties`:

```properties
white-list=true
enforce-whitelist=true
```

Add players:

```bash
# In server console
whitelist add PlayerName
whitelist reload
```

### Backup Encryption (Optional)

Encrypt sensitive backups:

```bash
# Encrypt backup
gpg --symmetric --cipher-algo AES256 backups/worlds/world_20250119_120000.tar.gz

# Decrypt backup
gpg --decrypt backups/worlds/world_20250119_120000.tar.gz.gpg > backup.tar.gz
```

## Advanced Configuration

### Public Server Hosting

#### Using Playit.gg

```bash
# Install playit
curl -SsL https://playit-cloud.github.io/ppa/key.gpg | sudo apt-key add -
sudo curl -SsL -o /etc/apt/sources.list.d/playit-cloud.list https://playit-cloud.github.io/ppa/playit-cloud.list
sudo apt update
sudo apt install playit

# Configure (follow prompts)
playit
```

#### Using Infrarust

Edit `config.yaml`:

```yaml
bind: 0.0.0.0:25565
providers:
  file:
    path: providers.toml
    hot_reload: true
```

### Multiple Server Instances

Run multiple servers:

```bash
# Copy server directory
cp -r MC-Server MC-Server-2

# Edit server.properties for different port
nano MC-Server-2/server.properties
# Change: server-port=25566

# Start second server
cd MC-Server-2
./scripts/server-start.sh
```

### Mod Management

#### Adding Mods

```bash
# Create mod profile
./scripts/mod-updates.sh profile create my-server 1.21.5 fabric ./mods

# Add performance mods
./scripts/mod-updates.sh add modrinth lithium
./scripts/mod-updates.sh add modrinth ferritecore
./scripts/mod-updates.sh add modrinth krypton

# Download all mods
./scripts/mod-updates.sh upgrade
```

#### Updating Mods

```bash
# Update all mods to latest compatible versions
./scripts/mod-updates.sh upgrade

# List installed mods
./scripts/mod-updates.sh list
```

### Custom World Generation

Use custom world generation mods:

1. Add world gen mods (e.g., Terralith, Amplified Nether)
2. Configure in respective config files
3. Generate new world or use on fresh server

## Verification

### Check Server Status

```bash
# Quick status check
./tools/monitor.sh status

# Detailed health check
./tools/monitor.sh alert
```

### Test Connections

```bash
# Test Java Edition connection
telnet localhost 25565

# Test Bedrock Edition connection (if Geyser enabled)
nc -u localhost 19132
```

### View Logs

```bash
# Live log monitoring
tail -f logs/latest.log

# Search for errors
./tools/logrotate.sh search "error" latest.log

# View log statistics
./tools/logrotate.sh stats
```

## Next Steps

1. Configure plugins in `config/` directory
2. Set up automated backups (cron)
3. Enable watchdog for auto-restart
4. Configure whitelist and permissions
5. Optimize performance based on player count
6. Set up monitoring dashboard

For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

For detailed tool documentation, see [TOOLS.md](TOOLS.md).
