#!/bin/bash

# Set performance profile before starting server
powerprofilesctl set performance 2>/dev/null || true

# Use awk for efficient memory calculation (allocate 1/3 of total RAM)
mem=$(awk '/MemTotal/ {print int($2/1024/1024/3)}' /proc/meminfo)

# Start playit in background (detached, no need for new window)
playit &

# Start Minecraft server in Alacritty
alacritty -e sh -c "${JAVA:-java} -Xmx${mem}G -Xms${mem}G -jar server.jar nogui"
