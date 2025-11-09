#!/bin/bash

paru --noconfirm --skipreview -Sq ferium jdk25-graalvm-bin
sudo pacman --noconfirm -Sq ferium
sleep 1
sudo pacman --noconfirm -Sq gamemode preload prelockd nohang memavaild adaptivemm uresourced
