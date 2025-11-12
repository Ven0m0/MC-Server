#!/usr/bin/env bash

# Install from AUR using paru
paru --noconfirm --skipreview -Sq ferium jdk25-graalvm-bin

# Install remaining packages from official repos in a single operation
sudo pacman --noconfirm -Sq gamemode preload prelockd nohang memavaild adaptivemm uresourced

# For the server
java -Xms10G -Xmx10G -XX:ArchiveClassesAtExit=minecraft_server.jsa -jar server.jar

# For the client
java -Xms4G -Xmx4G -XX:ArchiveClassesAtExit=minecraft_client.jsa -jar client.jar
