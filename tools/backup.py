#!/usr/bin/env python3
"""Simplified Minecraft server backup tool."""

import argparse
import os
import subprocess
import sys
import tarfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import shutil

from common import (
    SCRIPT_DIR,
    detect_arch,
    download_file,
    error,
    format_size_bytes,
    header,
    info,
    run_as_root,
    success,
)

BACKUP_DIR = SCRIPT_DIR / "minecraft" / "backups"
TIMESTAMP = time.strftime("%Y%m%d_%H%M%S")
MAX_BACKUPS = 10

RUSTIC_VERSION = os.environ.get("RUSTIC_VERSION", "0.10.2")
RUSTIC_REPO = Path(os.environ.get("RUSTIC_REPO", BACKUP_DIR / "rustic"))
RUSTIC_PASS_FILE = BACKUP_DIR / ".rustic_pass"
RUSTIC_BIN = SCRIPT_DIR / "tools" / "rustic"

os.environ["RUSTIC_REPOSITORY"] = str(RUSTIC_REPO)
os.environ["RUSTIC_PASSWORD_FILE"] = str(RUSTIC_PASS_FILE)

(BACKUP_DIR / "worlds").mkdir(parents=True, exist_ok=True)
(BACKUP_DIR / "configs").mkdir(parents=True, exist_ok=True)


def has(cmd: str) -> bool:
    return shutil.which(cmd) is not None


# ----------------------------------------------------------------------------
# RUSTIC FUNCTIONS
# ----------------------------------------------------------------------------
_rustic_bin = str(RUSTIC_BIN)


def install_rustic() -> bool:
    global _rustic_bin
    if RUSTIC_BIN.is_file():
        return True
    if has("rustic"):
        _rustic_bin = "rustic"
        return True
    info(f"Installing rustic v{RUSTIC_VERSION}...")
    arch = detect_arch()
    target = {
        "x86_64": "x86_64-unknown-linux-gnu",
        "aarch64": "aarch64-unknown-linux-musl",
        "armv7": "armv7-unknown-linux-musleabihf",
    }.get(arch)
    if target is None:
        error(f"Unsupported arch for rustic download: {arch}")
        return False
    url = f"https://github.com/rustic-rs/rustic/releases/download/v{RUSTIC_VERSION}/rustic-v{RUSTIC_VERSION}-{target}.tar.gz"
    import shutil
    import tempfile

    with tempfile.TemporaryDirectory() as tmp_dir:
        archive = Path(tmp_dir) / "rustic.tar.gz"
        try:
            download_file(url, archive)
            with tarfile.open(archive) as tf:
                tf.extractall(tmp_dir)
        except Exception:
            error("Failed to download/extract rustic")
            return False
        found = next(
            (
                p
                for p in Path(tmp_dir).rglob("rustic*")
                if p.is_file() and os.access(p, os.X_OK) or p.name == "rustic"
            ),
            None,
        )
        if found is None:
            error("Could not find rustic binary in archive")
            return False
        shutil.move(str(found), str(RUSTIC_BIN))
    RUSTIC_BIN.chmod(0o755)
    success(f"Rustic installed to {RUSTIC_BIN}")
    return True


def rustic_cmd(*args: str, **kwargs) -> subprocess.CompletedProcess:
    if not install_rustic():
        sys.exit(1)
    return subprocess.run([_rustic_bin, *args], **kwargs)


def rustic_init() -> None:
    RUSTIC_REPO.mkdir(parents=True, exist_ok=True)
    if not RUSTIC_PASS_FILE.is_file():
        info("Generating rustic password...")
        import secrets
        import string

        pw = "".join(
            secrets.choice(string.ascii_letters + string.digits) for _ in range(32)
        )
        RUSTIC_PASS_FILE.write_text(pw)
        RUSTIC_PASS_FILE.chmod(0o600)
    if not any(RUSTIC_REPO.iterdir()) if RUSTIC_REPO.is_dir() else True:
        info(f"Initializing rustic repo at {RUSTIC_REPO}...")
        rustic_cmd("init")
        success("Repository initialized")
    else:
        info("Rustic repo already exists")


