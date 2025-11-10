#!/bin/bash

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

# Set performance profile before starting server
powerprofilesctl set performance 2>/dev/null || true

# Use awk for efficient memory calculation (allocate 1/3 of total RAM)
mem=$(get_minecraft_memory_gb 3)

# Start playit in background (detached, no need for new window)
playit &

# Start Minecraft server in Alacritty
alacritty -e sh -c "${JAVA:-java} -Xmx${mem}G -Xms${mem}G -jar server.jar nogui"
