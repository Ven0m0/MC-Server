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
print_header() { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_error() { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_info() { printf '\033[1;33m→\033[0m %s\n' "$1"; }

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
    printf '%dB' "$size"
  fi
}

# Configuration
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(printf '%(%Y%m%d_%H%M%S)T' -1)
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
  tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/ world_nether/ world_the_end/ 2>/dev/null \
    || tar -czf "${BACKUP_DIR}/worlds/world_${TIMESTAMP}.tar.gz" world/
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
    [[ ! -d $backup_path ]] && continue
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
  printf '\n'
  printf 'World Backups:\n'
  # Use -printf for efficiency instead of calling du in a loop
  while IFS='|' read -r size_bytes name; do
    local size
    size=$(format_size_bytes "$size_bytes")
    printf '  %s (%s)\n' "$name" "$size"
  done < <(find "${BACKUP_DIR}/worlds" -name "*.tar.gz" -type f -printf '%s|%f\n' 2>/dev/null | sort -t'|' -k1 -rn | head -10)
  printf '\n'
  printf 'Config Backups:\n'
  while IFS='|' read -r size_bytes name; do
    local size
    size=$(format_size_bytes "$size_bytes")
    printf '  %s (%s)\n' "$name" "$size"
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

# Check if path is on Btrfs filesystem
is_btrfs() {
  local path="${1:-${SCRIPT_DIR}}"
  [[ $(stat -f -c %T "$path" 2>/dev/null) == "btrfs" ]]
}

# Create Btrfs snapshot
create_btrfs_snapshot() {
  local source="${1:-${SCRIPT_DIR}/world}"
  local snapshot_name="${2:-snapshot_${TIMESTAMP}}"

  [[ ! -d $source ]] && {
    print_error "Source directory not found: ${source}"
    return 1
  }

  is_btrfs "$source" || {
    print_error "Source is not on Btrfs filesystem"
    print_info "Use regular backup instead"
    return 1
  }

  command -v btrfs &>/dev/null || {
    print_error "btrfs command not found"
    return 1
  }

  local snapshot_dir="${BACKUP_DIR}/btrfs-snapshots"
  mkdir -p "$snapshot_dir"

  local snapshot_path="${snapshot_dir}/${snapshot_name}"

  print_info "Creating Btrfs snapshot: ${snapshot_name}"

  if [[ $EUID -eq 0 ]]; then
    btrfs subvolume snapshot -r "$source" "$snapshot_path"
  else
    sudo btrfs subvolume snapshot -r "$source" "$snapshot_path" || {
      print_error "Failed to create snapshot (root access required)"
      return 1
    }
  fi

  print_success "Btrfs snapshot created: ${snapshot_path}"
}

# List Btrfs snapshots
list_btrfs_snapshots() {
  local snapshot_dir="${BACKUP_DIR}/btrfs-snapshots"

  [[ ! -d $snapshot_dir ]] && {
    print_info "No Btrfs snapshots found"
    return 0
  }

  print_header "Btrfs Snapshots"
  printf '\n'

  command -v btrfs &>/dev/null || {
    print_error "btrfs command not found"
    return 1
  }

  # List subvolumes
  if [[ $EUID -eq 0 ]]; then
    btrfs subvolume list "$snapshot_dir" 2>/dev/null || {
      # Fallback: just list directories
      find "$snapshot_dir" -maxdepth 1 -type d -name "snapshot_*" -printf '%f\n' | sort
    }
  else
    # Non-root: just list directories
    find "$snapshot_dir" -maxdepth 1 -type d -name "snapshot_*" -printf '%f\n' | sort
  fi
}

# Delete Btrfs snapshot
delete_btrfs_snapshot() {
  local snapshot_name="$1"
  local snapshot_dir="${BACKUP_DIR}/btrfs-snapshots"
  local snapshot_path="${snapshot_dir}/${snapshot_name}"

  [[ ! -d $snapshot_path ]] && {
    print_error "Snapshot not found: ${snapshot_name}"
    return 1
  }

  command -v btrfs &>/dev/null || {
    print_error "btrfs command not found"
    return 1
  }

  print_info "Deleting Btrfs snapshot: ${snapshot_name}"
  read -r -p "Continue? (yes/no): " confirm
  [[ $confirm != "yes" ]] && {
    print_info "Cancelled"
    return 0
  }

  if [[ $EUID -eq 0 ]]; then
    btrfs subvolume delete "$snapshot_path"
  else
    sudo btrfs subvolume delete "$snapshot_path" || {
      print_error "Failed to delete snapshot (root access required)"
      return 1
    }
  fi

  print_success "Snapshot deleted"
}

# Restore Btrfs snapshot
restore_btrfs_snapshot() {
  local snapshot_name="$1"
  local target="${2:-${SCRIPT_DIR}/world}"
  local snapshot_dir="${BACKUP_DIR}/btrfs-snapshots"
  local snapshot_path="${snapshot_dir}/${snapshot_name}"

  [[ ! -d $snapshot_path ]] && {
    print_error "Snapshot not found: ${snapshot_name}"
    return 1
  }

  command -v btrfs &>/dev/null || {
    print_error "btrfs command not found"
    return 1
  }

  print_info "Restoring Btrfs snapshot: ${snapshot_name} -> ${target}"
  read -r -p "This will overwrite existing data. Continue? (yes/no): " confirm
  [[ $confirm != "yes" ]] && {
    print_info "Cancelled"
    return 0
  }

  # Backup current if exists
  [[ -d $target ]] && {
    local backup_name="${target}.pre-restore.${TIMESTAMP}"
    print_info "Backing up current to: ${backup_name}"
    mv "$target" "$backup_name"
  }

  # Create new snapshot from read-only snapshot
  if [[ $EUID -eq 0 ]]; then
    btrfs subvolume snapshot "$snapshot_path" "$target"
  else
    sudo btrfs subvolume snapshot "$snapshot_path" "$target" || {
      print_error "Failed to restore snapshot (root access required)"
      return 1
    }
  fi

  print_success "Snapshot restored"
}

# Show usage
show_usage() {
  cat <<EOF
Minecraft Server Backup Tool

Usage: $0 [command] [options]

Commands:
    Tar-based Backups:
        backup [world|config|mods|all]  Create backup (default: all)
        list                            List backups
        restore <file>                  Restore backup
        cleanup                         Clean old backups

    Btrfs Snapshots (requires Btrfs filesystem):
        snapshot [source] [name]        Create Btrfs snapshot
        snapshot-list                   List Btrfs snapshots
        snapshot-restore <name> [dest]  Restore Btrfs snapshot
        snapshot-delete <name>          Delete Btrfs snapshot

    Info:
        help                            Show this help

Options:
    --max-backups <num>            Keep N backups (default: 10)

Examples:
    # Tar backups
    $0 backup
    $0 backup world
    $0 list
    $0 restore backups/worlds/world_20250119_120000.tar.gz

    # Btrfs snapshots
    $0 snapshot
    $0 snapshot ./world my-snapshot
    $0 snapshot-list
    $0 snapshot-restore my-snapshot ./world
    $0 snapshot-delete old-snapshot

Notes:
    - Btrfs snapshots require btrfs-progs and root/sudo access
    - Btrfs snapshots are instant and space-efficient
    - Tar backups work on any filesystem
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
  snapshot) create_btrfs_snapshot "${2:-}" "${3:-}" ;;
  snapshot-list) list_btrfs_snapshots ;;
  snapshot-restore) restore_btrfs_snapshot "$2" "${3:-}" ;;
  snapshot-delete) delete_btrfs_snapshot "$2" ;;
  help | --help | -h) show_usage ;;
  *)
    print_error "Unknown command: $1"
    show_usage
    exit 1
    ;;
esac
