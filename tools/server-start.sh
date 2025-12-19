#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}/.."
# server-start.sh: Simplified Minecraft server launcher
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"
# Configuration
: "${SERVER_JAR:=server.jar}"
: "${ENABLE_PLAYIT:=true}"
: "${MIN_HEAP_GB:=4}"
: "${MC_NICE:=}"
: "${MC_IONICE:=}"
# Validation
check_dependencies java || exit 1
[[ ! -f $SERVER_JAR ]] && {
  print_error "Server jar not found: ${SERVER_JAR}"
  exit 1
}
# Memory Configuration
CPU_CORES=$(get_cpu_cores)
AVAILABLE_RAM=$(get_minecraft_memory_gb)
if ((AVAILABLE_RAM < MIN_HEAP_GB)); then
  print_info "Warning: Available RAM (${AVAILABLE_RAM}GB) is less than configured minimum (${MIN_HEAP_GB}GB)."
  print_info "Using ${AVAILABLE_RAM}GB to prevent OOM crash."
  HEAP_SIZE=$AVAILABLE_RAM
else
  HEAP_SIZE=$((AVAILABLE_RAM > MIN_HEAP_GB ? AVAILABLE_RAM : MIN_HEAP_GB))
fi
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"
print_info "Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"
# JDK Detection
JAVA_CMD="$(detect_java)"
JAVA_TYPE=""
# Fix archlinux-java if available
if has archlinux-java; then
  sudo archlinux-java fix &>/dev/null || :
fi
# Detect if running GraalVM
if "$JAVA_CMD" -version 2>&1 | grep -q "GraalVM"; then
  JAVA_TYPE="graalvm"
fi
# Simplified JVM Flags
JVM_FLAGS=(
  "-Xms${XMS}" "-Xmx${XMX}"
  -XX:+UseG1GC
  -XX:+UnlockExperimentalVMOptions
  -XX:MaxGCPauseMillis=200
  -XX:G1NewSizePercent=30
  -XX:G1ReservePercent=15
  -XX:G1HeapRegionSize=32M
  -XX:+AlwaysPreTouch
  -XX:+DisableExplicitGC
  -XX:+ParallelRefProcEnabled
  "-XX:ParallelGCThreads=${CPU_CORES}"
  "-XX:ConcGCThreads=$((CPU_CORES / 4 > 0 ? CPU_CORES / 4 : 1))"
  -Dfile.encoding=UTF-8 -Djava.awt.headless=true
)
# GraalVM Specific Optimizations
if [[ $JAVA_TYPE == "graalvm" ]]; then
  JVM_FLAGS+=(
    -Djdk.graal.TuneInlinerExploration=1
    -Djdk.graal.CompilerConfiguration=enterprise
    -Djdk.graal.Vectorization=true
    -XX:+UseJVMCICompiler
  )
fi
# HugePages Check (Linux)
if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  if grep -q "\[always\]" /sys/kernel/mm/transparent_hugepage/enabled; then
    JVM_FLAGS+=("-XX:+UseTransparentHugePages")
    print_success "Transparent Huge Pages enabled"
  fi
fi
# Playit Integration
if [[ $ENABLE_PLAYIT == "true" ]] && has playit; then
  print_info "Starting playit..."
  if ! pgrep -x "playit" &>/dev/null; then
    { setsid nohup playit &>/dev/null & } || :
    sleepy 2
  fi
fi
# Prepare Execution Command
CMD=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)
# Apply IO Priority (ionice)
if [[ -n "${MC_IONICE}" ]] && has ionice; then
  ionice_args=()
  IFS=' ' read -r -a ionice_args <<<"$MC_IONICE"
  CMD=("ionice" "${ionice_args[@]}" "${CMD[@]}")
  print_info "IO Priority: ${MC_IONICE}"
fi
# Apply CPU Priority (nice)
if [[ -n "${MC_NICE}" ]] && has nice; then
  CMD=("nice" "-n" "$MC_NICE" "${CMD[@]}")
  print_info "Nice Level: ${MC_NICE}"
fi
# Launch Server
print_header "Starting Minecraft Server"
printf '  JAR: %s\n' "$SERVER_JAR"
printf '  Memory: %s - %s\n' "$XMS" "$XMX"
printf '  CPU Cores: %s\n' "$CPU_CORES"
exec "${CMD[@]}"
