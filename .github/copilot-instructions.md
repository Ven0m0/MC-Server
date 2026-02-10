# GitHub Copilot Instructions - MC-Server

## Core Principles

1. **User cmds > Rules** - User instructions override all rules
2. **Edit > Create** - Minimize diffs, prefer editing existing files
3. **Subtraction > Addition** - Remove unnecessary code, avoid bloat
4. **Align w/ existing patterns** - Match codebase style consistently

---

## Project Context

**Type:** Minecraft Fabric server management suite
**Language:** Bash 5.0+ (100% shell scripts)
**Runtime:** Java 21+ (GraalVM/Temurin) + Minecraft 1.21.5
**Purpose:** Production server automation (start/stop, backup, monitor, optimize)

### Key Directories

```
tools/        - 13 shell scripts for server mgmt
minecraft/    - Server data (worlds, mods, config, backups)
docs/         - Setup, troubleshooting, hosting guides
.github/      - CI/CD workflows (MegaLinter, PackSquash, Dependabot)
```

### Critical Files

| File | Purpose |
|------|---------|
| `tools/server-start.sh` | Main launcher w/ JVM optimization |
| `tools/backup.sh` | Multi-strategy backups (tar, rustic, btrfs) |
| `tools/monitor.sh` | Health checks, TPS, resource metrics |
| `tools/common.sh` | Shared utils (logging, colors, validation) |
| `server.toml` | Minecraft server cfg (mcman format) |
| `mise.toml` | Tool versioning (PackSquash, Rustic, ChunkCleaner) |

---

## Bash Standards

### Script Template

```bash
#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'

source "${PWD}/tools/common.sh"

: "${VAR:=default}"  # Config w/ defaults

main() {
  local var="val"
  # Logic
}

main "$@"
```

### Style Rules

| Rule | Value |
|------|-------|
| **Indent** | 2 spaces (no tabs) |
| **Line End** | LF (Unix) |
| **Max Line** | 120 chars |
| **Quotes** | Always: `"$var"` not `$var` |
| **Naming** | `snake_case` (local), `SCREAMING_SNAKE` (global) |

### Required Idioms

```bash
# Conditionals: [[ ]] not [ ]
[[ -f "$file" ]] && process "$file"

# Arithmetic: (( )) not expr
(( count++ )); (( total += count ))

# Loops: while IFS= read -r
while IFS= read -r line; do
  process "$line"
done < file

# Arrays: mapfile
mapfile -t arr < <(cmd)
for item in "${arr[@]}"; do
  echo "$item"
done

# Capture: $() not backticks
result=$(cmd)

# Local refs
local -n ref="$1"
```

### Banned Patterns

```bash
# ❌ DON'T
for f in $(ls); do          # Parse ls output
eval "$cmd"                 # Security risk
result=`cmd`                # Backticks
rm -rf $dir/*               # Unquoted vars
grep -r "pattern" .         # Use Grep tool instead

# ✅ DO
for f in *.txt; do          # Glob
"$cmd"                      # Direct execution
result=$(cmd)               # $() substitution
rm -rf "$dir"/*             # Quoted
# Use dedicated tools/functions
```

### Output Functions

From `tools/common.sh`:

```bash
print_header "Task"     # Blue "==> Task"
print_success "Done"    # Green "✓ Done"
print_error "Failed"    # Red "✗ Failed" → stderr
print_info "Status"     # Yellow "→ Status"
```

---

## Code Patterns

### Error Handling

```bash
# Strict mode (required)
set -euo pipefail

# Explicit checks
if ! cmd; then
  print_error "Failed"
  exit 1
fi

# Cleanup
trap cleanup EXIT
```

### Variable Safety

```bash
# Always quote
echo "$var"
rm -rf "$dir"/*
command "$arg1" "$arg2"

# Default values
: "${VAR:=default}"
: "${PORT:=25565}"

# Required vars
: "${VAR:?Missing VAR}"
```

### Function Style

```bash
# Definition
do_thing() {
  local param="$1"
  local result

  # Logic
  result=$(compute "$param")

  # Output
  printf '%s\n' "$result"
}

# Usage
output=$(do_thing "input")
```

---

## ShellCheck Compliance

**Config:** `.shellcheckrc` enables all rules, warnings as errors

**Common fixes:**
- Quote vars: `"$var"` not `$var`
- Use `[[ ]]` not `[ ]`
- Declare `local` in functions
- Use `$()` not backticks
- Check cmd existence: `command -v prog >/dev/null 2>&1`

---

## Project-Specific Patterns

### Server Operations

```bash
# Start server
./tools/server-start.sh

# With proxy
./tools/server-start.sh --proxy lazymc

# Console
./tools/mc-client.sh attach
./tools/mc-client.sh send "cmd"

# RCON
./tools/rcon.sh "cmd"
```

### Backup Patterns

