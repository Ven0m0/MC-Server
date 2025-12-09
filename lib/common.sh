#!/usr/bin/env bash
# common.sh: Shared library for Minecraft server management scripts
# This file is sourced by all scripts in scripts/ and tools/ directories

# ============================================================================
# STANDARD INITIALIZATION
# ============================================================================

# Strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'

# Environment normalization
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# ============================================================================
# OUTPUT FORMATTING FUNCTIONS
# ============================================================================

# Print header with blue arrow
print_header(){ printf '\033[0;34m==>\033[0m %s\n' "$1"; }

# Print success message with green checkmark
print_success(){ printf '\033[0;32m✓\033[0m %s\n' "$1"; }

# Print error message with red X to stderr
print_error(){ printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }

# Print info message with yellow arrow
print_info(){ printf '\033[1;33m→\033[0m %s\n' "$1"; }

# ============================================================================
# SYSTEM FUNCTIONS
# ============================================================================

# Detect system architecture
# Usage: arch=$(detect_arch)
# Returns: x86_64, aarch64, or armv7
detect_arch(){
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "x86_64";;
    aarch64|arm64) echo "aarch64";;
    armv7l) echo "armv7";;
    *) print_error "Unsupported architecture: $arch"; exit 1;;
  esac
}

# Check if a command exists in PATH
# Usage: has_command <command>
# Returns: 0 if command exists, 1 otherwise
has_command(){ command -v "$1" &>/dev/null; }

# Check if multiple commands exist
# Usage: check_dependencies <cmd1> [cmd2] ...
# Returns: 0 if all exist, 1 if any missing (prints missing commands to stderr)
check_dependencies(){
  local missing=()
  for cmd in "$@"; do
    has_command "$cmd" || missing+=("$cmd")
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

# Detect available JSON processor (prefer jaq over jq)
# Usage: JSON_PROC=$(get_json_processor) || exit 1
# Returns: Name of available JSON processor (jaq or jq)
get_json_processor(){
  has_command jaq && {
    printf 'jaq'
    return
  }
  has_command jq && {
    printf 'jq'
    return
  }
  printf 'Error: No JSON processor found. Please install jq or jaq.\n' >&2
  return 1
}

# ============================================================================
# DOWNLOAD FUNCTIONS
# ============================================================================

# Fetch URL content to stdout
# Usage: fetch_url <url>
# Note: Prefers curl, falls back to wget
fetch_url(){
  local url="$1"
  has_command curl && {
    curl -fsSL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" "$url"
    return
  }
  has_command wget && {
    wget -qO- "$url"
    return
  }
  printf 'Error: No download tool found (curl or wget)\n' >&2
  return 1
}

# Download file to specified path
# Usage: download_file <url> <output> [connections]
# Note: Prefers aria2c, falls back to curl, then wget
download_file(){
  local url="$1" output="$2" connections="${3:-8}"

  has_command aria2c && {
    aria2c -x "$connections" -s "$connections" -o "$output" "$url" 2>/dev/null
    return
  }
  has_command curl && {
    curl -fsL -H "Accept-Encoding: identity" -H "Accept-Language: en" -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4.212 Safari/537.36" -o "$output" "$url"
    return
  }
  has_command wget && {
    wget -qO "$output" "$url"
    return
  }
  printf 'Error: No download tool found (aria2c, curl, or wget)\n' >&2
  return 1
}

# ============================================================================
# MEMORY CALCULATION FUNCTIONS
# ============================================================================

# Calculate total RAM in GB
# Usage: total_ram=$(get_total_ram_gb)
# Returns: Total RAM in gigabytes (rounded)
get_total_ram_gb(){
  awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null
}

# Calculate heap size (total RAM minus reserved for OS)
# Usage: heap=$(get_heap_size_gb [reserved_gb])
# Args: reserved_gb - GB to reserve for OS (default: 2)
# Returns: Heap size in GB (minimum 1)
get_heap_size_gb(){
  local reserved="${1:-2}"
  local total_ram
  total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  ((heap < 1)) && heap=1
  printf '%s' "$heap"
}

# Calculate Minecraft server memory allocation
# Usage: mem=$(get_minecraft_memory_gb [reserved_gb])
# Args: reserved_gb - GB to reserve for OS (default: 3)
# Returns: Memory allocation in GB
get_minecraft_memory_gb(){
  get_heap_size_gb "${1:-3}"
}

# Calculate client minimum memory (XMS)
# Usage: xms=$(get_client_xms_gb)
# Returns: XMS value in GB (25% of total RAM, minimum 1)
get_client_xms_gb(){
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xms=$((total_ram / 4))
  ((xms < 1)) && xms=1
  printf '%s' "$xms"
}

# Calculate client maximum memory (XMX)
# Usage: xmx=$(get_client_xmx_gb)
# Returns: XMX value in GB (50% of total RAM, minimum 2)
get_client_xmx_gb(){
  local total_ram
  total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2))
  ((xmx < 2)) && xmx=2
  printf '%s' "$xmx"
}

