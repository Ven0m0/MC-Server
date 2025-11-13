#!/usr/bin/env bash

rustup update
# From source
#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#git clone https://github.com/shadowner/infrarust
#cd infrarust
#cargo build --release

# Or via cargo
cargo install infrarust

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

sudo systemctl enable infrarust
sudo systemctl start infrarust
