#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
s=${BASH_SOURCE[0]}; [[ $s != /* ]] && s=$PWD/$s; cd -P -- "${s%/*}"
has(){ command -v -- "$1" &>/dev/null; }
date(){ local x="${1:-%d/%m/%y-%R}"; printf "%($x)T\n" '-1'; }
fcat(){ printf '%s\n' "$(<${1})"; }
sleepy(){ read -rt "${1:-1}" -- <><(:) &>/dev/null || :; }
# ============================================================================
# common.sh: Shared library for Minecraft server management scripts
# This file is sourced by all scripts in the tools/ directory
# ============================================================================
# OUTPUT FORMATTING FUNCTIONS
# ============================================================================
print_header(){ printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_success(){ printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_error(){ printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_info(){ printf '\033[1;33m→\033[0m %s\n' "$1"; }
# ============================================================================
# SYSTEM FUNCTIONS
# ============================================================================
detect_arch(){
  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'x86_64';;
    aarch64|arm64) printf 'aarch64';;
    armv7l) printf 'armv7';;
    *) print_error "Unsupported architecture: $arch"; exit 1;;
  esac
}
has_command(){ has "$1"; }
check_dependencies(){
  local missing=()
  for cmd in "$@"; do
    has "$cmd" || missing+=("$cmd")
  done
  ((${#missing[@]})) && {
    printf 'Error: Missing required dependencies: %s\n' "${missing[*]}" >&2
    printf 'Please install them before continuing.\n' >&2
    return 1
  }
}
# ============================================================================
# JSON PROCESSOR DETECTION
# ============================================================================
get_json_processor(){
  has jaq && { printf 'jaq'; return; }
  has jq && { printf 'jq'; return; }
  printf 'Error: No JSON processor found. Please install jq or jaq.\n' >&2
  return 1
}
# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================
fetch_url(){
  local url="$1"
  has curl && { curl -fsSL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" "$url"; return; }
  has wget && { wget -qO- "$url"; return; }
  printf 'Error: No download tool found (curl or wget)\n' >&2
  return 1
}
download_file(){
  local url="$1" output="$2" connections="${3:-8}"
  has aria2c && { aria2c -x "$connections" -s "$connections" -o "$output" "$url" &>/dev/null; return; }
  has curl && { curl -fsL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" -o "$output" "$url"; return; }
  has wget && { wget -qO "$output" "$url"; return; }
  printf 'Error: No download tool found (aria2c, curl, or wget)\n' >&2
  return 1
}
# ============================================================================
# MEMORY CALCULATION FUNCTIONS
# ============================================================================
get_total_ram_gb(){
  awk '/MemTotal/{printf "%.0f\n",$2/1024/1024}' /proc/meminfo &>/dev/null
}
get_heap_size_gb(){
  local reserved="${1:-2}" total_ram; total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved)); ((heap < 1)) && heap=1
  printf '%s' "$heap"
}
get_minecraft_memory_gb(){
  get_heap_size_gb "${1:-3}"
}
get_client_xms_gb(){
  local total_ram; total_ram=$(get_total_ram_gb)
  local xms=$((total_ram / 4)); ((xms < 1)) && xms=1
  printf '%s' "$xms"
}
get_client_xmx_gb(){
  local total_ram; total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2)); ((xmx < 2)) && xmx=2
  printf '%s' "$xmx"
}
# ============================================================================
# SYSTEM INFORMATION FUNCTIONS
# ============================================================================
get_cpu_cores(){
  nproc &>/dev/null || printf '4'
}
# ============================================================================
# DOWNLOAD CONFIGURATION FUNCTIONS
# ============================================================================
get_aria2c_opts(){
  printf '%s' "-x 16 -s 16"
}
get_aria2c_opts_array(){
  printf '%s\n' "-x" "16" "-s" "16"
}
# ============================================================================
# FILE SYSTEM FUNCTIONS
# ============================================================================
ensure_dir(){
  [[ ! -d $1 ]] && mkdir -p "$1" || return 0
}
format_size_bytes(){
  local bytes="$1"
  if ((bytes >= 1073741824)); then
    local gb=$((bytes / 1073741824)) decimal=$(((bytes % 1073741824) * 10 / 1073741824))
    printf '%d.%dG' "$gb" "$decimal"
  elif ((bytes >= 1048576)); then
    local mb=$((bytes / 1048576)) decimal=$(((bytes % 1048576) * 10 / 1048576))
    printf '%d.%dM' "$mb" "$decimal"
  elif ((bytes >= 1024)); then
    local kb=$((bytes / 1024)) decimal=$(((bytes % 1024) * 10 / 1024))
    printf '%d.%dK' "$kb" "$decimal"
  else
    printf '%dB' "$bytes"
  fi
}
# ============================================================================
# SCRIPT DIRECTORY DETECTION
# ============================================================================
get_script_dir(){
  printf '%s' "$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")/.." && pwd)"
}
# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================
is_server_running(){
  pgrep -f "fabric-server-launch.jar" &>/dev/null || pgrep -f "server.jar" &>/dev/null
}
check_server_port(){
  local port="${1:-25565}"
  if has nc; then
    nc -z localhost "$port" &>/dev/null
  elif has ss; then
    ss -tuln 2>/dev/null | rg -q ":${port} "
  else
    netstat -tuln 2>/dev/null | rg -q ":${port} "
  fi
}
# ============================================================================
# JAVA DETECTION FUNCTIONS
# ============================================================================
detect_java(){
  if [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/java" ]]; then
    printf '%s' "${JAVA_HOME}/bin/java"; return
  fi
  local java_cmd="java"
  if has archlinux-java; then
    local sel_java; sel_java="$(archlinux-java get &>/dev/null || printf '')"
    [[ -n $sel_java ]] && java_cmd="/usr/lib/jvm/${sel_java}/bin/java"
  elif has mise; then
    java_cmd="$(mise which java &>/dev/null || printf 'java')"
  fi
  [[ -x $java_cmd ]] || java_cmd="java"
  printf '%s' "$java_cmd"
}
# ============================================================================
# ROOT/SUDO CHECK FUNCTIONS
# ============================================================================
check_root(){
  [[ $EUID -eq 0 ]] && return 0
  has sudo && { print_info "Root access required. Using sudo..."; return 0; }
  print_error "Root access required but sudo not available"; return 1
}
send_command(){
  local cmd="$1" session_name="minecraft"
  if command -v screen &>/dev/null && screen -list | rg -q "$session_name" &>/dev/null; then
    print_info "Sending command to Screen: $cmd"
    screen -S "$session_name" -p 0 -X stuff "$cmd$(printf \\r)"
  elif command -v tmux &>/dev/null && tmux has-session -t "$session_name" &>/dev/null; then
    print_info "Sending command to Tmux: $cmd"
    tmux send-keys -t "$session_name" "$cmd" Enter
  else
    print_error "Server session '$session_name' not found (Screen/Tmux)."; return 1
  fi
}
game_command(){
  local cmd="$1" host="localhost" port="25575" pass=""
  command -v mcrcon &>/dev/null || { print_error "mcrcon is not installed. Cannot send command."; return 1; }
  mcrcon -H "$host" -P "$port" -p "$pass" -c "$cmd"
}