# ============================================================================
# SYSTEM INFORMATION FUNCTIONS
# ============================================================================

# Get number of CPU cores
# Usage: cores=$(get_cpu_cores)
# Returns: Number of CPU cores (defaults to 4 if detection fails)
get_cpu_cores(){
  nproc 2>/dev/null || printf '4'
}

# ============================================================================
# DOWNLOAD CONFIGURATION FUNCTIONS
# ============================================================================

# Get aria2c download options as string
# Usage: opts=$(get_aria2c_opts)
# Returns: aria2c options string
get_aria2c_opts(){
  printf '%s' "-x 16 -s 16"
}

# Get aria2c download options as array elements (one per line)
# Usage: mapfile -t arr < <(get_aria2c_opts_array)
# Returns: aria2c options, one per line
get_aria2c_opts_array(){
  printf '%s\n' "-x" "16" "-s" "16"
}

# ============================================================================
# FILE SYSTEM FUNCTIONS
# ============================================================================

# Create directory if it doesn't exist
# Usage: ensure_dir <path>
# Returns: 0 (always succeeds, creates directory if needed)
ensure_dir(){
  [[ ! -d $1 ]] && mkdir -p "$1" || return 0
}

# Format bytes to human-readable size
# Usage: formatted=$(format_size_bytes <bytes>)
# Returns: Human-readable size (e.g., "1.5G", "512M")
format_size_bytes(){
  local bytes="$1"
  if ((bytes >= 1073741824)); then
    printf '%.1fG' "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}")"
  elif ((bytes >= 1048576)); then
    printf '%.1fM' "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")"
  elif ((bytes >= 1024)); then
    printf '%.1fK' "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")"
  else
    printf '%dB' "$bytes"
  fi
}

# ============================================================================
# SCRIPT DIRECTORY DETECTION
# ============================================================================

# Get the root directory of the repository
# Usage: SCRIPT_DIR=$(get_script_dir)
# Note: This should be called from within a script to get the repo root
# Returns: Absolute path to repository root
get_script_dir(){
  # Use BASH_SOURCE[1] because this is called from within another script
  # cd to parent of the calling script's directory (scripts/ or tools/ -> repo root)
  printf '%s' "$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")/.." && pwd)"
}

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

# Check if Minecraft server process is running
# Usage: is_server_running && echo "Server is running"
# Returns: 0 if running, 1 if not
is_server_running(){
  pgrep -f "fabric-server-launch.jar" >/dev/null || pgrep -f "server.jar" >/dev/null
}

# Check if server port is open
# Usage: check_server_port [port]
# Args: port - Port number to check (default: 25565)
# Returns: 0 if port is open, 1 if closed
check_server_port(){
  local port="${1:-25565}"
  if has_command nc; then
    nc -z localhost "$port" &>/dev/null
  elif has_command ss; then
    ss -tuln | grep -q ":${port} "
  else
    netstat -tuln 2>/dev/null | grep -q ":${port} "
  fi
}

# ============================================================================
# JAVA DETECTION FUNCTIONS
# ============================================================================
# Detect best available Java command
# Usage: java_cmd=$(detect_java)
# Returns: Full path to java or "java" if using PATH
detect_java(){
  local java_cmd="java"
  # Check for Arch Linux java-runtime-common
  if has_command archlinux-java; then
    local sel_java
    sel_java="$(archlinux-java get 2>/dev/null || printf '')"
    [[ -n $sel_java ]] && java_cmd="/usr/lib/jvm/${sel_java}/bin/java"
  # Check for mise version manager
  elif has_command mise; then
    java_cmd="$(mise which java 2>/dev/null || printf 'java')"
  fi
  # Verify java command is executable, fallback to PATH
  [[ -x $java_cmd ]] || java_cmd="java"
  printf '%s' "$java_cmd"
}
# ============================================================================
# ROOT/SUDO CHECK FUNCTIONS
# ============================================================================
# Check if running as root or with sudo access
# Usage: check_root || return 1
# Returns: 0 if root or sudo available, 1 if neither
check_root(){
  [[ $EUID -eq 0 ]] && return 0
  has_command sudo && {
    print_info "Root access required. Using sudo..."
    return 0
  }
  print_error "Root access required but sudo not available"
  return 1
}
