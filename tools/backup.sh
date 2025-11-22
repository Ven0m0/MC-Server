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
print_header(){ echo -e "\033[0;34m==>\033[0m $1"; }
print_success(){ echo -e "\033[0;32m✓\033[0m $1"; }
print_error(){ echo -e "\033[0;31m✗\033[0m $1" >&2; }
print_info(){ echo -e "\033[1;33m→\033[0m $1"; }

# Configuration
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_BACKUPS=10

# Initialize backup directories
mkdir -p "${BACKUP_DIR}/worlds" "${BACKUP_DIR}/configs"

# Backup world data
backup_world(){
  print_info "Backing up world..."
  [[ ! -d "${SCRIPT_DIR}/world" ]] && { print_error "No world directory found"; return 1; }
  cd "${SCRIPT_DIR}"
  tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/ world_nether/ world_the_end/ 2>/dev/null \
    || tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/
  print_success "World backup created: world_${TIMESTAMP}.tar.gz"
}

# Backup configs
backup_configs(){
  print_info "Backing up configs..."
  cd "${SCRIPT_DIR}"
  tar -czf "${BACKUP_DIR}/configs/config_${TIMESTAMP}.tar.gz" \
    --exclude='*.jar' --exclude='mods' --exclude='world*' --exclude='logs' \
    --exclude='crash-reports' --exclude='backups' \
    config/ server.properties *.yml *.yaml *.toml *.ini *.json *.json5 2>/dev/null
  print_success "Config backup created: config_${TIMESTAMP}.tar.gz"
}

# Backup mods
backup_mods(){
  print_info "Backing up mods..."
  [[ ! -d "${SCRIPT_DIR}/mods" ]] && { print_info "No mods directory"; return 0; }
  cd "${SCRIPT_DIR}"
  tar -czf "${BACKUP_DIR}/configs/mods_${TIMESTAMP}.tar.gz" mods/
  print_success "Mods backup created: mods_${TIMESTAMP}.tar.gz"
}

# Clean old backups
cleanup_old_backups(){
  print_info "Cleaning old backups (keeping last ${MAX_BACKUPS})..."
  for dir in worlds configs; do
    local count=$(find "${BACKUP_DIR}/${dir}" -name "*.tar.gz" 2>/dev/null | wc -l)
    (( count > MAX_BACKUPS )) && {
      find "${BACKUP_DIR}/${dir}" -name "*.tar.gz" -type f -printf '%T@ %p\n' \
        | sort -n | head -n -"${MAX_BACKUPS}" | cut -d' ' -f2- | xargs rm -f
    }
  done
  print_success "Cleanup complete"
}

# List backups
list_backups(){
  print_header "Available backups"
  echo ""
  echo "World Backups:"
  find "${BACKUP_DIR}/worlds" -name "*.tar.gz" 2>/dev/null | sort -r | head -10 | while read -r f; do
    echo "  $(basename "$f") ($(du -h "$f" | cut -f1))"
  done
  echo ""
  echo "Config Backups:"
  find "${BACKUP_DIR}/configs" -name "*.tar.gz" 2>/dev/null | sort -r | head -10 | while read -r f; do
    echo "  $(basename "$f") ($(du -h "$f" | cut -f1))"
  done
}

# Restore backup
restore_backup(){
  local file="$1"
  [[ ! -f $file ]] && { print_error "File not found: $file"; exit 1; }
  print_info "Restoring: $(basename "$file")"
  read -p "This will overwrite existing data. Continue? (yes/no): " confirm
  [[ $confirm != "yes" ]] && { print_info "Cancelled"; exit 0; }
  cd "${SCRIPT_DIR}"
  tar -xzf "$file"
  print_success "Restore complete"
}

# Show usage
show_usage(){
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
