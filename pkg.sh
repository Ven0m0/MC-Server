#!/bin/bash

# Install from AUR using paru
paru --noconfirm --skipreview -Sq ferium jdk25-graalvm-bin

# Install remaining packages from official repos in a single operation
sudo pacman --noconfirm -Sq gamemode preload prelockd nohang memavaild adaptivemm uresourced
