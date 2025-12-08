#!/usr/bin/env bash
# common.sh: Shared library for MC-Server scripts
# Source this file at the beginning of other scripts:
#   SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/../scripts/common.sh"

# Guard against multiple inclusions
[[ -n ${_COMMON_SH_LOADED:-} ]] && return 0
readonly _COMMON_SH_LOADED=1

# ==============================================================================
# Strict Mode & Environment
# ==============================================================================
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Resolve current user (handles sudo)
_user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${_user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# ==============================================================================
# Output Formatting
# ==============================================================================
# ANSI color codes (disabled if not a terminal)
if [[ -t 1 ]]; then
  readonly _CLR_BLUE=$'\033[0;34m'
  readonly _CLR_GREEN=$'\033[0;32m'
  readonly _CLR_RED=$'\033[0;31m'
  readonly _CLR_YELLOW=$'\033[1;33m'
  readonly _CLR_RESET=$'\033[0m'
else
  readonly _CLR_BLUE='' _CLR_GREEN='' _CLR_RED='' _CLR_YELLOW='' _CLR_RESET=''
fi

# Print header message (blue arrow)
print_header() { printf '%s==>%s %s\n' "$_CLR_BLUE" "$_CLR_RESET" "$1"; }

# Print success message (green checkmark)
print_success() { printf '%s✓%s %s\n' "$_CLR_GREEN" "$_CLR_RESET" "$1"; }

# Print error message to stderr (red X)
print_error() { printf '%s✗%s %s\n' "$_CLR_RED" "$_CLR_RESET" "$1" >&2; }

# Print info message (yellow arrow)
print_info() { printf '%s→%s %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$1"; }

# Print warning message to stderr (yellow)
print_warn() { printf '%s⚠%s %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$1" >&2; }

# Die with error message and exit code
die() {
  printf '%s✗%s ERROR: %s\n' "$_CLR_RED" "$_CLR_RESET" "$*" >&2
  exit "${2:-1}"
}

# ==============================================================================
# Command Detection
# ==============================================================================
# Check if command exists in PATH
has_command() { command -v "$1" &>/dev/null; }

# Check multiple dependencies, return error listing missing ones
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
  done
  if ((${#missing[@]})); then
    print_error "Missing required dependencies: ${missing[*]}"
    print_info "Please install them before continuing."
    return 1
  fi
}

# Require dependencies or die
require_dependencies() {
  check_dependencies "$@" || exit 1
}

# ==============================================================================
# JSON Processing
# ==============================================================================
# Detect available JSON processor (prefer jaq over jq per CLAUDE.md)
get_json_processor() {
  if has_command jaq; then
    printf 'jaq'
  elif has_command jq; then
    printf 'jq'
  else
    print_error "No JSON processor found. Install jq or jaq."
    return 1
  fi
}

# Parse JSON with detected processor
# Usage: json_query '.field' <<< "$json" OR echo "$json" | json_query '.field'
json_query() {
  local query="$1"
  local json_proc
  json_proc=$(get_json_processor) || return 1
  "$json_proc" -r "$query"
}

# ==============================================================================
# Download Utilities
# ==============================================================================
# Fetch URL content to stdout (for API calls, JSON fetching)
fetch_url() {
  local url="$1"
  if has_command curl; then
    curl -fsSL "$url"
  elif has_command wget; then
    wget -qO- "$url"
  else
    print_error "No download tool found (curl or wget required)"
    return 1
  fi
}

# Download file to disk with progress (prefers aria2c > curl > wget per CLAUDE.md)
# Usage: download_file <url> <output_file> [connections]
download_file() {
  local url="$1" output="$2" connections="${3:-8}"

  if has_command aria2c; then
    aria2c -x"$connections" -s"$connections" \
      --allow-overwrite=true --auto-file-renaming=false \
      -d "$(dirname "$output")" -o "$(basename "$output")" "$url"
  elif has_command curl; then
    curl -fsSL \
      -H "Accept-Encoding: identity" \
      -H "Accept-Language: en" \
      -A "Mozilla/5.0 (compatible; MC-Server/1.0)" \
      -o "$output" "$url"
  elif has_command wget; then
    wget -qO "$output" "$url"
  else
    print_error "No download tool found (aria2c, curl, or wget)"
    return 1
  fi
}

# ==============================================================================
# System Information
# ==============================================================================
# Get total RAM in GB
get_total_ram_gb() {
  awk '/MemTotal/ {printf "%.0f\n", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 4
}

# Calculate heap size (total RAM minus reserved for OS)
# Usage: get_heap_size_gb [reserved_gb]
get_heap_size_gb() {
  local reserved="${1:-2}"
  local total_ram heap
  total_ram=$(get_total_ram_gb)
  heap=$((total_ram - reserved))
  ((heap < 1)) && heap=1
  printf '%d' "$heap"
}

# Get number of CPU cores
get_cpu_cores() {
  nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4
}

# Get available memory for Minecraft (total - 2GB for OS, min 2GB)
get_minecraft_memory_gb() {
  local total heap
  total=$(get_total_ram_gb)
  heap=$((total - 2))
  ((heap < 2)) && heap=2
  printf '%d' "$heap"
}

# Format byte size to human readable (1G, 1M, 1K, 1B)
format_size_bytes() {
  local size="$1"
  local -r KB=1024 MB=1048576 GB=1073741824
  if ((size >= GB)); then
    awk "BEGIN {printf \"%.1fG\", $size/$GB}"
  elif ((size >= MB)); then
    awk "BEGIN {printf \"%.1fM\", $size/$MB}"
  elif ((size >= KB)); then
    awk "BEGIN {printf \"%.1fK\", $size/$KB}"
  else
    printf '%dB' "$size"
  fi
}

# ==============================================================================
# Architecture Detection
# ==============================================================================
# Detect system architecture (returns: x86_64, aarch64, armv7l, etc.)
detect_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64 | amd64) printf 'x86_64' ;;
    aarch64 | arm64) printf 'aarch64' ;;
    armv7l | armhf) printf 'armv7l' ;;
    *) printf '%s' "$arch" ;;
  esac
}

