#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
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

# Common 7-Zip install locations for ZIP extraction fallback
_EXTRA_7Z_HINTS = [
    Path(r"C:\Program Files\7-Zip\7z.exe"),
    Path.home() / "7z.exe",
    Path.home() / "7z",
    Path.home() / ".local/bin/7z",
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


def find_7zip() -> str | None:
    """Find 7-Zip binary for ZIP extraction fallback. Returns path or None."""
    z = shutil.which("7z")
    if z:
        return z
    for hint in _EXTRA_7Z_HINTS:
        if hint.is_file():
            return str(hint)
    return None


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


_TEXTURE_EXTS = {".png"}
_SHADER_EXTS = {".fsh", ".vsh", ".glsl"}


def _verify_zip_integrity(zip_path: Path) -> None:
    """Verify a PackSquash output ZIP is not corrupted.

    PackSquash can legitimately store byte-identical files (e.g. arrow.png /
    tipped_arrow.png) as overlapping ZIP entries to save space -- valid for
    Minecraft's own reader, but rejected by Python's strict zipfile module.
    So this extracts with the same tolerant path _extract() uses (falls back
    to system unzip tools on BadZipFile) rather than trusting zipfile's CRC
    checks directly, then checks the extracted textures/shaders on disk.
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        dest = Path(tmp_dir)
        _extract(zip_path, dest)
        for f in dest.rglob("*"):
            if not f.is_file():
                continue
            ext = f.suffix.lower()
            if ext not in _TEXTURE_EXTS and ext not in _SHADER_EXTS:
                continue
            data = f.read_bytes()
            rel = f.relative_to(dest)
            if not data:
                raise RuntimeError(f"empty file in {zip_path.name}: {rel}")
            if ext == ".png" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError(f"bad PNG signature in {zip_path.name}: {rel}")
            if ext in _SHADER_EXTS:
                try:
                    data.decode("utf-8")
                except UnicodeDecodeError as e:
                    raise RuntimeError(
                        f"corrupted shader (invalid utf-8) in {zip_path.name}: {rel}"
                    ) from e


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
        # pack.png (the pack icon) is never atlas-stitched, so it has no
        # power-of-two requirement -- Minecraft displays it at any size.
        if f.suffix.lower() == ".png" and len(data) >= 24 and f.name != "pack.png":
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


def _capture_pack_metadata(
    pack_dir: Path,
) -> tuple[bytes | None, dict[str, list[tuple[str, bytes]]]]:
    """Capture pack.mcmeta and overlay file contents before PackSquash runs.

    PackSquash may rewrite pack.mcmeta (changing format numbers) and strip
    overlay directories it doesn't recognize. This captures the originals so
    they can be restored into the output ZIP afterward.

    Returns (mcmeta_bytes_or_None, {overlay_name: [(arcname, content), ...]}).
    File contents are read into memory because the source pack_dir lives in a
    temp directory that is cleaned up before restore time.
    """
    mcmeta_bytes: bytes | None = None
    meta = pack_dir / "pack.mcmeta"
    if meta.exists():
        mcmeta_bytes = meta.read_bytes()

    overlays: dict[str, list[tuple[str, bytes]]] = {}
    for entry in (
        json.loads(mcmeta_bytes).get("overlays", {}).get("entries", [])
        if mcmeta_bytes
        else []
    ):
        name = entry.get("directory")
        if not name:
            continue
        overlay_path = pack_dir / name
        if not overlay_path.is_dir():
            continue
        files: list[tuple[str, bytes]] = []
        for f in overlay_path.rglob("*"):
            if f.is_file():
                rel = f.relative_to(overlay_path).as_posix()
                arcname = f"{name}/{rel}"
                files.append((arcname, f.read_bytes()))
        if files:
            overlays[name] = files

    return mcmeta_bytes, overlays


def _repack_zip(src_dir: Path, zip_path: Path) -> None:
    """Repack a directory into a ZIP.

    Creates a fresh ZIP file (no PackSquash obfuscation issues since we control
    the content being written).
    """
    temp_zip = zip_path.with_suffix(".temp.zip")
    with zipfile.ZipFile(temp_zip, "w") as zf:
        for f in src_dir.rglob("*"):
            if f.is_file():
                rel = f.relative_to(src_dir).as_posix()
                zf.write(f, rel)
    temp_zip.replace(zip_path)


def _restore_pack_metadata(
    zip_path: Path,
    mcmeta_bytes: bytes | None,
    overlays: dict[str, list[tuple[str, bytes]]],
) -> None:
    """Restore original pack.mcmeta and overlay files into output ZIP."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        work_dir = Path(tmp_dir) / "work"
        work_dir.mkdir()
        _extract(zip_path, work_dir)

        existing = set(
            f.relative_to(work_dir).as_posix()
            for f in work_dir.rglob("*")
            if f.is_file()
        )

        if mcmeta_bytes is not None:
            (work_dir / "pack.mcmeta").write_bytes(mcmeta_bytes)

        for name, files in overlays.items():
            for arcname, data in files:
                if arcname not in existing:
                    target = work_dir / arcname
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)

        _repack_zip(work_dir, zip_path)


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
        z7 = find_7zip()
        if z7:
            try:
                subprocess.run(
                    [z7, "x", str(zip_path), f"-o{dest}", "-y", "-bb0", "-bd"],
                    check=True,
                    capture_output=True,
                )
                return
            except subprocess.CalledProcessError:
                pass
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
        mcmeta_bytes, overlay_dirs = _capture_pack_metadata(pack_dir)
        _run(ps_bin, pack_dir, zip_path)
    try:
        _verify_zip_integrity(zip_path)
    except Exception:
        shutil.copy2(bak, zip_path)
        raise
    _restore_pack_metadata(zip_path, mcmeta_bytes, overlay_dirs)
    return before, zip_path.stat().st_size


