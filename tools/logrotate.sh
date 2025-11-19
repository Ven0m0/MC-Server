#!/usr/bin/env bash
# Simplified Minecraft server log management

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
LOGS_DIR="${SCRIPT_DIR}/logs"
ARCHIVE_DIR="${LOGS_DIR}/archive"
MAX_LOG_AGE_DAYS=30
MAX_ARCHIVED_LOGS=50
LOG_SIZE_LIMIT_MB=100

# Initialize
mkdir -p "$ARCHIVE_DIR"

# Rotate log file
rotate_log() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return 1

    local size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
    [[ $size_mb -eq 0 ]] && return 0

    print_info "Rotating $(basename "$log_file") (${size_mb}MB)..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local name=$(basename "$log_file" .log)
    local archived="${ARCHIVE_DIR}/${name}_${timestamp}.log"

    cp "$log_file" "$archived"
    gzip "$archived"
    : > "$log_file"

    print_success "Rotated: ${name}_${timestamp}.log.gz"
}

# Rotate all logs
rotate_all() {
    print_header "Rotating logs"

    [[ -f "${LOGS_DIR}/latest.log" ]] && rotate_log "${LOGS_DIR}/latest.log"
    [[ -f "${LOGS_DIR}/debug.log" ]] && rotate_log "${LOGS_DIR}/debug.log"

    # Rotate large logs
    find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f | while read -r log; do
        local size_mb=$(du -m "$log" 2>/dev/null | cut -f1)
        [[ $size_mb -gt $LOG_SIZE_LIMIT_MB ]] && rotate_log "$log"
    done

    print_success "Rotation complete"
}

# Compress old logs
compress_old() {
    print_header "Compressing old logs"

    local count=0

    # Compress in logs directory
    find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f -mtime +1 | while read -r log; do
        local name=$(basename "$log")
        [[ "$name" != "latest.log" && "$name" != "debug.log" && "$name" != "watchdog.log" ]] && {
            print_info "Compressing: $name"
            gzip "$log"
            ((count++))
        }
    done

    # Compress in archive
    find "$ARCHIVE_DIR" -name "*.log" -type f | while read -r log; do
        print_info "Compressing: $(basename "$log")"
        gzip "$log"
        ((count++))
    done

    [[ $count -gt 0 ]] && print_success "Compressed $count files" || print_info "Nothing to compress"
}

# Clean old logs
clean_old() {
    print_header "Cleaning logs older than ${MAX_LOG_AGE_DAYS} days"

    local count=0

    find "$LOGS_DIR" -maxdepth 1 \( -name "*.log.gz" -o -name "*.log" \) -type f -mtime +${MAX_LOG_AGE_DAYS} | while read -r log; do
        print_info "Deleting: $(basename "$log")"
        rm -f "$log"
        ((count++))
    done

    find "$ARCHIVE_DIR" -name "*.log.gz" -type f -mtime +${MAX_LOG_AGE_DAYS} | while read -r log; do
        print_info "Deleting: $(basename "$log")"
        rm -f "$log"
        ((count++))
    done

    [[ $count -gt 0 ]] && print_success "Deleted $count files" || print_info "Nothing to clean"
}

# Limit archived logs
limit_archives() {
    print_header "Limiting archives to ${MAX_ARCHIVED_LOGS}"

    local count=$(find "$ARCHIVE_DIR" -name "*.log.gz" -type f | wc -l)
    [[ $count -le $MAX_ARCHIVED_LOGS ]] && { print_info "Archive count ($count) OK"; return 0; }

    print_info "Removing oldest archives..."
    find "$ARCHIVE_DIR" -name "*.log.gz" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -${MAX_ARCHIVED_LOGS} | cut -d' ' -f2- | while read -r log; do
            rm -f "$log"
        done

    print_success "Archives cleaned"
}

# Show statistics
show_stats() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "        Log Management Statistics"
    echo "═══════════════════════════════════════════"
    echo ""

    if [[ -d "$LOGS_DIR" ]]; then
        local count=$(find "$LOGS_DIR" -maxdepth 1 -name "*.log*" -type f | wc -l)
        local size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
        echo "Current Logs:"
        echo "  Count: $count"
        echo "  Size: $size"
        echo ""

        echo "Active Logs:"
        for log in latest.log debug.log watchdog.log; do
            [[ -f "${LOGS_DIR}/${log}" ]] && {
                local s=$(du -h "${LOGS_DIR}/${log}" 2>/dev/null | cut -f1)
                local lines=$(wc -l < "${LOGS_DIR}/${log}")
                echo "  ${log}: ${s} (${lines} lines)"
            }
        done
        echo ""
    fi

    if [[ -d "$ARCHIVE_DIR" ]]; then
        local count=$(find "$ARCHIVE_DIR" -name "*.log.gz" -type f | wc -l)
        local size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
        echo "Archives:"
        echo "  Count: $count"
        echo "  Size: $size"
        echo ""
    fi

    echo "═══════════════════════════════════════════"
}

# View log
view_log() {
    local log="${1:-latest.log}"
    local lines="${2:-50}"
    local path="${LOGS_DIR}/${log}"

    [[ ! -f "$path" ]] && { print_error "Log not found: $log"; return 1; }

    print_info "Last $lines lines of $log:"
    echo ""
    tail -n "$lines" "$path"
}

# Search logs
search_log() {
    local pattern="$1"
    local log="${2:-latest.log}"
    local path="${LOGS_DIR}/${log}"

    [[ ! -f "$path" ]] && { print_error "Log not found: $log"; return 1; }

    print_info "Searching for '$pattern' in $log:"
    echo ""
    grep --color=auto -i "$pattern" "$path" || print_info "No matches"
}

# Full maintenance
full_maintenance() {
    print_header "Full log maintenance"
    echo ""
    rotate_all
    echo ""
    compress_old
    echo ""
    clean_old
    echo ""
    limit_archives
    echo ""
    show_stats
}

# Show usage
show_usage() {
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
    rotate) rotate_all;;
    compress) compress_old;;
    clean) MAX_LOG_AGE_DAYS="${2:-$MAX_LOG_AGE_DAYS}"; clean_old;;
    limit) MAX_ARCHIVED_LOGS="${2:-$MAX_ARCHIVED_LOGS}"; limit_archives;;
    maintenance) full_maintenance;;
    stats) show_stats;;
    view) view_log "${2:-latest.log}" "${3:-50}";;
    search)
        [[ -z "$2" ]] && { print_error "Provide search pattern"; exit 1; }
        search_log "$2" "${3:-latest.log}";;
    help|--help|-h) show_usage;;
    *) print_error "Unknown command: $1"; show_usage; exit 1;;
esac
