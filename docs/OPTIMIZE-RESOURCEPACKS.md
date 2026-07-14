# Resource Pack Optimization

Documentation for `tools/optimize-resourcepacks.py` - a utility that runs
[PackSquash](https://github.com/ComunidadAylas/PackSquash) against Minecraft
resource packs to reduce file size while preserving visual fidelity.

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Single ZIP Pack](#single-zip-pack)
  - [Single Directory Pack](#single-directory-pack)
  - [Batch Mode](#batch-mode)
  - [Self-Test](#self-test)
- [How It Works](#how-it-works)
  - [Processing Pipeline](#processing-pipeline)
  - [File Sanitization](#file-sanitization)
  - [Pack Metadata Correction](#pack-metadata-correction)
  - [Integrity Verification](#integrity-verification)
  - [Backup and Rollback](#backup-and-rollback)
- [Configuration](#configuration)
- [Exit Codes](#exit-codes)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

PackSquash is a tool that re-encodes textures, audio, and other assets inside
resource packs to minimize their final ZIP size. This script wraps PackSquash
with additional safeguards:

- **Automatic binary discovery** - finds PackSquash via `mise`, `PATH`, or
  common install locations
- **Pre-processing** - removes files PackSquash cannot handle and fixes
  pack metadata for newer Minecraft versions
- **Post-processing verification** - extracts the output ZIP and validates
  PNG signatures and shader encoding before accepting the result
- **Safe rollback** - creates `.bak` backups before overwriting and restores
  them automatically if verification fails
- **Batch processing** - optimize every pack in a folder in one invocation

## Requirements

| Dependency | Version | Required | Purpose |
|------------|---------|----------|---------|
| Python | 3.13+ | Yes | Script runtime (uses `uv run --script`) |
| PackSquash | Latest | Yes | The optimization engine |
| `uv` | Any | Yes | Script launcher (shebang: `uv run --script`) |
| `mise` | Any | No | Preferred PackSquash provider |
| `7z` (7-Zip) | Any | No | Preferred fallback ZIP extraction (Windows & Linux) |
| PowerShell | Any | No | Fallback ZIP extraction on Windows |
| `unzip` | Any | No | Fallback ZIP extraction on Linux/macOS |

### Installing PackSquash

The script searches for the PackSquash binary in this order:

1. `mise which packsquash` (if `mise` is installed)
2. `packsquash` on `PATH`
3. `~/packsquash.exe` (Windows)
4. `~/packsquash`
5. `~/.local/bin/packsquash`

**Via mise (recommended):**

```bash
mise i -y
```

The project's `mise.toml` includes PackSquash:

```toml
[tools]
"cargo:https://github.com/ComunidadAylas/PackSquash" = "latest"
```

**Manual install:** Download from the
[PackSquash releases page](https://github.com/ComunidadAylas/PackSquash/releases)
and place the binary in one of the searched locations.

## Usage

```text
uv run tools/optimize-resourcepacks.py <pack.zip>        # single ZIP pack
uv run tools/optimize-resourcepacks.py <pack_dir>        # single directory pack
uv run tools/optimize-resourcepacks.py <resourcepacks/>  # batch: all packs in a folder
uv run tools/optimize-resourcepacks.py --selftest        # run built-in self-test
```

### Single ZIP Pack

Optimizes a `.zip` resource pack in place. The original file is backed up to
`<pack>.zip.bak` before overwriting.

```bash
uv run tools/optimize-resourcepacks.py minecraft/resourcepacks/Faithful.zip
```

Output:

```text
==> Faithful.zip  (12.3M)
  backed up -> Faithful.zip.bak
  done  8.1M  saved 4.2M
```

If a `.bak` already exists from a prior run, the script uses it as the source
(rather than the already-optimized file) to avoid double-compression artifacts.

### Single Directory Pack

Optimizes an unpacked resource pack directory. Produces a `.zip` file next
to the directory.

```bash
uv run tools/optimize-resourcepacks.py minecraft/resourcepacks/MyPack/
```

Output:

```text
==> MyPack
  done  3.7M
```

The directory itself is never modified. The script copies it to a temporary
location, sanitizes the copy, and runs PackSquash against that.

### Batch Mode

When given a folder that is not itself a resource pack (no `pack.mcmeta` at
its root), the script treats it as a batch container and processes every
resource pack found inside it.

```bash
uv run tools/optimize-resourcepacks.py minecraft/resourcepacks/
```

Output:

```text
Found 4 resource packs in resourcepacks/
==> Faithful.zip  (12.3M)
  done  8.1M  saved 4.2M
==> MyPack
  done  3.7M
==> OldPack.zip  (5.1M)
  FAILED: bad PNG signature in OldPack.zip: assets/old/textures/block/dirt.png
==> CustomPack
  done  1.2M

3/4 packs optimized successfully.
```

A pack is included in batch mode if it is a `.zip` file containing
`pack.mcmeta` or a directory containing `pack.mcmeta`.

### Self-Test

Runs an assert-based check of the integrity verifier logic. Useful after
modifying the script.

```bash
uv run tools/optimize-resourcepacks.py --selftest
```

Output on success:

```text
selftest OK
```

The self-test creates temporary ZIPs with valid and corrupted content,
verifies that `_verify_zip_integrity` accepts the good archive and rejects
the bad ones, then cleans up.

## How It Works

### Processing Pipeline

```
Input (ZIP or directory)
  |
  v
Extract/copy to temp directory
  |
  v
_unwrap() -- detect and enter single nested subdirectory
  |
  v
_remove_problematic() -- strip files PackSquash cannot handle
  |
  v
_fix_pack_metadata() -- correct pack.mcmeta for newer MC versions
  |
  v
_run() -- invoke PackSquash with generated TOML config
  |
  v
_verify_zip_integrity() -- extract and validate output
  |
  v
Output ZIP (or rollback on failure)
```

### File Sanitization

The `_remove_problematic()` function deletes files that would cause
PackSquash to fail:

**Empty or whitespace-only files:**

PackSquash attempts to parse JSON and shader files. An empty file causes a
parse error. Any file whose byte content is entirely whitespace is removed.

**Non-power-of-two PNG textures:**

Minecraft's texture atlas system requires PNG textures to have width and
height that are powers of two (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, ...).
PackSquash rejects non-compliant textures. The script reads the PNG header
(bytes 16-24 for width and height) and removes any PNG that does not meet
this requirement.

The pack icon (`pack.png`) is exempt from this rule because Minecraft
displays it at arbitrary sizes without atlas stitching.

### Pack Metadata Correction

The `_fix_pack_metadata()` function corrects `pack.mcmeta` for compatibility
with newer Minecraft versions:

**Inject `pack_format` from `min_format`:**

Resource packs targeting Minecraft 1.20.2+ may use `min_format`/`max_format`
ranges instead of a fixed `pack_format`. PackSquash expects `pack_format` to
be present. If only `min_format` exists, the script injects `pack_format`
using the first value of `min_format`.

**Add `min_format`/`max_format` to overlay entries:**

Overlays with `formats.min_inclusive`/`formats.max_inclusive` (the newer
syntax) also need `min_format`/`max_format` keys when `max_format` exceeds
64. The script adds these keys if missing.

Changes are only written back to disk if at least one correction was made.

### Integrity Verification

After PackSquash produces the output ZIP, `_verify_zip_integrity()` extracts
it to a temporary directory and validates every texture and shader file:

| File Type | Check |
|-----------|-------|
| `.png` | Must start with the PNG magic bytes (`\x89PNG\r\n\x1a\n`) |
| `.fsh`, `.vsh`, `.glsl` | Must be valid UTF-8 |
| Any texture/shader | Must not be empty (zero bytes) |

If any check fails, a `RuntimeError` is raised with the file path and failure
reason. The caller then restores the `.bak` backup.

**PackSquash ZIP obfuscation:** PackSquash can store byte-identical files
(e.g., `arrow.png` and `tipped_arrow.png`) as overlapping ZIP entries to
save space. This is valid for Minecraft's reader but rejected by Python's
strict `zipfile` module. The `_extract()` function handles this by trying 7-Zip
first (when available), then falling back to `Expand-Archive` (Windows) or `unzip`
(Linux/macOS) when `zipfile.ZipFile` raises `BadZipFile`.

### Backup and Rollback

| Mode | Backup behavior |
|------|----------------|
| ZIP input | Copies `<pack>.zip` to `<pack>.zip.bak` before overwriting |
| Directory input | If `<dir>.zip` already exists, backs it up to `<dir>.zip.bak` |
| Batch mode | Each pack is backed up independently |

**Rollback triggers:**

- PackSquash exits with a non-zero code (`CalledProcessError`)
- Integrity verification fails (`RuntimeError`)

On rollback, the `.bak` is copied back over the output. If no `.bak` exists
(directory mode with no prior output), the incomplete output file is deleted.

## Configuration

### PackSquash TOML Template

The script uses `minecraft/packsquash.toml` as a template. At runtime, it
replaces two placeholder strings:

| Placeholder | Replaced with |
|-------------|---------------|
| `pack_directory = ''` | Path to the temporary pack directory |
| `output_file_path = ''` | Path to the output ZIP |

All other settings in the template (compression level, file type handling,
etc.) are passed through unchanged.

Example template (`minecraft/packsquash.toml`):

```toml
pack_directory = ''
output_file_path = ''

[options]
zip_compression_iterations = 0
```

See the
[PackSquash documentation](https://github.com/ComunidadAylas/PackSquash/wiki)
for all available options.

### Environment Variables

The script does not read environment variables. All configuration is via
the TOML template and command-line arguments.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All packs processed successfully (or self-test passed) |
| 1 | No argument provided, target not found, PackSquash missing, no packs found in batch folder, or target is not a resource pack |

Individual pack failures in batch mode do not cause a non-zero exit code.
The script reports the success count and continues processing remaining
packs. A non-zero exit only occurs for pre-condition failures (missing
binary, invalid path, etc.).

## Examples

### Optimize a single downloaded pack

```bash
# Download a pack
wget -O ~/Downloads/MyPack.zip https://example.com/mypack.zip

# Optimize it
uv run tools/optimize-resourcepacks.py ~/Downloads/MyPack.zip
```

### Optimize all packs in the server's resourcepacks folder

```bash
uv run tools/optimize-resourcepacks.py minecraft/resourcepacks/
```

### Optimize a pack you are developing (unpacked)

```bash
uv run tools/optimize-resourcepacks.py ~/projects/MyPack/
# Produces ~/projects/MyPack.zip
```

### Verify the self-test after modifying the script

```bash
uv run tools/optimize-resourcepacks.py --selftest
```

### Re-optimize after updating PackSquash

```bash
mise upgrade packsquash
uv run tools/optimize-resourcepacks.py minecraft/resourcepacks/
```

Because the script uses the `.bak` file as source when one exists,
re-running after a PackSquash update always starts from the original
uncompressed pack, not a previously optimized one.

## Troubleshooting

### Error: packsquash not found

```text
ERROR: packsquash not found. Run: mise install
```

**Solution:** Install PackSquash via `mise install`, or download the binary
manually and place it in one of the searched locations (see
[Requirements](#requirements)).

### Error: does not appear to be a resource pack

```text
ERROR: MyFolder does not appear to be a resource pack (no pack.mcmeta)
```

**Solution:** Ensure the target contains a `pack.mcmeta` file at its root
(or at the root of a single nested subdirectory). If the target is a folder
meant for batch processing, ensure it does not itself contain `pack.mcmeta`
at the root (which would make the script treat it as a single pack).

### PackSquash fails on a specific file

If PackSquash reports an error about a specific file, the script catches
the `CalledProcessError`, restores the backup, and reports the failure.
Review the PackSquash error output for details. Common causes:

- **Corrupted PNG** - the file is not a valid PNG image
- **Invalid JSON** - a `.json` file has syntax errors
- **Unsupported format** - the file type is not recognized by PackSquash

The pre-processing step removes empty files and non-power-of-two PNGs
automatically, but other issues require manual intervention.

### Integrity verification fails after optimization

```text
FAILED: bad PNG signature in MyPack.zip: assets/mypack/textures/block/stone.png
```

**Solution:** This indicates PackSquash produced a corrupted output. The
script restores the `.bak` automatically. Try updating PackSquash or
reporting the issue to the
[PackSquash project](https://github.com/ComunidadAylas/PackSquash/issues).

### PowerShell Expand-Archive fails on Windows

This fallback only triggers when Python's `zipfile` module cannot read the
PackSquash output (due to overlapping entries). 7-Zip is tried first; if
unavailable, the script falls back to `Expand-Archive`. If all extraction
methods fail, the ZIP is genuinely corrupted. Restore from the `.bak` manually:

```powershell
Copy-Item MyPack.zip.bak MyPack.zip -Force
```
