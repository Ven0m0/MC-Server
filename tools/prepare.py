#!/usr/bin/env python3
"""Prepare Minecraft server environment and optional components."""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (
    SCRIPT_DIR,
    detect_arch,
    download_file,
    error,
    get_client_xmx_gb,
    get_minecraft_memory_gb,
    header,
    info,
    success,
    total_ram_gb,
    verify_checksum,
)

sys.path.insert(0, str(SCRIPT_DIR / "minecraft" / "config"))
from versions import LAZYMC_VERSION, get_checksum_for_arch

INSTALL_DIR = Path(os.environ.get("INSTALL_DIR", Path.home() / ".local" / "bin"))
CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", SCRIPT_DIR / "minecraft" / "config"))
LAZYMC_CONFIG = CONFIG_DIR / "lazymc.toml"

LAZYMC_CONFIG_TEMPLATE = """\
# lazymc configuration https://github.com/timvisee/lazymc
[server]
directory = "."
command = "./tools/server-start.py"

[public]
# address = "example.com:25565"

[join]
# Methods to use for waking the server (lobby, kick)
methods = ["lobby", "kick"]

[time]
sleep_after = 600
minimum_online_time = 60

[advanced]
# Port to listen on (must match Minecraft server port)
bind_address = "0.0.0.0:25565"
# Actual Minecraft server address when running
server_address = "127.0.0.1:25565"
# Logging verbosity (off, error, warn, info, debug, trace)
log_level = "warn"
"""


def _run_quiet(cmd: list[str]) -> bool:
    return subprocess.run(cmd, capture_output=True).returncode == 0


def prepare_server() -> None:
    header("Minecraft Environment Preparation")
    server_heap = get_minecraft_memory_gb(2)
    client_heap = get_client_xmx_gb()
    info(
        f"Total RAM: {total_ram_gb()}G | Server heap: {server_heap}G | Client heap: {client_heap}G"
    )

    if Path("server.jar").is_file():
        info("Generating AppCDS archive for server...")
        r = subprocess.run(
            [
                "java",
                f"-Xms{server_heap}G",
                f"-Xmx{server_heap}G",
                "-XX:ArchiveClassesAtExit=minecraft_server.jsa",
                "-jar",
                "server.jar",
                "--nogui",
            ]
        )
        if r.returncode != 0:
            error("Server AppCDS generation failed")
        if Path("minecraft_server.jsa").is_file():
            success("Server AppCDS archive created")
    else:
        error("server.jar not found - skipping server preparation")

    if Path("client.jar").is_file():
        info("Generating AppCDS archive for client...")
        r = subprocess.run(
            [
                "java",
                f"-Xms{client_heap}G",
                f"-Xmx{client_heap}G",
                "-XX:ArchiveClassesAtExit=minecraft_client.jsa",
                "-jar",
                "client.jar",
            ]
        )
        if r.returncode != 0:
            error("Client AppCDS generation failed")
        if Path("minecraft_client.jsa").is_file():
            success("Client AppCDS archive created")
    else:
        info("client.jar not found - skipping client preparation")

    header("Configuring system")
    if shutil.which("ufw"):
        if _run_quiet(["sudo", "ufw", "allow", "25565"]):
            success("Firewall configured (port 25565)")
        else:
            error("Failed to configure firewall")

    if Path("minecraft").is_dir():
        info("Setting ownership of minecraft directory...")
        user = os.environ.get("USER") or os.environ.get("USERNAME", "")
        _run_quiet(["sudo", "chown", "-R", user, str(SCRIPT_DIR / "minecraft")])

    info("Setting executable permissions on scripts...")
    for script in (SCRIPT_DIR / "tools").glob("*.py"):
        script.chmod(0o755)
    os.umask(0o077)

    if shutil.which("systemctl"):
        _run_quiet(["sudo", "systemctl", "daemon-reload"])
        success("Systemd configuration reloaded")

    if shutil.which("loginctl"):
        user = os.environ.get("USER") or os.environ.get("USERNAME", "")
        if _run_quiet(["loginctl", "enable-linger", user]):
            success("User linger enabled for systemd services")

    if not shutil.which("screen"):
        info("Installing screen...")
        if shutil.which("pacman"):
            _run_quiet(["sudo", "pacman", "-Sq", "screen", "--needed", "--noconfirm"])
        elif shutil.which("apt-get"):
            _run_quiet(["sudo", "apt-get", "install", "-y", "screen"])
        if shutil.which("screen"):
            success("Screen installed")

    success("Server preparation complete!")


def download_lazymc(version: str) -> None:
    arch = detect_arch()
    header(f"Downloading lazymc v{version}")
    download_arch = arch.replace("x86_64", "x64")
    url = f"https://github.com/timvisee/lazymc/releases/download/v{version}/lazymc-v{version}-linux-{download_arch}"
    target_file = INSTALL_DIR / "lazymc"
    expected_checksum = get_checksum_for_arch("lazymc", arch)
    INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    download_file(url, target_file, 16)
    if not verify_checksum(target_file, expected_checksum):
        error("Checksum verification failed - removing downloaded file")
        target_file.unlink(missing_ok=True)
        sys.exit(1)
    target_file.chmod(0o755)
    success(f"lazymc installed to {target_file}")


def generate_lazymc_config() -> None:
    header("Generating lazymc configuration")
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    LAZYMC_CONFIG.write_text(LAZYMC_CONFIG_TEMPLATE)
    success(f"Configuration created at {LAZYMC_CONFIG}")
    info("NOTE: You may need to adjust server port configuration")
    info("lazymc listens on 25565, server should run on 25566")


def show_lazymc_usage() -> None:
    header("lazymc Setup Complete!")
    print()
    info(f"Installation directory: {INSTALL_DIR}")
    info(f"Configuration file: {LAZYMC_CONFIG}")
    print()
    header("Quick Start:")
    print("  Start lazymc:  ./tools/server-start.py lazymc start")
    print("  Stop lazymc:   ./tools/server-start.py lazymc stop")
    print("  View status:   ./tools/server-start.py lazymc status")
    print()
    header("Important Notes:")
    info("1. Update server.properties to use port 25566")
    info("2. lazymc will listen on port 25565 and proxy to the server")
    info("3. Server will auto-sleep after 600 seconds of inactivity")
    info(f"4. Edit {LAZYMC_CONFIG} to customize settings")
    print()


def install_lazymc() -> None:
    download_lazymc(LAZYMC_VERSION)
    generate_lazymc_config()
    show_lazymc_usage()


def show_usage() -> None:
    print(f"""\
Minecraft Server Preparation Script

Usage: {sys.argv[0]} [command]

Commands:
  server              Prepare server environment (default)
  lazymc-install      Download and configure lazymc
  lazymc-config       Generate lazymc configuration only
  help                Show this help message

Environment Variables:
  LAZYMC_VERSION      Version of lazymc to install (default: {LAZYMC_VERSION})
  INSTALL_DIR         Installation directory (default: {INSTALL_DIR})
  CONFIG_DIR          Configuration directory (default: {CONFIG_DIR})
""")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Minecraft Server Preparation Script", add_help=False
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="server",
        choices=[
            "server",
            "lazymc-install",
            "lazymc",
            "lazymc-config",
            "help",
            "--help",
            "-h",
        ],
    )
    args = parser.parse_args()

    if args.command == "server":
        prepare_server()
    elif args.command in ("lazymc-install", "lazymc"):
        install_lazymc()
    elif args.command == "lazymc-config":
        generate_lazymc_config()
    else:
        show_usage()


if __name__ == "__main__":
    main()
