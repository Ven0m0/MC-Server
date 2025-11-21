#!/usr/bin/env bash
# Common functions and utilities for MC-Server scripts

# Auto-initialize SCRIPT_DIR when this file is sourced
if [[ -z ${SCRIPT_DIR:-} ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  export SCRIPT_DIR
fi

# Initialize strict mode for bash scripts
init_strict_mode() {
  set -euo pipefail
  shopt -s nullglob globstar
  IFS=$'\n\t'
  export LC_ALL=C LANG=C
  local user="${SUDO_USER:-${USER:-$(id -un)}}"
  export HOME="/home/${user}"
  SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"
}

# Get script's working directory
get_script_dir() { cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && pwd; }
# Change to script directory
cd_script_dir() { cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" || return 1; }
# Calculate total RAM in GB
get_total_ram_gb() { awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }
# Calculate heap size (total RAM minus reserved for OS)
# Usage: get_heap_size_gb [reserved_gb]
# Default reserved is 2GB
get_heap_size_gb() {
  local reserved="${1:-2}"
  local total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  [[ $heap -lt 1 ]] && heap=1
  echo "$heap"
}

# Calculate Minecraft memory allocation (alias for get_heap_size_gb)
# Usage: get_minecraft_memory_gb [reserved_gb]
# Default reserved is 3GB
get_minecraft_memory_gb() { get_heap_size_gb "${1:-3}"; }
# Check if command exists
has_command() { command -v "$1" &>/dev/null; }
# Check if required commands are available
check_dependencies() {
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Please install them before continuing." >&2
    return 1
  fi
}
# Detect JSON processor (prefer jaq over jq)
get_json_processor() {
  if has_command jaq; then
    echo "jaq"
  elif has_command jq; then
    echo "jq"
  else
    echo "Error: No JSON processor found. Please install jq or jaq." >&2
    return 1
  fi
}
# Fetch URL to stdout
fetch_url() {
  local url="$1"
  if has_command aria2c; then
    aria2c -q -d /tmp -o - "$url" 2>/dev/null
  elif has_command curl; then
    curl -fsSL "$url"
  elif has_command wget; then
    wget -qO- "$url"
  else
    echo "Error: No download tool found (aria2c, curl, or wget)" >&2
    return 1
  fi
}
# Download file with aria2c or curl fallback
download_file() {
  local url="$1" output="$2" connections="${3:-8}"
  if has_command aria2c; then
    aria2c -x "$connections" -s "$connections" -o "$output" "$url"
  elif has_command curl; then
    curl -fsL -o "$output" "$url"
  elif has_command wget; then
    wget -qO "$output" "$url"
  else
    echo "Error: No download tool found (aria2c, curl, or wget)" >&2
    return 1
  fi
}
# Create directory if it doesn't exist
ensure_dir() { [[ ! -d $1 ]] && mkdir -p "$1" || return 0; }
# Extract natives from JAR file
extract_natives() {
  local jar_file="$1" dest_dir="$2"
  ensure_dir "$dest_dir"
  unzip -q -o "$jar_file" -d "$dest_dir" 2>/dev/null || :
  # Remove META-INF directory
  rm -rf "${dest_dir}/META-INF"
}
# Get aria2c download options for consistent configuration
get_aria2c_opts() { echo "-x 16 -s 16"; }
# Get aria2c options as array (safely handles word splitting)
get_aria2c_opts_array() { echo "-x" "16" "-s" "16"; }
# Calculate client memory allocation (Xms = 1/4 RAM, Xmx = 1/2 RAM)
get_client_xms_gb() {
  local total_ram=$(get_total_ram_gb)
  local xms=$((total_ram / 4))
  [[ $xms -lt 1 ]] && xms=1
  echo "$xms"
}
get_client_xmx_gb() {
  local total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2))
  [[ $xmx -lt 2 ]] && xmx=2
  echo "$xmx"
}
# Get number of CPU cores
get_cpu_cores() { nproc 2>/dev/null || echo 4; }
# Output formatting helpers
print_header() { echo -e "\033[0;34m==>\033[0m $1"; }
print_success() { echo -e "\033[0;32m✓\033[0m $1"; }
print_error() { echo -e "\033[0;31m✗\033[0m $1" >&2; }
print_info() { echo -e "\033[1;33m→\033[0m $1"; }
