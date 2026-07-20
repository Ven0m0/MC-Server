#!/usr/bin/env python3
"""Minecraft world optimization and chunk cleaning tool."""

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import SCRIPT_DIR, download_file, error, header, info, success

CHUNK_CLEANER_VERSION = "1.0.0"
CHUNK_CLEANER_URL = (
    f"https://github.com/zeroBzeroT/ChunkCleaner/releases/download/"
    f"v{CHUNK_CLEANER_VERSION}/ChunkCleaner-Linux64"
)
CHUNK_CLEANER_BIN = SCRIPT_DIR / "tools" / "ChunkCleaner-Linux64"
MIN_INHABITED_TICKS = 200
PLAYER_INACTIVITY_DAYS = 90

_dir_size_cache: dict[str, int] = {}


def warning(msg: str) -> None:
    print(f"\033[1;33m⚠\033[0m {msg}")


def get_dir_size(path: Path) -> int:
    key = str(path)
    if key not in _dir_size_cache:
        total = 0
        if path.is_dir():
            for f in path.rglob("*"):
                if f.is_file():
                    total += f.stat().st_size
        _dir_size_cache[key] = total
    return _dir_size_cache[key]


def _dim_region_dir(dimension_path: Path) -> Path | None:
    name = dimension_path.name
    if name == "world":
        return dimension_path / "region"
    if name == "world_nether":
        return dimension_path / "DIM-1" / "region"
    if name == "world_the_end":
        return dimension_path / "DIM1" / "region"
    return None


def download_chunk_cleaner() -> bool:
    if CHUNK_CLEANER_BIN.is_file():
        info("ChunkCleaner already installed")
        return True
    info(f"Downloading ChunkCleaner v{CHUNK_CLEANER_VERSION}...")
    try:
        download_file(CHUNK_CLEANER_URL, CHUNK_CLEANER_BIN)
    except Exception:
        error("Failed to download ChunkCleaner")
        return False
    CHUNK_CLEANER_BIN.chmod(0o755)
    success("ChunkCleaner installed successfully")
    return True


def create_backup() -> None:
    info("Creating backup before optimization...")
    r = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "tools" / "backup.py"), "backup", "world"],
        capture_output=True,
    )
    if r.returncode != 0:
        warning("Backup script failed, continuing anyway...")
    else:
        success("Backup created")


def process_dimension(dimension_path: Path, min_ticks: int, dry_run: bool) -> bool:
    dim_name = dimension_path.name
    region_dir = _dim_region_dir(dimension_path)
    if region_dir is None or not region_dir.is_dir():
        return True

    info(f"Processing {dim_name}...")
    backup_region = region_dir.with_name(
        f"{region_dir.name}_backup_{time.strftime('%Y%m%d_%H%M%S')}"
    )

    if dry_run:
        info(f"[DRY RUN] Would clean chunks in: {region_dir}")
        chunk_count = len(list(region_dir.glob("*.mca")))
        info(f"[DRY RUN] Found {chunk_count} region files")
        return True

    r = subprocess.run(
        [
            str(CHUNK_CLEANER_BIN),
            "-path",
            str(region_dir),
            "-newPath",
            str(backup_region),
            "-minInhabitedTicks",
            str(min_ticks),
        ]
    )
    if r.returncode != 0:
        error(f"ChunkCleaner failed for {dim_name}")
        return False

    if backup_region.is_dir():
        old_size, new_size = get_dir_size(backup_region), get_dir_size(region_dir)
        saved_mb = (old_size - new_size) // (1024 * 1024)
        success(f"{dim_name}: Saved {saved_mb}MB (backup: {backup_region})")
    return True


def clean_chunks(world_path: Path, min_ticks: int, dry_run: bool) -> None:
    if not world_path.is_dir():
        error(f"World directory not found: {world_path}")
        sys.exit(1)
    header("Chunk Cleaning")
    info(f"World: {world_path}")
    info(f"Minimum inhabited ticks: {min_ticks}")

    if not download_chunk_cleaner():
        sys.exit(1)

    dims = [
        world_path,
        world_path.with_name(f"{world_path.name}_nether"),
        world_path.with_name(f"{world_path.name}_the_end"),
    ]
    import concurrent.futures

    with concurrent.futures.ThreadPoolExecutor() as pool:
        results = list(
            pool.map(
                lambda d: process_dimension(d, min_ticks, dry_run),
                (d for d in dims if d.is_dir()),
            )
        )
    if not all(results):
        error("Some dimension processing failed")


