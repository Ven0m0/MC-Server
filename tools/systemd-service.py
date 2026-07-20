#!/usr/bin/env python3
"""Minecraft server systemd service management."""

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (
    SCRIPT_DIR,
    check_dependencies,
    check_root,
    detect_java,
    error,
    header,
    info,
    run_as_root,
    success,
)

SERVICE_NAME = "minecraft-server"
SERVICE_FILE = Path("/etc/systemd/system") / f"{SERVICE_NAME}.service"

SERVICE_TEMPLATE = """\
[Unit]
Description=Minecraft Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User={user}
WorkingDirectory={working_dir}
ExecStart={start_script}
ExecStop=/bin/kill -SIGTERM $MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Performance
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0
MemoryMax=90%
CPUQuota=95%

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={working_dir}

# Allow network access
PrivateNetwork=false

[Install]
WantedBy=multi-user.target
"""

INFRARUST_TEMPLATE = """\
[Unit]
Description=Infrarust Minecraft Proxy
After=network.target
Wants=network-online.target

[Service]
Type=simple
User={user}
WorkingDirectory={working_dir}
ExecStart={bin}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Performance
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0

[Install]
WantedBy=multi-user.target
"""


def _write_root_file(path: Path, content: str) -> None:
    run_as_root("tee", str(path), input=content, text=True, stdout=subprocess.DEVNULL)


def create_service(
    start_script: str = "", working_dir: str = "", run_user: str = ""
) -> None:
    import os

    start_script = start_script or str(SCRIPT_DIR / "tools" / "server-start.py")
    working_dir = working_dir or str(SCRIPT_DIR)
    run_user = run_user or os.environ.get("USER", "")

    if not check_root():
        return
    if not Path(start_script).is_file():
        error(f"Start script not found: {start_script}")
        return

    header("Creating systemd service")
    java_cmd = detect_java()
    info(f"User: {run_user}")
    info(f"Working directory: {working_dir}")
    info(f"Start script: {start_script}")
    info(f"Java: {java_cmd}")

    content = SERVICE_TEMPLATE.format(
        user=run_user, working_dir=working_dir, start_script=start_script
    )
    _write_root_file(SERVICE_FILE, content)
    run_as_root("systemctl", "daemon-reload")

    success(f"Service created: {SERVICE_NAME}")
    info(f"Enable with: sudo systemctl enable {SERVICE_NAME}")
    info(f"Start with: sudo systemctl start {SERVICE_NAME}")


def create_infrarust_service(
    infrarust_dir: str = "/opt/infrarust", run_user: str = "minecraft"
) -> None:
    if not check_root():
        return

    header("Setting up Infrarust Minecraft Proxy")

    if not shutil.which("infrarust"):
        info("Installing infrarust via cargo...")
        if not check_dependencies("cargo"):
            return
        try:
            subprocess.run(["cargo", "install", "--locked", "infrarust"], check=True)
        except subprocess.CalledProcessError:
            error("Failed to install infrarust")
            return
        success("Infrarust installed successfully")
    else:
        info("Infrarust already installed")

    run_as_root("mkdir", "-p", infrarust_dir)
    try:
        run_as_root("chown", f"{run_user}:{run_user}", infrarust_dir)
    except subprocess.CalledProcessError:
        pass

    infrarust_bin = shutil.which("infrarust") or "/usr/local/bin/infrarust"

    info("Creating infrarust systemd service...")
    info(f"User: {run_user}")
    info(f"Working directory: {infrarust_dir}")
    info(f"Binary: {infrarust_bin}")

    content = INFRARUST_TEMPLATE.format(
        user=run_user, working_dir=infrarust_dir, bin=infrarust_bin
    )
    infrarust_service = Path("/etc/systemd/system/infrarust.service")
    _write_root_file(infrarust_service, content)
    run_as_root("systemctl", "daemon-reload")

    success("Infrarust service created")
    info("Enable with: sudo systemctl enable infrarust")
    info("Start with: sudo systemctl start infrarust")
    info("Check status with: sudo systemctl status infrarust")


