# Plan: Add 7-Zip as Preferred Extraction Fallback

## Goal

Replace the PowerShell `Expand-Archive` / `unzip` fallback in `_extract()` with 7-Zip CLI when available, improving robustness for PackSquash-obfuscated ZIPs.

## Scope

- **In scope**: Add 7-Zip detection, modify `_extract()` to prefer 7-Zip, update documentation
- **Out of scope**: Compression changes, PackSquash TOML tuning, ZIP creation fallback

## Design Decisions

### 7-Zip Binary Discovery

Add a `find_7zip()` function following the same pattern as `find_packsquash()`:

1. Check `shutil.which("7z")` for 7-Zip on PATH
2. Check `C:\Program Files\7-Zip\7z.exe` (Windows default install location)
3. Check `~/7z.exe`, `~/7z`, `~/.local/bin/7z` (user home locations)
4. Return `None` if not found (graceful fallback, not fatal)

### Extraction Command

Use 7-Zip with these flags for optimal extraction:

```
7z x "archive.zip" -o"output_dir" -y -bb0 -bd
```

- `x`: Extract with full directory structure
- `-o"dir"`: Output directory (no space after `-o`)
- `-y`: Auto-confirm all prompts
- `-bb0`: No output (quiet mode)
- `-bd`: Disable progress bar (reduces subprocess overhead)

### Fallback Chain

The new `_extract()` flow:

1. Try Python's `zipfile.ZipFile` (primary, zero subprocess overhead)
2. On `BadZipFile`: Try 7-Zip if available (preferred fallback)
3. If 7-Zip not available: PowerShell `Expand-Archive` (Windows) or `unzip` (Linux/macOS)

### Error Handling

- 7-Zip subprocess failures: Fall through to PowerShell/unzip (don't crash)
- 7-Zip not found: Skip to PowerShell/unzip (graceful degradation)
- All failures: Propagate the last exception (existing behavior)

## Implementation Steps

### 1. Add `_EXTRA_7Z_HINTS` Constant

Add a list of common 7-Zip install locations, similar to `_EXTRA_HINTS` for PackSquash:

```python
_EXTRA_7Z_HINTS = [
    Path(r"C:\Program Files\7-Zip\7z.exe"),
    Path.home() / "7z.exe",
    Path.home() / "7z",
    Path.home() / ".local/bin/7z",
]
```

### 2. Add `find_7zip()` Function

Add a function that returns the 7-Zip binary path or `None`:

```python
def find_7zip() -> str | None:
    """Find 7-Zip binary. Returns path or None if not available."""
    z = shutil.which("7z")
    if z:
        return z
    for hint in _EXTRA_7Z_HINTS:
        if hint.is_file():
            return str(hint)
    return None
```

### 3. Modify `_extract()` Function

Replace the current fallback logic:

**Before:**
```python
except zipfile.BadZipFile:
    if sys.platform == "win32":
        subprocess.run(["powershell", "-Command", ...], check=True, capture_output=True)
    else:
        subprocess.run(["unzip", "-o", ...], check=True)
```

**After:**
```python
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
            pass  # Fall through to PowerShell/unzip
    if sys.platform == "win32":
        subprocess.run(["powershell", "-Command", ...], check=True, capture_output=True)
    else:
        subprocess.run(["unzip", "-o", ...], check=True)
```

### 4. Update Documentation

Update `docs/OPTIMIZE-RESOURCEPACKS.md`:

- Add 7-Zip to the Requirements table (optional, for extraction fallback)
- Update the "How It Works → Integrity Verification" section to mention 7-Zip as the preferred fallback
- Update the "Troubleshooting → PowerShell Expand-Archive fails" section to note 7-Zip is tried first

## Testing

### Manual Testing

1. **Test with standard ZIP**: Verify Python's zipfile handles it (no 7-Zip invocation)
2. **Test with PackSquash-obfuscated ZIP**: Verify 7-Zip handles it when Python's zipfile fails
3. **Test without 7-Zip**: Temporarily rename `7z.exe`, verify PowerShell/unzip fallback works
4. **Test with corrupted ZIP**: Verify error propagation (all methods fail gracefully)

### Self-Test

Run `uv run tools/optimize-resourcepacks.py --selftest` to verify the integrity verifier still works.

## Risks

| Risk | Mitigation |
|------|------------|
| 7-Zip not on PATH or at default location | Graceful fallback to PowerShell/unzip |
| 7-Zip subprocess fails | Fall through to PowerShell/unzip |
| 7-Zip extraction produces different output | Unlikely; 7-Zip is more robust than Python's zipfile for edge cases |
| Performance regression from subprocess overhead | Minimal; only triggered on BadZipFile, which is rare for standard packs |

## Files to Modify

1. `tools/optimize-resourcepacks.py` - Add `find_7zip()`, `_EXTRA_7Z_HINTS`, modify `_extract()`
2. `docs/OPTIMIZE-RESOURCEPACKS.md` - Update requirements and troubleshooting sections
