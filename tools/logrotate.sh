#!/usr/bin/env bash
# Simplified Minecraft server log management

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/common.sh
source "${SCRIPT_DIR}/tools/common.sh"

# Configuration
LOGS_DIR="${SCRIPT_DIR}/logs"
ARCHIVE_DIR="${LOGS_DIR}/archive"
MAX_LOG_AGE_DAYS=30
MAX_ARCHIVED_LOGS=50
LOG_SIZE_LIMIT_MB=100

# Initialize
mkdir -p "$ARCHIVE_DIR"

# Rotate log file
rotate_log(){
  local log_file="$1"
  [[ ! -f $log_file ]] && return 1
  local size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
  ((size_mb == 0)) && return 0
  local name="${log_file##*/}"
  name="${name%.log}"
  print_info "Rotating ${name} (${size_mb}MB)..."
  local timestamp
  timestamp=$(printf '%(%Y%m%d_%H%M%S)T' -1)
  local archived="${ARCHIVE_DIR}/${name}_${timestamp}.log"
  cp "$log_file" "$archived"
  gzip "$archived"
  : >"$log_file"
  print_success "Rotated: ${name}_${timestamp}.log.gz"
}

# Rotate all logs
rotate_all(){
  print_header "Rotating logs"
  [[ -f "${LOGS_DIR}/latest.log" ]] && rotate_log "${LOGS_DIR}/latest.log"
  [[ -f "${LOGS_DIR}/debug.log" ]] && rotate_log "${LOGS_DIR}/debug.log"
  # Use find with -size filter instead of du for better performance
  while IFS= read -r -d '' log; do
    rotate_log "$log"
  done < <(find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f -size +"${LOG_SIZE_LIMIT_MB}M" -print0 2>/dev/null)
  print_success "Rotation complete"
}

# Compress old logs
compress_old(){
  print_header "Compressing old logs"

  local file_list
  file_list=$(mktemp)

  {
    find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f \
      ! -name "latest.log" ! -name "debug.log" ! -name "watchdog.log" -print0
    find "$ARCHIVE_DIR" -name "*.log" -type f -print0 2>/dev/null
  } > "$file_list"

  local count
  count=$(tr -cd '\0' < "$file_list" | wc -c)

  if ((count > 0)); then
    local threads
    threads=$(get_cpu_cores)
    print_info "Compressing $count files with $threads threads..."
    xargs -0 -a "$file_list" -P "$threads" -n 1 gzip
    print_success "Compressed $count files"
  else
    print_info "Nothing to compress"
  fi

  rm -f "$file_list"
}

# Clean old logs
clean_old(){
  print_header "Cleaning logs older than ${MAX_LOG_AGE_DAYS} days"
  local count=0
  # Single find call for both directories
  while IFS= read -r -d '' log; do
    print_info "Deleting: ${log##*/}"
    rm -f "$log"
    ((count+=1))
  done < <(find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f -mtime +"$MAX_LOG_AGE_DAYS" -print0; find "$ARCHIVE_DIR" -name "*.log.gz" -type f -mtime +"$MAX_LOG_AGE_DAYS" -print0 2>/dev/null)
  if ((count > 0)); then
    print_success "Deleted $count files"
  else
    print_info "Nothing to clean"
  fi
}

