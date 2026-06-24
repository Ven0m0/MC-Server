#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""optimize-resourcepacks.py: Optimize resource packs with PackSquash.

Usage:
  optimize-resourcepacks.py <pack.zip>        # single ZIP pack
  optimize-resourcepacks.py <pack_dir>        # single directory pack
  optimize-resourcepacks.py <resourcepacks/>  # batch: all packs in a folder
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
TOML_TEMPLATE = REPO_ROOT / "minecraft" / "packsquash.toml"

# Extra locations to search for the binary before giving up
_EXTRA_HINTS = [
    Path.home() / "packsquash.exe",
    Path.home() / "packsquash",
    Path.home() / ".local/bin/packsquash",
]


def find_packsquash() -> str:
    if shutil.which("mise"):
        r = subprocess.run(
            ["mise", "which", "packsquash"], capture_output=True, text=True
        )
        if r.returncode == 0 and Path(r.stdout.strip()).is_file():
            return r.stdout.strip()
    ps = shutil.which("packsquash")
    if ps:
        return ps
    for hint in _EXTRA_HINTS:
        if hint.is_file():
            return str(hint)
    print("ERROR: packsquash not found. Run: mise install", file=sys.stderr)
    sys.exit(1)


def fmt_bytes(n: int) -> str:
    for unit, div in [("G", 1 << 30), ("M", 1 << 20), ("K", 1 << 10)]:
        if n >= div:
            return f"{n / div:.1f}{unit}"
    return f"{n}B"


def backup(path: Path) -> None:
    bak = path.with_suffix(path.suffix + ".bak")
    shutil.copy2(path, bak)
    print(f"  backed up -> {bak.name}")


def _run(ps_bin: str, pack_dir: Path, output_zip: Path) -> None:
    toml = (
        TOML_TEMPLATE.read_text()
        .replace("pack_directory = ''", f"pack_directory = '{pack_dir.as_posix()}'")
        .replace(
            "output_file_path = ''", f"output_file_path = '{output_zip.as_posix()}'"
        )
    )
    with tempfile.NamedTemporaryFile(
        suffix=".toml", mode="w", delete=False, encoding="utf-8"
    ) as f:
        f.write(toml)
        tmp = f.name
    try:
        subprocess.run([ps_bin, tmp], check=True)
    finally:
        os.unlink(tmp)


def _is_power_of_two(n: int) -> bool:
    return n > 0 and (n & (n - 1)) == 0


def _remove_problematic(d: Path) -> None:
    """Remove files that PackSquash cannot process:
    - Empty/whitespace-only files (would fail JSON/shader parsing)
    - PNG files with non-power-of-two dimensions
    """
    for f in d.rglob("*"):
        if not f.is_file():
            continue
        data = f.read_bytes()
        if not data.strip():
            f.chmod(0o644)
            f.unlink()
            continue
        if f.suffix.lower() == ".png" and len(data) >= 24:
            # PNG header: width at bytes 16-20, height at bytes 20-24
            w = int.from_bytes(data[16:20], "big")
            h = int.from_bytes(data[20:24], "big")
            if not (_is_power_of_two(w) and _is_power_of_two(h)):
                f.chmod(0o644)
                f.unlink()


def _fix_pack_metadata(d: Path) -> None:
    """Fix pack.mcmeta for newer MC versions:
    - Inject pack_format if only min_format/max_format are present (1.20.2+ packs)
    - Add min_format/max_format to overlay entries missing them (required when max > 64)
    """
    meta = d / "pack.mcmeta"
    if not meta.exists():
        return
    data = json.loads(meta.read_bytes())
    changed = False
    pack = data.get("pack", {})
    if "pack_format" not in pack and "min_format" in pack:
        min_f = pack["min_format"]
        pack["pack_format"] = min_f[0] if isinstance(min_f, list) else min_f
        changed = True
    for entry in data.get("overlays", {}).get("entries", []):
        fmt = entry.get("formats", {})
        if "min_format" not in entry and "min_inclusive" in fmt:
            entry["min_format"] = fmt["min_inclusive"]
            changed = True
        if "max_format" not in entry and "max_inclusive" in fmt:
            entry["max_format"] = fmt["max_inclusive"]
            changed = True
    if changed:
        meta.write_text(json.dumps(data), encoding="utf-8")


