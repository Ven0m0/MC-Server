#!/usr/bin/env python3
"""Minecraft server watchdog."""

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import SCRIPT_DIR, check_server_port, is_server_running

SERVER_START_SCRIPT = SCRIPT_DIR / "tools" / "server-start.py"
CHECK_INTERVAL = 30
MAX_RESTART_ATTEMPTS = 3
RESTART_COOLDOWN = 300
LOG_FILE = SCRIPT_DIR / "logs" / "watchdog.log"
SERVER_PORT = 25565

restart_count = 0
last_restart_time = 0.0


def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line)
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def check_health() -> bool:
    if not is_server_running():
        log("Process not running.")
        return False
    log_file = SCRIPT_DIR / "logs" / "latest.log"
    if log_file.is_file():
        idle = time.time() - log_file.stat().st_mtime
        if idle > 300 and not check_server_port(SERVER_PORT):
            log(f"Stalled: No log activity for {int(idle)}s and port unreachable.")
            return False
    return True


def can_restart() -> bool:
    global last_restart_time, restart_count
    now = time.time()
    if (
        now - last_restart_time < RESTART_COOLDOWN
        and restart_count >= MAX_RESTART_ATTEMPTS
    ):
        log("Too many restarts, waiting for cooldown...")
        return False
    last_restart_time = now
    restart_count += 1
    return True


def start_server() -> bool:
    if not SERVER_START_SCRIPT.is_file():
        log(f"Server start script not found: {SERVER_START_SCRIPT}")
        return False
    log("Starting server...")
    subprocess.Popen([sys.executable, str(SERVER_START_SCRIPT)])
    time.sleep(5)
    return True


def stop_server() -> bool:
    log("Stopping server...")
    for pattern in ("fabric-server-launch.jar", "server.jar"):
        subprocess.run(["pkill", "-f", pattern], capture_output=True)
    time.sleep(2)
    return True


def restart_server() -> bool:
    global restart_count
    log("Restarting server...")
    if not can_restart():
        return False
    if is_server_running():
        stop_server()
    return start_server()


def monitor_mode() -> None:
    global restart_count, last_restart_time
    log(
        f"Watchdog started (interval: {CHECK_INTERVAL}s, max attempts: {MAX_RESTART_ATTEMPTS})"
    )
    while True:
        if not check_health():
            log("Health check failed - restarting")
            if restart_server():
                log("Restart successful")
                time.sleep(RESTART_COOLDOWN)
                restart_count = 0
            else:
                log("Restart failed")
                if restart_count >= MAX_RESTART_ATTEMPTS:
                    log("Waiting 30 minutes before retry...")
                    time.sleep(1800)
                    restart_count = 0
                    last_restart_time = 0
        time.sleep(CHECK_INTERVAL)


def show_usage() -> None:
    print(f"""\
Minecraft Server Watchdog

Usage: {sys.argv[0]} [command]

Commands:
    monitor     Start watchdog (auto-restart on crash)
    restart     Restart server immediately
    start       Start server
    stop        Stop server
    status      Check if running
    help        Show this help

Examples:
    {sys.argv[0]} monitor      # Start watchdog
    {sys.argv[0]} restart      # Restart now
    {sys.argv[0]} status       # Check status
""")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Minecraft server watchdog", add_help=False
    )
    parser.add_argument("command", nargs="?", default="help")
    ns = parser.parse_args()

    match ns.command:
        case "monitor":
            monitor_mode()
        case "restart":
            restart_server()
        case "start":
            start_server()
        case "stop":
            stop_server()
        case "status":
            if is_server_running():
                log("Server is running")
            else:
                log("Server is not running")
                sys.exit(1)
        case "help" | "--help" | "-h":
            show_usage()
        case _:
            log(f"Unknown command: {ns.command}")
            show_usage()
            sys.exit(1)


if __name__ == "__main__":
    main()
