### Bash

```bash
echo "Taking ownership of all server files/folders in dirname/minecraft..."
sudo chown -R userxname dirname/minecraft
sudo chmod -R 755 dirname/minecraft/*.sh
umask 077
sudo systemctl daemon-reload
```

### Service

```markdown
[Unit]
Description=Minecraft Server Service
After=network-online.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=dirname/minecraft
Type=forking
ExecStart=/bin/bash dirname/minecraft/start.sh
ExecStop=/bin/bash dirname/minecraft/stop.sh
GuessMainPID=no
TimeoutStartSec=1800
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
NoNewPrivileges=true
PrivateUsers=true
ProtectClock=true
ProtectKernelLogs=true
ProtectHostname=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictNamespaces=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
AmbientCapabilities=CAP_KILL
CapabilityBoundingSet=CAP_KILL
WorkingDirectory=/var/lib/minecraft/deploy/server
ReadWriteDirectories=/var/lib/minecraft

[Install]
WantedBy=multi-user.target
```

### Java flags

```markdown
-XX:-UseAESCTRIntrinsics -Djava.locale.providers=JRE -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -XX:+UseDynamicNumberOfGCThreads
```

- https://github.com/MeowIce/meowice-flags
- https://github.com/Obydux/Minecraft-GraalVM-Flags
- https://www.leafmc.one/docs/how-to/java-flags

### Other repos to integrate

- https://github.com/hpi-swa/native-minecraft-server
- https://github.com/oddlama/minecraft-server
- https://github.com/Dan-megabyte/minecraft-server
- https://github.com/Edenhofer/minecraft-server
- https://github.com/MinecraftServerControl/mscs
- https://github.com/msmhq/msm
- https://github.com/Fenixin/Minecraft-Region-Fixer
- https://github.com/TheRemote/MinecraftBedrockServer

### Optimization

- https://github.com/Radk6/MC-Optimization-Guide
- https://www.graalvm.org/22.2/reference-manual/native-image/guides/optimize-native-executable-with-pgo
- https://www.graalvm.org/22.2/reference-manual/native-image/optimizations-and-performance/MemoryManagement

### Texture packs

- https://github.com/Mickey42302/JavaEditionCorrections