def _unwrap(d: Path) -> Path:
    """If d contains only one subdirectory with pack.mcmeta, return that subdir."""
    children = list(d.iterdir())
    if (
        len(children) == 1
        and children[0].is_dir()
        and (children[0] / "pack.mcmeta").exists()
    ):
        return children[0]
    return d


def _extract(zip_path: Path, dest: Path) -> None:
    """Extract ZIP, falling back to system tools for PackSquash-obfuscated files."""
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(dest)
    except zipfile.BadZipFile:
        if sys.platform == "win32":
            subprocess.run(
                [
                    "powershell",
                    "-Command",
                    f'Expand-Archive -LiteralPath "{zip_path}" -DestinationPath "{dest}" -Force',
                ],
                check=True,
                capture_output=True,
            )
        else:
            subprocess.run(["unzip", "-o", str(zip_path), "-d", str(dest)], check=True)


def process_zip(ps_bin: str, zip_path: Path) -> tuple[int, int]:
    bak = zip_path.with_suffix(zip_path.suffix + ".bak")
    # Use .bak as source if it exists (original before any prior PackSquash run)
    source = bak if bak.exists() else zip_path
    before = source.stat().st_size
    if not bak.exists():
        backup(zip_path)
    with tempfile.TemporaryDirectory() as tmp_dir:
        _extract(source, Path(tmp_dir))
        pack_dir = _unwrap(Path(tmp_dir))
        _remove_problematic(pack_dir)
        _fix_pack_metadata(pack_dir)
        _run(ps_bin, pack_dir, zip_path)
    return before, zip_path.stat().st_size


def process_dir(ps_bin: str, pack_dir: Path) -> tuple[int, int]:
    output_zip = pack_dir.with_suffix(".zip")
    before = output_zip.stat().st_size if output_zip.exists() else 0
    if output_zip.exists():
        backup(output_zip)
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_pack = Path(tmp_dir) / pack_dir.name
        shutil.copytree(pack_dir, tmp_pack, copy_function=shutil.copy)
        _remove_problematic(tmp_pack)
        _fix_pack_metadata(tmp_pack)
        _run(ps_bin, tmp_pack, output_zip)
    return before, output_zip.stat().st_size


def is_resource_pack(path: Path) -> bool:
    """Return True if path looks like a resource pack (has pack.mcmeta)."""
    if path.is_dir():
        return (path / "pack.mcmeta").exists()
    if path.suffix.lower() == ".zip":
        try:
            with zipfile.ZipFile(path, "r") as zf:
                names = zf.namelist()
            return "pack.mcmeta" in names or any(
                n.endswith("/pack.mcmeta") for n in names
            )
        except Exception:
            return False
    return False


def process_one(ps_bin: str, target: Path) -> bool:
    size_str = fmt_bytes(target.stat().st_size) if target.is_file() else ""
    print(f"==> {target.name}{f'  ({size_str})' if size_str else ''}")
    try:
        if target.is_dir():
            before, after = process_dir(ps_bin, target)
        else:
            before, after = process_zip(ps_bin, target)
        saved = f"  saved {fmt_bytes(before - after)}" if before > after else ""
        print(f"  done  {fmt_bytes(after)}{saved}")
        return True
    except subprocess.CalledProcessError:
        print("  FAILED", file=sys.stderr)
        return False


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    target = Path(sys.argv[1]).resolve()
    if not target.exists():
        print(f"ERROR: not found: {target}", file=sys.stderr)
        sys.exit(1)

    ps_bin = find_packsquash()

    # Batch mode: a folder that is itself NOT a pack (no pack.mcmeta at root)
    if target.is_dir() and not (target / "pack.mcmeta").exists():
        packs = sorted(p for p in target.iterdir() if is_resource_pack(p))
        if not packs:
            print(f"ERROR: no resource packs found in {target}", file=sys.stderr)
            sys.exit(1)
        print(f"Found {len(packs)} resource packs in {target.name}/")
        ok = sum(process_one(ps_bin, p) for p in packs)
        print(f"\n{ok}/{len(packs)} packs optimized successfully.")
        return

    if not is_resource_pack(target):
        print(
            f"ERROR: {target.name} does not appear to be a resource pack (no pack.mcmeta)",
            file=sys.stderr,
        )
        sys.exit(1)

    process_one(ps_bin, target)


if __name__ == "__main__":
    main()
