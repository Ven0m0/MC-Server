#!/usr/bin/env bash
# prepare.sh: Prepare Minecraft server/client environment

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

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
