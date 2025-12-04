# GEMINI.md - Context & Instructions

## Project Overview
This is a production-ready Minecraft server management suite using Bash for automation, monitoring, and maintenance. It targets Arch/Wayland, Debian/Raspbian, and Termux environments. The system supports Fabric, Geyser (Bedrock), and advanced performance optimizations (GraalVM, ServerCore).

## Operational Scope
- **Tone**: Blunt, factual, precise, concise.
- **Output**: Result-first. Minimize conversational filler.
- **Encoding**: UTF-8. Strip U+202F/U+200B/U+00AD.

## Scripting Guidelines (Bash)
- **Header**:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  shopt -s nullglob globstar
  IFS=$'\n\t'
  export LC_ALL=C LANG=C
