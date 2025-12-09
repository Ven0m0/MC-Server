#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
s=${BASH_SOURCE[0]}; [[ $s != /* ]] && s=$PWD/$s; cd -P -- "${s%/*}/.."
has(){ command -v -- "$1" &>/dev/null; }
# lazymc.sh: Manage lazymc for automatic server sleep/wake
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"
CONFIG_DIR="${CONFIG_DIR:-$PWD/config}"
LAZYMC_CONFIG="${CONFIG_DIR}/lazymc.toml"
LAZYMC_PID_FILE="/tmp/lazymc.pid"
LAZYMC_LOG_FILE="logs/lazymc.log"
check_lazymc(){
  if ! has lazymc; then
    print_error "lazymc not found"
    print_info "Run './scripts/lazymc-setup.sh install' to install"
    exit 1
  fi
}
check_config(){
  if [[ ! -f $LAZYMC_CONFIG ]]; then
    print_error "Configuration not found: ${LAZYMC_CONFIG}"
    print_info "Run './scripts/lazymc-setup.sh config' to generate"
    exit 1
  fi
}
start_lazymc(){
  check_lazymc
  check_config
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
    exit 1
  fi
}
stop_lazymc(){
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
    exit 1
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
restart_lazymc(){
  stop_lazymc
  sleepy 1
  start_lazymc
}
status_lazymc(){
  check_lazymc
  print_header "lazymc Status"
  if [[ -f $LAZYMC_PID_FILE ]]; then
    local pid
    pid="$(<"$LAZYMC_PID_FILE")"
    if kill -0 "$pid" &>/dev/null; then
      print_success "Running (PID: ${pid})"
      if has ps; then
        printf '\n'
        ps -p "$pid" -o pid,ppid,cmd,etime,rss &>/dev/null || :
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
show_logs(){
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    exit 1
  fi
  local lines="${1:-50}"
  tail -n "$lines" "$LAZYMC_LOG_FILE"
}
follow_logs(){
  if [[ ! -f $LAZYMC_LOG_FILE ]]; then
    print_error "Log file not found: ${LAZYMC_LOG_FILE}"
    exit 1
  fi
  tail -f "$LAZYMC_LOG_FILE"
}
show_usage(){
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
main(){
  local cmd="${1:-help}"
  case "$cmd" in
    start) start_lazymc;;
    stop) stop_lazymc;;
    restart) restart_lazymc;;
    status) status_lazymc;;
    logs) show_logs "${2:-50}";;
    follow) follow_logs;;
    help|--help|-h) show_usage;;
    *) print_error "Unknown command: $cmd"; printf '\n'; show_usage; exit 1;;
  esac
}
main "$@"