def remove_service() -> None:
    if not check_root():
        return
    header("Removing systemd service")

    if (
        subprocess.run(["systemctl", "is-active", "--quiet", SERVICE_NAME]).returncode
        == 0
    ):
        info("Stopping service...")
        run_as_root("systemctl", "stop", SERVICE_NAME)

    if (
        subprocess.run(
            ["systemctl", "is-enabled", "--quiet", SERVICE_NAME], capture_output=True
        ).returncode
        == 0
    ):
        info("Disabling service...")
        run_as_root("systemctl", "disable", SERVICE_NAME)

    if SERVICE_FILE.is_file():
        run_as_root("rm", "-f", str(SERVICE_FILE))

    run_as_root("systemctl", "daemon-reload")
    success("Service removed")


def enable_service() -> None:
    if not check_root():
        return
    if not SERVICE_FILE.is_file():
        error(f"Service not found. Create it first with: {sys.argv[0]} create")
        return
    info(f"Enabling {SERVICE_NAME}...")
    run_as_root("systemctl", "enable", SERVICE_NAME)
    success("Service enabled (will start on boot)")


def start_service() -> None:
    if not check_root():
        return
    if not SERVICE_FILE.is_file():
        error(f"Service not found. Create it first with: {sys.argv[0]} create")
        return
    info(f"Starting {SERVICE_NAME}...")
    run_as_root("systemctl", "start", SERVICE_NAME)
    success("Service started")


def stop_service() -> None:
    if not check_root():
        return
    info(f"Stopping {SERVICE_NAME}...")
    run_as_root("systemctl", "stop", SERVICE_NAME)
    success("Service stopped")


def show_status() -> None:
    if not SERVICE_FILE.is_file():
        info("Service not installed")
        return
    subprocess.run(["systemctl", "status", SERVICE_NAME, "--no-pager"])


def show_logs(lines: int = 50) -> None:
    if not SERVICE_FILE.is_file():
        error("Service not found")
        return
    subprocess.run(["journalctl", "-u", SERVICE_NAME, "-n", str(lines), "--no-pager"])


def follow_logs() -> None:
    if not SERVICE_FILE.is_file():
        error("Service not found")
        return
    subprocess.run(["journalctl", "-u", SERVICE_NAME, "-f"])


def show_usage() -> None:
    print(f"""\
Minecraft Server Systemd Service Management

USAGE:
    {sys.argv[0]} <COMMAND> [OPTIONS]

COMMANDS:
    create [script] [dir] [user]   Create systemd service
    create-infrarust [dir] [user]  Create Infrarust proxy service
    remove                         Remove systemd service
    enable                         Enable service (auto-start on boot)
    start                          Start service
    stop                           Stop service
    restart                        Restart service
    status                         Show service status
    logs [lines]                   Show logs (default: 50 lines)
    follow                         Follow logs in real-time
    help                           Show this help

EXAMPLES:
    {sys.argv[0]} create
    {sys.argv[0]} create ./tools/server-start.py /opt/minecraft minecraft
    {sys.argv[0]} create-infrarust /opt/infrarust minecraft
    {sys.argv[0]} enable
    {sys.argv[0]} start
    {sys.argv[0]} status
    {sys.argv[0]} logs 100
    {sys.argv[0]} follow

NOTES:
    - Requires root/sudo access
    - Service name: {SERVICE_NAME}
    - Service file: {SERVICE_FILE}
    - Logs via journalctl
    - create-infrarust also installs infrarust via cargo if needed
""")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Systemd service management", add_help=False
    )
    parser.add_argument("command", nargs="?", default="help")
    parser.add_argument("args", nargs="*")
    ns = parser.parse_args()
    a = ns.args

    match ns.command:
        case "create":
            create_service(*(a + [""] * (3 - len(a)))[:3])
        case "create-infrarust":
            kwargs = {}
            if len(a) > 0:
                kwargs["infrarust_dir"] = a[0]
            if len(a) > 1:
                kwargs["run_user"] = a[1]
            create_infrarust_service(**kwargs)
        case "remove":
            remove_service()
        case "enable":
            enable_service()
        case "start":
            start_service()
        case "stop":
            stop_service()
        case "restart":
            stop_service()
            time.sleep(2)
            start_service()
        case "status":
            show_status()
        case "logs":
            show_logs(int(a[0]) if a else 50)
        case "follow":
            follow_logs()
        case "help" | "--help" | "-h":
            show_usage()
        case _:
            error(f"Unknown command: {ns.command}")
            show_usage()
            sys.exit(1)


if __name__ == "__main__":
    main()
