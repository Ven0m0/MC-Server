# Bash

```bash
echo "Taking ownership of all server files/folders in dirname/minecraft..."
sudo chown -R userxname dirname/minecraft
sudo chmod -R 755 dirname/minecraft/*.sh
```


### Service

```markdown
[Unit]
Description=Minecraft Server Service
After=network-online.target

[Service]
User=userxname
WorkingDirectory=dirname/minecraft
Type=forking
ExecStart=/bin/bash dirname/minecraft/start.sh
ExecStop=/bin/bash dirname/minecraft/stop.sh
GuessMainPID=no
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
```
