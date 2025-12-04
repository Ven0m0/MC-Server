# Config Format/Lint/Autofix Script

A comprehensive script for formatting, linting, and minifying JSON and YAML
configuration files.

## Features

- **JSON Formatting**: Pretty-print with jq using 2-space indentation
- **JSON Minification**: Remove all unnecessary whitespace
- **YAML Formatting**: Format YAML files with yamlfmt or yq
- **Parallel Processing**: Utilize multi-core systems for faster processing
- **Validation**: Check config files for syntax errors
- **Smart Exclusions**: Skip node_modules, .git, build artifacts, and lock files
- **Size Reporting**: Track file size changes during minification

## Installation

### Required Dependencies

```bash
# Install jq (required for JSON)
sudo apt-get install jq
# or
brew install jq
```

### Optional Dependencies

```bash
# Install mikefarah/yq for YAML formatting
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Or install yamlfmt (recommended for YAML)
go install github.com/google/yamlfmt/cmd/yamlfmt@latest

# Install GNU Parallel for faster processing
sudo apt-get install parallel
# or
brew install parallel
```

## Usage

### Basic Usage

```bash
# Format all config files in the project
./scripts/format-config.sh

# Format configs in a specific directory
./scripts/format-config.sh config/

# Check formatting without making changes (CI mode)
./scripts/format-config.sh --mode check

# Minify configs (remove whitespace)
./scripts/format-config.sh --mode minify

# Dry run to see what would be done
./scripts/format-config.sh --dry-run --verbose
```

### Advanced Options

```bash
# Use custom number of parallel jobs
./scripts/format-config.sh --jobs 8

# Verbose output
./scripts/format-config.sh --verbose

# Combine options
./scripts/format-config.sh --mode check --verbose config/
```

## Operation Modes

### Format Mode (default)

Pretty-prints JSON and YAML files with proper indentation:

```bash
./scripts/format-config.sh --mode format
```

**Before:**

```json
{ "key1": true, "key2": "value", "nested": { "item": 123 } }
```

**After:**

```json
{
  "key1": true,
  "key2": "value",
  "nested": {
    "item": 123
  }
}
```

### Minify Mode

Removes all unnecessary whitespace to reduce file size:

```bash
./scripts/format-config.sh --mode minify
```

**Before:**

```json
{
  "key1": true,
  "key2": "value"
}
```

**After:**

```json
{ "key1": true, "key2": "value" }
```

### Check Mode (CI/CD)

Validates formatting without making changes. Exits with code 1 if any files need
formatting:

```bash
./scripts/format-config.sh --mode check
```

Use this in CI/CD pipelines to enforce formatting standards.

## GitHub Actions Workflow

The script is integrated into a GitHub Actions workflow that:

1. **Automatically validates** formatting on all PRs
1. **Auto-fixes** formatting on pushes to main/claude branches
1. **Comments on PRs** when formatting is needed
1. **Validates JSON/YAML** syntax separately

### Workflow Features

- Triggers on changes to config files
- Installs all required dependencies
- Runs in check mode for PRs
- Auto-commits fixes for direct pushes
- Supports manual trigger with mode selection

### Manual Workflow Trigger

You can manually trigger the workflow with different modes:

1. Go to Actions → Config Format & Lint
1. Click "Run workflow"
1. Select mode: check, format, or minify

## Exclusions

The script automatically excludes:

### Directories

- `.git`
- `node_modules`
- `dist`, `build`
- `__pycache__`, `.venv`
- `vendor`, `target`, `.gradle`

### Files

- `*.min.json`, `*.min.yml`, `*.min.yaml` (already minified)
- `*-lock.json`, `package-lock.json`, `yarn.lock` (lock files)

## Examples

### Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
./scripts/format-config.sh --mode check || {
    echo "Config files need formatting. Run: ./scripts/format-config.sh"
    exit 1
}
```

### CI Integration

```yaml
- name: Check config formatting
  run: ./scripts/format-config.sh --mode check --verbose
```

### Minify for Production

```bash
# Create minified versions for production
./scripts/format-config.sh --mode minify dist/config/
```

## Troubleshooting

### YAML Formatting Skipped

If you see warnings about YAML formatting being skipped:

1. Install mikefarah/yq (recommended):

   ```bash
   wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
   chmod +x /usr/local/bin/yq
   ```

1. Or install yamlfmt:

   ```bash
   go install github.com/google/yamlfmt/cmd/yamlfmt@latest
   ```

### Performance Issues

For large repositories:

```bash
# Increase parallel jobs (default: 4)
./scripts/format-config.sh --jobs 8

# Process only specific directory
./scripts/format-config.sh config/
```

## Inspiration

This script incorporates concepts from:

- [Ven0m0/Linux-OS minify.sh](https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/Scripts/other/minify.sh)
- Production-ready error handling and reporting
- Multi-tool fallback support
- Parallel processing capabilities

## License

Same as parent project.