def process_dir(ps_bin: str, pack_dir: Path) -> tuple[int, int]:
    output_zip = pack_dir.with_suffix(".zip")
    bak = output_zip.with_suffix(output_zip.suffix + ".bak")
    before = output_zip.stat().st_size if output_zip.exists() else 0
    if output_zip.exists():
        backup(output_zip)
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_pack = Path(tmp_dir) / pack_dir.name
        shutil.copytree(pack_dir, tmp_pack, copy_function=shutil.copy)
        _remove_problematic(tmp_pack)
        _fix_pack_metadata(tmp_pack)
        mcmeta_bytes, overlay_dirs = _capture_pack_metadata(tmp_pack)
        _run(ps_bin, tmp_pack, output_zip)
    try:
        _verify_zip_integrity(output_zip)
    except Exception:
        if bak.exists():
            shutil.copy2(bak, output_zip)
        else:
            output_zip.unlink(missing_ok=True)
        raise
    _restore_pack_metadata(output_zip, mcmeta_bytes, overlay_dirs)
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
    except (subprocess.CalledProcessError, RuntimeError) as e:
        print(f"  FAILED: {e}", file=sys.stderr)
        return False


def _selftest() -> None:
    """assert-based self-check for _verify_zip_integrity. Run via --selftest."""
    good_png = b"\x89PNG\r\n\x1a\n" + b"\0" * 20
    with tempfile.TemporaryDirectory() as tmp:
        ok_zip = Path(tmp) / "ok.zip"
        with zipfile.ZipFile(ok_zip, "w") as zf:
            zf.writestr("assets/x/textures/block/stone.png", good_png)
            zf.writestr("assets/x/shaders/core/rendertype_solid.fsh", "void main() {}")
        _verify_zip_integrity(ok_zip)  # must not raise

        for name, data in [
            ("assets/x/textures/block/stone.png", b"not a png"),
            ("assets/x/shaders/core/rendertype_solid.fsh", b"\xff\xfe\x00bad"),
        ]:
            bad_zip = Path(tmp) / "bad.zip"
            with zipfile.ZipFile(bad_zip, "w") as zf:
                zf.writestr(name, data)
            try:
                _verify_zip_integrity(bad_zip)
            except RuntimeError:
                pass
            else:
                raise AssertionError(f"expected RuntimeError for corrupted {name}")
    print("selftest OK")


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--selftest":
        _selftest()
        return

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
