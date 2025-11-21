#!/usr/bin/env bash
# server-start.sh: Simplified Minecraft server launcher

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Check if required commands are available
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Please install them before continuing." >&2
    return 1
  fi
}

# Calculate total RAM in GB
get_total_ram_gb() { awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }

# Calculate heap size (total RAM minus reserved for OS)
get_heap_size_gb() {
  local reserved="${1:-2}"
  local total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  [[ $heap -lt 1 ]] && heap=1
  echo "$heap"
}

# Get number of CPU cores
get_cpu_cores() { nproc 2>/dev/null || echo 4; }

# Output formatting helpers
print_header() { echo -e "\033[0;34m==>\033[0m $1"; }
print_error() { echo -e "\033[0;31m✗\033[0m $1" >&2; }
print_info() { echo -e "\033[1;33m→\033[0m $1"; }

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
if has_command archlinux-java; then
  sudo archlinux-java fix 2>/dev/null || :
  SEL_JAVA="$(archlinux-java get 2>/dev/null)"
  [[ -n $SEL_JAVA ]] && JAVA_CMD="/usr/lib/jvm/${SEL_JAVA}/bin/java"
elif has_command mise; then
  JAVA_CMD="$(mise which java 2>/dev/null)" || JAVA_CMD="java"
fi

# Simplified JVM Flags
JVM_FLAGS=(
  "-Xms${XMS}" "-Xmx${XMX}"
  -XX:+UseG1GC
  -XX:+UnlockExperimentalVMOptions
  -XX:MaxGCPauseMillis=50
  -XX:G1NewSizePercent=30
  -XX:G1ReservePercent=15
  -XX:G1HeapRegionSize=16M
  -XX:+AlwaysPreTouch
  -XX:+DisableExplicitGC
  -XX:+ParallelRefProcEnabled
  "-XX:ParallelGCThreads=${CPU_CORES}"
  -Dfile.encoding=UTF-8
)

# Playit Integration
if [[ $ENABLE_PLAYIT == "true" ]] && has_command playit; then
  print_info "Starting playit..."
  { setsid nohup playit &>/dev/null & } || :
  sleep 2
fi

# Launch Server
print_header "Starting Minecraft Server"
echo "  JAR: ${SERVER_JAR}"
echo "  Memory: ${XMS} - ${XMX}"
echo "  CPU Cores: ${CPU_CORES}"
echo ""

exec "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui
