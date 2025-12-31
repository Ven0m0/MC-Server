#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}/.."
# server-start.sh: Minecraft server launcher with integrated lazymc support
# shellcheck source=tools/common.sh
source "${PWD}/tools/common.sh"

# Configuration
: "${SERVER_JAR:=server.jar}"
: "${ENABLE_PLAYIT:=true}"
: "${ENABLE_LAZYMC:=false}"
: "${MIN_HEAP_GB:=4}"
: "${MC_NICE:=}"
: "${MC_IONICE:=}"

# Lazymc configuration
CONFIG_DIR="${CONFIG_DIR:-$PWD/config}"
LAZYMC_CONFIG="${CONFIG_DIR}/lazymc.toml"
LAZYMC_PID_FILE="/tmp/lazymc.pid"
LAZYMC_LOG_FILE="logs/lazymc.log"

# ============================================================================
# Lazymc Functions
# ============================================================================

check_lazymc() {
  if ! has lazymc; then
    print_error "lazymc not found"
    print_info "Run './tools/prepare.sh lazymc-install' to install"
    return 1
  fi
}

check_lazymc_config() {
  if [[ ! -f $LAZYMC_CONFIG ]]; then
    print_error "Configuration not found: ${LAZYMC_CONFIG}"
    print_info "Run './tools/prepare.sh lazymc-config' to generate"
    return 1
  fi
}

start_lazymc() {
  check_lazymc || return 1
  check_lazymc_config || return 1

  if [[ -f $LAZYMC_PID_FILE ]]; then
    local existing_pid
    existing_pid="$(<"$LAZYMC_PID_FILE")"
    if kill -0 "$existing_pid" &>/dev/null; then
      print_info "lazymc is already running (PID: ${existing_pid})"
      return 0
    fi
  fi

  print_header "Starting lazymc"
  mkdir -p "$(dirname "$LAZYMC_LOG_FILE")"
  nohup lazymc start --config "$LAZYMC_CONFIG" >>"$LAZYMC_LOG_FILE" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$LAZYMC_PID_FILE"
  sleepy 2

  if kill -0 "$pid" &>/dev/null; then
    print_success "lazymc started (PID: ${pid})"
    print_info "Log file: ${LAZYMC_LOG_FILE}"
  else
    print_error "Failed to start lazymc"
    print_info "Check logs: ${LAZYMC_LOG_FILE}"
    rm -f "$LAZYMC_PID_FILE"
    return 1
  fi
}

stop_lazymc() {
  if [[ ! -f $LAZYMC_PID_FILE ]]; then
    print_info "lazymc is not running (no PID file)"
    return 0
  fi

  local pid
  pid="$(<"$LAZYMC_PID_FILE")"
  if ! kill -0 "$pid" &>/dev/null; then
    print_info "lazymc is not running (stale PID file)"
    rm -f "$LAZYMC_PID_FILE"
    return 0
  fi

  print_header "Stopping lazymc"
  kill "$pid" &>/dev/null || {
    print_error "Failed to stop lazymc (PID: ${pid})"
    return 1
  }

  local count=0
  while kill -0 "$pid" &>/dev/null && ((count < 10)); do
    sleepy 1
    ((count++))
  done

  if kill -0 "$pid" &>/dev/null; then
    print_info "Force killing lazymc"
    kill -9 "$pid" &>/dev/null || :
  fi

  rm -f "$LAZYMC_PID_FILE"
  print_success "lazymc stopped"
}

restart_lazymc() {
  stop_lazymc
  sleepy 1
  start_lazymc
}

status_lazymc() {
  check_lazymc || return 1
  print_header "lazymc Status"

  if [[ -f $LAZYMC_PID_FILE ]]; then
    local pid
    pid="$(<"$LAZYMC_PID_FILE")"
    if kill -0 "$pid" &>/dev/null; then
      print_success "Running (PID: ${pid})"
      if has ps; then
        printf '\n'
        ps -p "$pid" -o pid,ppid,cmd,etime,rss 2>/dev/null || :
      fi
    else
      print_error "Not running (stale PID file)"
      rm -f "$LAZYMC_PID_FILE"
    fi
  else
    print_info "Not running"
  fi

  if [[ -f $LAZYMC_CONFIG ]]; then
    printf '\n'
    print_info "Configuration: ${LAZYMC_CONFIG}"
  fi

  if [[ -f $LAZYMC_LOG_FILE ]]; then
    printf '\n'
    print_header "Recent Logs"
    tail -n 10 "$LAZYMC_LOG_FILE" || :
  fi
}

