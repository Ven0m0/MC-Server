#!/usr/bin/env bash
# server-start.sh: Simplified Minecraft server launcher
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}" LC_ALL=C LANG=C
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Check if required commands are available
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
  done
  ((${#missing[@]})) && {
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Please install them before continuing." >&2
    return 1
  }
}

# Calculate total RAM in GB
get_total_ram_gb() { awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }

# Calculate heap size (total RAM minus reserved for OS)
get_heap_size_gb() {
  local reserved="${1:-2}"
  local total_ram
  total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  ((heap < 1)) && heap=1
  echo "$heap"
}

# Get number of CPU cores
get_cpu_cores() { nproc 2>/dev/null || echo 4; }

# Output formatting helpers
print_header() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_error() { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_info() { printf '\033[1;33m→\033[0m %s\n' "$1"; }

# Configuration
: "${SERVER_JAR:=server.jar}"
: "${ENABLE_PLAYIT:=true}"
: "${MIN_HEAP_GB:=4}"

# Validation
check_dependencies java || exit 1
[[ ! -f $SERVER_JAR ]] && {
  print_error "Server jar not found: ${SERVER_JAR}"
  exit 1
}

# Memory Configuration
CPU_CORES=$(get_cpu_cores)
HEAP_SIZE=$(get_heap_size_gb 2)
[[ $HEAP_SIZE -lt $MIN_HEAP_GB ]] && HEAP_SIZE=$MIN_HEAP_GB
XMS="${HEAP_SIZE}G"
XMX="${HEAP_SIZE}G"

print_info "Memory: ${XMS} - ${XMX} | CPU Cores: ${CPU_CORES}"

# JDK Detection
JAVA_CMD="java"
JAVA_TYPE=""
if has_command archlinux-java; then
  sudo archlinux-java fix 2>/dev/null || :
  SEL_JAVA="$(archlinux-java get 2>/dev/null)"
  [[ -n $SEL_JAVA ]] && JAVA_CMD="/usr/lib/jvm/${SEL_JAVA}/bin/java"
elif has_command mise; then
  JAVA_CMD="$(mise which java 2>/dev/null)" || JAVA_CMD="java"
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

# Launch Server
print_header "Starting Minecraft Server"
echo "  JAR: ${SERVER_JAR}"
echo "  Memory: ${XMS} - ${XMX}"
echo "  CPU Cores: ${CPU_CORES}"
exec "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui
