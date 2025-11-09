#!/bin/bash
# Common functions and utilities for MC-Server scripts

# Initialize strict mode for bash scripts
init_strict_mode() {
    set -euo pipefail
    IFS=$'\n\t'
}

# Get script's working directory and cd to it
get_script_dir() {
    local dir
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && pwd)"
    echo "$dir"
}

# Change to script directory
cd_script_dir() {
    local dir
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && pwd)"
    cd "$dir"
}

# Calculate total RAM in GB
get_total_ram_gb() {
    awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null
}

# Calculate memory allocation for Minecraft (fraction of total RAM)
# Usage: get_minecraft_memory_gb [fraction]
# Default fraction is 3 (1/3 of total RAM)
get_minecraft_memory_gb() {
    local divisor="${1:-3}"
    awk -v div="$divisor" '/MemTotal/ {print int($2/1024/1024/div)}' /proc/meminfo
}

# Calculate heap size (total RAM minus reserved for OS)
# Usage: get_heap_size_gb [reserved_gb]
# Default reserved is 2GB
get_heap_size_gb() {
    local reserved="${1:-2}"
    local total_ram
    total_ram=$(get_total_ram_gb)
    local heap=$((total_ram - reserved))
    [[ $heap -lt 1 ]] && heap=1
    echo "$heap"
}

# Check if command exists
has_command() {
    command -v "$1" &>/dev/null
}
