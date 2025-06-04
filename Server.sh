#!/bin/bash

# bash -c "./playit; exec bash"
konsole -e bash -c "./playit; exec bash" &
sleep 5
alacritty -e ./start.sh