#!/usr/bin/env bash
# prepare.sh: Prepare Minecraft server/client environment with AppCDS archives

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode

echo "[*] Minecraft Environment Preparation"
echo "─────────────────────────────────────────────────────────────"

# ─── Install Dependencies (Arch Linux only) ─────────────────────────────────────
if has_command paru; then
    print_header "Installing dependencies via paru..."
    paru --noconfirm --skipreview -Sq \
        ferium jdk25-graalvm-bin gamemode preload \
        prelockd nohang memavaild adaptivemm uresourced 2>/dev/null || \
        print_info "Some packages may have failed to install"
    print_success "Dependencies installation attempted"
else
    print_info "paru not found - skipping Arch Linux package installation"
fi

# ─── Calculate Memory Allocation ────────────────────────────────────────────────
TOTAL_RAM=$(get_total_ram_gb)
SERVER_HEAP=$(get_heap_size_gb 2)  # Reserve 2GB for OS
CLIENT_HEAP=$(get_client_xmx_gb)   # Use half of RAM for client

print_header "System Resources"
echo "  Total RAM: ${TOTAL_RAM}G"
echo "  Server heap: ${SERVER_HEAP}G"
echo "  Client heap: ${CLIENT_HEAP}G"

# ─── Generate AppCDS Archive for Server ─────────────────────────────────────────
if [[ -f server.jar ]]; then
    print_header "Generating AppCDS archive for server..."
    java -Xms"${SERVER_HEAP}G" -Xmx"${SERVER_HEAP}G" \
        -XX:ArchiveClassesAtExit=minecraft_server.jsa \
        -jar server.jar --nogui || print_error "Server AppCDS generation failed"
    [[ -f minecraft_server.jsa ]] && print_success "Server AppCDS archive created: minecraft_server.jsa"
else
    print_error "server.jar not found - skipping server preparation"
fi

# ─── Generate AppCDS Archive for Client ─────────────────────────────────────────
if [[ -f client.jar ]]; then
    print_header "Generating AppCDS archive for client..."
    java -Xms"${CLIENT_HEAP}G" -Xmx"${CLIENT_HEAP}G" \
        -XX:ArchiveClassesAtExit=minecraft_client.jsa \
        -jar client.jar || print_error "Client AppCDS generation failed"
    [[ -f minecraft_client.jsa ]] && print_success "Client AppCDS archive created: minecraft_client.jsa"
else
    print_info "client.jar not found - skipping client preparation"
fi

echo "─────────────────────────────────────────────────────────────"
print_success "Preparation complete!"
