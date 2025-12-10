# 🔧 Troubleshooting Guide

Common issues and solutions for Minecraft server management.

## Table of Contents

- [Server Won't Start](#server-wont-start)
- [Performance Issues](#performance-issues)
- [Connection Issues](#connection-issues)
- [Crash Issues](#crash-issues)
- [Backup & Recovery](#backup--recovery)
- [Mod Issues](#mod-issues)
- [Tool Issues](#tool-issues)

## Server Won't Start

### Issue: EULA not accepted

**Error Message:**

```text
You need to agree to the EULA in order to run the server
```

**Solution:**

```bash
# Run prepare script
./tools/prepare.sh

# Or manually
echo "eula=true" > eula.txt
```

### Issue: Port already in use

**Error Message:**

```
Failed to bind to port 25565
```

**Solution:**

```bash
# Check what's using the port
sudo lsof -i :25565
sudo netstat -tulpn | grep 25565

# Kill the process
sudo kill -9 <PID>

# Or change port in server.properties
nano server.properties
# Change: server-port=25566
```

### Issue: Out of memory

**Error Message:**

```
java.lang.OutOfMemoryError: Java heap space
```

**Solution:**

```bash
# Check available RAM
free -h

# Edit server start script to allocate more RAM
# The script auto-calculates, but you can override:
export MIN_RAM="4G"
export MAX_RAM="8G"
./tools/server-start.sh
```

### Issue: Java version mismatch

**Error Message:**

```
Unsupported class file major version
```

**Solution:**

```bash
# Check Java version (needs 21+)
java -version

# Install correct version
sudo apt update
sudo apt install -y openjdk-21-jdk

# Set default Java version
sudo update-alternatives --config java
```

### Issue: Missing fabric-server-launch.jar

**Error Message:**

```
Error: Unable to access jarfile fabric-server-launch.jar
```

**Solution:**

```bash
# Re-download Fabric server
./tools/mod-updates.sh install-fabric

# Or manually download
wget https://meta.fabricmc.net/v2/versions/loader/1.21.5/0.16.2/1.0.1/server/jar -O fabric-server-launch.jar
```

## Performance Issues

### Issue: Server lag / Low TPS

**Symptoms:**

- TPS below 20
- Player movement lag
- Block break/place delay

**Diagnosis:**

```bash
# Check server status
./tools/monitor.sh status

# Check for errors
./tools/monitor.sh errors

# View performance metrics
tail -f logs/latest.log | grep -i "tps\|mspt"
```

**Solutions:**

1. **Check system resources:**

```bash
# CPU usage
top -p $(pgrep -f fabric-server-launch)

# Memory usage
./tools/monitor.sh status

# Disk I/O
iotop -o
```

1. **Reduce view distance:**

```properties
# In server.properties
view-distance=8
simulation-distance=6
```

1. **Optimize ServerCore settings:**

```yaml
# In config/servercore/config.yml
dynamic:
  enabled: true
  target_mspt: 40 # Lower for better performance
```

1. **Clear entities:**

```
# In server console
/kill @e[type=!player]
```

1. **Pre-generate chunks:**

```
# Install Chunky mod, then in console
/chunky radius 5000
/chunky start
```

### Issue: High memory usage

**Solution:**

```bash
# Adjust GC settings in tools/server-start.sh
# Add these flags:
-XX:+UseG1GC \
-XX:MaxGCPauseMillis=200 \
-XX:G1HeapRegionSize=32M \
-XX:G1ReservePercent=20
```

### Issue: CPU at 100%

**Diagnosis:**

```bash
# Check what's causing high CPU
top
# Press 'P' to sort by CPU

# Check server threads
jstack $(pgrep -f fabric-server-launch) > threads.txt
```

**Solutions:**

1. Reduce mob spawning in ServerCore config
2. Limit redstone contraptions
3. Use optimization mods (Lithium, Krypton)
4. Reduce number of loaded chunks

## Connection Issues

### Issue: Can't connect to server

**Diagnosis:**

```bash
# Check if server is running
./tools/monitor.sh status

# Check if port is open
nc -zv localhost 25565

# Check from another machine
nc -zv <server-ip> 25565
```

**Solutions:**

1. **Check firewall:**

```bash
# UFW
sudo ufw allow 25565/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 25565 -j ACCEPT
```

1. **Check server binding:**

```properties
# In server.properties
server-ip=0.0.0.0  # Listen on all interfaces
```

1. **Verify online mode:**

```properties
# In server.properties
online-mode=true  # Set to false only for offline/LAN
```

### Issue: Bedrock players can't connect

**Diagnosis:**

```bash
# Check Geyser status
tail -f logs/latest.log | grep -i geyser

# Verify Geyser port
nc -zvu localhost 19132
```

**Solutions:**

1. **Open Bedrock port:**

```bash
sudo ufw allow 19132/udp
```

1. **Check Geyser config:**

```yaml
# In config/Geyser-Fabric/config.yml
bedrock:
  port: 19132
  address: 0.0.0.0
```

1. **Verify Floodgate:**

```yaml
# In config/floodgate/config.yml
enabled: true
```

### Issue: Connection timeout

**Solutions:**

1. **Increase timeout settings:**

```properties
# In server.properties
network-compression-threshold=256
max-tick-time=60000
```

1. **Check network:**

```bash
# Test ping
ping <server-ip>

# Test route
traceroute <server-ip>
```

## Crash Issues

### Issue: Server crashes randomly

**Diagnosis:**

```bash
# Check crash reports
ls -lt crash-reports/ | head -5
cat crash-reports/crash-*.txt

# Check for out of memory
grep -i "OutOfMemoryError" logs/latest.log

# Check for thread dumps
ls -lt | grep ".dump"
```

**Solutions:**

1. **Enable watchdog:**

```bash
# Start watchdog service
./tools/watchdog.sh monitor
```

1. **Increase memory:**

```bash
# Edit server start script or export:
export MAX_RAM="8G"
```

1. **Update mods:**

```bash
./tools/mod-updates.sh upgrade
```

1. **Check mod compatibility:**

```bash
# Remove mods one by one to identify culprit
mv mods/suspicious-mod.jar mods-disabled/
```

### Issue: Server won't restart after crash

**Solution:**

```bash
# Check if process is stuck
ps aux | grep fabric-server-launch

# Force kill
pkill -9 -f fabric-server-launch

# Clean up and restart
./tools/watchdog.sh start
```

### Issue: World corruption

**Symptoms:**

- Chunks not loading
- "Saving chunks" stuck
- Error messages about region files

**Solution:**

```bash
# Restore from backup
./tools/backup.sh list
./tools/backup.sh restore backups/worlds/world_20250119_120000.tar.gz

# Or use Minecraft tools to repair
# Install MCC Tools and scan for errors
```

## Backup & Recovery

### Issue: Backup failed

**Diagnosis:**

```bash
# Check disk space
df -h

# Check permissions
ls -la backups/

# Test backup manually
./tools/backup.sh backup world
```

**Solutions:**

1. **Free up disk space:**

```bash
# Clean old logs
./tools/logrotate.sh clean 7

# Clean old backups
./tools/backup.sh cleanup --max-backups 5
```

1. **Fix permissions:**

```bash
chmod -R u+w backups/
```

### Issue: Restore failed

**Solution:**

```bash
# Verify backup integrity
tar -tzf backups/worlds/world_20250119_120000.tar.gz

# Stop server first
./tools/watchdog.sh stop

# Remove old world
mv world world.old

# Extract backup
tar -xzf backups/worlds/world_20250119_120000.tar.gz

# Start server
./tools/watchdog.sh start
```

## Mod Issues

### Issue: Mod dependency missing

**Error Message:**

```
Mod X requires mod Y version Z
```

**Solution:**

```bash
# Check mod dependencies
./tools/mod-updates.sh list

# Add missing dependency
./tools/mod-updates.sh add modrinth <mod-slug>

# Download
./tools/mod-updates.sh upgrade
```

### Issue: Mod version incompatible

**Error Message:**

```
Incompatible mod set!
```

**Solution:**

```bash
# Remove incompatible mod
rm mods/incompatible-mod.jar

# Or update to compatible version
./tools/mod-updates.sh upgrade
```

### Issue: Mod conflicts

**Symptoms:**

- Server crash on startup
- Mixins failing
- Class conflicts

**Solution:**

```bash
# Binary search for conflicting mod
# 1. Disable half of mods
mkdir mods-test
mv mods/*.jar mods-test/

# 2. Enable half
mv mods-test/mod1.jar mods-test/mod2.jar ... mods/

# 3. Test
./tools/server-start.sh

# 4. Repeat until found
```

## Tool Issues

### Issue: Monitor script shows "Server not running" but it is

**Solution:**

```bash
# Update PID file
pgrep -f fabric-server-launch > .server.pid

# Or restart monitoring
./tools/monitor.sh status
```

### Issue: Backup script can't send server commands

**Solution:**

```bash
# Start server in screen/tmux
screen -dmS minecraft ./tools/server-start.sh

# Or in tmux
tmux new-session -d -s minecraft ./tools/server-start.sh
```

### Issue: Watchdog not restarting server

**Diagnosis:**

```bash
# Check watchdog log
tail -f logs/watchdog.log

# Check restart attempts
grep "restart" logs/watchdog.log
```

**Solution:**

```bash
# Increase max attempts
./tools/watchdog.sh monitor --max-attempts 5

# Decrease cooldown
./tools/watchdog.sh monitor --cooldown 120

# Check start script path in watchdog.sh
# Ensure SERVER_START_SCRIPT path is correct
```

### Issue: Log rotation not working

**Solution:**

```bash
# Check permissions
ls -la logs/

# Fix permissions
chmod u+w logs/
chmod u+w logs/archive/

# Test manually
./tools/logrotate.sh rotate
```

## Getting More Help

### Collect Diagnostic Information

```bash
# Create diagnostic report
{
    echo "=== System Info ==="
    uname -a
    cat /etc/os-release
    echo ""

    echo "=== Java Version ==="
    java -version
    echo ""

    echo "=== Server Status ==="
    ./tools/monitor.sh status
    echo ""

    echo "=== Disk Usage ==="
    df -h
    echo ""

    echo "=== Memory Usage ==="
    free -h
    echo ""

    echo "=== Recent Errors ==="
    tail -100 logs/latest.log | grep -i error
    echo ""

    echo "=== Crash Reports ==="
    ls -lt crash-reports/ | head -3

} > diagnostic-report.txt
```

### Enable Debug Logging

```properties
# In server.properties
debug=true

# Or with JVM flag
java -Dfabric.log.level=debug -jar fabric-server-launch.jar
```

### Useful Commands

```bash
# Check all running Java processes
ps aux | grep java

# Monitor logs in real-time
tail -f logs/latest.log

# Search for specific error
grep -r "error message" logs/

# Check network connections
ss -tulpn | grep java

# Monitor system resources
htop

# Check disk I/O
iotop -o
```

## Additional Resources

- [Fabric Documentation](https://fabricmc.net/wiki/)
- [Server Optimization Guide](https://github.com/YouHaveTrouble/minecraft-optimization)
- [Geyser Wiki](https://wiki.geysermc.org/)
- [ServerCore Documentation](https://github.com/Wesley1808/ServerCore)

## Still Having Issues?

1. Check the server logs: `logs/latest.log`
2. Check crash reports: `crash-reports/`
3. Search existing issues in the repository
4. Create a new issue with:
  - Description of the problem
  - Steps to reproduce
  - Server logs
  - System information
  - Diagnostic report

```
```
