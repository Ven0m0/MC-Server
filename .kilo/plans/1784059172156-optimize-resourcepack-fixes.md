# Plan: Resource Pack Optimization Fixes

## Summary

Three changes to `tools/optimize-resourcepacks.py` and `minecraft/packsquash.toml`:

1. Strip non-essential language assets (keep only en_us, en_gb, de_de)
2. Fix packsquash.toml compression settings to prevent output bloat
3. Fix overlay_53/ directory skipping: merge overlays into main dir before PackSquash for proper optimization

---

## Change 1: Strip Non-Essential Language Assets

### What

Add a `_strip_languages(pack_dir: Path)` function that removes all language files except `en_us`, `en_gb`, and `de_de` from all `*/lang/` directories.

### Implementation

New function in `optimize-resourcepacks.py`:

```python
# Near the top with other constants
_KEEP_LANGS = frozenset({"en_us", "en_gb", "de_de"})

def _strip_languages(d: Path) -> None:
    """Remove all language files except en_us, en_gb, de_de from `*/lang/` dirs."""
    for lang_dir in d.rglob("lang"):
        if not lang_dir.is_dir():
            continue
        for f in list(lang_dir.iterdir()):
            if not f.is_file():
                continue
            stem = f.stem.lower()
            if stem not in _KEEP_LANGS:
                f.chmod(0o644)
                f.unlink()
```

### Placement in both `process_zip` and `process_dir`

Insert `_strip_languages(pack_dir)` between `_remove_problematic(pack_dir)` and `_fix_pack_metadata(pack_dir)`.

### Why this placement

- Runs BEFORE `_capture_pack_metadata` so stripped languages aren't captured or restored
- Runs AFTER `_remove_problematic` (which removes empty/corrupted files first)
- Runs BEFORE `_run` so PackSquash never sees the stripped files

### Edge cases

- `*/lang/` directories might not exist (no-op)
- Case-insensitive matching on stem handles `en_US`, `En_us`, etc.
- `.json` and `.lang` extensions both covered (checking stem, not extension)

---

## Change 2: Fix Compression Larger Than Original

### What

Edit `minecraft/packsquash.toml` to prevent PackSquash from producing output ZIPs larger than the input.

### Root Cause

Three settings cause bloat:

| Setting | Current | New | Rationale |
|---------|---------|-----|-----------|
| `recompress_compressed_files` | `true` | `false` | Decompressing + recompressing already-efficient ZIP entries (especially PNGs in their native compression) often produces larger files. PackSquash's per-file optimization (PNG re-encode, JSON minify) happens regardless of this flag. |
| `zip_compression_iterations` | `30` | `5` | 30 iterations of ZIP compression tuning is excessive; the marginal gain per iteration diminishes rapidly and can overshoot into bloat. 5 iterations captures most gains. |
| `image_data_compression_iterations` | `50` | `20` | Same reasoning as above — 50 PNG compression passes often produces larger output as it chases diminishing returns. |

### Files changed

Only `minecraft/packsquash.toml`, lines 21-23 and 36.

### Verification

After change, run on a known test pack and compare output size vs input size. Output should be smaller than input (or at minimum not significantly larger).

---

## Change 3: Fix overlay_53/ Directory Skipped During Optimization

### What

Currently, overlay directory files (e.g., `overlay_53/`) are captured from the extracted pack before PackSquash and restored after, but they never pass through PackSquash optimization. PackSquash strips the overlay directory from its output. The fix merges overlay files into the main pack directory before PackSquash runs, then reconstructs the overlay structure from the optimized output.

### Design Decision (confirmed)

Accept the merge approach: overlay files overwrite base files at main paths during PackSquash. For the pack's target format range, the overlay versions are the correct ones.

### Implementation

#### 3a. Fix `_fix_pack_metadata` for non-dict `formats` (safety)

Current code at line 188 does `fmt = entry.get("formats", {})` then `"min_inclusive" in fmt`. If `formats` is an integer (e.g., `"formats": 53`) this raises `TypeError`. Add a guard:

```python
fmt = entry.get("formats", {})
if not isinstance(fmt, dict):
    continue  # cannot process non-dict formats; skip
```

#### 3b. New function `_merge_overlays_into_main`

```python
def _merge_overlays_into_main(
    pack_dir: Path,
    overlays: dict[str, list[tuple[str, bytes]]],
) -> dict[str, str]:
    """Copy overlay files into main pack dir for PackSquash optimization.

    Returns dict mapping overlay_arcname -> main_arcname for reconstruction.
    """
    mapping: dict[str, str] = {}
    for name, files in overlays.items():
        prefix = f"{name}/"
        for arcname, _data in files:
            if not arcname.startswith(prefix):
                continue
            main_arcname = arcname[len(prefix):]  # strip "overlay_53/" prefix
            main_file = pack_dir / main_arcname
            main_file.parent.mkdir(parents=True, exist_ok=True)
            main_file.write_bytes(_data)  # overlay version overwrites base
            mapping[arcname] = main_arcname
    return mapping
```

#### 3c. Modify `_capture_pack_metadata`

Keep the current signature and return value. No changes needed to the capture logic itself — it still captures overlay file contents in memory.

#### 3d. Modify `_restore_pack_metadata` to reconstruct overlays

New behavior: after extracting the output ZIP and before repacking, for each overlay file, copy the OPTIMIZED version from the main path to the overlay path:

