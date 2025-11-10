# MC-Server

Comprehensive Minecraft server and client management toolkit with automated setup, mod management, and performance optimization.

## Quick Start

### Server Setup
```bash
# Download and install Fabric server
./mcdl.sh

# Launch optimized server
./launcher.sh
```

### Client Launcher
```bash
# Download and launch Minecraft client
./mc-client.sh 1.21.6 YourUsername
```

### Mod Management
```bash
# Create a mod profile
./mod-manager.sh profile create my-mods 1.21.6 fabric ./mods

# Add mods from Modrinth
./mod-manager.sh add modrinth sodium
./mod-manager.sh add modrinth lithium

# Download all mods
./mod-manager.sh upgrade
```

## Features

### Server Management
- [Fabric](https://fabricmc.net/use/server)
- [Geyser](https://geysermc.org)
  - [ViaBedrock](https://github.com/RaphiMC/ViaBedrock)
- [Playit.gg](https://playit.gg)

## Server management

- [mcv-cli](https://crates.io/crates/mcvcli)
- [Anvil-mc](https://crates.io/crates/anvil-mc)
- [mcsctl](https://github.com/Hetsh/mcsctl)
- [ferium](https://github.com/gorilla-devs/ferium)
- [minecetch](https://github.com/KirillkoTankisto/minefetch)
- [automc](https://crates.io/crates/automc)
- [Linux game server manager](https://linuxgsm.com) **|** [Github](https://github.com/GameServerManagers/LinuxGSM)
- [Auto mcs](https://www.auto-mcs.com) **|** [Github](https://github.com/macarooni-man/auto-mcs)
- [Chunker](https://oss.chunker.app)
- https://github.com/TheRemote/MinecraftBedrockServer

## Compress the java files and their contents for reducing load times

- [Mc-repack](https://crates.io/crates/mc-repack)
- [PackSquash](https://github.com/ComunidadAylas/PackSquash)
- [World trimmer](https://github.com/Quozul/minecraft_world_trimmer)
- [GraalVM native image as server jdk](https://github.com/hpi-swa/native-minecraft-server)

## Proxy / Hosting

- [Infrarust](https://infrarust.dev/) [Cargo](https://crates.io/crates/infrarust)

## Other

- [minecraft-wayland](https://github.com/Admicos/minecraft-wayland)
- [glfw-wayland](https://github.com/BoyOrigin/glfw-wayland)
- https://github.com/krusic22/Potato-Scripts
- https://github.com/Fabric-Development/fabric-cli
- https://github.com/mindstorm38/portablemc
- https://github.com/Sushkyn/mc-launcher

## TWEAKS

- [meowice-flags](https://github.com/MeowIce/meowice-flags)
- [Graalvm-flags](https://github.com/Obydux/Minecraft-GraalVM-Flags)

## Scripts

### Server Scripts

- **`mcdl.sh`** - Downloads and installs Fabric server for specified Minecraft version
- **`launcher.sh`** - Auto-tuned JVM launcher with GraalVM/Temurin support and performance optimizations
- **`Server.sh`** - Simple server starter with Alacritty terminal integration

### Client Scripts

- **`mc-client.sh`** - Full-featured Minecraft client launcher
  - Automatic version downloading from Mojang servers
  - Asset and library management
  - Native library extraction
  - Optimized JVM settings
  - Based on [mc-launcher](https://github.com/Sushkyn/mc-launcher)

### Mod Management

- **`mod-manager.sh`** - Comprehensive mod manager inspired by [Ferium](https://github.com/gorilla-devs/ferium)
  - Profile-based mod organization
  - Download mods from Modrinth and CurseForge
  - Automatic version compatibility checking
  - Bulk mod updates
  - Clean, informative CLI interface

## Usage Examples

### Client Launcher

Download and launch any Minecraft version:
```bash
# Launch latest version
./mc-client.sh 1.21.6 Player

# Launch older version
./mc-client.sh 1.20.1 MyUsername

# Custom Minecraft directory
MC_DIR=/path/to/minecraft ./mc-client.sh 1.21.6 Player
```

The client launcher will:
1. Download version manifest from Mojang
2. Download client JAR file
3. Download all game assets (textures, sounds, etc.)
4. Download required libraries and natives
5. Launch the game with optimized settings

### Mod Manager

#### Profile Management
```bash
# Create a new profile
./mod-manager.sh profile create fabric-mods 1.21.6 fabric ./mods

# List all profiles
./mod-manager.sh profile list

# Switch between profiles
./mod-manager.sh profile switch fabric-mods
```

#### Adding Mods
```bash
# Add mods from Modrinth (by slug)
./mod-manager.sh add modrinth sodium
./mod-manager.sh add modrinth lithium
./mod-manager.sh add modrinth iris
./mod-manager.sh add modrinth modmenu

# Add mods from CurseForge (by project ID)
./mod-manager.sh add curseforge 12345

# List mods in current profile
./mod-manager.sh list
```

#### Downloading Mods
```bash
# Download/update all mods in current profile
./mod-manager.sh upgrade

# This will:
# - Fetch latest compatible versions
# - Clean output directory
# - Download all mods in parallel
```

#### Removing Mods
```bash
# Remove mod by slug or ID
./mod-manager.sh remove sodium
```

## Dependencies

### Required
- `bash` - Shell scripting
- `java` - Java runtime for Minecraft
- `unzip` - Extract native libraries

### Recommended
- `aria2c` - Fast parallel downloads (fallback to curl/wget)
- `jaq` or `jq` - JSON processing
- `curl` or `wget` - HTTP downloads

### Server-Specific
- `playit` - Tunneling service for public access (optional)

## Configuration

### Environment Variables

**Server Launcher (`launcher.sh`)**:
- `MC_JDK` - JDK selection: `graalvm` or `temurin` (default: `graalvm`)
- `JAVA_GRAALVM` - Path to GraalVM installation
- `JAVA_TEMURIN` - Path to Temurin installation

**Client Launcher (`mc-client.sh`)**:
- `MC_DIR` - Minecraft directory (default: `~/.minecraft`)

**Mod Manager (`mod-manager.sh`)**:
- `XDG_CONFIG_HOME` - Config directory (default: `~/.config`)

### Performance Tuning

The server launcher (`launcher.sh`) automatically:
- Detects CPU cores and RAM
- Allocates optimal heap size (Total RAM - 2GB)
- Enables Transparent Huge Pages
- Configures G1GC with optimized settings
- Applies GraalVM Enterprise optimizations (if available)

## File Structure

```
MC-Server/
├── mc-client.sh          # Minecraft client launcher
├── mod-manager.sh        # Mod management tool
├── mcdl.sh              # Fabric server downloader
├── launcher.sh          # Optimized server launcher
├── Server.sh            # Simple server starter
├── lib/
│   └── common.sh        # Shared utility functions
└── config/              # Server configuration files
```

### TODO:

- https://github.com/Botspot/pi-apps/blob/master/apps/Minecraft%20Java%20Server/install

