#!/usr/bin/env python3
"""Shared utilities for Minecraft server management scripts."""

import json
import os
import platform
import shutil
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
