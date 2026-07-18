# Mod Jar Compression

Notes on shrinking `.jar` files in `minecraft/mods/` — smaller mod jars mean
less disk I/O and faster world/resource reloads. This is a companion to
[OPTIMIZE-RESOURCEPACKS.md](OPTIMIZE-RESOURCEPACKS.md), which covers the same
idea for resource pack ZIPs via PackSquash.

## Table of Contents

- [mc-repack (primary tool)](#mc-repack-primary-tool)
  - [Already wired into this repo](#already-wired-into-this-repo)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Config reference](#config-reference)
  - [Benchmarks](#benchmarks)
- [Alternatives](#alternatives)
  - [AdvanceCOMP (advzip)](#advancecomp-advzip)
  - [TinyModPack](#tinymodpack)
- [Recommendation](#recommendation)

## mc-repack (primary tool)

[**mc-repack**](https://github.com/szeweq/mc-repack) (Rust, by `szeweq`) is a
repacking tool built specifically for Minecraft mods and resource packs. Unlike
a raw re-deflate, it understands the file types inside a mod jar and optimizes
each one:

- Minifies and strips comments from JSON (`serde-json`)
- Re-encodes PNGs with `oxipng`
- Optimizes TOML and NBT files
- Optimizes OGG audio with `optivorbis`
- Removes accidentally-packed junk (Blender/Photoshop project files, etc.)
- Strips Unicode BOM and comment lines from `.cfg`, `.obj`, `.mtl`, `.zs`,
  `.vsh`, `.fsh`
- Recompresses remaining entries, optionally with Zopfli (slower, smaller)
- Skips compressing small files where the "compressed" form would end up
  larger than the original (also loads faster uncompressed)

### Already wired into this repo

`tools/mod-updates.py` has a `setup-repack` command that writes
`~/.config/mc-repack.toml` with this project's chosen settings:

```toml
[json]
remove_underscored = true
[nbt]
use_zopfli = true
[png]
use_zopfli = true
[toml]
strip_strings = true
[jar]
keep_dirs = false
use_zopfli = true
```

```bash
./tools/mod-updates.py setup-repack     # write/refresh the config
./tools/mod-updates.py full-update      # includes setup-repack as one step
```

**Gap:** `setup-repack` only writes the config file — it does not invoke
`mc-repack` against `minecraft/mods/`. Run the tool manually (see
[Usage](#usage)) after `setup-repack`, or after adding new mods via Ferium.

### Installation

```bash
cargo install mc-repack
# or, latest commit:
cargo install --git https://github.com/szeweq/mc-repack
```

Prebuilt binaries: [Releases page](https://github.com/szeweq/mc-repack/releases/latest).

### Usage

```bash
mc-repack jars --in minecraft/mods --out minecraft/mods-repacked
```

- `jars` operates on `.jar`/`.zip` entries (this is the subcommand for mods).
- `files` transforms an unpacked file tree directly (useful for resource
  pack directories instead of PackSquash, if preferred).
- A directory input processes every file inside it (non-recursive).
- `mc-repack --help` lists all flags.

Always output to a separate directory first (`mods-repacked/`), sanity-check
the server boots against it, then swap it in for `minecraft/mods/` — mc-repack
itself warns that some parse errors it reports (e.g. "trailing comma at line
X column Y") are informational and safe to ignore, but a repacked jar should
still be smoke-tested before replacing the original.

### Config reference

| Section | Key | Effect |
|---------|-----|--------|
| `[json]` | `remove_underscored` | Strips keys/comments starting with `_` (common "comment" convention in MC JSON) |
| `[nbt]` | `use_zopfli` | Zopfli-recompress NBT entries instead of default Deflate |
| `[png]` | `use_zopfli` | Zopfli-recompress PNG IDAT chunks via `oxipng` |
| `[toml]` | `strip_strings` | Removes redundant string quoting/whitespace |
| `[jar]` | `keep_dirs` | Whether to preserve empty directory entries in the output jar |
| `[jar]` | `use_zopfli` | Zopfli-recompress the jar's own ZIP central directory entries |

Zopfli options trade compression time for a smaller result (see
[Benchmarks](#benchmarks)) — fine for a one-off repack pass, not for
something run on every server start.

### Benchmarks

From the project README, real mod jars before/after (0.21, Zopfli):

| Mod | Original | Repacked | Saved |
|-----|---------:|---------:|------:|
| minecolonies-1.19.2-1.0.1247-BETA.jar | 72.8 MB | 62.7 MB | ~14% |
| twilightforest-1.19.3-4.2.1549-universal.jar | 22.5 MB | 21.2 MB | ~6% |
| TConstruct-1.18.2-3.6.3.111.jar | 15.2 MB | 13.6 MB | ~11% |
| BloodMagic-1.18.2-3.2.6-41.jar | 13.6 MB | 11.6 MB | ~15% |
| ImmersiveEngineering-1.19.3-9.3.0-163.jar | 10.3 MB | 9.46 MB | ~8% |

More samples: [szeweq.xyz/mc-repack/mods](https://szeweq.xyz/mc-repack/mods).

## Alternatives

Considered these when researching mc-repack; keeping notes here in case
mc-repack ever breaks on a specific mod and a fallback is needed.

### AdvanceCOMP (`advzip`)

Generic ZIP/jar re-deflate using Zopfli-grade search, no file-type awareness
(won't touch PNG/JSON/NBT internals like mc-repack does — just re-compresses
the raw bytes already in each entry).

```bash
advzip --recompress -4 --iter 4 minecraft/mods/somemod.jar
```

Lossless, no bytecode/content changes, but slower for the same or smaller
gain than mc-repack since it doesn't know what's inside the entries. Fine as
a last-resort fallback, not a first choice.

### TinyModPack

[stanhebben/TinyModPack](https://github.com/stanhebben/TinyModPack) — older
modpack packager with an optional recompress flag that unpacks each mod jar
and re-encodes with LZMA. ~25% size reduction reported, but its own docs warn
recompressed jars aren't byte-identical and a few mods misbehave when
repacked. mc-repack is the actively maintained, Minecraft-file-type-aware
option; only worth reaching for TinyModPack if mc-repack doesn't cover a
specific packaging need.

## Recommendation

Use mc-repack. It's already configured in this repo (`tools/mod-updates.py
setup-repack`) and is purpose-built for Minecraft jar internals rather than a
blind re-deflate. Run it into a separate output directory, verify the server
starts and mods behave, then swap it into `minecraft/mods/`.