```bash
# Create
./tools/backup.sh backup name
./tools/backup.sh backup --rustic   # Deduplicated
./tools/backup.sh backup --btrfs    # COW snapshot

# Restore
./tools/backup.sh restore name.tar.gz
./tools/backup.sh list
```

### Monitoring

```bash
# Status
./tools/monitor.sh status   # Full report
./tools/monitor.sh watch    # Continuous
./tools/monitor.sh alert    # Health check
```

---

## Config Files

| File | Type | Purpose |
|------|------|---------|
| `server.toml` | TOML | Minecraft server settings |
| `mise.toml` | TOML | Tool installation |
| `.editorconfig` | INI | Code formatting |
| `.megalinter.yml` | YAML | Linting rules |
| `.shellcheckrc` | RC | Bash validation |
| `minecraft/config/*.{yml,json}` | YAML/JSON | Mod configurations |

---

## Toolchain

**Prefer:**
- `jaq` → `jq` (JSON)
- `aria2c` → `curl` (downloads)
- `fd` → `find` (file search)
- `rg` → `grep` (content search)
- `bat` → `cat` (syntax highlight)

**Required:**
- Bash 5.0+
- Java 21+
- curl/wget
- tar/gzip

**Optional:**
- jq/jaq (JSON)
- aria2c (parallel DL)
- mise (tool mgmt)

---

## Performance Tips

### Script Optimization

```bash
# ✅ Minimize forks
while IFS= read -r line; do
  process "$line"
done < file

# ❌ Fork per line
cat file | while read line; do
  process "$line"
done

# ✅ Batch ops
mapfile -t lines < file
for line in "${lines[@]}"; do
  process "$line"
done

# ✅ Builtins over externals
[[ $a -eq $b ]]     # not [ $a -eq $b ]
(( total += val ))  # not total=$((total + val))
```

### Regex Optimization

```bash
# ✅ Anchor patterns
^pattern$           # Full match
^start.*end$        # Start + end

# ✅ Literal search
grep -F "literal"   # Faster than regex
```

---

## CI/CD Integration

**Workflows:**
- `mega-linter.yml` - Bash, YAML, JSON, Markdown linting
- `image-optimization.yml` - PNG/JPG/SVG compression
- `packsquash.yml` - Resource pack validation
- `automerge-dependabot.yml` - Auto-merge deps

**Local testing:**
```bash
mega-linter --flavor bash
shellcheck tools/*.sh
bash -n tools/*.sh
```

---

## Documentation Standards

### Inline Comments

```bash
# Explain WHY not WHAT
backup_dir="/var/backups"  # Needed for restore validation

# Complex logic only
# Extract player UUIDs from server logs for whitelist sync
grep -oP 'UUID of player \K[a-f0-9-]+' logs/latest.log
```

### Function Headers

```bash
# backup_world - Creates tar archive of world directory
#   $1: World name (e.g., "world", "world_nether")
#   $2: Backup name (optional, defaults to timestamp)
# Returns: Path to created backup archive
backup_world() {
  # Implementation
}
```

### README Updates

When adding features:
1. Update `README.md` tool section
2. Add to "Quick Start" if user-facing
3. Update `TODO.md` to track enhancements
4. Document in `docs/SETUP.md` if setup-related

---

## Common Tasks

### Adding New Script

```bash
# 1. Create in tools/
cat > tools/new.sh << 'EOF'
#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
source "${PWD}/tools/common.sh"

main() {
  print_header "New Task"
  # Logic
}

main "$@"
EOF

# 2. Test
chmod +x tools/new.sh
bash -n tools/new.sh
shellcheck tools/new.sh

# 3. Document in README.md
```

### Debugging

```bash
# Enable debug
export DEBUG=true
./tools/script.sh

# Trace execution
bash -x tools/script.sh

# Check systemd
journalctl -u minecraft@default -f
```

---

## Tone & Style

- **Blunt, factual, precise** - No fluff
- **Result-first** - Answer then explain
- **Lists ≤7 items** - Break up large lists
- **Abbr OK** - cfg, impl, deps, val, opt, Δ
- **Strip invisible chars** - U+202F, U+200B, U+00AD

---

## Quick Reference

**Essential Commands:**
```bash
./tools/prepare.sh              # Setup
./tools/server-start.sh         # Start
./tools/mc-client.sh attach     # Console
./tools/monitor.sh status       # Health
./tools/backup.sh backup all    # Backup
```

**Key Patterns:**
```bash
source tools/common.sh          # Always source utils
: "${VAR:=default}"             # Config defaults
[[ condition ]] && action       # Safe conditionals
mapfile -t arr < <(cmd)         # Array capture
while IFS= read -r; do          # Line iteration
```

**ShellCheck:**
```bash
shellcheck tools/*.sh           # Validate all
bash -n script.sh               # Syntax check
```

---

**Last Updated:** 2026-02-10 (Optimized for GitHub Copilot)
