#!/bin/bash



# Use awk instead of grep+sed chain for better performance
mem=$(awk '/MemTotal/ {print int($2/1024/1024/3)}' /proc/meminfo)

${JAVA:-java} -Xmx"${mem}"G -Xms"${mem}"G -jar server.jar nogui

powerprofilesctl set performance

# Start playit in a new Konsole window and detach immediately
konsole --noclose -e playit &

# Now start the Minecraft server in Alacritty (removed unnecessary sleep)
alacritty -e ./start.sh
