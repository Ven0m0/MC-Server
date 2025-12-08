#!/usr/bin/env bash
# infrarust.sh: Install and configure Infrarust Minecraft proxy service
set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'; export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"; export HOME="/home/${user}"; SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"
has_command(){ command -v "$1" &>/dev/null; }
check_dependencies(){ local missing=(); for cmd in "$@"; do has_command "$cmd" || missing+=("$cmd"); done; ((${#missing[@]})) && { printf 'Error: Missing required dependencies: %s\n' "${missing[*]}" >&2; printf 'Please install them before continuing.\n' >&2; return 1; }; }
print_header(){ printf '\033[0;34m==>\033[0m %s\n' "$1"; }; print_success(){ printf '\033[0;32m✓\033[0m %s\n' "$1"; }; print_error(){ printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }; print_info(){ printf '\033[1;33m→\033[0m %s\n' "$1"; }
print_header "Setting up Infrarust Minecraft Proxy"
if ! has_command infrarust; then print_info "Installing infrarust via cargo..."; check_dependencies cargo || exit 1; cargo install --locked infrarust || { print_error "Failed to install infrarust"; exit 1; }; print_success "Infrarust installed successfully"; else print_info "Infrarust already installed"; fi
print_info "Creating systemd service..."; sudo mkdir -p /etc/systemd/system
sudo tee /etc/systemd/system/infrarust.service >/dev/null <<'EOF'
# /etc/systemd/system/infrarust.service
[Unit]
Description=Infrarust Minecraft Proxy
After=network.target

[Service]
Type=simple
User=minecraft
ExecStart=/usr/local/bin/infrarust
WorkingDirectory=/opt/infrarust
Restart=always

[Install]
WantedBy=multi-user.target
EOF
print_success "Systemd service file created"; print_info "Enabling and starting infrarust service..."
if sudo systemctl enable --now infrarust; then print_success "Infrarust service enabled and started"; print_info "Check status with: sudo systemctl status infrarust"; else print_error "Failed to enable/start infrarust service"; exit 1; fi
