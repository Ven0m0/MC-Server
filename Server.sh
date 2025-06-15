#!/bin/bash

# Start playit in a new Konsole window and detach immediately
konsole --noclose -e playit &
sleep 5

# Now start the Minecraft server in Alacritty
alacritty -e ./start.sh