def _cleanup_old_files(
    directory: Path,
    glob: str,
    days: int,
    dry_run: bool,
    label: str,
    size_unit: str = "MB",
) -> None:
    if not directory.is_dir():
        info(f"No {directory.name} directory found")
        return
    header(f"{label} Cleanup")
    info(f"Removing {label.lower()} older than {days} days...")
    cutoff = time.time() - days * 86400
    files = [
        f for f in directory.glob(glob) if f.is_file() and f.stat().st_mtime < cutoff
    ]

    total_size = 0
    for f in files:
        size = f.stat().st_size
        total_size += size
        if dry_run:
            info(f"[DRY RUN] Would remove: {f.name}")
        else:
            f.unlink()

    if files:
        divisor = 1024 * 1024 if size_unit == "MB" else 1024
        size_val = total_size // divisor
        verb = "Would remove" if dry_run else "Removed"
        info(
            f"[DRY RUN] {verb} {len(files)} files ({size_val}{size_unit})"
        ) if dry_run else success(f"{verb} {len(files)} files ({size_val}{size_unit})")
    else:
        info(f"No old {label.lower()} found")


def clean_player_data(world_path: Path, days: int, dry_run: bool) -> None:
    _cleanup_old_files(world_path / "playerdata", "*.dat", days, dry_run, "Player Data")


def clean_statistics(world_path: Path, days: int, dry_run: bool) -> None:
    _cleanup_old_files(world_path / "stats", "*.json", days, dry_run, "Statistics")


def clean_advancements(world_path: Path, days: int, dry_run: bool) -> None:
    _cleanup_old_files(
        world_path / "advancements",
        "*.json",
        days,
        dry_run,
        "Advancements",
        size_unit="KB",
    )


def clean_session_locks(world_path: Path, dry_run: bool) -> None:
    header("Session Lock Cleanup")
    count = 0
    for dimension_path in (
        world_path,
        world_path.with_name(f"{world_path.name}_nether"),
        world_path.with_name(f"{world_path.name}_the_end"),
    ):
        lock = dimension_path / "session.lock"
        if lock.is_file():
            if dry_run:
                info(f"[DRY RUN] Would remove: {lock}")
            else:
                lock.unlink()
            count += 1
    if count:
        verb = "Would remove" if dry_run else "Removed"
        (info if dry_run else success)(f"{verb} {count} session.lock files")
    else:
        info("No session.lock files found")


def optimize_regions(world_path: Path, dry_run: bool) -> None:
    header("Region File Optimization")
    info("Analyzing region files for optimization...")
    total_before = 0
    for dimension_path in (
        world_path,
        world_path.with_name(f"{world_path.name}_nether"),
        world_path.with_name(f"{world_path.name}_the_end"),
    ):
        region_dir = _dim_region_dir(dimension_path)
        if region_dir is None or not region_dir.is_dir():
            continue
        before = get_dir_size(region_dir)
        total_before += before
        small_files = [f for f in region_dir.glob("*.mca") if f.stat().st_size < 8192]
        if dry_run:
            for f in small_files:
                info(
                    f"[DRY RUN] Small region file: {f.name} ({f.stat().st_size} bytes)"
                )
        if small_files:
            info(f"{dimension_path.name}: Found {len(small_files)} small region files")
    info(f"Current total region size: {total_before // (1024 * 1024)}MB")