# Detect OS type
detect_os() {
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    linux) printf 'linux' ;;
    darwin) printf 'macos' ;;
    *) printf '%s' "$os" ;;
  esac
}

# ==============================================================================
# Path Utilities
# ==============================================================================
# Get absolute path of script's directory
# Usage: SCRIPT_DIR=$(get_script_dir)
get_script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

# Get project root (assumes scripts/ or tools/ subdirectory)
get_project_root() {
  local dir
  dir=$(get_script_dir)
  case "$dir" in
    */scripts | */tools) dirname "$dir" ;;
    *) printf '%s' "$dir" ;;
  esac
}

# ==============================================================================
# File Operations
# ==============================================================================
# Safely backup file before modification
backup_file() {
  local file="$1"
  [[ -f $file ]] && cp -a "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
}

# Create directory if it doesn't exist
ensure_dir() {
  local dir="$1"
  [[ -d $dir ]] || mkdir -p "$dir"
}

# ==============================================================================
# Process Management
# ==============================================================================
# Check if process is running by name pattern
is_process_running() {
  local pattern="$1"
  pgrep -f "$pattern" >/dev/null 2>&1
}

# Get PID of process by name pattern
get_process_pid() {
  local pattern="$1"
  pgrep -f "$pattern" | head -1
}

# ==============================================================================
# Timestamp Utilities
# ==============================================================================
# Get current timestamp in standard format
get_timestamp() {
  printf '%(%Y%m%d_%H%M%S)T' -1
}

# Get ISO timestamp
get_iso_timestamp() {
  printf '%(%Y-%m-%dT%H:%M:%S)T' -1
}
