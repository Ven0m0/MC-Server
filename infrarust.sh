#!/bin/bash

rustup update
# From source
#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#git clone https://github.com/shadowner/infrarust
#cd infrarust
#cargo build --release

# Or via cargo
cargo install infrarust

sudo mkdir -p /etc/systemd/system
sudo touch /etc/systemd/system/infrarust.service

echo '
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
' | sudo tee /etc/systemd/system/infrarust.service


sudo systemctl enable infrarust
sudo systemctl start infrarust
