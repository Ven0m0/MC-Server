#!/usr/bin/env bash
# Simplified Minecraft server watchdog
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"  LC_ALL=C LANG=C
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Initialize SCRIPT_DIR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# Configuration
SERVER_START_SCRIPT="${SCRIPT_DIR}/scripts/server-start.sh"
CHECK_INTERVAL=30
MAX_RESTART_ATTEMPTS=3
RESTART_COOLDOWN=300
LOG_FILE="${SCRIPT_DIR}/logs/watchdog.log"
SERVER_PORT=25565

# State
RESTART_COUNT=0
LAST_RESTART_TIME=0

# Logging
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Check if server is running
is_server_running() { pgrep -f "fabric-server-launch.jar" >/dev/null || pgrep -f "server.jar" >/dev/null; }
check_network() {
  # If nc is available, check if port is actually open
  if has_command nc; then
    nc -z localhost "$SERVER_PORT" >/dev/null 2>&1
    return $?
  fi
  return 0 # Skip check if nc not installed
}
check_health() {
  if ! is_server_running; then
    log "Process not running."; return 1
  fi
  # Check Log Activity (Hang detection)
  local log_file="${SCRIPT_DIR}/logs/latest.log"
  if [[ -f $log_file ]]; then
    local last_log=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    local idle=$(( $(date +%s) - last_log ))
    if ((idle > 300)); then
      # If no logs for 5 mins, check network before killing
      if ! check_network; then
        log "Stalled: No log activity for ${idle}s and port unreachable."; return 1
      fi
    fi
  fi
  return 0
}

# Restart server
restart_server() {
  log "Restarting server..."
  can_restart || return 1
  is_server_running && stop_server
  start_server
}

# Check health
check_health() {
  is_server_running || { log "Server not running"; return 1; }
  local log_file="${SCRIPT_DIR}/logs/latest.log"
  [[ -f $log_file ]] && {
    local last_log
    last_log=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local idle=$((now - last_log))
    ((idle > 300)) && {
      log "No log activity for ${idle}s"; return 1; }
    }
  }
  return 0
}

# Monitor mode
monitor_mode() {
  log "Watchdog started (interval: ${CHECK_INTERVAL}s, max attempts: ${MAX_RESTART_ATTEMPTS})"
  while true; do
    check_health || {
      log "Health check failed - restarting"
      restart_server && {
        log "Restart successful"
        sleep "$RESTART_COOLDOWN"
        RESTART_COUNT=0
      } || {
        log "Restart failed"
        ((RESTART_COUNT >= MAX_RESTART_ATTEMPTS)) && {
          log "Waiting 30 minutes before retry..."
          sleep 1800
          RESTART_COUNT=0
          LAST_RESTART_TIME=0
        }
      }
    }
    sleep "$CHECK_INTERVAL"
  done
}

# Show usage
show_usage() {
  cat <<EOF
Minecraft Server Watchdog

Usage: $0 [command]

Commands:
    monitor     Start watchdog (auto-restart on crash)
    restart     Restart server immediately
    start       Start server
    stop        Stop server
    status      Check if running
    help        Show this help

Examples:
    $0 monitor      # Start watchdog
    $0 restart      # Restart now
    $0 status       # Check status
EOF
}

# Main
case "${1:-help}" in
monitor) monitor_mode ;;
restart) restart_server ;;
start) start_server ;;
stop) stop_server ;;
status)
  if is_server_running; then
    log "Server is running"
    exit 0
  else
    log "Server is not running"
    exit 1
  fi
  ;;
help | --help | -h) show_usage ;;
*)
  log "Unknown command: $1"
  show_usage
  exit 1
  ;;
esac
