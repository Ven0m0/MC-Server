#!/usr/bin/env python3
"""Shared utilities for Minecraft server management scripts."""

import hashlib
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).parent.parent


def header(msg: str) -> None:
    print(f"\033[0;34m==>\033[0m {msg}")


def success(msg: str) -> None:
    print(f"\033[0;32m✓\033[0m {msg}")


def error(msg: str) -> None:
    print(f"\033[0;31m✗\033[0m {msg}", file=sys.stderr)


def info(msg: str) -> None:
    print(f"\033[1;33m→\033[0m {msg}")


def detect_arch() -> str:
    m = platform.machine().lower()
    if m in ("x86_64", "amd64"):
        return "x86_64"
    if m in ("aarch64", "arm64"):
        return "aarch64"
    if m.startswith("armv7"):
        return "armv7"
    error(f"Unsupported architecture: {m}")
    sys.exit(1)


def fetch_json(url: str) -> Any:
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read())


def download_file(url: str, dest: str | Path, connections: int = 8) -> None:
    path = Path(dest)
    path.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("aria2c") and connections > 1:
        _ = subprocess.run(
            [
                "aria2c",
                "-x",
                str(connections),
                "-s",
                str(connections),
                "-d",
                str(path.parent),
                "-o",
                path.name,
                url,
            ],
            check=True,
            capture_output=True,
        )
    else:
        with urllib.request.urlopen(url) as r, open(path, "wb") as f:
            shutil.copyfileobj(r, f)


def is_server_running() -> bool:
    for pat in ("fabric-server-launch.jar", "server.jar"):
        if subprocess.run(["pgrep", "-f", pat], capture_output=True).returncode == 0:
            return True
    return False


def get_server_pid() -> int | None:
    r = subprocess.run(
        ["pgrep", "-f", "fabric-server-launch.jar"], capture_output=True, text=True
    )
    pids = r.stdout.strip().split()
    return int(pids[0]) if pids else None


def total_ram_gb() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    return int(line.split()[1]) // (1024 * 1024)
    except OSError:
        pass
    return 4


def heap_size_gb(reserved: int = 2) -> int:
    return max(1, total_ram_gb() - reserved)


def cpu_cores() -> int:
    return os.cpu_count() or 4


def get_client_xms_gb() -> int:
    return max(1, total_ram_gb() // 4)


def get_client_xmx_gb() -> int:
    return max(2, total_ram_gb() // 2)


def get_minecraft_memory_gb(reserved: int = 3) -> int:
    return heap_size_gb(reserved)


def ensure_dir(path: str | Path) -> None:
    Path(path).mkdir(parents=True, exist_ok=True)


def format_size_bytes(num_bytes: int) -> str:
    for unit, size in (("G", 1073741824), ("M", 1048576), ("K", 1024)):
        if num_bytes >= size:
            whole, rem = divmod(num_bytes, size)
            return f"{whole}.{rem * 10 // size}{unit}"
    return f"{num_bytes}B"


def check_dependencies(*cmds: str) -> bool:
    missing = [c for c in cmds if not shutil.which(c)]
    if missing:
        error(f"Missing required dependencies: {' '.join(missing)}")
        print("Please install them before continuing.", file=sys.stderr)
        return False
    return True


def verify_checksum(file: str | Path, expected_sha256: str) -> bool:
    if not expected_sha256:
        info("No checksum provided, skipping verification")
        return True
    path = Path(file)
    if not path.is_file():
        error(f"File not found: {file}")
        return False
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected_sha256:
        error(f"Checksum verification failed for {file}")
        error(f"Expected: {expected_sha256}")
        error(f"Actual:   {actual}")
        return False
    success(f"Checksum verified for {path.name}")
    return True


def check_root() -> bool:
    if os.geteuid() == 0:
        return True
    if shutil.which("sudo"):
        info("Root access required. Using sudo...")
        return True
    error("Root access required but sudo not available")
    return False


def run_as_root(*cmd: str, **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    args = list(cmd) if os.geteuid() == 0 else ["sudo", *cmd]
    return subprocess.run(args, check=True, **kwargs)


def detect_java() -> str:
    java_home = os.environ.get("JAVA_HOME")
    if java_home and (Path(java_home) / "bin" / "java").is_file():
        return str(Path(java_home) / "bin" / "java")
    if shutil.which("mise"):
        r = subprocess.run(["mise", "which", "java"], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return "java"


def check_server_port(port: int = 25565, host: str = "localhost") -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        return s.connect_ex((host, port)) == 0


def send_command(cmd: str, session_name: str = "minecraft") -> bool:
    if shutil.which("screen"):
        r = subprocess.run(["screen", "-list"], capture_output=True, text=True)
        if session_name in r.stdout:
            info(f"Sending command to Screen: {cmd}")
            subprocess.run(
                ["screen", "-S", session_name, "-p", "0", "-X", "stuff", f"{cmd}\r"]
            )
            return True
    if shutil.which("tmux"):
        r = subprocess.run(["tmux", "has-session", "-t", session_name])
        if r.returncode == 0:
            info(f"Sending command to Tmux: {cmd}")
            subprocess.run(["tmux", "send-keys", "-t", session_name, cmd, "Enter"])
            return True
    error(f"Server session '{session_name}' not found (Screen/Tmux).")
    return False


def game_command(
    cmd: str,
    host: str | None = None,
    port: int | None = None,
    password: str | None = None,
) -> None:
    host = host or os.environ.get("RCON_HOST", "localhost")
    port = port or int(os.environ.get("RCON_PORT", "25575"))
    password = password if password is not None else os.environ.get("RCON_PASSWORD", "")
    if shutil.which("mcrcon"):
        env = {
            **os.environ,
            "MCRCON_HOST": host,
            "MCRCON_PORT": str(port),
            "MCRCON_PASS": password,
        }
        subprocess.run(["mcrcon", "-c", cmd], env=env, check=True)
    else:
        subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "tools" / "rcon.py"),
                host,
                str(port),
                password,
                cmd,
            ],
            check=True,
        )