def show_stats(world_path: Path) -> None:
    header("World Statistics")
    for dimension_path in (
        world_path,
        world_path.with_name(f"{world_path.name}_nether"),
        world_path.with_name(f"{world_path.name}_the_end"),
    ):
        if not dimension_path.is_dir():
            continue
        print(f"\n=== {dimension_path.name} ===")
        region_dir = _dim_region_dir(dimension_path)
        if region_dir and region_dir.is_dir():
            files = list(region_dir.glob("*.mca"))
            print(
                f"  Region files: {len(files)} ({get_dir_size(region_dir) / 1024 / 1024:.1f}M)"
            )
        entities_dir = region_dir.parent / "entities" if region_dir else None
        if entities_dir and entities_dir.is_dir():
            files = list(entities_dir.glob("*.mca"))
            print(
                f"  Entity files: {len(files)} ({get_dir_size(entities_dir) / 1024 / 1024:.1f}M)"
            )
        poi_dir = region_dir.parent / "poi" if region_dir else None
        if poi_dir and poi_dir.is_dir():
            files = list(poi_dir.glob("*.mca"))
            print(
                f"  POI files: {len(files)} ({get_dir_size(poi_dir) / 1024 / 1024:.1f}M)"
            )

    print()
    playerdata = world_path / "playerdata"
    if playerdata.is_dir():
        print(
            f"Player data: {len(list(playerdata.glob('*.dat')))} players ({get_dir_size(playerdata) / 1024 / 1024:.1f}M)"
        )
    stats_dir = world_path / "stats"
    if stats_dir.is_dir():
        print(
            f"Statistics: {len(list(stats_dir.glob('*.json')))} files ({get_dir_size(stats_dir) / 1024 / 1024:.1f}M)"
        )
    advancements_dir = world_path / "advancements"
    if advancements_dir.is_dir():
        print(
            f"Advancements: {len(list(advancements_dir.glob('*.json')))} files ({get_dir_size(advancements_dir) / 1024 / 1024:.1f}M)"
        )
    total = get_dir_size(world_path) if world_path.is_dir() else 0
    print(f"\nTotal world size: {total / 1024 / 1024:.1f}M")


def show_usage() -> None:
    print(f"""\
Minecraft World Optimization Tool

Usage: {sys.argv[0]} [command] [options]

Commands:
    chunks                Clean unused chunks
    players                Clean old player data
    stats                 Clean old statistics
    advancements          Clean old advancements
    locks                 Remove session.lock files
    optimize              Optimize region files
    all                   Run all optimizations
    info                  Show world statistics
    help                  Show this help

Options:
    --world <path>        World directory path (default: {SCRIPT_DIR}/world)
    --min-ticks <num>     Minimum inhabited ticks for chunks (default: 200)
    --player-days <num>   Player inactivity days threshold (default: 90)
    --dry-run             Show what would be done without making changes
    --no-backup           Skip creating backup before optimization
    --install-cleaner     Download ChunkCleaner tool only

Examples:
    {sys.argv[0]} chunks --min-ticks 500
    {sys.argv[0]} players --player-days 180
    {sys.argv[0]} all --dry-run
    {sys.argv[0]} info
    {sys.argv[0]} --install-cleaner

Note: ChunkCleaner will be automatically downloaded on first use.
      Backups are created before any destructive operations.
""")


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", nargs="?", default="help")
    parser.add_argument("--world", default=str(SCRIPT_DIR / "world"))
    parser.add_argument("--min-ticks", type=int, default=MIN_INHABITED_TICKS)
    parser.add_argument("--player-days", type=int, default=PLAYER_INACTIVITY_DAYS)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-backup", action="store_true")
    parser.add_argument("--install-cleaner", action="store_true")
    ns = parser.parse_args()

    if ns.install_cleaner:
        download_chunk_cleaner()
        return

    world_dir = Path(ns.world)
    create_backup_ = not ns.no_backup

    if ns.dry_run:
        warning("DRY RUN MODE - No changes will be made")

    match ns.command:
        case "chunks":
            if create_backup_:
                create_backup()
            clean_chunks(world_dir, ns.min_ticks, ns.dry_run)
        case "players":
            if create_backup_:
                create_backup()
            clean_player_data(world_dir, ns.player_days, ns.dry_run)
        case "stats":
            if create_backup_:
                create_backup()
            clean_statistics(world_dir, ns.player_days, ns.dry_run)
        case "advancements":
            if create_backup_:
                create_backup()
            clean_advancements(world_dir, ns.player_days, ns.dry_run)
        case "locks":
            clean_session_locks(world_dir, ns.dry_run)
        case "optimize":
            optimize_regions(world_dir, ns.dry_run)
        case "all":
            if create_backup_:
                create_backup()
            clean_chunks(world_dir, ns.min_ticks, ns.dry_run)
            clean_player_data(world_dir, ns.player_days, ns.dry_run)
            clean_statistics(world_dir, ns.player_days, ns.dry_run)
            clean_advancements(world_dir, ns.player_days, ns.dry_run)
            clean_session_locks(world_dir, ns.dry_run)
            optimize_regions(world_dir, ns.dry_run)
            success("All optimizations complete!")
        case "info":
            show_stats(world_dir)
        case "help" | "--help" | "-h":
            show_usage()
        case _:
            error(f"Unknown command: {ns.command}")
            show_usage()
            sys.exit(1)


if __name__ == "__main__":
    main()
