#!/usr/bin/env bash
# Simplified Minecraft server watchdog

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
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

# State
RESTART_COUNT=0
LAST_RESTART_TIME=0

# Logging
mkdir -p "$(dirname "$LOG_FILE")"
log(){
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Check if server is running
is_server_running(){
  pgrep -f "fabric-server-launch.jar" >/dev/null || pgrep -f "server.jar" >/dev/null
}

# Can we restart?
can_restart(){
  local current_time=$(date +%s) time_since=$((current_time - LAST_RESTART_TIME))
  (( time_since < RESTART_COOLDOWN )) && {
    log "Too soon to restart. Wait $((RESTART_COOLDOWN - time_since))s"
    return 1
  }
  (( RESTART_COUNT >= MAX_RESTART_ATTEMPTS )) && {
    log "Max restart attempts ($MAX_RESTART_ATTEMPTS) reached"
    return 1
  }
  return 0
}

# Start server
start_server(){
  log "Starting server..."
  [[ ! -x $SERVER_START_SCRIPT ]] && { log "Start script not found"; return 1; }
  cd "$SCRIPT_DIR"
  command -v screen &>/dev/null && {
    screen -dmS minecraft bash -c "cd '$SCRIPT_DIR' && '$SERVER_START_SCRIPT'"
  } || command -v tmux &>/dev/null && {
    tmux new-session -d -s minecraft "cd '$SCRIPT_DIR' && '$SERVER_START_SCRIPT'"
  } || {
    nohup "$SERVER_START_SCRIPT" >"${SCRIPT_DIR}/logs/server.log" 2>&1 &
  }
  sleep 30
  is_server_running && {
    log "Server started successfully"
    LAST_RESTART_TIME=$(date +%s)
    ((RESTART_COUNT++))
    return 0
  }
  log "Server failed to start"
  return 1
}

# Stop server
stop_server(){
  log "Stopping server..."
  screen -list 2>/dev/null | grep -q "minecraft" && screen -S minecraft -X stuff "stop^M"
  tmux list-sessions 2>/dev/null | grep -q "minecraft" && tmux send-keys -t minecraft "stop" Enter
  local wait=0
  while is_server_running && (( wait < 60 )); do
    sleep 5
    ((wait += 5))
  done
  is_server_running && pkill -9 -f "fabric-server-launch.jar"
  log "Server stopped"
}

# Restart server
restart_server(){
  log "Restarting server..."
  can_restart || return 1
  is_server_running && stop_server
  start_server
}

# Check health
check_health(){
  is_server_running || { log "Server not running"; return 1; }
  local log_file="${SCRIPT_DIR}/logs/latest.log"
  [[ -f $log_file ]] && {
    local last_log=$(stat -c %Y "$log_file" 2>/dev/null || echo 0) now=$(date +%s) idle=$((now - last_log))
    (( idle > 300 )) && { log "No log activity for ${idle}s"; return 1; }
  }
  return 0
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
        (( RESTART_COUNT >= MAX_RESTART_ATTEMPTS )) && {
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
