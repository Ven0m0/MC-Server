#!/usr/bin/env bash
# Simplified Minecraft server backup tool

# Initialize strict mode
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C
user="${SUDO_USER:-${USER:-$(id -un)}}"
export HOME="/home/${user}"
SHELL="$(command -v bash 2>/dev/null || echo '/usr/bin/bash')"

# Initialize SCRIPT_DIR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# Output formatting helpers
print_header() { echo -e "\033[0;34m==>\033[0m $1"; }
print_success() { echo -e "\033[0;32m✓\033[0m $1"; }
print_error() { echo -e "\033[0;31m✗\033[0m $1" >&2; }
print_info() { echo -e "\033[1;33m→\033[0m $1"; }

# Format byte sizes to human-readable form (1G, 1M, 1K, 1B)
# Usage: format_size_bytes <size_in_bytes>
format_size_bytes() {
  local size="$1"
  # Byte conversion constants
  local KB=1024 MB=1048576 GB=1073741824
  if ((size >= GB)); then
    awk "BEGIN {printf \"%.1fG\", $size/$GB}"
  elif ((size >= MB)); then
    awk "BEGIN {printf \"%.1fM\", $size/$MB}"
  elif ((size >= KB)); then
    awk "BEGIN {printf \"%.1fK\", $size/$KB}"
  else
    echo "${size}B"
  fi
}

# Configuration
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_BACKUPS=10

# Initialize backup directories
mkdir -p "${BACKUP_DIR}/worlds" "${BACKUP_DIR}/configs"

# Backup world data
backup_world() {
  print_info "Backing up world..."
  [[ ! -d "${SCRIPT_DIR}/world" ]] && {
    print_error "No world directory found"
    return 1
  }
  cd "$SCRIPT_DIR"
  tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/ world_nether/ world_the_end/ 2>/dev/null ||
    tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/
  print_success "World backup created: world_${TIMESTAMP}.tar.gz"
}

# Backup configs
backup_configs() {
  print_info "Backing up configs..."
  cd "$SCRIPT_DIR"
  tar -czf "${BACKUP_DIR}/configs/config_${TIMESTAMP}.tar.gz" \
    --exclude='*.jar' --exclude='mods' --exclude='world*' --exclude='logs' \
    --exclude='crash-reports' --exclude='backups' \
    config/ server.properties ./*.yml ./*.yaml ./*.toml ./*.ini ./*.json ./*.json5 2>/dev/null
  print_success "Config backup created: config_${TIMESTAMP}.tar.gz"
}

# Backup mods
backup_mods() {
  print_info "Backing up mods..."
  [[ ! -d "${SCRIPT_DIR}/mods" ]] && {
    print_info "No mods directory"
    return 0
  }
  cd "$SCRIPT_DIR"
  tar -czf "${BACKUP_DIR}/configs/mods_${TIMESTAMP}.tar.gz" mods/
  print_success "Mods backup created: mods_${TIMESTAMP}.tar.gz"
}

# Clean old backups
cleanup_old_backups() {
  print_info "Cleaning old backups (keeping last ${MAX_BACKUPS})..."
  for dir in worlds configs; do
    local backup_path="${BACKUP_DIR}/${dir}"
    [[ ! -d "$backup_path" ]] && continue
    # Single find call that counts and cleans in one pass
    local files
    mapfile -t files < <(find "$backup_path" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n -"$MAX_BACKUPS" | cut -d' ' -f2-)
    if [[ ${#files[@]} -gt 0 ]]; then
      printf '%s\0' "${files[@]}" | xargs -0 rm -f 2>/dev/null || true
    fi
  done
  print_success "Cleanup complete"
}

# List backups
list_backups() {
  print_header "Available backups"
  echo ""
  echo "World Backups:"
  # Use -printf for efficiency instead of calling du in a loop
  while IFS='|' read -r size_bytes name; do
    local size
    size=$(format_size_bytes "$size_bytes")
    echo "  ${name} (${size})"
  done < <(find "${BACKUP_DIR}/worlds" -name "*.tar.gz" -type f -printf '%s|%f\n' 2>/dev/null | sort -t'|' -k1 -rn | head -10)
  echo ""
  echo "Config Backups:"
  while IFS='|' read -r size_bytes name; do
    local size
    size=$(format_size_bytes "$size_bytes")
    echo "  ${name} (${size})"
  done < <(find "${BACKUP_DIR}/configs" -name "*.tar.gz" -type f -printf '%s|%f\n' 2>/dev/null | sort -t'|' -k1 -rn | head -10)
}

# Restore backup
restore_backup() {
  local file="$1"
  [[ ! -f $file ]] && {
    print_error "File not found: $file"
    exit 1
  }
  print_info "Restoring: $(basename "$file")"
  read -r -p "This will overwrite existing data. Continue? (yes/no): " confirm
  [[ $confirm != "yes" ]] && {
    print_info "Cancelled"
    exit 0
  }
  cd "$SCRIPT_DIR"
  tar -xzf "$file"
  print_success "Restore complete"
}

# Show usage
show_usage() {
  cat <<EOF
Minecraft Server Backup Tool

Usage: $0 [command] [options]

Commands:
    backup [world|config|mods|all]  Create backup (default: all)
    list                            List backups
    restore <file>                  Restore backup
    cleanup                         Clean old backups
    help                            Show this help

Options:
    --max-backups <num>            Keep N backups (default: 10)

Examples:
    $0 backup
    $0 backup world
    $0 list
    $0 restore backups/worlds/world_20250119_120000.tar.gz
EOF
}

# Main
case "${1:-backup}" in
backup)
  case "${2:-all}" in
  world) backup_world ;;
  config) backup_configs ;;
  mods) backup_mods ;;
  all | *)
    backup_world
    backup_configs
    backup_mods
    ;;
  esac
  cleanup_old_backups
  ;;
list) list_backups ;;
restore) restore_backup "$2" ;;
cleanup) cleanup_old_backups ;;
help | --help | -h) show_usage ;;
*)
  print_error "Unknown command: $1"
  show_usage
  exit 1
  ;;
esac
