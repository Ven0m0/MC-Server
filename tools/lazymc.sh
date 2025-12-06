#!/usr/bin/env bash
# lazymc.sh: Manage lazymc for automatic server sleep/wake
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'

# Output formatting helpers
print_header() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_error() { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_info() { printf '\033[1;33m→\033[0m %s\n' "$1"; }

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Configuration
CONFIG_DIR="${CONFIG_DIR:-$PWD/config}"
LAZYMC_CONFIG="${CONFIG_DIR}/lazymc.toml"
LAZYMC_PID_FILE="/tmp/lazymc.pid"
LAZYMC_LOG_FILE="logs/lazymc.log"

# Ensure lazymc is installed
check_lazymc() {
  if ! has_command lazymc; then
    print_error "lazymc not found"
    print_info "Run './scripts/lazymc-setup.sh install' to install"
    exit 1
  fi
}

# Check if lazymc config exists
check_config() {
  if [[ ! -f $LAZYMC_CONFIG ]]; then
    print_error "Configuration not found: ${LAZYMC_CONFIG}"
    print_info "Run './scripts/lazymc-setup.sh config' to generate"
    exit 1
  fi
}

# Start lazymc
start_lazymc() {
  check_lazymc
  check_config

  # Check if already running
  if [[ -f $LAZYMC_PID_FILE ]]; then
    local existing_pid
    existing_pid="$(cat "$LAZYMC_PID_FILE")"
    if kill -0 "$existing_pid" 2>/dev/null; then
      print_info "lazymc is already running (PID: ${existing_pid})"
      return 0
    fi
  fi

  print_header "Starting lazymc"

  # Create logs directory if it doesn't exist
  mkdir -p "$(dirname "$LAZYMC_LOG_FILE")"

  # Start lazymc in background
  nohup lazymc start --config "$LAZYMC_CONFIG" >> "$LAZYMC_LOG_FILE" 2>&1 &
  local pid=$!

  # Save PID
  echo "$pid" > "$LAZYMC_PID_FILE"

  # Wait a moment and check if still running
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    print_success "lazymc started (PID: ${pid})"
    print_info "Log file: ${LAZYMC_LOG_FILE}"
  else
    print_error "Failed to start lazymc"
    print_info "Check logs: ${LAZYMC_LOG_FILE}"
    rm -f "$LAZYMC_PID_FILE"
    exit 1
  fi
}

# Stop lazymc
stop_lazymc() {
  if [[ ! -f $LAZYMC_PID_FILE ]]; then
    print_info "lazymc is not running (no PID file)"
    return 0
  fi

  local pid
  pid="$(cat "$LAZYMC_PID_FILE")"

  if ! kill -0 "$pid" 2>/dev/null; then
    print_info "lazymc is not running (stale PID file)"
    rm -f "$LAZYMC_PID_FILE"
    return 0
  fi

  print_header "Stopping lazymc"
  kill "$pid" 2>/dev/null || {
    print_error "Failed to stop lazymc (PID: ${pid})"
    exit 1
  }

  # Wait for process to exit
  local count=0
  while kill -0 "$pid" 2>/dev/null && ((count < 10)); do
    sleep 1
    ((count++))
  done

  if kill -0 "$pid" 2>/dev/null; then
    print_info "Force killing lazymc"
    kill -9 "$pid" 2>/dev/null || :
  fi

  rm -f "$LAZYMC_PID_FILE"
  print_success "lazymc stopped"
}

# Restart lazymc
restart_lazymc() {
  stop_lazymc
  sleep 1
  start_lazymc
}

# Show lazymc status
status_lazymc() {
  check_lazymc

  print_header "lazymc Status"

  if [[ -f $LAZYMC_PID_FILE ]]; then
    local pid
    pid="$(cat "$LAZYMC_PID_FILE")"

    if kill -0 "$pid" 2>/dev/null; then
      print_success "Running (PID: ${pid})"

      # Show process info
      if has_command ps; then
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

  # Show configuration
  if [[ -f $LAZYMC_CONFIG ]]; then
    printf '\n'
    print_info "Configuration: ${LAZYMC_CONFIG}"
  fi

  # Show recent log entries
  if [[ -f $LAZYMC_LOG_FILE ]]; then
    printf '\n'
    print_header "Recent Logs"
    tail -n 10 "$LAZYMC_LOG_FILE" || :
  fi
}

# Show logs
show_logs() {
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    exit 1
  fi

  local lines="${1:-50}"
  tail -n "$lines" "$LAZYMC_LOG_FILE"
}

# Follow logs
follow_logs() {
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    exit 1
  fi

  tail -f "$LAZYMC_LOG_FILE"
}

# Show usage
show_usage() {
  print_header "lazymc Management Script"
  printf '\n'
  printf 'Usage: %s <command> [options]\n' "$0"
  printf '\n'
  printf 'Commands:\n'
  printf '  start      Start lazymc daemon\n'
  printf '  stop       Stop lazymc daemon\n'
  printf '  restart    Restart lazymc daemon\n'
  printf '  status     Show lazymc status\n'
  printf '  logs       Show recent logs (default: 50 lines)\n'
  printf '  follow     Follow logs in real-time\n'
  printf '  help       Show this help message\n'
  printf '\n'
  printf 'Examples:\n'
  printf '  %s start\n' "$0"
  printf '  %s status\n' "$0"
  printf '  %s logs 100\n' "$0"
  printf '\n'
}

# Main
main() {
  local cmd="${1:-help}"

  case "$cmd" in
    start)
      start_lazymc
      ;;
    stop)
      stop_lazymc
      ;;
    restart)
      restart_lazymc
      ;;
    status)
      status_lazymc
      ;;
    logs)
      show_logs "${2:-50}"
      ;;
    follow)
      follow_logs
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      print_error "Unknown command: $cmd"
      printf '\n'
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
