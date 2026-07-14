# Fix: PackSquash Rewrites pack.mcmeta and Strips Overlay Directories

## Problem

Running `tools/optimize-resourcepacks.py` on `VanillaTweaks_r226513_MC26.2.x_fixed.zip` produces `VanillaTweaks_optimized.zip` that is broken for MC 26.2:

1. **PackSquash rewrites `pack.mcmeta`** - Detects MC version from assets and writes format numbers 34-75 (MC 1.21.1-1.21.5) instead of the original 84-91 (MC 26.1-26.2)
2. **PackSquash strips overlay directories** - Only 6 of ~12 overlay directories survive (overlay_34_55, overlay_34_74, overlay_42, overlay_46, overlay_53, overlay_63). The rest are stripped because PackSquash only keeps files matching its optimization globs
3. **No overlay covers format 91** (MC 26.2) - the pack doesn't appear in resource pack selection

## Root Cause

`automatic_minecraft_quirks_detection = true` in `packsquash.toml` causes PackSquash to detect the MC version from asset structure and rewrite `pack.mcmeta` with what it believes is correct. PackSquash also strips any files/directories that don't match its optimization patterns, which includes overlay directories whose contents it considers already optimal or unmapped.

## Fix

### 1. Preserve original `pack.mcmeta` and overlay directories

Add a pre-PackSquash capture step and post-PackSquash restore:

**New helper: `_capture_pack_metadata(pack_dir: Path) -> tuple[bytes, dict[str, Path]]`**
- Read `pack.mcmeta` as bytes (the corrected version after `_fix_pack_metadata`)
- Scan for overlay directories: any top-level dir that is NOT `assets/` and is referenced in `pack.mcmeta` overlays.entries
- Return `(mcmeta_bytes, {overlay_name: overlay_path})`

**New helper: `_restore_pack_metadata(zip_path: Path, mcmeta_bytes: bytes, overlays: dict[str, Path]) -> None`**
- Replace `pack.mcmeta` in the output ZIP with the saved version
- For each overlay directory that is missing from the ZIP, add all its files back

**New helper: `_inject_file_into_zip(zip_path: Path, name: str, content: bytes)`**
- Open ZIP in append mode, write the file entry

**New helper: `_inject_directory_into_zip(zip_path: Path, src_dir: Path, zip_prefix: str)`**
- Walk src_dir, add each file as `<zip_prefix>/<relative_path>` entry in the ZIP

### 2. Integrate into `process_zip()` and `process_dir()`

In both functions, after `_fix_pack_metadata()` and before `_run()`:
```python
mcmeta_bytes, overlay_dirs = _capture_pack_metadata(pack_dir)
```

After `_run()` produces the output ZIP and `_verify_zip_integrity()` passes:
```python
_restore_pack_metadata(zip_path, mcmeta_bytes, overlay_dirs)
```

### 3. Increase PNG compression iterations

In `minecraft/packsquash.toml`, change:
```toml
image_data_compression_iterations = 25
```
to:
```toml
image_data_compression_iterations = 50
```

## Files Modified

1. `tools/optimize-resourcepacks.py` - Add capture/restore helpers, integrate into process_zip/process_dir
2. `minecraft/packsquash.toml` - Increase `image_data_compression_iterations` from 25 to 50

## Validation

- `./tools/optimize-resourcepacks.py --selftest` passes
- Test on `VanillaTweaks_r226513_MC26.2.x_fixed.zip`: output ZIP has correct `pack.mcmeta` with formats 84-91 and all overlay directories present
- Verify `pack.mcmeta` JSON is valid and overlays reference existing directories
