#!/usr/bin/env python3
"""Minecraft server log rotation and management."""

import gzip
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import SCRIPT_DIR, header, success, error, info

LOGS_DIR = SCRIPT_DIR / "logs"
ARCHIVE_DIR = LOGS_DIR / "archive"
MAX_LOG_AGE_DAYS = 30
MAX_ARCHIVED_LOGS = 50
LOG_SIZE_LIMIT_MB = 100

ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)


def rotate_log(log_file: Path):
    if not log_file.exists() or log_file.stat().st_size == 0:
        return
    size_mb = log_file.stat().st_size // (1024 * 1024)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = ARCHIVE_DIR / f"{log_file.stem}_{ts}.log.gz"
    info(f"Rotating {log_file.name} ({size_mb}MB)...")
    # ponytail: copy-then-truncate preserves open file handles (server may have file open)
    with log_file.open("rb") as fin, gzip.open(dest, "wb") as fout:
        shutil.copyfileobj(fin, fout)
    log_file.write_bytes(b"")
    success(f"Rotated: {dest.name}")


def rotate_all():
    header("Rotating logs")
    for name in ("latest.log", "debug.log"):
        rotate_log(LOGS_DIR / name)
    for log in LOGS_DIR.glob("*.log"):
        if log.stat().st_size > LOG_SIZE_LIMIT_MB * 1024 * 1024:
            rotate_log(log)
    success("Rotation complete")


def compress_old():
    header("Compressing old logs")
    skip = {"latest.log", "debug.log", "watchdog.log"}
    logs = [f for f in LOGS_DIR.glob("*.log") if f.name not in skip]
    logs += list(ARCHIVE_DIR.glob("*.log"))
    if not logs:
        info("Nothing to compress")
        return
    info(f"Compressing {len(logs)} files...")
    for log in logs:
        with log.open("rb") as fin, gzip.open(log.with_suffix(".log.gz"), "wb") as fout:
            shutil.copyfileobj(fin, fout)
        log.unlink()
    success(f"Compressed {len(logs)} files")


def clean_old(days=MAX_LOG_AGE_DAYS):
    header(f"Cleaning logs older than {days} days")
    cutoff = time.time() - days * 86400
    deleted = 0
    for pattern, root in (("*.log", LOGS_DIR), ("*.log.gz", ARCHIVE_DIR)):
        for f in root.glob(pattern):
            if f.stat().st_mtime < cutoff:
                info(f"Deleting: {f.name}")
                f.unlink()
                deleted += 1
    success(f"Deleted {deleted} files") if deleted else info("Nothing to clean")


def limit_archives(max_count=MAX_ARCHIVED_LOGS):
    header(f"Limiting archives to {max_count}")
    archives = sorted(ARCHIVE_DIR.glob("*.log.gz"), key=lambda f: f.stat().st_mtime)
    excess = len(archives) - max_count
    if excess <= 0:
        info(f"Archive count ({len(archives)}) OK")
        return
    for old in archives[:excess]:
        old.unlink()
    success("Archives cleaned")


def show_stats():
    print("\n" + "=" * 43)
    print("        Log Management Statistics")
    print("=" * 43 + "\n")
    if LOGS_DIR.exists():
        logs = [f for f in LOGS_DIR.glob("*.log*") if f.is_file()]
        size = sum(f.stat().st_size for f in logs)
        print(
            f"Current Logs:\n  Count: {len(logs)}\n  Size: {size // (1024 * 1024)}MB\n"
        )
        print("Active Logs:")
        for name in ("latest.log", "debug.log", "watchdog.log"):
            p = LOGS_DIR / name
            if p.exists():
                kb = p.stat().st_size // 1024
                lines = p.read_text(errors="replace").count("\n")
                print(f"  {name}: {kb}KB ({lines} lines)")
        print()
    if ARCHIVE_DIR.exists():
        archives = list(ARCHIVE_DIR.glob("*.log.gz"))
        size = sum(f.stat().st_size for f in archives)
        print(
            f"Archives:\n  Count: {len(archives)}\n  Size: {size // (1024 * 1024)}MB\n"
        )
    print("=" * 43)


USAGE = """\
Minecraft Server Log Management
Usage: logrotate.py [rotate|compress|clean [days]|limit [n]|maintenance|stats|view [log] [lines]|search <pattern> [log]|help]"""

args = sys.argv[1:]
cmd = args[0] if args else "help"
if cmd == "rotate":
    rotate_all()
elif cmd == "compress":
    compress_old()
elif cmd == "clean":
    clean_old(int(args[1]) if len(args) > 1 else MAX_LOG_AGE_DAYS)
elif cmd == "limit":
    limit_archives(int(args[1]) if len(args) > 1 else MAX_ARCHIVED_LOGS)
elif cmd == "maintenance":
    header("Full log maintenance")
    rotate_all()
    compress_old()
    clean_old()
    limit_archives()
    show_stats()
elif cmd == "stats":
    show_stats()
elif cmd == "view":
    log = args[1] if len(args) > 1 else "latest.log"
    lines = int(args[2]) if len(args) > 2 else 50
    p = LOGS_DIR / log
    try:
        print("\n".join(p.read_text(errors="replace").splitlines()[-lines:]))
    except OSError:
        error(f"Log not found: {log}")
        sys.exit(1)
elif cmd == "search":
    if len(args) < 2:
        error("Provide search pattern")
        sys.exit(1)
    pattern, log = args[1], (args[2] if len(args) > 2 else "latest.log")
    p = LOGS_DIR / log
    try:
        matches = [
            ln
            for ln in p.read_text(errors="replace").splitlines()
            if pattern.lower() in ln.lower()
        ]
        print("\n".join(matches)) if matches else info(f"No matches for {pattern!r}")
    except OSError:
        error(f"Log not found: {log}")
        sys.exit(1)
elif cmd in ("help", "--help", "-h"):
    print(USAGE)
else:
    error(f"Unknown command: {cmd}")
    print(USAGE)
    sys.exit(1)
