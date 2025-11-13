#!/usr/bin/env bash

command -v infrarust &>/dev/null || cargo install --locked infrarust

# Create systemd service directory and file in one operation
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

sudo systemctl enable --now infrarust