# Limit archived logs
limit_archives(){
  print_header "Limiting archives to ${MAX_ARCHIVED_LOGS}"
  # Single find with -printf is more efficient than find | wc -l
  local files
  mapfile -t files < <(find "$ARCHIVE_DIR" -name "*.log.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n)
  local count=${#files[@]}
  ((count <= MAX_ARCHIVED_LOGS)) && {
    print_info "Archive count ($count) OK"
    return 0
  }
  print_info "Removing oldest archives..."
  local to_remove=$((count - MAX_ARCHIVED_LOGS))
  for ((i = 0; i < to_remove; i++)); do
    local log="${files[i]#* }" # Remove timestamp prefix
    rm -f "$log"
  done
  print_success "Archives cleaned"
}

# Show statistics
show_stats(){
  printf '\n'
  printf '═══════════════════════════════════════════\n'
  printf '        Log Management Statistics\n'
  printf '═══════════════════════════════════════════\n'
  printf '\n'
  [[ -d $LOGS_DIR ]] && {
    # Single find call for count and single du for all stats
    local count
    count=$(find "$LOGS_DIR" -maxdepth 1 -name "*.log*" -type f -print 2>/dev/null | wc -l)
    local size
    size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
    printf 'Current Logs:\n'
    printf '  Count: %s\n' "$count"
    printf '  Size: %s\n' "$size"
    printf '\n'
    printf 'Active Logs:\n'
    # Combine du calls for active logs
    local active_logs=()
    for log in latest.log debug.log watchdog.log; do
      [[ -f "${LOGS_DIR}/${log}" ]] && active_logs+=("${LOGS_DIR}/${log}")
    done
    if [[ ${#active_logs[@]} -gt 0 ]]; then
      # Single du call for all active logs
      while IFS=$'\t' read -r s path; do
        local log_name lines
        log_name=$(basename "$path")
        lines=$(wc -l <"$path" 2>/dev/null || printf '0')
        printf '  %s: %s (%s lines)\n' "$log_name" "$s" "$lines"
      done < <(du -h "${active_logs[@]}" 2>/dev/null)
    fi
    printf '\n'
  }
  [[ -d $ARCHIVE_DIR ]] && {
    local count
    count=$(find "$ARCHIVE_DIR" -name "*.log.gz" -type f -print 2>/dev/null | wc -l)
    local size
    size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
    printf 'Archives:\n'
    printf '  Count: %s\n' "$count"
    printf '  Size: %s\n' "$size"
    printf '\n'
  }
  printf '═══════════════════════════════════════════\n'
}

# View log
view_log(){
  local log="${1:-latest.log}"
  local lines="${2:-50}"
  local path="${LOGS_DIR}/${log}"
  print_info "Last $lines lines of $log:"
  printf '\n'
  tail -n "$lines" "$path" 2>/dev/null || {
    print_error "Log not found: $log"
    return 1
  }
}

# Search logs
search_log(){
  local pattern="$1"
  local log="${2:-latest.log}"
  local path="${LOGS_DIR}/${log}"
  print_info "Searching for '$pattern' in $log:"
  printf '\n'
grep --color=auto -i "$pattern" "$path" 2>/dev/null
local status=$?
if (( status == 1 )); then
  print_info "No matches found for '$pattern'"
elif (( status > 1 )); then
  print_error "Log not found: $log"
  return 1
fi
}

# Full maintenance
full_maintenance(){
  print_header "Full log maintenance"
  printf '\n'
  rotate_all
  printf '\n'
  compress_old
  printf '\n'
  clean_old
  printf '\n'
  limit_archives
  printf '\n'
  show_stats
}

# Show usage
show_usage(){
  cat <<EOF
Minecraft Server Log Management

Usage: $0 [command] [options]

Commands:
    rotate                      Rotate current logs
    compress                    Compress old logs
    clean [days]               Clean logs older than N days (default: 30)
    limit [count]              Keep N most recent archives (default: 50)
    maintenance                 Full maintenance
    stats                       Show statistics
    view [log] [lines]         View log (default: latest.log, 50 lines)
    search <pattern> [log]     Search in log
    help                        Show this help

Examples:
    $0 rotate
    $0 clean 14
    $0 maintenance
    $0 stats
    $0 view latest.log 100
    $0 search "error" latest.log
EOF
}

# Main
case "${1:-help}" in
  rotate) rotate_all ;;
  compress) compress_old ;;
  clean)
    MAX_LOG_AGE_DAYS="${2:-$MAX_LOG_AGE_DAYS}"
    clean_old
    ;;
  limit)
    MAX_ARCHIVED_LOGS="${2:-$MAX_ARCHIVED_LOGS}"
    limit_archives
    ;;
  maintenance) full_maintenance ;;
  stats) show_stats ;;
  view) view_log "${2:-latest.log}" "${3:-50}" ;;
  search)
    [[ -z ${2:-} ]] && {
      print_error "Provide search pattern"
      exit 1
    }
    search_log "$2" "${3:-latest.log}"
    ;;
  help | --help | -h) show_usage ;;
  *)
    print_error "Unknown command: $1"
    show_usage
    exit 1
    ;;
esac
