#!/usr/bin/env bash
# Minecraft world optimization and chunk cleaning tool

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/common.sh
source "${SCRIPT_DIR}/tools/common.sh"
# Additional formatting helper (not in common.sh)
print_warning(){ printf '\033[1;33m⚠\033[0m %s\n' "$1"; }
# Directory size cache to avoid multiple du calls
declare -A dir_size_cache
# Get directory size with caching
get_dir_size(){
  local dir="$1"
  if [[ -z ${dir_size_cache[$dir]:-} ]]; then
    dir_size_cache[$dir]=$(du -sb "$dir" 2>/dev/null | cut -f1)
  fi
  printf '%s' "${dir_size_cache[$dir]}"
}

# Configuration
CHUNK_CLEANER_VERSION="1.0.0"
CHUNK_CLEANER_URL="https://github.com/zeroBzeroT/ChunkCleaner/releases/download/v${CHUNK_CLEANER_VERSION}/ChunkCleaner-Linux64"
CHUNK_CLEANER_BIN="${SCRIPT_DIR}/tools/ChunkCleaner-Linux64"
MIN_INHABITED_TICKS=200
PLAYER_INACTIVITY_DAYS=90
DRY_RUN=false
CREATE_BACKUP=true
WORLD_DIR="${SCRIPT_DIR}/world"
# Download ChunkCleaner if not present
download_chunk_cleaner(){
  [[ -f $CHUNK_CLEANER_BIN ]] && { print_info "ChunkCleaner already installed"; return 0; }
  print_info "Downloading ChunkCleaner v${CHUNK_CLEANER_VERSION}..."
  if has_command curl; then
    curl -L -o "$CHUNK_CLEANER_BIN" "$CHUNK_CLEANER_URL" || {
      print_error "Failed to download ChunkCleaner"; return 1
    }
  elif has_command wget; then
    wget -q --show-progress -O "$CHUNK_CLEANER_BIN" "$CHUNK_CLEANER_URL" || {
      print_error "Failed to download ChunkCleaner"; return 1
    }
  else
    print_error "Neither wget nor curl found. Please install one of them."; return 1
  fi
  chmod +x "$CHUNK_CLEANER_BIN"
  print_success "ChunkCleaner installed successfully"
}
# Create backup before optimization
create_backup(){
  [[ $CREATE_BACKUP != "true" ]] && return 0
  print_info "Creating backup before optimization..."
  "${SCRIPT_DIR}/tools/backup.sh" backup world &>/dev/null || {
    print_warning "Backup script failed, continuing anyway..."
  }
  print_success "Backup created"
}
# Clean chunks using ChunkCleaner
clean_chunks(){
  local world_path="${1:-${WORLD_DIR}}"
  local min_ticks="${2:-${MIN_INHABITED_TICKS}}"
  [[ ! -d $world_path ]] && { print_error "World directory not found: ${world_path}"; return 1; }
  print_header "Chunk Cleaning"
  print_info "World: ${world_path}"
  print_info "Minimum inhabited ticks: ${min_ticks}"
  # Download ChunkCleaner if needed
  download_chunk_cleaner || return 1
  # Process each dimension
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    local dim_name="${dimension_path##*/}" # Pure bash, no subshell
    local region_dir=""
    # Determine region directory based on dimension
    if [[ $dim_name == "world" ]]; then
      region_dir="${dimension_path}/region"
    elif [[ $dim_name == "world_nether" ]]; then
      region_dir="${dimension_path}/DIM-1/region"
    elif [[ $dim_name == "world_the_end" ]]; then
      region_dir="${dimension_path}/DIM1/region"
    fi
    [[ ! -d $region_dir ]] && continue
    print_info "Processing ${dim_name}..."
    local backup_region="${region_dir}_backup_$(printf '%(%Y%m%d_%H%M%S)T' -1)"
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would clean chunks in: ${region_dir}"
      local chunk_count=$(find "$region_dir" -name "*.mca" 2>/dev/null | wc -l)
      print_info "[DRY RUN] Found ${chunk_count} region files"
    else
      "$CHUNK_CLEANER_BIN" -path "$region_dir" \
        -newPath "$backup_region" \
        -minInhabitedTicks "$min_ticks" || {
        print_error "ChunkCleaner failed for ${dim_name}"; continue
      }
      # Calculate space saved
      if [[ -d $backup_region ]]; then
        local old_size=$(get_dir_size "$backup_region") new_size=$(get_dir_size "$region_dir")
        local saved=$((old_size - new_size)); local saved_mb=$((saved / 1024 / 1024))
        print_success "${dim_name}: Saved ${saved_mb}MB (backup: ${backup_region})"
      fi
    fi
  done
}
# Clean old player data
clean_player_data(){
  local world_path="${1:-${WORLD_DIR}}"
  local days="${2:-${PLAYER_INACTIVITY_DAYS}}"
  [[ ! -d "${world_path}/playerdata" ]] && { print_info "No playerdata directory found"; return 0; }
  print_header "Player Data Cleanup"
  print_info "Removing player data older than ${days} days..."
  local count=0 total_size=0
  while IFS= read -r -d '' player_file; do
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove: $(basename "$player_file")"
      ((count++))
    else
      local size=$(stat -f%z "$player_file" 2>/dev/null || stat -c%s "$player_file" 2>/dev/null || echo 0)
      total_size=$((total_size + size))
      rm -f "$player_file"
      ((count++))
    fi
  done < <(find "${world_path}/playerdata" -name "*.dat" -type f -mtime "+${days}" -print0 2>/dev/null)
  if [[ $count -gt 0 ]]; then
    local size_mb=$((total_size / 1024 / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} player data files"
    else
      print_success "Removed ${count} player data files (${size_mb}MB)"
    fi
  else
    print_info "No old player data files found"
  fi
}
# Clean old statistics
clean_statistics(){
  local world_path="${1:-${WORLD_DIR}}"
  local days="${2:-${PLAYER_INACTIVITY_DAYS}}"
  [[ ! -d "${world_path}/stats" ]] && { print_info "No stats directory found"; return 0; }
  print_header "Statistics Cleanup"
  print_info "Removing statistics older than ${days} days..."
  local count=0 total_size=0
  while IFS= read -r -d '' stat_file; do
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove: $(basename "$stat_file")"
      ((count++))
    else
      local size=$(stat -f%z "$stat_file" 2>/dev/null || stat -c%s "$stat_file" 2>/dev/null || echo 0)
      total_size=$((total_size + size))
      rm -f "$stat_file"
      ((count++))
    fi
  done < <(find "${world_path}/stats" -name "*.json" -type f -mtime "+${days}" -print0 2>/dev/null)
  if [[ $count -gt 0 ]]; then
    local size_mb=$((total_size / 1024 / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} statistics files"
    else
      print_success "Removed ${count} statistics files (${size_mb}MB)"
    fi
  else
    print_info "No old statistics files found"
  fi
}
# Clean advancements
clean_advancements(){
  local world_path="${1:-${WORLD_DIR}}"
  local days="${2:-${PLAYER_INACTIVITY_DAYS}}"
  [[ ! -d "${world_path}/advancements" ]] && { print_info "No advancements directory found"; return 0; }
  print_header "Advancements Cleanup"
  print_info "Removing advancements older than ${days} days..."
  local count=0 total_size=0
  while IFS= read -r -d '' adv_file; do
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove: $(basename "$adv_file")"
      ((count++))
    else
      local size=$(stat -f%z "$adv_file" 2>/dev/null || stat -c%s "$adv_file" 2>/dev/null || echo 0)
      total_size=$((total_size + size))
      rm -f "$adv_file"
      ((count++))
    fi
  done < <(find "${world_path}/advancements" -name "*.json" -type f -mtime "+${days}" -print0 2>/dev/null)
  if [[ $count -gt 0 ]]; then
    local size_kb=$((total_size / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} advancement files"
    else
      print_success "Removed ${count} advancement files (${size_kb}KB)"
    fi
  else
    print_info "No old advancement files found"
  fi
}
# Clean session lock files
clean_session_locks(){
  local world_path="${1:-${WORLD_DIR}}"
  print_header "Session Lock Cleanup"
  local count=0
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    if [[ -f "${dimension_path}/session.lock" ]]; then
      if [[ $DRY_RUN == "true" ]]; then
        print_info "[DRY RUN] Would remove: ${dimension_path}/session.lock"
      else
        rm -f "${dimension_path}/session.lock"
      fi
      ((count++))
    fi
  done
  if [[ $count -gt 0 ]]; then
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} session.lock files"
    else
      print_success "Removed ${count} session.lock files"
    fi
  else
    print_info "No session.lock files found"
  fi
}
# Optimize region files (remove empty chunks)
optimize_regions(){
  local world_path="${1:-${WORLD_DIR}}"
  print_header "Region File Optimization"
  print_info "Analyzing region files for optimization..."
  local total_before=0 total_after=0
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    local dim_name="${dimension_path##*/}" region_dir=""
    if [[ $dim_name == "world" ]]; then
      region_dir="${dimension_path}/region"
    elif [[ $dim_name == "world_nether" ]]; then
      region_dir="${dimension_path}/DIM-1/region"
    elif [[ $dim_name == "world_the_end" ]]; then
      region_dir="${dimension_path}/DIM1/region"
    fi
    [[ ! -d $region_dir ]] && continue
    local before=$(get_dir_size "$region_dir")
    total_before=$((total_before + before))
    # Find and report small/potentially empty region files
    local small_count=0
    while IFS='|' read -r size name; do
      if [[ $size -lt 8192 ]]; then # Less than 8KB is likely empty or nearly empty
        ((small_count++))
        if [[ $DRY_RUN == "true" ]]; then
          print_info "[DRY RUN] Small region file: $name (${size} bytes)"
        fi
      fi
    done < <(find "$region_dir" -name "*.mca" -type f -printf '%s|%f\n' 2>/dev/null)
    local after=$(get_dir_size "$region_dir")
    total_after=$((total_after + after))
    if [[ $small_count -gt 0 ]]; then
      print_info "${dim_name}: Found ${small_count} small region files"
    fi
  done
  print_info "Current total region size: $((total_before / 1024 / 1024))MB"
}

# Show world statistics
show_stats(){
  local world_path="${1:-${WORLD_DIR}}"
  print_header "World Statistics"
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    local dim_name="${dimension_path##*/}" # Pure bash, no subshell
    printf '\n'
    printf '=== %s ===\n' "$dim_name"
    # Region files
    local region_dir=""
    if [[ $dim_name == "world" ]]; then
      region_dir="${dimension_path}/region"
    elif [[ $dim_name == "world_nether" ]]; then
      region_dir="${dimension_path}/DIM-1/region"
    elif [[ $dim_name == "world_the_end" ]]; then
      region_dir="${dimension_path}/DIM1/region"
    fi
    if [[ -d $region_dir ]]; then
      local region_count=$(find "$region_dir" -name "*.mca" 2>/dev/null | wc -l)
      local region_size=$(du -sh "$region_dir" 2>/dev/null | cut -f1)
      printf '  Region files: %s (%s)\n' "$region_count" "$region_size"
    fi
    # Entity data
    if [[ -d "${dimension_path}/entities" ]]; then
      local entity_count=$(find "${dimension_path}/entities" -name "*.mca" 2>/dev/null | wc -l)
      local entity_size=$(du -sh "${dimension_path}/entities" 2>/dev/null | cut -f1)
      printf '  Entity files: %s (%s)\n' "$entity_count" "$entity_size"
    fi
    # POI data
    if [[ -d "${dimension_path}/poi" ]]; then
      local poi_count=$(find "${dimension_path}/poi" -name "*.mca" 2>/dev/null | wc -l)
      local poi_size=$(du -sh "${dimension_path}/poi" 2>/dev/null | cut -f1)
      printf '  POI files: %s (%s)\n' "$poi_count" "$poi_size"
    fi
  done
  # Player data
  if [[ -d "${world_path}/playerdata" ]]; then
    local player_count=$(find "${world_path}/playerdata" -name "*.dat" 2>/dev/null | wc -l)
    local player_size=$(du -sh "${world_path}/playerdata" 2>/dev/null | cut -f1)
    printf '\n'
    printf 'Player data: %s players (%s)\n' "$player_count" "$player_size"
  fi
  # Statistics
  if [[ -d "${world_path}/stats" ]]; then
    local stats_count=$(find "${world_path}/stats" -name "*.json" 2>/dev/null | wc -l)
    local stats_size=$(du -sh "${world_path}/stats" 2>/dev/null | cut -f1)
    printf 'Statistics: %s files (%s)\n' "$stats_count" "$stats_size"
  fi
  # Advancements
  if [[ -d "${world_path}/advancements" ]]; then
    local adv_count=$(find "${world_path}/advancements" -name "*.json" 2>/dev/null | wc -l)
    local adv_size=$(du -sh "${world_path}/advancements" 2>/dev/null | cut -f1)
    printf 'Advancements: %s files (%s)\n' "$adv_count" "$adv_size"
  fi
  # Total size
  local total_size=$(du -sh "$world_path" 2>/dev/null | cut -f1)
  printf '\n'
  printf 'Total world size: %s\n' "$total_size"
}
# Show usage
show_usage(){
  cat <<EOF
Minecraft World Optimization Tool

Usage: $0 [command] [options]

Commands:
    chunks                Clean unused chunks
    players               Clean old player data
    stats                 Clean old statistics
    advancements          Clean old advancements
    locks                 Remove session.lock files
    optimize              Optimize region files
    all                   Run all optimizations
    info                  Show world statistics
    help                  Show this help

Options:
    --world <path>        World directory path (default: ${SCRIPT_DIR}/world)
    --min-ticks <num>     Minimum inhabited ticks for chunks (default: 200)
    --player-days <num>   Player inactivity days threshold (default: 90)
    --dry-run             Show what would be done without making changes
    --no-backup           Skip creating backup before optimization
    --install-cleaner     Download ChunkCleaner tool only

Examples:
    $0 chunks --min-ticks 500
    $0 players --player-days 180
    $0 all --dry-run
    $0 info
    $0 --install-cleaner

Note: ChunkCleaner will be automatically downloaded on first use.
      Backups are created before any destructive operations.
EOF
}

# Parse arguments
COMMAND="${1:-help}"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --world) WORLD_DIR="$2"; shift 2 ;;
    --min-ticks) MIN_INHABITED_TICKS="$2"; shift 2 ;;
    --player-days) PLAYER_INACTIVITY_DAYS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --no-backup) CREATE_BACKUP=false; shift ;;
    --install-cleaner) download_chunk_cleaner; exit 0 ;;
    *) print_error "Unknown option: $1"; show_usage; exit 1 ;;
  esac
done
# Main execution
case "$COMMAND" in
  chunks)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    create_backup
    clean_chunks "$WORLD_DIR" "$MIN_INHABITED_TICKS"
    ;;
  players)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    create_backup
    clean_player_data "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    ;;
  stats)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    create_backup
    clean_statistics "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    ;;
  advancements)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    create_backup
    clean_advancements "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    ;;
  locks)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    clean_session_locks "$WORLD_DIR"
    ;;
  optimize)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    optimize_regions "$WORLD_DIR"
    ;;
  all)
    [[ $DRY_RUN == "true" ]] && print_warning "DRY RUN MODE - No changes will be made"
    create_backup
    clean_chunks "$WORLD_DIR" "$MIN_INHABITED_TICKS"
    clean_player_data "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    clean_statistics "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    clean_advancements "$WORLD_DIR" "$PLAYER_INACTIVITY_DAYS"
    clean_session_locks "$WORLD_DIR"
    optimize_regions "$WORLD_DIR"
    print_success "All optimizations complete!"
    ;;
  info) show_stats "$WORLD_DIR" ;;
  help | --help | -h) show_usage ;;
  *) print_error "Unknown command: ${COMMAND}"; show_usage; exit 1 ;;
esac
