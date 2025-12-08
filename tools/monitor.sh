#!/usr/bin/env bash
# monitor.sh: Simplified Minecraft server monitor

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"
export SCRIPT_DIR

# Configuration
LOG_FILE="${SCRIPT_DIR}/logs/latest.log"
SERVER_PORT=25565
CHECK_INTERVAL=60

# Check if process is running
check_process() {
  is_process_running "fabric-server-launch.jar" || is_process_running "server.jar"
}

# Check if port is listening
check_port() {
  if has_command nc; then
    nc -z localhost "$SERVER_PORT" 2>/dev/null
  elif has_command ss; then
    ss -tuln | grep -q ":${SERVER_PORT} "
  else
    netstat -tuln 2>/dev/null | grep -q ":${SERVER_PORT} "
  fi
}

# Get server status
get_status() {
  print_header "Server Status"
  check_process && printf '  Process: Running\n' || printf '  Process: Not Running\n'
  check_port && printf '  Port %s: Listening\n' "$SERVER_PORT" || printf '  Port %s: Not Listening\n' "$SERVER_PORT"
  printf '\n'
}

# Get memory usage
get_memory() {
  local pid
  pid=$(get_process_pid "fabric-server-launch.jar")
  [[ -z $pid ]] && { printf 'Server not running\n'; return 1; }
  print_header "Memory Usage"
  local mem_kb mem_mb
  mem_kb=$(ps -p "$pid" -o rss= | awk '{print $1}')
  mem_mb=$((mem_kb / 1024))
  printf '  PID: %s\n' "$pid"
  printf '  Memory: %s MB\n\n' "$mem_mb"
}

# Get disk usage
get_disk() {
  print_header "Disk Usage"
  local dirs_to_check=()
  [[ -d "${SCRIPT_DIR}/world" ]] && dirs_to_check+=("${SCRIPT_DIR}/world")
  [[ -d "${SCRIPT_DIR}/backups" ]] && dirs_to_check+=("${SCRIPT_DIR}/backups")
  [[ -d "${SCRIPT_DIR}/logs" ]] && dirs_to_check+=("${SCRIPT_DIR}/logs")

  if ((${#dirs_to_check[@]} > 0)); then
    while IFS=$'\t' read -r size path; do
      local name
      name=$(basename "$path")
      case "$name" in
        world) printf '  World: %s\n' "$size" ;;
        backups) printf '  Backups: %s\n' "$size" ;;
        logs) printf '  Logs: %s\n' "$size" ;;
      esac
    done < <(du -sh "${dirs_to_check[@]}" 2>/dev/null)
  fi
  printf '  Total: %s\n\n' "$(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)"
}

# Get player activity
get_players() {
  [[ ! -f $LOG_FILE ]] && { printf 'Log file not found\n'; return 1; }
  print_header "Recent Player Activity"
  tail -200 "$LOG_FILE" 2>/dev/null | grep -E '(joined|left) the game' | tail -5 || printf 'No recent activity\n'
  printf '\n'
}

# Check for errors
check_errors() {
  [[ ! -f $LOG_FILE ]] && { printf 'Log file not found\n'; return 1; }
  print_header "Recent Errors"
  local errors warns
  errors=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo 0)
  warns=$(tail -100 "$LOG_FILE" 2>/dev/null | grep -ci 'WARN' || echo 0)
  printf '  Errors in last 100 lines: %s\n' "$errors"
  printf '  Warnings in last 100 lines: %s\n' "$warns"
  if ((errors > 0)); then
    printf '\n  Last 3 errors:\n'
    tail -100 "$LOG_FILE" 2>/dev/null | grep -i 'ERROR\|SEVERE' | tail -3 | sed 's/^/    /'
  fi
  printf '\n'
}

# Get uptime
get_uptime() {
  local pid
  pid=$(get_process_pid "fabric-server-launch.jar")
  [[ -z $pid ]] && { printf 'Server not running\n'; return 1; }
  print_header "Server Uptime"
  local uptime_sec days hours mins
  uptime_sec=$(ps -p "$pid" -o etimes= | tr -d ' ')
  days=$((uptime_sec / 86400))
  hours=$(((uptime_sec % 86400) / 3600))
  mins=$(((uptime_sec % 3600) / 60))
  printf '  %dd %dh %dm\n\n' "$days" "$hours" "$mins"
}

# Show comprehensive status
show_status() {
  printf '\n'
  printf '════════════════════════════════════════════════════════\n'
  printf '      Minecraft Server Monitor - %s\n' "$(get_iso_timestamp)"
  printf '════════════════════════════════════════════════════════\n\n'
  get_status
  get_uptime
  get_memory
  get_disk
  get_players
  check_errors
  printf '════════════════════════════════════════════════════════\n'
}

# Watch mode
watch_mode() {
  printf 'Starting monitor (Ctrl+C to stop)\n'
  printf 'Update interval: %ss\n\n' "$CHECK_INTERVAL"
  while true; do
    clear
    show_status
    sleep "$CHECK_INTERVAL"
  done
}

# Alert mode
alert_mode() {
  local issues=0
  check_process || { print_error "Process not running"; ((issues++)); }
  check_port || { print_error "Port not listening"; ((issues++)); }
  if [[ -f $LOG_FILE ]]; then
    local errors
    errors=$(tail -20 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo 0)
    ((errors > 5)) && { print_error "High error rate: $errors errors"; ((issues++)); }
  fi
  local disk
  disk=$(df -h "$SCRIPT_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
  ((disk > 90)) && { print_error "Disk usage critical: ${disk}%"; ((issues++)); }
  ((issues == 0)) && { print_success "All checks passed"; return 0; }
  print_error "Health check failed: $issues issue(s)"
  return 1
}

# Show usage
show_usage() {
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
  *) print_error "Unknown command: $1"; show_usage; exit 1 ;;
esac
