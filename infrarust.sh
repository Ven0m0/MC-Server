#!/usr/bin/env bash
# infrarust.sh: Install and configure Infrarust Minecraft proxy service

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

init_strict_mode

print_header "Setting up Infrarust Minecraft Proxy"

# Check and install infrarust if needed
if ! has_command infrarust; then
    print_info "Installing infrarust via cargo..."
    check_dependencies cargo || exit 1
    cargo install --locked infrarust || {
        print_error "Failed to install infrarust"
        exit 1
    }
    print_success "Infrarust installed successfully"
else
    print_info "Infrarust already installed"
fi

# Create systemd service directory and file
print_info "Creating systemd service..."
sudo mkdir -p /etc/systemd/system
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

print_success "Systemd service file created"

# Enable and start the service
print_info "Enabling and starting infrarust service..."
if sudo systemctl enable --now infrarust; then
    print_success "Infrarust service enabled and started"
    print_info "Check status with: sudo systemctl status infrarust"
else
    print_error "Failed to enable/start infrarust service"
    exit 1
fi
