### Bash

```bash
game_command "save-all flush"
game_command "save-off"
game_command "say Starting backup..."
# backup stuf...
game_command "save-on"
game_command "say Backup finished"

game_command "say Server shutting down in 10 seconds"
sleep 10
game_command "say Shutting down..."
game_command "stop"
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
- https://github.com/hpi-swa/native-minecraft-server
- https://www.graalvm.org/22.2/reference-manual/native-image/guides/optimize-native-executable-with-pgo
- https://www.graalvm.org/22.2/reference-manual/native-image/optimizations-and-performance/MemoryManagement

### Texture packs

- https://github.com/Mickey42302/JavaEditionCorrections


### Mod updater/manager

- https://github.com/minepkg/minepkg
- https://github.com/juraj-hrivnak/Pakku
- https://github.com/talwat/pap
- https://github.com/morr0ne/podzol
- https://github.com/mrquantumoff/quadrant
- https://github.com/crispyricepc/mcpkg
- https://github.com/Kraftland/mcctl