show_lazymc_logs() {
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    return 1
  fi
  local lines="${1:-50}"
  tail -n "$lines" "$LAZYMC_LOG_FILE"
}

follow_lazymc_logs() {
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    return 1
  fi
  tail -f "$LAZYMC_LOG_FILE"
}

# ============================================================================
# Server Launch Functions
# ============================================================================

launch_server() {
  # Validation
  check_dependencies java || exit 1
  [[ ! -f $SERVER_JAR ]] && {
    print_error "Server jar not found: ${SERVER_JAR}"
    exit 1
  }
  # Memory Configuration
  local CPU_CORES AVAILABLE_RAM HEAP_SIZE XMS XMX
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
  local JAVA_CMD JAVA_TYPE=""
  JAVA_CMD="$(detect_java)"

  # Fix archlinux-java if available
  if has archlinux-java; then
    sudo archlinux-java fix &>/dev/null || :
  fi

  # Detect if running GraalVM
  if "$JAVA_CMD" -version 2>&1 | grep -q "GraalVM"; then
    JAVA_TYPE="graalvm"
  fi

  # Simplified JVM Flags
  local JVM_FLAGS=(
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

  # Lazymc Integration
  if [[ $ENABLE_LAZYMC == "true" ]]; then
    start_lazymc || print_info "Continuing without lazymc..."
  fi

  # Prepare Execution Command
  local CMD=("$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$SERVER_JAR" --nogui)

  # Apply IO Priority (ionice)
  if [[ -n "${MC_IONICE}" ]] && has ionice; then
    local ionice_args=()
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
}

# ============================================================================
# Usage and Main
# ============================================================================

show_usage() {
  print_header "Minecraft Server Launcher"
  printf '\n'
  printf 'Usage: %s [command] [options]\n' "$0"
  printf '\n'
  printf 'Commands:\n'
  printf '  (none)              Start the Minecraft server directly\n'
  printf '  lazymc start        Start lazymc daemon (auto sleep/wake proxy)\n'
  printf '  lazymc stop         Stop lazymc daemon\n'
  printf '  lazymc restart      Restart lazymc daemon\n'
  printf '  lazymc status       Show lazymc status\n'
  printf '  lazymc logs [n]     Show recent logs (default: 50 lines)\n'
  printf '  lazymc follow       Follow logs in real-time\n'
  printf '  help                Show this help message\n'
  printf '\n'
  printf 'Environment Variables:\n'
  printf '  SERVER_JAR          Server jar file (default: server.jar)\n'
  printf '  ENABLE_PLAYIT       Enable playit.gg tunnel (default: true)\n'
  printf '  ENABLE_LAZYMC       Start lazymc with server (default: false)\n'
  printf '  MIN_HEAP_GB         Minimum heap size in GB (default: 4)\n'
  printf '  MC_NICE             Nice level for CPU priority\n'
  printf '  MC_IONICE           Ionice class for IO priority\n'
  printf '\n'
  printf 'Examples:\n'
  printf '  %s                           # Start server\n' "$0"
  printf '  ENABLE_LAZYMC=true %s        # Start server with lazymc\n' "$0"
  printf '  %s lazymc start              # Start lazymc daemon only\n' "$0"
  printf '  %s lazymc status             # Check lazymc status\n' "$0"
  printf '\n'
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    lazymc)
      local subcmd="${2:-help}"
      case "$subcmd" in
        start) start_lazymc ;;
        stop) stop_lazymc ;;
        restart) restart_lazymc ;;
        status) status_lazymc ;;
        logs) show_lazymc_logs "${3:-50}" ;;
        follow) follow_lazymc_logs ;;
        *) print_error "Unknown lazymc command: $subcmd"; show_usage; exit 1 ;;
      esac
      ;;
    help | --help | -h)
      show_usage
      ;;
    "")
      launch_server
      ;;
    *)
      print_error "Unknown command: $cmd"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
