#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}/.."
# prepare.sh: Prepare Minecraft server environment and optional components
# shellcheck source=lib/common.sh
source "${PWD}/lib/common.sh"
# shellcheck source=config/versions.sh
source "${PWD}/config/versions.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$PWD/config}"
LAZYMC_CONFIG="${CONFIG_DIR}/lazymc.toml"
# ============================================================================
# SERVER PREPARATION FUNCTIONS
# ============================================================================
prepare_server(){
  print_header "Minecraft Environment Preparation"
  local total_ram server_heap client_heap
  total_ram=$(get_total_ram_gb)
  server_heap=$(get_heap_size_gb 2)
  client_heap=$(get_client_xmx_gb)
  print_info "Total RAM: ${total_ram}G | Server heap: ${server_heap}G | Client heap: ${client_heap}G"
  # Generate AppCDS archive for server
  if [[ -f server.jar ]]; then
    print_info "Generating AppCDS archive for server..."
    java -Xms"${server_heap}G" -Xmx"${server_heap}G" \
      -XX:ArchiveClassesAtExit=minecraft_server.jsa \
      -jar server.jar --nogui || print_error "Server AppCDS generation failed"
    [[ -f minecraft_server.jsa ]] && print_success "Server AppCDS archive created"
  else
    print_error "server.jar not found - skipping server preparation"
  fi
  # Generate AppCDS archive for client
  if [[ -f client.jar ]]; then
    print_info "Generating AppCDS archive for client..."
    java -Xms"${client_heap}G" -Xmx"${client_heap}G" \
      -XX:ArchiveClassesAtExit=minecraft_client.jsa \
      -jar client.jar || print_error "Client AppCDS generation failed"
    [[ -f minecraft_client.jsa ]] && print_success "Client AppCDS archive created"
  else
    print_info "client.jar not found - skipping client preparation"
  fi
  # System configuration
  print_header "Configuring system"
  # Firewall
  if has ufw; then
    sudo ufw allow 25565 &>/dev/null || print_error "Failed to configure firewall"
    print_success "Firewall configured (port 25565)"
  fi
  # File permissions
  if [[ -d minecraft ]]; then
    print_info "Setting ownership of minecraft directory..."
    sudo chown -R "${USER:-$(id -un)}" "${PWD}/minecraft" || :
  fi
  print_info "Setting executable permissions on scripts..."
  sudo chmod -R 755 ./*.sh &>/dev/null || chmod -R 755 ./*.sh &>/dev/null || :
  umask 077
  # Systemd
  if has systemctl; then
    sudo systemctl daemon-reload &>/dev/null || :
    print_success "Systemd configuration reloaded"
  fi
  # Enable linger for user systemd services
  if has loginctl; then
    loginctl enable-linger "$USER" &>/dev/null || :
    print_success "User linger enabled for systemd services"
  fi
  # Install screen if missing
  if ! has screen; then
    print_info "Installing screen..."
    if has pacman; then
      sudo pacman -Sq screen --needed --noconfirm &>/dev/null || :
    elif has apt-get; then
      sudo apt-get install -y screen &>/dev/null || :
    fi
    has screen && print_success "Screen installed"
  fi
  print_success "Server preparation complete!"
}
# ============================================================================
# LAZYMC FUNCTIONS
# ============================================================================
download_lazymc(){
  local arch version url target_file expected_checksum
  arch="$(detect_arch)"
  version="$1"
  print_header "Downloading lazymc v${version}"
  url="https://github.com/timvisee/lazymc/releases/download/v${version}/lazymc-v${version}-linux-${arch}"
  target_file="${INSTALL_DIR}/lazymc"
  expected_checksum=$(get_checksum_for_arch "lazymc" "$arch")
  mkdir -p "$INSTALL_DIR"
  if has aria2c; then
    aria2c -x 16 -s 16 -k 1M -d "$INSTALL_DIR" -o lazymc "$url"
  elif has curl; then
    curl -fsSL -o "$target_file" "$url"
  elif has wget; then
    wget -q -O "$target_file" "$url"
  else
    print_error "No download tool found (aria2c, curl, or wget required)"
    exit 1
  fi
  verify_checksum "$target_file" "$expected_checksum" || {
    print_error "Checksum verification failed - removing downloaded file"
    rm -f "$target_file"
    exit 1
  }
  chmod +x "$target_file"
  print_success "lazymc installed to ${target_file}"
}
generate_lazymc_config(){
  print_header "Generating lazymc configuration"
  mkdir -p "$CONFIG_DIR"
  cat >"$LAZYMC_CONFIG" <<'EOF'
# lazymc configuration https://github.com/timvisee/lazymc
[server]
directory = "."
command = "./tools/server-start.sh"

[public]
# address = "example.com:25565"

[join]
# Methods to use for waking the server (lobby, kick)
methods = ["lobby", "kick"]

[time]
sleep_after = 600
minimum_online_time = 60

[advanced]
# Port to listen on (must match Minecraft server port)
bind_address = "0.0.0.0:25565"
# Actual Minecraft server address when running
server_address = "127.0.0.1:25565"
# Logging verbosity (off, error, warn, info, debug, trace)
log_level = "warn"
EOF
  print_success "Configuration created at ${LAZYMC_CONFIG}"
  print_info "NOTE: You may need to adjust server port configuration"
  print_info "lazymc listens on 25565, server should run on 25566"
}
show_lazymc_usage(){
  print_header "lazymc Setup Complete!"
  printf '\n'
  print_info "Installation directory: ${INSTALL_DIR}"
  print_info "Configuration file: ${LAZYMC_CONFIG}"
  printf '\n'
  print_header "Quick Start:"
  printf '  Start lazymc:  ./tools/lazymc.sh start\n'
  printf '  Stop lazymc:   ./tools/lazymc.sh stop\n'
  printf '  View status:   ./tools/lazymc.sh status\n'
  printf '\n'
  print_header "Important Notes:"
  print_info "1. Update server.properties to use port 25566"
  print_info "2. lazymc will listen on port 25565 and proxy to the server"
  print_info "3. Server will auto-sleep after 600 seconds of inactivity"
  print_info "4. Edit ${LAZYMC_CONFIG} to customize settings"
  printf '\n'
}
install_lazymc(){
  download_lazymc "$LAZYMC_VERSION"
  generate_lazymc_config
  show_lazymc_usage
}
# ============================================================================
# HELP
# ============================================================================
show_help(){
  print_header "Minecraft Server Preparation Script"
  printf '\n'
  printf 'Usage: %s [command]\n' "$0"
  printf '\n'
  printf 'Commands:\n'
  printf '  server              Prepare server environment (default)\n'
  printf '  lazymc-install      Download and configure lazymc\n'
  printf '  lazymc-config       Generate lazymc configuration only\n'
  printf '  help                Show this help message\n'
  printf '\n'
  printf 'Environment Variables:\n'
  printf '  LAZYMC_VERSION      Version of lazymc to install (default: %s)\n' "$LAZYMC_VERSION"
  printf '  INSTALL_DIR         Installation directory (default: %s)\n' "$INSTALL_DIR"
  printf '  CONFIG_DIR          Configuration directory (default: %s)\n' "$CONFIG_DIR"
  printf '\n'
  printf 'Examples:\n'
  printf '  %s                  # Prepare server environment\n' "$0"
  printf '  %s server           # Prepare server environment\n' "$0"
  printf '  %s lazymc-install   # Install lazymc proxy\n' "$0"
  printf '  %s lazymc-config    # Generate lazymc config\n' "$0"
  printf '\n'
}
# ============================================================================
# MAIN
# ============================================================================
main(){
  local cmd="${1:-server}"
  case "$cmd" in
    server) prepare_server ;;
    lazymc-install | lazymc) install_lazymc ;;
    lazymc-config) generate_lazymc_config ;;
    help | --help | -h) show_help ;;
    *) print_error "Unknown command: $cmd"; printf '\n'; show_help; exit 1 ;;
  esac
}
main "$@"
