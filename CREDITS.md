# Credits and Attribution

## mcctl Integration

This repository includes an integrated and modernized version of **mcctl** (Minecraft Server Control), originally created by **Kimiblock**.

- **Original Project**: [Kraftland/mcctl](https://github.com/Kraftland/mcctl)
- **Original Author**: Kimiblock
- **Upstream Version**: v1.6-stable
- **License**: GPL-3.0
- **Integration Location**: `tools/mcctl.sh`

### Changes in Integration

The integrated version has been modernized to follow this repository's code standards:

- **Modern Bash**: Uses strict mode (`set -euo pipefail`) and bash 5.0+ features
- **Modular Design**: Integrates with `lib/common.sh` for shared functionality
- **Code Style**: Follows repository standards (2-space indent, snake_case variables)
- **Extended Features**: Added support for additional plugins while maintaining upstream compatibility
- **Documentation**: Integrated into repository's documentation system

### Acknowledgments

We are grateful to Kimiblock and the Kraftland project for creating and maintaining mcctl. Their work has significantly enhanced the Paper/Spigot server management capabilities of this repository.

## Other Components

- **Playit.gg**: Proxy and tunneling support
- **Infrarust**: Alternative proxy solution
- **lazymc**: Auto sleep/wake functionality for Minecraft servers
- **GeyserMC**: Bedrock/Java interoperability (Geyser and Floodgate)
- **Paper Project**: Paper server implementation
- **Spigot**: Spigot server implementation and BuildTools

All third-party components are subject to their respective licenses.
