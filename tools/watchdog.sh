#!/usr/bin/env bash
# Simplified Minecraft server watchdog

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/common.sh
source "${SCRIPT_DIR}/tools/common.sh"

# Configuration
SERVER_START_SCRIPT="${SCRIPT_DIR}/tools/server-start.sh"
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
log(){ printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*" | tee -a "$LOG_FILE"; }

check_network(){ check_server_port "$SERVER_PORT"; }
check_health(){
  if ! is_server_running; then
    log "Process not running."
    return 1
  fi
  # Check Log Activity (Hang detection)
  local log_file="${SCRIPT_DIR}/logs/latest.log"
  if [[ -f $log_file ]]; then
    local last_log=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    local idle=$(($(printf '%(%s)T' -1) - last_log))
    if ((idle > 300)); then
      # If no logs for 5 mins, check network before killing
      if ! check_network; then
        log "Stalled: No log activity for ${idle}s and port unreachable."
        return 1
      fi
    fi
  fi
  return 0
}

# Check if can restart (rate limiting)
can_restart(){
  local now
  now=$(printf '%(%s)T' -1)
  local time_since_last=$((now - LAST_RESTART_TIME))

  if ((time_since_last < RESTART_COOLDOWN && RESTART_COUNT >= MAX_RESTART_ATTEMPTS)); then
    log "Too many restarts, waiting for cooldown..."
    return 1
  fi

  LAST_RESTART_TIME=$now
  ((RESTART_COUNT++))
  return 0
}

# Start server
start_server(){
  if [[ ! -x $SERVER_START_SCRIPT ]]; then
    log "Server start script not found or not executable: ${SERVER_START_SCRIPT}"
    return 1
  fi
  log "Starting server..."
  bash "$SERVER_START_SCRIPT" &
  sleep 5
  return 0
}

# Stop server
stop_server(){
  log "Stopping server..."
  pkill -f "fabric-server-launch.jar" || pkill -f "server.jar" || true
  sleep 2
  return 0
}

# Restart server
restart_server(){
  log "Restarting server..."
  can_restart || return 1
  is_server_running && stop_server
  start_server
}

# Monitor mode
monitor_mode(){
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
show_usage(){
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
