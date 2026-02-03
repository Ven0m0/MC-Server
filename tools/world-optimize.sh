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
# Process single dimension (helper for parallel execution)
process_dimension(){
  local dimension_path="$1" min_ticks="$2"
  local dim_name="${dimension_path##*/}"
  local region_dir=""

  # Determine region directory based on dimension
  if [[ $dim_name == "world" ]]; then
    region_dir="${dimension_path}/region"
  elif [[ $dim_name == "world_nether" ]]; then
    region_dir="${dimension_path}/DIM-1/region"
  elif [[ $dim_name == "world_the_end" ]]; then
    region_dir="${dimension_path}/DIM1/region"
  fi

  [[ ! -d $region_dir ]] && return 0

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
      print_error "ChunkCleaner failed for ${dim_name}"; return 1
    }
    # Calculate space saved
    if [[ -d $backup_region ]]; then
      local old_size=$(get_dir_size "$backup_region") new_size=$(get_dir_size "$region_dir")
      local saved=$((old_size - new_size)); local saved_mb=$((saved / 1024 / 1024))
      print_success "${dim_name}: Saved ${saved_mb}MB (backup: ${backup_region})"
    fi
  fi
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

  # Export function and variables for parallel execution
  export -f process_dimension get_dir_size print_info print_error print_success
  export CHUNK_CLEANER_BIN DRY_RUN

  # Process dimensions in parallel
  local pids=()
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    process_dimension "$dimension_path" "$min_ticks" &
    pids+=($!)
  done

  # Wait for all background jobs to complete
  local failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || ((failed++))
  done

  [[ $failed -gt 0 ]] && print_error "Some dimension processing failed" || return 0
}
# Clean old player data
clean_player_data(){
  local world_path="${1:-${WORLD_DIR}}"
  local days="${2:-${PLAYER_INACTIVITY_DAYS}}"
  [[ ! -d "${world_path}/playerdata" ]] && { print_info "No playerdata directory found"; return 0; }
  print_header "Player Data Cleanup"
  print_info "Removing player data older than ${days} days..."
  local count=0 total_size=0
  if [[ $DRY_RUN == "true" ]]; then
    while IFS='|' read -r -d '' size file; do
      print_info "[DRY RUN] Would remove: ${file##*/}"
      total_size=$((total_size + size))
      count=$((count + 1))
    done < <(find "${world_path}/playerdata" -name "*.dat" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)
  else
    local temp_list
    temp_list=$(mktemp)
    while IFS='|' read -r -d '' size file; do
      total_size=$((total_size + size))
      count=$((count + 1))
      printf "%s\0" "$file" >> "$temp_list"
    done < <(find "${world_path}/playerdata" -name "*.dat" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)

    if [[ -s "$temp_list" ]]; then
      xargs -0 rm -f < "$temp_list"
    fi
    rm -f "$temp_list"
  fi
  if [[ $count -gt 0 ]]; then
    local size_mb=$((total_size / 1024 / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} player data files (${size_mb}MB)"
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
  if [[ $DRY_RUN == "true" ]]; then
    while IFS='|' read -r -d '' size file; do
      print_info "[DRY RUN] Would remove: ${file##*/}"
      total_size=$((total_size + size))
      count=$((count + 1))
    done < <(find "${world_path}/stats" -name "*.json" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)
  else
    local temp_list
    temp_list=$(mktemp)
    while IFS='|' read -r -d '' size file; do
      total_size=$((total_size + size))
      count=$((count + 1))
      printf "%s\0" "$file" >> "$temp_list"
    done < <(find "${world_path}/stats" -name "*.json" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)

    if [[ -s "$temp_list" ]]; then
      xargs -0 rm -f < "$temp_list"
    fi
    rm -f "$temp_list"
  fi
  if [[ $count -gt 0 ]]; then
    local size_mb=$((total_size / 1024 / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} statistics files (${size_mb}MB)"
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
  if [[ $DRY_RUN == "true" ]]; then
    while IFS='|' read -r -d '' size file; do
      print_info "[DRY RUN] Would remove: ${file##*/}"
      total_size=$((total_size + size))
      count=$((count + 1))
    done < <(find "${world_path}/advancements" -name "*.json" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)
  else
    local temp_list
    temp_list=$(mktemp)
    while IFS='|' read -r -d '' size file; do
      total_size=$((total_size + size))
      count=$((count + 1))
      printf "%s\0" "$file" >> "$temp_list"
    done < <(find "${world_path}/advancements" -name "*.json" -type f -mtime "+${days}" -printf '%s|%p\0' 2>/dev/null)

    if [[ -s "$temp_list" ]]; then
      xargs -0 rm -f < "$temp_list"
    fi
    rm -f "$temp_list"
  fi
  if [[ $count -gt 0 ]]; then
    local size_kb=$((total_size / 1024))
    if [[ $DRY_RUN == "true" ]]; then
      print_info "[DRY RUN] Would remove ${count} advancement files (${size_kb}KB)"
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

  # Collect all paths for batch du call
  local -a du_paths=()
  local -A path_labels=()

  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    local dim_name="${dimension_path##*/}"

    # Add dimension directories
    if [[ $dim_name == "world" ]]; then
      [[ -d "${dimension_path}/region" ]] && { du_paths+=("${dimension_path}/region"); path_labels["${dimension_path}/region"]="${dim_name}:region"; }
      [[ -d "${dimension_path}/entities" ]] && { du_paths+=("${dimension_path}/entities"); path_labels["${dimension_path}/entities"]="${dim_name}:entities"; }
      [[ -d "${dimension_path}/poi" ]] && { du_paths+=("${dimension_path}/poi"); path_labels["${dimension_path}/poi"]="${dim_name}:poi"; }
    elif [[ $dim_name == "world_nether" ]]; then
      [[ -d "${dimension_path}/DIM-1/region" ]] && { du_paths+=("${dimension_path}/DIM-1/region"); path_labels["${dimension_path}/DIM-1/region"]="${dim_name}:region"; }
      [[ -d "${dimension_path}/DIM-1/entities" ]] && { du_paths+=("${dimension_path}/DIM-1/entities"); path_labels["${dimension_path}/DIM-1/entities"]="${dim_name}:entities"; }
      [[ -d "${dimension_path}/DIM-1/poi" ]] && { du_paths+=("${dimension_path}/DIM-1/poi"); path_labels["${dimension_path}/DIM-1/poi"]="${dim_name}:poi"; }
    elif [[ $dim_name == "world_the_end" ]]; then
      [[ -d "${dimension_path}/DIM1/region" ]] && { du_paths+=("${dimension_path}/DIM1/region"); path_labels["${dimension_path}/DIM1/region"]="${dim_name}:region"; }
      [[ -d "${dimension_path}/DIM1/entities" ]] && { du_paths+=("${dimension_path}/DIM1/entities"); path_labels["${dimension_path}/DIM1/entities"]="${dim_name}:entities"; }
      [[ -d "${dimension_path}/DIM1/poi" ]] && { du_paths+=("${dimension_path}/DIM1/poi"); path_labels["${dimension_path}/DIM1/poi"]="${dim_name}:poi"; }
    fi
  done

  # Add common paths
  [[ -d "${world_path}/playerdata" ]] && { du_paths+=("${world_path}/playerdata"); path_labels["${world_path}/playerdata"]="playerdata"; }
  [[ -d "${world_path}/stats" ]] && { du_paths+=("${world_path}/stats"); path_labels["${world_path}/stats"]="stats"; }
  [[ -d "${world_path}/advancements" ]] && { du_paths+=("${world_path}/advancements"); path_labels["${world_path}/advancements"]="advancements"; }
  du_paths+=("$world_path")
  path_labels["$world_path"]="total"

  # Single du call for all paths
  local -A sizes=()
  while IFS=$'\t' read -r size path; do
    sizes["$path"]="$size"
  done < <(du -sh "${du_paths[@]}" 2>/dev/null)

  # Display results by dimension
  local current_dim=""
  for dimension_path in "$world_path" "${world_path}_nether" "${world_path}_the_end"; do
    [[ ! -d $dimension_path ]] && continue
    local dim_name="${dimension_path##*/}"

    printf '\n=== %s ===\n' "$dim_name"

    # Determine region path based on dimension
    local region_dir="" entities_dir="" poi_dir=""
    if [[ $dim_name == "world" ]]; then
      region_dir="${dimension_path}/region"
      entities_dir="${dimension_path}/entities"
      poi_dir="${dimension_path}/poi"
    elif [[ $dim_name == "world_nether" ]]; then
      region_dir="${dimension_path}/DIM-1/region"
      entities_dir="${dimension_path}/DIM-1/entities"
      poi_dir="${dimension_path}/DIM-1/poi"
    elif [[ $dim_name == "world_the_end" ]]; then
      region_dir="${dimension_path}/DIM1/region"
      entities_dir="${dimension_path}/DIM1/entities"
      poi_dir="${dimension_path}/DIM1/poi"
    fi

    [[ -n ${sizes[$region_dir]:-} ]] && printf '  Region files: %s (%s)\n' "$(find "$region_dir" -name "*.mca" 2>/dev/null | wc -l)" "${sizes[$region_dir]}"
    [[ -n ${sizes[$entities_dir]:-} ]] && printf '  Entity files: %s (%s)\n' "$(find "$entities_dir" -name "*.mca" 2>/dev/null | wc -l)" "${sizes[$entities_dir]}"
    [[ -n ${sizes[$poi_dir]:-} ]] && printf '  POI files: %s (%s)\n' "$(find "$poi_dir" -name "*.mca" 2>/dev/null | wc -l)" "${sizes[$poi_dir]}"
  done

  printf '\n'
  [[ -n ${sizes["${world_path}/playerdata"]:-} ]] && printf 'Player data: %s players (%s)\n' "$(find "${world_path}/playerdata" -name "*.dat" 2>/dev/null | wc -l)" "${sizes["${world_path}/playerdata"]}"
  [[ -n ${sizes["${world_path}/stats"]:-} ]] && printf 'Statistics: %s files (%s)\n' "$(find "${world_path}/stats" -name "*.json" 2>/dev/null | wc -l)" "${sizes["${world_path}/stats"]}"
  [[ -n ${sizes["${world_path}/advancements"]:-} ]] && printf 'Advancements: %s files (%s)\n' "$(find "${world_path}/advancements" -name "*.json" 2>/dev/null | wc -l)" "${sizes["${world_path}/advancements"]}"
  printf '\nTotal world size: %s\n' "${sizes[$world_path]}"
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
