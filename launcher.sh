#!/usr/bin/env bash
# mc-launcher.sh: auto-tuned Minecraft JVM launcher

# Source common functions and JVM config
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/jvm-config.sh"

init_strict_mode
[[ $EUID -ne 0 ]] && sudo -v
cd_script_dir
printf '%s\n' "$PWD" || exit 1

has_command java || { echo >&2 "No JDK found. Aborting..."; exit 1; }

# System optimizations
sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null <<< 'madvise'
powerprofilesctl set performance
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler >/dev/null
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null

# Configuration
CPU_CORES=$(get_cpu_cores)
XMS=$(get_heap_size_gb 2)
XMX=$(get_heap_size_gb 2)
JARNAME="server.jar"
AFTERJAR="--nogui"

# Detect JDK and build flags
: "${MC_JDK:=graalvm}"
detect_jdk
mapfile -t JVM_FLAGS < <(get_launcher_jvm_flags "$XMS" "$XMX" "$CPU_CORES")

# CPU affinity
TASKSET_CMD=(taskset -c 0-$((CPU_CORES-1)))

# Clear caches and start services
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
read -rt 1 -- <> <(:) &>/dev/null || :

{ setsid nohup playit >/dev/null 2>&1 & } || :
read -rt 1 -- <> <(:) &>/dev/null || :

# Launch Minecraft server
"${TASKSET_CMD[@]}" "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$JARNAME" "$AFTERJAR"
