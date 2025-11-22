#!/usr/bin/env bash
# Simplified Minecraft server monitor

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

# Output formatting helpers
print_header(){ echo -e "\033[0;34m==>\033[0m $1"; }
print_success(){ echo -e "\033[0;32m✓\033[0m $1"; }
print_error(){ echo -e "\033[0;31m✗\033[0m $1" >&2; }

# Configuration
LOG_FILE="${SCRIPT_DIR}/logs/latest.log"
SERVER_PORT=25565
CHECK_INTERVAL=60

# Check if process is running
check_process(){
  pgrep -f "fabric-server-launch.jar" >/dev/null || pgrep -f "server.jar" >/dev/null
}

# Check if port is listening
check_port(){
  command -v nc &>/dev/null && { nc -z localhost "$SERVER_PORT" 2>/dev/null; return; }
  command -v ss &>/dev/null && { ss -tuln | grep -q ":${SERVER_PORT} "; return; }
  netstat -tuln 2>/dev/null | grep -q ":${SERVER_PORT} "
}

# Get server status
get_status(){
  print_header "Server Status"
  check_process && echo "  Process: Running" || echo "  Process: Not Running"
  check_port && echo "  Port $SERVER_PORT: Listening" || echo "  Port $SERVER_PORT: Not Listening"
  echo ""
}

# Get memory usage
get_memory(){
  local pid=$(pgrep -f "fabric-server-launch.jar" | head -1)
  [[ -z $pid ]] && { echo "Server not running"; return 1; }
  print_header "Memory Usage"
  local mem_kb=$(ps -p "$pid" -o rss= | awk '{print $1}') mem_mb=$((mem_kb / 1024))
  echo "  PID: $pid"
  echo "  Memory: ${mem_mb} MB"
  echo ""
}

# Get disk usage
get_disk(){
  print_header "Disk Usage"
  [[ -d "${SCRIPT_DIR}/world" ]] && echo "  World: $(du -sh "${SCRIPT_DIR}/world" 2>/dev/null | cut -f1)"
  [[ -d "${SCRIPT_DIR}/backups" ]] && echo "  Backups: $(du -sh "${SCRIPT_DIR}/backups" 2>/dev/null | cut -f1)"
  [[ -d "${SCRIPT_DIR}/logs" ]] && echo "  Logs: $(du -sh "${SCRIPT_DIR}/logs" 2>/dev/null | cut -f1)"
  echo "  Total: $(du -sh "${SCRIPT_DIR}" 2>/dev/null | cut -f1)"
  echo ""
}

# Get player activity
get_players(){
  [[ ! -f $LOG_FILE ]] && { echo "Log file not found"; return 1; }
  print_header "Recent Player Activity"
  tail -200 "$LOG_FILE" 2>/dev/null | grep -E '(joined|left) the game' | tail -5 || echo "No recent activity"
  echo ""
}

# Check for errors
check_errors(){
  [[ ! -f $LOG_FILE ]] && { echo "Log file not found"; return 1; }
  print_header "Recent Errors"
  local errors=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo 0)
  local warns=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -ci 'WARN' || echo 0)
  echo "  Errors in last 100 lines: $errors"
  echo "  Warnings in last 100 lines: $warns"
  (( errors > 0 )) && {
    echo ""
    echo "  Last 3 errors:"
    tail -100 "$LOG_FILE" 2>/dev/null | grep -i 'ERROR\|SEVERE' | tail -3 | sed 's/^/    /'
  }
  echo ""
}

# Get uptime
get_uptime(){
  local pid=$(pgrep -f "fabric-server-launch.jar" | head -1)
  [[ -z $pid ]] && { echo "Server not running"; return 1; }
  print_header "Server Uptime"
  local uptime_sec=$(ps -p "$pid" -o etimes= | tr -d ' ')
  local days=$((uptime_sec / 86400)) hours=$(((uptime_sec % 86400) / 3600)) mins=$(((uptime_sec % 3600) / 60))
  echo "  ${days}d ${hours}h ${mins}m"
  echo ""
}

# Show comprehensive status
show_status(){
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "      Minecraft Server Monitor - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "════════════════════════════════════════════════════════"
  echo ""
  get_status
  get_uptime
  get_memory
  get_disk
  get_players
  check_errors
  echo "════════════════════════════════════════════════════════"
}

# Watch mode
watch_mode(){
  echo "Starting monitor (Ctrl+C to stop)"
  echo "Update interval: ${CHECK_INTERVAL}s"
  echo ""
  while true; do
    clear
    show_status
    sleep "$CHECK_INTERVAL"
  done
}

# Alert mode
alert_mode(){
  local issues=0
  check_process || { print_error "Process not running"; ((issues++)); }
  check_port || { print_error "Port not listening"; ((issues++)); }
  [[ -f $LOG_FILE ]] && {
    local errors=$(tail -20 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo 0)
    (( errors > 5 )) && { print_error "High error rate: $errors errors"; ((issues++)); }
  }
  local disk=$(df -h "${SCRIPT_DIR}" | tail -1 | awk '{print $5}' | sed 's/%//')
  (( disk > 90 )) && { print_error "Disk usage critical: ${disk}%"; ((issues++)); }
  (( issues == 0 )) && { print_success "All checks passed"; return 0; }
  print_error "Health check failed: $issues issue(s)"
  return 1
}

# Show usage
show_usage(){
  cat <<EOF
Minecraft Server Monitor

Usage: $0 [command]

Commands:
    status      Show server status (default)
    watch       Continuous monitoring
    alert       Run health check
    players     Show player activity
    errors      Show recent errors
    help        Show this help

Examples:
    $0              # Show status
    $0 watch        # Watch mode
    $0 alert        # Health check
EOF
}

# Main
case "${1:-status}" in
status) show_status ;;
watch) watch_mode ;;
alert) alert_mode ;;
players) get_players ;;
errors) check_errors ;;
help | --help | -h) show_usage ;;
*)
  print_error "Unknown command: $1"
  show_usage
  exit 1
  ;;
esac
