#!/usr/bin/env python3
"""Minecraft server monitor."""

import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (
    SCRIPT_DIR,
    header,
    success,
    error,
    is_server_running,
    get_server_pid,
)

LOG_FILE = SCRIPT_DIR / "logs" / "latest.log"
SERVER_PORT = 25565
CHECK_INTERVAL = 60


def port_open():
    try:
        socket.create_connection(("localhost", SERVER_PORT), timeout=1).close()
        return True
    except OSError:
        return False


def get_status():
    header("Server Status")
    print(f"  Process: {'Running' if is_server_running() else 'Not Running'}")
    print(f"  Port {SERVER_PORT}: {'Listening' if port_open() else 'Not Listening'}")
    print()


def get_memory(pid=None):
    pid = pid or get_server_pid()
    if not pid:
        print("Server not running\n")
        return
    header("Memory Usage")
    r = subprocess.run(
        ["ps", "-p", str(pid), "-o", "rss="], capture_output=True, text=True
    )
    mem_mb = int(r.stdout.strip() or 0) // 1024
    print(f"  PID: {pid}")
    print(f"  Memory: {mem_mb} MB\n")


def get_disk():
    header("Disk Usage")
    dirs = [(SCRIPT_DIR / n, n.title()) for n in ("world", "backups", "logs")]
    paths = [str(d) for d, _ in dirs if d.exists()]
    if paths:
        r = subprocess.run(["du", "-sh"] + paths, capture_output=True, text=True)
        sizes = {
            line.split("\t")[1].strip(): line.split("\t")[0]
            for line in r.stdout.splitlines()
            if "\t" in line
        }
        for d, label in dirs:
            if str(d) in sizes:
                print(f"  {label}: {sizes[str(d)]}")
    r = subprocess.run(["du", "-sh", str(SCRIPT_DIR)], capture_output=True, text=True)
    print(f"  Total: {r.stdout.split()[0] if r.returncode == 0 else '?'}\n")


def get_players():
    header("Recent Player Activity")
    try:
        lines = LOG_FILE.read_text(errors="replace").splitlines()
        matches = [
            ln for ln in lines if "joined the game" in ln or "left the game" in ln
        ]
        print("\n".join(matches[-5:]) if matches else "No recent activity")
    except OSError:
        print("Log file not found")
    print()


def check_errors():
    header("Recent Errors")
    try:
        lines = LOG_FILE.read_text(errors="replace").splitlines()[-100:]
    except OSError:
        print("Log file not found\n")
        return
    errs = [ln for ln in lines if "ERROR" in ln or "SEVERE" in ln]
    warns = [ln for ln in lines if "WARN" in ln]
    print(f"  Errors in last 100 lines: {len(errs)}")
    print(f"  Warnings in last 100 lines: {len(warns)}")
    if errs:
        print("\n  Last 3 errors:")
        for ln in errs[-3:]:
            print(f"    {ln}")
    print()


def get_uptime(pid=None):
    pid = pid or get_server_pid()
    if not pid:
        print("Server not running\n")
        return
    header("Server Uptime")
    r = subprocess.run(
        ["ps", "-p", str(pid), "-o", "etimes="], capture_output=True, text=True
    )
    secs = int(r.stdout.strip() or 0)
    print(f"  {secs // 86400}d {(secs % 86400) // 3600}h {(secs % 3600) // 60}m\n")


def show_status():
    print()
    print("=" * 56)
    print(f"      Minecraft Server Monitor - {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 56 + "\n")
    get_status()
    pid = get_server_pid()
    get_uptime(pid)
    get_memory(pid)
    get_disk()
    get_players()
    check_errors()
    print("=" * 56)


def alert_mode():
    issues = 0
    if not is_server_running():
        error("Process not running")
        issues += 1
    if not port_open():
        error("Port not listening")
        issues += 1
    try:
        lines = LOG_FILE.read_text(errors="replace").splitlines()[-20:]
        errs = sum(1 for ln in lines if "ERROR" in ln or "SEVERE" in ln)
        if errs > 5:
            error(f"High error rate: {errs} errors")
            issues += 1
    except OSError:
        pass
    du = shutil.disk_usage(str(SCRIPT_DIR))
    if du.used / du.total > 0.9:
        error(f"Disk usage critical: {du.used / du.total:.0%}")
        issues += 1
    if issues == 0:
        success("All checks passed")
        return 0
    error(f"Health check failed: {issues} issue(s)")
    return 1


USAGE = """\
Minecraft Server Monitor
Usage: monitor.py [status|watch|alert|players|errors|help]"""

cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "status":
    show_status()
elif cmd == "watch":
    print(f"Starting monitor (Ctrl+C to stop)\nUpdate interval: {CHECK_INTERVAL}s\n")
    while True:
        subprocess.run(["clear"])
        show_status()
        time.sleep(CHECK_INTERVAL)
elif cmd == "alert":
    sys.exit(alert_mode())
elif cmd == "players":
    get_players()
elif cmd == "errors":
    check_errors()
elif cmd in ("help", "--help", "-h"):
    print(USAGE)
else:
    error(f"Unknown command: {cmd}")
    print(USAGE)
    sys.exit(1)
