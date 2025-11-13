#!/usr/bin/env bash
# start.sh: G1GC-optimized Fabric server launcher

# Source common functions and JVM config
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/jvm-config.sh"

sudo -v

# Build JVM flags
mapfile -t JVM_FLAGS < <(get_start_jvm_flags)

# Launch with gamemode
sudo gamemoderun java "${JVM_FLAGS[@]}" -Dfile.encoding=UTF-8 -jar fabric-server.jar --nogui
