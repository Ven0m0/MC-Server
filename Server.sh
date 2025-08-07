#!/bin/bash



mem=$(grep MemTotal /proc/meminfo | sed -e 's/MemTotal:[ ]*//' | sed -e 's/ kB//') # some new stuff 
mem=$(($mem/1024/1024))
mem=$(($mem/3))

$JAVA -Xmx${mem}G -Xms${mem}G -jar server.jar nogui

powerprofilesctl set performance

# Start playit in a new Konsole window and detach immediately
konsole --noclose -e playit &
sleep 5

# Now start the Minecraft server in Alacritty
alacritty -e ./start.sh