def rustic_backup(tag: str = "manual") -> None:
    rustic_init()
    header("Running Rustic Backup")
    info(f"Source: {SCRIPT_DIR}")
    info(f"Repo: {RUSTIC_REPO}")
    rustic_cmd(
        "backup",
        ".",
        "--exclude",
        ".git",
        "--exclude",
        "backups",
        "--exclude",
        "logs",
        "--exclude",
        "cache",
        "--exclude",
        "crash-reports",
        "--exclude",
        "debug",
        "--exclude",
        "session.lock",
        "--tag",
        tag,
        cwd=SCRIPT_DIR,
        check=True,
    )
    success("Rustic backup complete")


def rustic_restore(snapshot: str = "latest", dest: str = "") -> None:
    dest = dest or str(SCRIPT_DIR)
    header("Restoring from Rustic")
    info(f"Snapshot: {snapshot}")
    info(f"Destination: {dest}")
    if input("This will overwrite files in destination. Continue? (yes/no): ") != "yes":
        info("Cancelled")
        return
    rustic_cmd("restore", snapshot, dest, check=True)
    success("Restore complete")


# ----------------------------------------------------------------------------
# TAR FUNCTIONS
# ----------------------------------------------------------------------------
def backup_world() -> None:
    info("Backing up world...")
    world_dir = SCRIPT_DIR / "world"
    if not world_dir.is_dir():
        error("No world directory found")
        return
    dirs = [world_dir]
    for extra in ("world_nether", "world_the_end"):
        p = SCRIPT_DIR / extra
        if p.is_dir():
            dirs.append(p)
    archive = BACKUP_DIR / "worlds" / f"world_{TIMESTAMP}.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        for d in dirs:
            tf.add(d, arcname=d.relative_to(SCRIPT_DIR))
    success(f"World backup created: {archive.name}")


def backup_configs() -> None:
    info("Backing up configs...")
    archive = BACKUP_DIR / "configs" / f"config_{TIMESTAMP}.tar.gz"
    excluded_names = {"mods"}
    excluded_prefixes = ("world",)

    def _filter(ti: tarfile.TarInfo) -> tarfile.TarInfo | None:
        name = Path(ti.name).name
        if ti.name.endswith(".jar") or name in excluded_names:
            return None
        if any(
            Path(ti.name).parts[0].startswith(p)
            for p in excluded_prefixes
            if Path(ti.name).parts
        ):
            return None
        return ti

    with tarfile.open(archive, "w:gz") as tf:
        cfg_dir = SCRIPT_DIR / "minecraft" / "config"
        if cfg_dir.is_dir():
            tf.add(cfg_dir, arcname="minecraft/config", filter=_filter)
        props = SCRIPT_DIR / "minecraft" / "server.properties"
        if props.is_file():
            tf.add(props, arcname="minecraft/server.properties")
        for pattern in ("*.yml", "*.yaml", "*.toml", "*.ini", "*.json", "*.json5"):
            for f in SCRIPT_DIR.glob(pattern):
                tf.add(f, arcname=f.name)
    success(f"Config backup created: {archive.name}")


def backup_mods() -> None:
    info("Backing up mods...")
    mods_dir = SCRIPT_DIR / "mods"
    if not mods_dir.is_dir():
        info("No mods directory")
        return
    archive = BACKUP_DIR / "configs" / f"mods_{TIMESTAMP}.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(mods_dir, arcname="mods")
    success(f"Mods backup created: {archive.name}")


