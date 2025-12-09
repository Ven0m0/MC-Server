#!/usr/bin/env bash
# Simplified Minecraft server backup tool
# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# Configuration
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(printf '%(%Y%m%d_%H%M%S)T' -1)
MAX_BACKUPS=10
# Rustic Configuration
RUSTIC_VERSION="${RUSTIC_VERSION:-0.10.2}"
RUSTIC_REPO="${RUSTIC_REPO:-${BACKUP_DIR}/rustic}"
RUSTIC_PASS_FILE="${BACKUP_DIR}/.rustic_pass"
RUSTIC_BIN="${SCRIPT_DIR}/tools/rustic"
# Export for rustic to use implicitly
export RUSTIC_REPOSITORY="$RUSTIC_REPO"
export RUSTIC_PASSWORD_FILE="$RUSTIC_PASS_FILE"
# Initialize backup directories
mkdir -p "${BACKUP_DIR}/worlds" "${BACKUP_DIR}/configs"
# ----------------------------------------------------------------------------
# RUSTIC FUNCTIONS
# ----------------------------------------------------------------------------
# Install rustic binary
install_rustic() {
  if [[ -f "$RUSTIC_BIN" ]]; then return 0; fi
  if has_command rustic; then
    RUSTIC_BIN="rustic"; return 0
  fi
  print_info "Installing rustic v${RUSTIC_VERSION}..."
  local arch
  arch=$(detect_arch) || return 1
  local target=""
  case "$arch" in
    x86_64) target="x86_64-unknown-linux-gnu" ;;
    aarch64) target="aarch64-unknown-linux-musl" ;;
    armv7) target="armv7-unknown-linux-musleabihf" ;;
    *) print_error "Unsupported arch for rustic download: $arch"; return 1 ;;
  esac
  local url="https://github.com/rustic-rs/rustic/releases/download/v${RUSTIC_VERSION}/rustic-v${RUSTIC_VERSION}-${target}.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  download_file "$url" "${tmp_dir}/rustic.tar.gz" || return 1
  tar -xzf "${tmp_dir}/rustic.tar.gz" -C "$tmp_dir" || return 1
  # Binary name might vary in tarball, find executable
  local bin_found
  bin_found=$(find "$tmp_dir" -type f -name "rustic" -o -name "rustic-*" | head -1)
  if [[ -f "$bin_found" ]]; then
    mv "$bin_found" "$RUSTIC_BIN"
    chmod +x "$RUSTIC_BIN"
    rm -rf "$tmp_dir"
    print_success "Rustic installed to $RUSTIC_BIN"
  else
    print_error "Could not find rustic binary in archive"
    rm -rf "$tmp_dir"
    return 1
  fi
}
# Wrapper for rustic command
rustic_cmd() {
  install_rustic || exit 1
  "$RUSTIC_BIN" "$@"
}
# Initialize rustic repository
rustic_init() {
  mkdir -p "$RUSTIC_REPO"
  if [[ ! -f "$RUSTIC_PASS_FILE" ]]; then
    print_info "Generating rustic password..."
    tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > "$RUSTIC_PASS_FILE"
    chmod 600 "$RUSTIC_PASS_FILE"
  fi
  if [[ -z "$(ls -A "$RUSTIC_REPO" 2>/dev/null)" ]]; then
    print_info "Initializing rustic repo at ${RUSTIC_REPO}..."
    rustic_cmd init
    print_success "Repository initialized"
  else
    print_info "Rustic repo already exists"
  fi
}
# Perform rustic backup
rustic_backup() {
  local tag="${1:-manual}"
  rustic_init
  print_header "Running Rustic Backup"
  print_info "Source: ${SCRIPT_DIR}"
  print_info "Repo: ${RUSTIC_REPO}"
  cd "$SCRIPT_DIR" || exit 1
  # Backup everything except cache/artifacts
  # Rustic deduplication makes this efficient
  rustic_cmd backup . \
    --exclude ".git" \
    --exclude "backups" \
    --exclude "logs" \
    --exclude "cache" \
    --exclude "crash-reports" \
    --exclude "debug" \
    --exclude "session.lock" \
    --tag "$tag"
  print_success "Rustic backup complete"
}
# Restore from rustic
rustic_restore() {
  local snapshot="${1:-latest}"
  local dest="${2:-${SCRIPT_DIR}}"
  print_header "Restoring from Rustic"
  print_info "Snapshot: $snapshot"
  print_info "Destination: $dest"
  read -r -p "This will overwrite files in destination. Continue? (yes/no): " confirm
  [[ $confirm != "yes" ]] && {
    print_info "Cancelled"
    return 0
  }
  rustic_cmd restore "$snapshot" "$dest"
  print_success "Restore complete"
}
# ----------------------------------------------------------------------------
# EXISTING TAR FUNCTIONS
# ----------------------------------------------------------------------------
# Backup world data
backup_world(){
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
backup_configs(){
  print_info "Backing up configs..."
  cd "$SCRIPT_DIR"
  tar -czf "${BACKUP_DIR}/configs/config_${TIMESTAMP}.tar.gz" \
    --exclude='*.jar' --exclude='mods' --exclude='world*' --exclude='logs' \
    --exclude='crash-reports' --exclude='backups' \
    config/ server.properties ./*.yml ./*.yaml ./*.toml ./*.ini ./*.json ./*.json5 2>/dev/null
  print_success "Config backup created: config_${TIMESTAMP}.tar.gz"
}
# Backup mods
backup_mods(){
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
cleanup_old_backups(){
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
  # Also prune rustic repo if it exists
  if [[ -d "$RUSTIC_REPO" ]]; then
    print_info "Pruning rustic repository..."
    rustic_cmd forget --prune --keep-last "$MAX_BACKUPS"
  fi
  print_success "Cleanup complete"
}
# List backups
list_backups(){
  print_header "Available Tar Backups"
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
  if [[ -d "$RUSTIC_REPO" ]]; then
    printf '\n'
    print_header "Rustic Snapshots"
    rustic_cmd snapshots
  fi
}
# Restore backup
restore_backup(){
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
# ----------------------------------------------------------------------------
# BTRFS FUNCTIONS
# ----------------------------------------------------------------------------
# Check if path is on Btrfs filesystem
is_btrfs(){
  local path="${1:-${SCRIPT_DIR}}"
  [[ $(stat -f -c %T "$path" 2>/dev/null) == "btrfs" ]]
}
# Create Btrfs snapshot
create_btrfs_snapshot(){
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
list_btrfs_snapshots(){
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
delete_btrfs_snapshot(){
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
restore_btrfs_snapshot(){
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
show_usage(){
  cat <<EOF
Minecraft Server Backup Tool

Usage: $0 [command] [options]

Commands:
    Tar-based Backups:
        backup [world|config|mods|all]  Create backup (default: all)
        list                            List backups
        restore <file>                  Restore backup
        cleanup                         Clean old backups

    Rustic Backups (Deduplicated):
        rustic-init                     Initialize rustic repository
        rustic-backup [tag]             Backup server directory (excludes logs/backups)
        rustic-restore [snapshot]       Restore snapshot (default: latest)
        rustic-list                     List snapshots
        rustic-prune                    Prune old snapshots

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
    $0 list

    # Rustic backups
    $0 rustic-backup
    $0 rustic-restore latest

    # Btrfs snapshots
    $0 snapshot
    $0 snapshot-list

Notes:
    - Rustic backups are encrypted and deduplicated (repo: backups/rustic)
    - Rustic password is auto-generated in backups/.rustic_pass
EOF
}
case "${1:-backup}" in 
  backup) case "${2:-all}" in world) backup_world;; config) backup_configs;; mods) backup_mods;; all|*) backup_world; backup_configs; backup_mods;; esac; cleanup_old_backups;; 
  list) list_backups;; 
  restore) restore_backup "$2";; 
  cleanup) cleanup_old_backups;; 
  rustic-init) rustic_init;;
  rustic-backup) rustic_backup "${2:-}";;
  rustic-restore) rustic_restore "${2:-}" "${3:-}";;
  rustic-list) rustic_cmd snapshots;;
  rustic-prune) rustic_cmd forget --prune --keep-last "$MAX_BACKUPS";;
  snapshot) create_btrfs_snapshot "${2:-}" "${3:-}";; 
  snapshot-list) list_btrfs_snapshots;; 
  snapshot-restore) restore_btrfs_snapshot "$2" "${3:-}";; 
  snapshot-delete) delete_btrfs_snapshot "$2";; 
  help|--help|-h) show_usage;; 
  *) print_error "Unknown command: $1"; show_usage; exit 1;; 
esac
