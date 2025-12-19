# Dependencies

This document lists all required and optional dependencies for the MC-Server Management Suite.

## Required Dependencies

These tools must be installed on your system to run the Minecraft server:

| Tool | Version | Purpose | Package Name |
|------|---------|---------|--------------|
| **bash** | 5.0+ | Shell runtime | `bash` |
| **java** | 21+ | Minecraft runtime | See Java section below |
| **curl** or **wget** | Any | File downloads | `curl` or `wget` |
| **jq** or **jaq** | Any | JSON processing | `jq` (jaq preferred but optional) |
| **tar** | Any | Backup compression | `tar` |
| **screen** or **tmux** | Any | Server session management | `screen` or `tmux` |

## Java Installation

The server requires Java 21 or newer. Recommended distributions:

- **GraalVM Enterprise/Community** (best performance)
- **Eclipse Temurin** (OpenJDK)
- **Oracle JDK** (commercial license)

## Installation by Distribution

### Arch Linux

```bash
# Minimal required packages
sudo pacman -S bash jdk21-openjdk curl jq screen tar

# Recommended optional packages
sudo pacman -S aria2 parallel tmux wget
```

### Ubuntu / Debian

```bash
# Minimal required packages
sudo apt update
sudo apt install bash openjdk-21-jdk curl jq screen tar

# Recommended optional packages
sudo apt install aria2 parallel tmux wget
```

### Fedora / RHEL / CentOS

```bash
# Minimal required packages
sudo dnf install bash java-21-openjdk curl jq screen tar

# Recommended optional packages
sudo dnf install aria2 parallel tmux wget
```

### Alpine Linux

```bash
# Minimal required packages
apk add bash openjdk21 curl jq screen tar

# Recommended optional packages
apk add aria2 parallel tmux wget
```

## Optional Performance Tools

These tools improve performance but are not required:

| Tool | Purpose | Benefit | Auto-Install |
|------|---------|---------|--------------|
| **aria2c** | Parallel downloads | 3-5x faster downloads | No |
| **parallel** | Parallel processing | Faster config formatting | No |
| **yq** | YAML processing | Better YAML handling | No |
| **yamlfmt** | YAML formatting | Code quality | No |
| **rustic** | Btrfs backups | Advanced backup features | Yes (auto-download) |
| **mcrcon** | RCON client | Remote server control | No |
| **rg** (ripgrep) | Fast text search | Faster log searching | No |

### Installing Optional Tools

#### Arch Linux
```bash
sudo pacman -S aria2 parallel go ripgrep
go install github.com/mikefarah/yq/v4@latest
go install github.com/google/yamlfmt/cmd/yamlfmt@latest
```

#### Ubuntu / Debian
```bash
sudo apt install aria2 parallel golang ripgrep
go install github.com/mikefarah/yq/v4@latest
go install github.com/google/yamlfmt/cmd/yamlfmt@latest
```

#### Fedora
```bash
sudo dnf install aria2 parallel golang ripgrep
go install github.com/mikefarah/yq/v4@latest
go install github.com/google/yamlfmt/cmd/yamlfmt@latest
```

## Tool Preferences

The scripts automatically detect and prefer certain tools when multiple options are available:

- **JSON Processing:** `jaq` > `jq`
- **Downloads:** `aria2c` > `curl` > `wget`
- **YAML Processing:** `yamlfmt` > `yq`
- **Parallel Execution:** `parallel` > `rust-parallel`
- **Session Management:** `screen` or `tmux` (both supported equally)

## Verification

To check if you have all required dependencies installed:

```bash
# Check core dependencies
for cmd in bash java curl jq tar screen; do
  if command -v "$cmd" &>/dev/null; then
    echo "✓ $cmd"
  else
    echo "✗ $cmd (missing)"
  fi
done

# Check Java version
java -version 2>&1 | head -1
```

## Minecraft-Specific Tools

These tools are downloaded automatically by the scripts when needed:

| Tool | Auto-Install | Purpose |
|------|--------------|---------|
| **lazymc** | Yes | Auto sleep/wake proxy |
| **rustic** | Yes | Btrfs backup utility |
| **ChunkCleaner** | Yes | World optimization |

## Plugin Dependencies (mcctl)

When using Paper/Spigot servers, plugins are downloaded automatically via `mcctl.sh`:

- ViaVersion, ViaBackwards (protocol support)
- Geyser, Floodgate (Bedrock/Java crossplay)
- LuckPerms (permissions)
- ProtocolLib (protocol API)
- Vault (economy API)
- GriefPrevention (land protection)
- And more (see `./tools/mcctl.sh help` for full list)

## System Requirements

### Minimum
- **CPU:** 2 cores
- **RAM:** 4 GB
- **Disk:** 10 GB free space
- **OS:** Linux kernel 4.0+

### Recommended
- **CPU:** 4+ cores
- **RAM:** 8+ GB
- **Disk:** 50+ GB free space (for backups)
- **OS:** Linux kernel 5.0+

## Firewall Configuration

The server requires the following ports:

| Port | Protocol | Purpose |
|------|----------|---------|
| 25565 | TCP | Minecraft Java Edition |
| 19132 | UDP | Minecraft Bedrock Edition (Geyser) |
| 25575 | TCP | RCON (if enabled) |

### UFW (Ubuntu/Debian)
```bash
sudo ufw allow 25565/tcp
sudo ufw allow 19132/udp
sudo ufw allow 25575/tcp  # Optional: RCON
```

### firewalld (Fedora/RHEL)
```bash
sudo firewall-cmd --permanent --add-port=25565/tcp
sudo firewall-cmd --permanent --add-port=19132/udp
sudo firewall-cmd --permanent --add-port=25575/tcp  # Optional: RCON
sudo firewall-cmd --reload
```

## Troubleshooting

### "command not found" errors

If you get "command not found" errors, install the missing dependency using your distribution's package manager.

### Java version issues

If you have multiple Java versions installed:

**Arch Linux:**
```bash
archlinux-java set java-21-openjdk
```

**Ubuntu/Debian:**
```bash
sudo update-alternatives --config java
```

**Using mise (universal):**
```bash
mise use java@21
```

### Permission issues

Some scripts may need sudo access. Ensure your user is in the `sudo` or `wheel` group:

```bash
sudo usermod -aG sudo $USER  # Ubuntu/Debian
sudo usermod -aG wheel $USER  # Fedora/RHEL
```

## See Also

- [CLAUDE.md](CLAUDE.md) - Project overview and commands
- [DEPENDENCY_AUDIT.md](DEPENDENCY_AUDIT.md) - Detailed dependency audit report
- [tools/prepare.sh](tools/prepare.sh) - Environment preparation script
