#!/usr/bin/env bash
# For the server
java -Xms10G -Xmx10G -XX:ArchiveClassesAtExit=minecraft_server.jsa -jar server.jar

# For the client
java -Xms4G -Xmx4G -XX:ArchiveClassesAtExit=minecraft_client.jsa -jar client.jar