```python
def _restore_pack_metadata(
    zip_path: Path,
    mcmeta_bytes: bytes | None,
    overlays: dict[str, list[tuple[str, bytes]]],
    overlay_mapping: dict[str, str] | None = None,
) -> None:
    """Restore pack.mcmeta and reconstruct overlay dirs from optimized output."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        work_dir = Path(tmp_dir) / "work"
        work_dir.mkdir()
        _extract(zip_path, work_dir)

        existing = set(
            f.relative_to(work_dir).as_posix()
            for f in work_dir.rglob("*")
            if f.is_file()
        )

        # Reconstruct overlay dirs from optimized main-path files
        if overlay_mapping:
            for overlay_arcname, main_arcname in overlay_mapping.items():
                overlay_target = work_dir / overlay_arcname
                if overlay_arcname in existing:
                    continue  # PackSquash kept it; already optimized
                main_src = work_dir / main_arcname
                if main_src.exists():
                    overlay_target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(main_src, overlay_target)

        # Restore pack.mcmeta (preserves overlay entries)
        if mcmeta_bytes is not None:
            (work_dir / "pack.mcmeta").write_bytes(mcmeta_bytes)

        # Restore remaining overlay files not covered by mapping
        for name, files in overlays.items():
            prefix = f"{name}/"
            for arcname, data in files:
                if arcname in existing or (overlay_mapping and arcname in overlay_mapping):
                    continue  # already handled
                target = work_dir / arcname
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)

        _repack_zip(work_dir, zip_path)
```

#### 3e. Update `process_zip`

```python
def process_zip(ps_bin: str, zip_path: Path) -> tuple[int, int]:
    bak = zip_path.with_suffix(zip_path.suffix + ".bak")
    source = bak if bak.exists() else zip_path
    before = source.stat().st_size
    if not bak.exists():
        backup(zip_path)
    with tempfile.TemporaryDirectory() as tmp_dir:
        _extract(source, Path(tmp_dir))
        pack_dir = _unwrap(Path(tmp_dir))
        _remove_problematic(pack_dir)
        _strip_languages(pack_dir)                    # NEW: Change 1
        _fix_pack_metadata(pack_dir)
        _widen_pack_format(pack_dir)
        mcmeta_bytes, overlay_dirs = _capture_pack_metadata(pack_dir)
        overlay_mapping = _merge_overlays_into_main(pack_dir, overlay_dirs)  # NEW
        _run(ps_bin, pack_dir, zip_path)
    try:
        _verify_zip_integrity(zip_path)
    except Exception:
        shutil.copy2(bak, zip_path)
        raise
    _restore_pack_metadata(zip_path, mcmeta_bytes, overlay_dirs, overlay_mapping)  # MODIFIED
    return before, zip_path.stat().st_size
```

#### 3f. Update `process_dir` (same pattern)

```python
def process_dir(ps_bin: str, pack_dir: Path) -> tuple[int, int]:
    output_zip = pack_dir.with_name(pack_dir.name + ".zip")
    bak = output_zip.with_suffix(output_zip.suffix + ".bak")
    before = output_zip.stat().st_size if output_zip.exists() else 0
    if output_zip.exists():
        backup(output_zip)
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_pack = Path(tmp_dir) / pack_dir.name
        shutil.copytree(pack_dir, tmp_pack, copy_function=shutil.copy)
        _remove_problematic(tmp_pack)
        _strip_languages(tmp_pack)                     # NEW: Change 1
        _fix_pack_metadata(tmp_pack)
        _widen_pack_format(tmp_pack)
        mcmeta_bytes, overlay_dirs = _capture_pack_metadata(tmp_pack)
        overlay_mapping = _merge_overlays_into_main(tmp_pack, overlay_dirs)  # NEW
        _run(ps_bin, tmp_pack, output_zip)
    try:
        _verify_zip_integrity(output_zip)
    except Exception:
        if bak.exists():
            shutil.copy2(bak, output_zip)
        else:
            output_zip.unlink(missing_ok=True)
        raise
    _restore_pack_metadata(output_zip, mcmeta_bytes, overlay_dirs, overlay_mapping)  # MODIFIED
    return before, output_zip.stat().st_size
```

---

## Files Changed

| File | Changes |
|------|---------|
| `tools/optimize-resourcepacks.py` | Add `_KEEP_LANGS` constant, `_strip_languages()`, `_merge_overlays_into_main()`; modify `_restore_pack_metadata()`, `_fix_pack_metadata()`, `process_zip()`, `process_dir()` |
| `minecraft/packsquash.toml` | Lines 21 (`recompress_compressed_files` -> `false`), 22 (`zip_compression_iterations` -> `5`), 36 (`image_data_compression_iterations` -> `20`) |

---

## Validation

1. **Syntax**: `uv run tools/optimize-resourcepacks.py --selftest` must pass
2. **Language stripping**: Run on a pack with known language files; verify only en_us, en_gb, de_de survive
3. **Compression**: Run on a pack that previously produced larger output; verify output is smaller than input
4. **Overlay_53**: Run on a pack with overlay_53; verify overlay directory exists in output with optimized content
5. **Full workflow**: Batch mode works end-to-end

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Language stripping deletes non-language files in `lang/` dirs | Only operates in `*/lang/` directories; stem-based filtering specific |
| Compression settings reduce optimization quality | PNG re-encoding still runs; only ZIP-level iteration counts reduced |
| Overlay merge overwrites base files in output | For target format range, overlay versions ARE the correct files |
| Non-dict `formats` in other overlays | isinstance guard prevents crash; non-dict formats skipped safely |
| Existing callers of `_restore_pack_metadata` | `overlay_mapping` defaults to `None` for backward compat |