def cleanup_old_backups() -> None:
    info(f"Cleaning old backups (keeping last {MAX_BACKUPS})...")
    for sub in ("worlds", "configs"):
        backup_path = BACKUP_DIR / sub
        if not backup_path.is_dir():
            continue
        files = sorted(backup_path.glob("*.tar.gz"), key=lambda f: f.stat().st_mtime)
        for f in files[:-MAX_BACKUPS] if len(files) > MAX_BACKUPS else []:
            f.unlink()
    if RUSTIC_REPO.is_dir():
        info("Pruning rustic repository...")
        rustic_cmd("forget", "--prune", "--keep-last", str(MAX_BACKUPS))
    success("Cleanup complete")


def list_backups() -> None:
    header("Available Tar Backups")
    print()
    print("World Backups:")
    for f in sorted(
        (BACKUP_DIR / "worlds").glob("*.tar.gz"),
        key=lambda f: f.stat().st_size,
        reverse=True,
    )[:10]:
        print(f"  {f.name} ({format_size_bytes(f.stat().st_size)})")
    print()
    print("Config Backups:")
    for f in sorted(
        (BACKUP_DIR / "configs").glob("*.tar.gz"),
        key=lambda f: f.stat().st_size,
        reverse=True,
    )[:10]:
        print(f"  {f.name} ({format_size_bytes(f.stat().st_size)})")
    if RUSTIC_REPO.is_dir():
        print()
        header("Rustic Snapshots")
        rustic_cmd("snapshots")


def restore_backup(file: str) -> None:
    path = Path(file)
    if not path.is_file():
        error(f"File not found: {file}")
        sys.exit(1)
    info(f"Restoring: {path.name}")
    if input("This will overwrite existing data. Continue? (yes/no): ") != "yes":
        info("Cancelled")
        return
    with tarfile.open(path) as tf:
        tf.extractall(SCRIPT_DIR)
    success("Restore complete")


# ----------------------------------------------------------------------------
# BTRFS FUNCTIONS
# ----------------------------------------------------------------------------
def is_btrfs(path: Path) -> bool:
    r = subprocess.run(
        ["stat", "-f", "-c", "%T", str(path)], capture_output=True, text=True
    )
    return r.stdout.strip() == "btrfs"


def btrfs_cmd(*args: str, **kwargs) -> subprocess.CompletedProcess | None:
    if not has("btrfs"):
        error("btrfs command not found")
        return None
    return run_as_root("btrfs", *args, **kwargs)


def create_btrfs_snapshot(source: str = "", name: str = "") -> None:
    source_dir = Path(source) if source else SCRIPT_DIR / "world"
    snapshot_name = name or f"snapshot_{TIMESTAMP}"
    if not source_dir.is_dir():
        error(f"Source directory not found: {source_dir}")
        return
    if not is_btrfs(source_dir):
        error("Source is not on Btrfs filesystem")
        info("Use regular backup instead")
        return
    snapshot_dir = BACKUP_DIR / "btrfs-snapshots"
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    snapshot_path = snapshot_dir / snapshot_name
    info(f"Creating Btrfs snapshot: {snapshot_name}")
    if (
        btrfs_cmd("subvolume", "snapshot", "-r", str(source_dir), str(snapshot_path))
        is None
    ):
        return
    success(f"Btrfs snapshot created: {snapshot_path}")


def list_btrfs_snapshots() -> None:
    snapshot_dir = BACKUP_DIR / "btrfs-snapshots"
    if not snapshot_dir.is_dir():
        info("No Btrfs snapshots found")
        return
    header("Btrfs Snapshots")
    print()
    if not has("btrfs"):
        error("btrfs command not found")
        return
    r = btrfs_cmd(
        "subvolume", "list", str(snapshot_dir), capture_output=True, text=True
    )
    if r is None or r.returncode != 0:
        for d in sorted(snapshot_dir.glob("snapshot_*")):
            if d.is_dir():
                print(d.name)
    else:
        print(r.stdout)


