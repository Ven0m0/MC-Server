#!/usr/bin/env bash
# lazymc-setup.sh: Install and configure lazymc for automatic server sleep
set -euo pipefail

# Output formatting helpers
print_header() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_error() { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_info() { printf '\033[1;33m→\033[0m %s\n' "$1"; }

# Check if command exists
has_command() { command -v "$1" &>/dev/null; }

# Configuration
LAZYMC_VERSION="${LAZYMC_VERSION:-0.2.11}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$(pwd)/config}"
LAZYMC_CONFIG="${CONFIG_DIR}/lazymc.toml"

# Detect architecture
detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l) echo "armv7" ;;
    *) print_error "Unsupported architecture: $arch"; exit 1 ;;
  esac
}

# Download lazymc binary
download_lazymc() {
  local arch version url target_file
  arch="$(detect_arch)"
  version="$1"

  print_header "Downloading lazymc v${version}"

  # Construct download URL for Linux
  url="https://github.com/timvisee/lazymc/releases/download/v${version}/lazymc-v${version}-linux-${arch}"
  target_file="${INSTALL_DIR}/lazymc"

  # Create install directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"

  # Download using available tool
  if has_command aria2c; then
    aria2c -x 16 -s 16 -k 1M -d "$INSTALL_DIR" -o lazymc "$url"
  elif has_command curl; then
    curl -fsSL -o "$target_file" "$url"
  elif has_command wget; then
    wget -q -O "$target_file" "$url"
  else
    print_error "No download tool found (aria2c, curl, or wget required)"
    exit 1
  fi

  # Make executable
  chmod +x "$target_file"
  print_success "lazymc installed to ${target_file}"
}

# Generate lazymc configuration
generate_config() {
  print_header "Generating lazymc configuration"

  mkdir -p "$CONFIG_DIR"

  cat > "$LAZYMC_CONFIG" << 'EOF'
# lazymc configuration
# https://github.com/timvisee/lazymc

[server]
# Directory containing the Minecraft server
directory = "."

# Command to start the Minecraft server
command = "./scripts/server-start.sh"

[public]
# Public address for server status queries (optional)
# address = "example.com:25565"

[join]
# Methods to use for waking the server (lobby, kick)
methods = ["lobby", "kick"]

[time]
# Time in seconds before server sleeps when empty
sleep_after = 600

# Minimum uptime in seconds before server can sleep
minimum_online_time = 60

[advanced]
# Port to listen on (must match Minecraft server port)
# Lazymc will proxy connections on this port
bind_address = "0.0.0.0:25565"

# Actual Minecraft server address when running
# Set to different port if needed
server_address = "127.0.0.1:25566"

# Logging verbosity (off, error, warn, info, debug, trace)
log_level = "info"
EOF

  print_success "Configuration created at ${LAZYMC_CONFIG}"
  print_info "NOTE: You may need to adjust server port configuration"
  print_info "lazymc listens on 25565, server should run on 25566"
}

# Show usage instructions
show_usage() {
  print_header "lazymc Setup Complete!"
  printf '\n'
  print_info "Installation directory: ${INSTALL_DIR}"
  print_info "Configuration file: ${LAZYMC_CONFIG}"
  printf '\n'
  print_header "Quick Start:"
  printf '  Start lazymc:  lazymc start --config %s\n' "$LAZYMC_CONFIG"
  printf '  Stop lazymc:   lazymc stop --config %s\n' "$LAZYMC_CONFIG"
  printf '  View status:   lazymc status --config %s\n' "$LAZYMC_CONFIG"
  printf '\n'
  print_header "Important Notes:"
  print_info "1. Update server.properties to use port 25566"
  print_info "2. lazymc will listen on port 25565 and proxy to the server"
  print_info "3. Server will auto-sleep after 600 seconds of inactivity"
  print_info "4. Edit ${LAZYMC_CONFIG} to customize settings"
  printf '\n'
}

# Main installation flow
main() {
  local cmd="${1:-install}"

  case "$cmd" in
    install)
      download_lazymc "$LAZYMC_VERSION"
      generate_config
      show_usage
      ;;
    config)
      generate_config
      ;;
    help|--help|-h)
      print_header "lazymc Setup Script"
      printf '\n'
      printf 'Usage: %s [command]\n' "$0"
      printf '\n'
      printf 'Commands:\n'
      printf '  install    Download lazymc and generate config (default)\n'
      printf '  config     Generate configuration only\n'
      printf '  help       Show this help message\n'
      printf '\n'
      printf 'Environment Variables:\n'
      printf '  LAZYMC_VERSION  Version to install (default: %s)\n' "$LAZYMC_VERSION"
      printf '  INSTALL_DIR     Installation directory (default: %s)\n' "$INSTALL_DIR"
      printf '  CONFIG_DIR      Configuration directory (default: %s)\n' "$CONFIG_DIR"
      ;;
    *)
      print_error "Unknown command: $cmd"
      print_info "Run '$0 help' for usage"
      exit 1
      ;;
  esac
}

main "$@"
