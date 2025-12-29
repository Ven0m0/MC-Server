# Minecraft Configuration Directory

This directory contains all plugin and mod configurations for the Minecraft server. Files are automatically loaded by their respective mods/plugins at server startup.

## Directory Structure

```
config/
├── Geyser-Fabric/              # Bedrock Edition support
│   └── config.yml
├── floodgate/                  # Bedrock authentication
│   └── config.yml
├── servercore/                 # Performance optimizations
│   ├── config.yml
│   └── optimizations.yml
└── [various mod configs]       # Individual mod settings
```

## Configuration Files

### Core Performance Mods

#### **ServerCore** (`servercore/`)
- **Purpose**: Comprehensive server performance optimization
- **Files**:
  - `config.yml` - Main configuration (feature toggles, limits)
  - `optimizations.yml` - Performance tuning settings
- **Key Features**: Mob spawn optimization, chunk loading improvements, network optimizations
- **Documentation**: [ServerCore Wiki](https://modrinth.com/mod/servercore)

#### **Very Many Players (VMP)** (`vmp.properties`)
- **Purpose**: Multi-threaded optimizations for high player counts
- **Type**: Properties file
- **Key Settings**: Threading options, chunk loading, mob AI
- **Documentation**: [VMP Modrinth](https://modrinth.com/mod/vmp)

#### **FerriteCore** (`ferritecore.mixin.properties`)
- **Purpose**: Memory usage reduction via data structure optimizations
- **Type**: Mixin properties (advanced users only)
- **Note**: Modifications not recommended unless you understand Mixin internals

#### **Async** (`async.toml`)
- **Purpose**: Asynchronous chunk and world operations
- **Type**: TOML configuration
- **Key Features**: Async chunk saving, world generation optimizations

### Cross-Platform Support

#### **Geyser-Fabric** (`Geyser-Fabric/config.yml`)
- **Purpose**: Bedrock Edition (mobile/console) player support
- **Type**: YAML configuration
- **Key Settings**:
  - `bedrock.address` - Bedrock server bind address (default: 0.0.0.0)
  - `bedrock.port` - Bedrock port (default: 19132)
  - `remote.address` - Java server address
  - `remote.port` - Java server port
- **Documentation**: [Geyser Wiki](https://wiki.geysermc.org/)

#### **Floodgate** (`floodgate/config.yml`)
- **Purpose**: Allows Bedrock players to join without Java Edition account
- **Type**: YAML configuration
- **Key Settings**: Username prefix, skin handling, authentication
- **Documentation**: [Floodgate Wiki](https://wiki.geysermc.org/floodgate/)

### Rendering & Client Performance

#### **Cesium** (`cesium.json`)
- **Purpose**: Sodium-based rendering optimizations for servers
- **Type**: JSON configuration
- **Key Features**: Render distance optimizations, chunk rendering

#### **Annuus** (`annuus.json`)
- **Purpose**: Additional rendering optimizations
- **Type**: JSON configuration

#### **Structure Layout Optimizer** (`structure_layout_optimizer.jsonc`)
- **Purpose**: Optimize structure generation layout
- **Type**: JSON with comments (JSONC)
- **Key Features**: Reduces structure generation lag

### Gameplay & Mechanics

#### **Slumber** (`slumber.properties`)
- **Purpose**: Sleep mechanics improvements and optimizations
- **Type**: Properties file
- **Key Features**: Configurable sleep percentages, phantoms, weather

#### **Shielded Zombies** (`ShieldedZombies.yaml`)
- **Purpose**: Zombie mob variants with shields
- **Type**: YAML configuration
- **Key Settings**: Spawn rates, shield types, difficulty scaling

#### **Giant Spawn** (`giantspawn.json5`)
- **Purpose**: Giant zombie spawn configuration
- **Type**: JSON5 (JSON with comments)
- **Key Settings**: Spawn conditions, health, damage

#### **Mob Filter** (`mobfilter.json5`)
- **Purpose**: Control which mobs can spawn and where
- **Type**: JSON5
- **Key Features**: Dimension-based filtering, biome restrictions

#### **MineSpawners** (`minespawners-config.json`)
- **Purpose**: Mineable spawner blocks configuration
- **Type**: JSON configuration
- **Key Settings**: Tool requirements, drops, silk touch behavior

#### **More Furnaces** (`morefurnaces.conf`)
- **Purpose**: Additional furnace types and improvements
- **Type**: HOCON configuration
- **Key Features**: Speed multipliers, fuel efficiency

#### **Sepals** (`sepals.json`)
- **Purpose**: Flower and plant-related features
- **Type**: JSON configuration

### Technical & Debug Mods

#### **Neruina** (`neruina.json`)
- **Purpose**: Ticking entity crash prevention
- **Type**: JSON configuration
- **Key Features**: Entity watchdog, crash mitigation, logging

#### **Packet Fixer** (`packetfixer.properties`)
- **Purpose**: Fix packet handling issues and improve network stability
- **Type**: Properties file
- **Key Features**: Packet validation, network optimizations

#### **Footprint** (`footprint_config.properties`)
- **Purpose**: Performance profiling and monitoring
- **Type**: Properties file
- **Key Features**: Tick time tracking, memory monitoring

### Version Tracking

#### **versions.sh** (`versions.sh`)
- **Purpose**: Track installed mod/plugin versions for documentation
- **Type**: Shell script (source file)
- **Usage**: Sourced by management scripts (prepare.sh, mcctl.sh)
- **Contains**: Version numbers for lazymc, LuckPerms, FreedomChat, etc.

## Configuration Best Practices

### Before Modifying Configs

1. **Backup First**: Always backup configs before making changes
   ```bash
   ./tools/backup.sh backup config
   ```

2. **Test Changes**: Test configuration changes in a development environment first

3. **One Change at a Time**: Modify one setting at a time to identify issues

4. **Read Documentation**: Consult mod-specific documentation before changing advanced settings

### File Format Guidelines

- **YAML files** (`.yml`, `.yaml`): Mind indentation (use spaces, not tabs)
- **JSON files** (`.json`): Ensure valid JSON syntax (use a validator)
- **JSON5 files** (`.json5`, `.jsonc`): Support comments and trailing commas
- **Properties files** (`.properties`): Key=value format, no spaces around `=`
- **TOML files** (`.toml`): INI-like format with sections `[section]`

### Recommended Edit Tools

- **CLI**: `nano`, `vim`, or `micro`
- **GUI**: VS Code, Sublime Text (with syntax highlighting)
- **Validation**: `jaq`/`jq` for JSON, `yamllint` for YAML

### Common Configuration Tasks

#### Adjust Bedrock Port (Geyser)
```yaml
# Geyser-Fabric/config.yml
bedrock:
  port: 19132  # Change if port conflicts exist
```

#### Change Sleep Percentage (Slumber)
```properties
# slumber.properties
sleep-percentage=50  # Percentage of players needed to sleep
```

#### Increase Mob Spawn Limits (ServerCore)
```yaml
# servercore/config.yml
mob_spawning:
  spawn_limits:
    monster: 70  # Vanilla default: 70
    creature: 10 # Vanilla default: 10
```

#### Disable Specific Mob Spawns (Mob Filter)
```json5
// mobfilter.json5
{
  "denied_mobs": [
    "minecraft:phantom",  // Disable phantoms
    "minecraft:creeper"   // Disable creepers
  ]
}
```

## Troubleshooting

### Server Won't Start After Config Change

1. Check server logs: `logs/latest.log`
2. Look for config-related errors
3. Restore from backup: `./tools/backup.sh restore [backup-file]`
4. Validate JSON/YAML syntax using online validators

### Configuration Not Taking Effect

1. Ensure server was restarted after config change
2. Check file permissions: `chmod 644 minecraft/config/*`
3. Verify file is in correct location
4. Check for mod-specific reload commands

### Conflicting Configurations

Some mods may override others. Load order considerations:

1. **ServerCore** - Apply early (general optimizations)
2. **VMP** - Apply after core mods (threading)
3. **Geyser/Floodgate** - Apply late (networking)

## Related Documentation

- [Main README](../../README.md) - Project overview
- [SETUP Guide](../../docs/SETUP.md) - Initial setup instructions
- [Mod List](../../docs/mods.txt) - Complete installed mod list
- [Mod Links](../../docs/mods-links.txt) - Download links and sources
- [Troubleshooting](../../docs/TROUBLESHOOTING.md) - Common issues

## Version Management

Version numbers for key plugins are tracked in `versions.sh`. This file is sourced by:

- `tools/prepare.sh` - For lazymc installation
- `tools/mcctl.sh` - For Paper/Spigot plugin management

To update a plugin version:

1. Edit `minecraft/config/versions.sh`
2. Update the version variable (e.g., `LUCKPERMS_VERSION="5.4.102"`)
3. Run the update command: `./tools/mcctl.sh update <plugin>`

---

**Last Updated**: 2025-01-19
**Server Version**: Fabric 1.21.5
**Configuration Schema**: v2.1
