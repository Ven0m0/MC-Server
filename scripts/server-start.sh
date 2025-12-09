#!/usr/bin/env bash
# server-start.sh: Simplified Minecraft server launcher
# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# Configuration
: "${SERVER_JAR:=server.jar}"
: "${ENABLE_PLAYIT:=true}"
: "${MIN_HEAP_GB:=4}"
: "${MC_NICE:=}"
: "${MC_IONICE:=}"
# Validation
check_dependencies java || exit 1
[[ ! -f $SERVER_JAR ]] && { print_error "Server jar not found: ${SERVER_JAR}"; exit 1; }
# Memory Configuration
CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)
((HEAP_SIZE < MIN_HEAP_GB)) && HEAP_SIZE=$MIN_HEAP_GB
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"
print_info "Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"
# JDK Detection
JAVA_CMD="$(detect_java)"
JAVA_TYPE=""
# Fix archlinux-java if available
if has_command archlinux-java; then
  sudo archlinux-java fix 2>/dev/null || :
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
if [[ $ENABLE_PLAYIT == "true" ]] && has_command playit; then
  print_info "Starting playit..."
  if ! pgrep -x "playit" >/dev/null; then
    { setsid nohup playit &>/dev/null & } || :
    sleep 2
  fi
fi
# Prepare Execution Command
CMD=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)
# Apply IO Priority (ionice)
if [[ -n "${MC_IONICE}" ]] && has_command ionice; then
  local -a ionice_args
  # Temporarily allow space splitting for arguments
  IFS=' ' read -r -a ionice_args <<< "$MC_IONICE"
  CMD=("ionice" "${ionice_args[@]}" "${CMD[@]}")
  print_info "IO Priority: ${MC_IONICE}"
fi
# Apply CPU Priority (nice)
if [[ -n "${MC_NICE}" ]] && has_command nice; then
  CMD=("nice" "-n" "$MC_NICE" "${CMD[@]}")
  print_info "Nice Level: ${MC_NICE}"
fi
# Launch Server
print_header "Starting Minecraft Server"
printf '  JAR: %s\n' "$SERVER_JAR"
printf '  Memory: %s - %s\n' "$XMS" "$XMX"
printf '  CPU Cores: %s\n' "$CPU_CORES"
exec "${CMD[@]}"
