#!/usr/bin/env bash
# prepare.sh: Prepare Minecraft server/client environment

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Calculate total RAM in GB
get_total_ram_gb() { awk '/MemTotal/ {printf "%.0f\n",$2/1024/1024}' /proc/meminfo 2>/dev/null; }

# Calculate heap size (total RAM minus reserved for OS)
get_heap_size_gb() {
  local reserved="${1:-2}"
  local total_ram=$(get_total_ram_gb)
  local heap=$((total_ram - reserved))
  [[ $heap -lt 1 ]] && heap=1
  echo "$heap"
}

# Calculate client memory allocation
get_client_xmx_gb() {
  local total_ram=$(get_total_ram_gb)
  local xmx=$((total_ram / 2))
  [[ $xmx -lt 2 ]] && xmx=2
  echo "$xmx"
}

# Output formatting helpers
print_header() { echo -e "\033[0;34m==>\033[0m $1"; }
print_success() { echo -e "\033[0;32m✓\033[0m $1"; }
print_error() { echo -e "\033[0;31m✗\033[0m $1" >&2; }
print_info() { echo -e "\033[1;33m→\033[0m $1"; }

print_header "Minecraft Environment Preparation"

# Calculate Memory Allocation
TOTAL_RAM=$(get_total_ram_gb)
SERVER_HEAP=$(get_heap_size_gb 2)
CLIENT_HEAP=$(get_client_xmx_gb)

print_info "Total RAM: ${TOTAL_RAM}G | Server heap: ${SERVER_HEAP}G | Client heap: ${CLIENT_HEAP}G"

# Generate AppCDS Archive for Server
if [[ -f server.jar ]]; then
  print_info "Generating AppCDS archive for server..."
  java -Xms"${SERVER_HEAP}G" -Xmx"${SERVER_HEAP}G" \
    -XX:ArchiveClassesAtExit=minecraft_server.jsa \
    -jar server.jar --nogui || print_error "Server AppCDS generation failed"
  [[ -f minecraft_server.jsa ]] && print_success "Server AppCDS archive created"
else
  print_error "server.jar not found - skipping server preparation"
fi

# Generate AppCDS Archive for Client
if [[ -f client.jar ]]; then
  print_info "Generating AppCDS archive for client..."
  java -Xms"${CLIENT_HEAP}G" -Xmx"${CLIENT_HEAP}G" \
    -XX:ArchiveClassesAtExit=minecraft_client.jsa \
    -jar client.jar || print_error "Client AppCDS generation failed"
  [[ -f minecraft_client.jsa ]] && print_success "Client AppCDS archive created"
else
  print_info "client.jar not found - skipping client preparation"
fi

print_success "Preparation complete!"