def delete_btrfs_snapshot(name: str) -> None:
    snapshot_path = BACKUP_DIR / "btrfs-snapshots" / name
    if not snapshot_path.is_dir():
        error(f"Snapshot not found: {name}")
        return
    info(f"Deleting Btrfs snapshot: {name}")
    if input("Continue? (yes/no): ") != "yes":
        info("Cancelled")
        return
    if btrfs_cmd("subvolume", "delete", str(snapshot_path)) is None:
        return
    success("Snapshot deleted")


def restore_btrfs_snapshot(name: str, target: str = "") -> None:
    target_dir = Path(target) if target else SCRIPT_DIR / "world"
    snapshot_path = BACKUP_DIR / "btrfs-snapshots" / name
    if not snapshot_path.is_dir():
        error(f"Snapshot not found: {name}")
        return
    info(f"Restoring Btrfs snapshot: {name} -> {target_dir}")
    if input("This will overwrite existing data. Continue? (yes/no): ") != "yes":
        info("Cancelled")
        return
    if target_dir.is_dir():
        backup_name = target_dir.with_name(f"{target_dir.name}.pre-restore.{TIMESTAMP}")
        info(f"Backing up current to: {backup_name}")
        target_dir.rename(backup_name)
    if btrfs_cmd("subvolume", "snapshot", str(snapshot_path), str(target_dir)) is None:
        return
    success("Snapshot restored")


def show_usage() -> None:
    print(f"""\
Minecraft Server Backup Tool

Usage: {sys.argv[0]} [command] [options]

Commands:
    Tar-based Backups:
        backup [world|config|mods|all]  Create backup (default: all)
        list                            List backups
        restore <file>                  Restore backup
        cleanup                         Clean old backups

    Rustic Backups (Deduplicated):
        rustic-init                     Initialize rustic repository
        rustic-backup [tag]             Backup server directory (excludes logs/backups)
        rustic-restore [snapshot]       Restore snapshot (default: latest)
        rustic-list                     List snapshots
        rustic-prune                    Prune old snapshots

    Btrfs Snapshots (requires Btrfs filesystem):
        snapshot [source] [name]        Create Btrfs snapshot
        snapshot-list                   List Btrfs snapshots
        snapshot-restore <name> [dest]  Restore Btrfs snapshot
        snapshot-delete <name>          Delete Btrfs snapshot

    Info:
        help                            Show this help

Notes:
    - Rustic backups are encrypted and deduplicated (repo: backups/rustic)
    - Rustic password is auto-generated in backups/.rustic_pass
""")


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", nargs="?", default="backup")
    parser.add_argument("args", nargs="*")
    ns = parser.parse_args()
    a = ns.args

    match ns.command:
        case "backup":
            what = a[0] if a else "all"
            if what == "world":
                backup_world()
            elif what == "config":
                backup_configs()
            elif what == "mods":
                backup_mods()
            else:
                backup_world()
                backup_configs()
                backup_mods()
            cleanup_old_backups()
        case "list":
            list_backups()
        case "restore":
            restore_backup(a[0])
        case "cleanup":
            cleanup_old_backups()
        case "rustic-init":
            rustic_init()
        case "rustic-backup":
            rustic_backup(a[0] if a else "manual")
        case "rustic-restore":
            rustic_restore(a[0] if a else "latest", a[1] if len(a) > 1 else "")
        case "rustic-list":
            rustic_cmd("snapshots")
        case "rustic-prune":
            rustic_cmd("forget", "--prune", "--keep-last", str(MAX_BACKUPS))
        case "snapshot":
            create_btrfs_snapshot(a[0] if a else "", a[1] if len(a) > 1 else "")
        case "snapshot-list":
            list_btrfs_snapshots()
        case "snapshot-restore":
            restore_btrfs_snapshot(a[0], a[1] if len(a) > 1 else "")
        case "snapshot-delete":
            delete_btrfs_snapshot(a[0])
        case "help" | "--help" | "-h":
            show_usage()
        case _:
            error(f"Unknown command: {ns.command}")
            show_usage()
            sys.exit(1)


if __name__ == "__main__":
    main()
