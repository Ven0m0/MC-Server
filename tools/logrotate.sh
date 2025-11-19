#!/usr/bin/env bash
# Minecraft Server Log Management and Rotation
# Clean, compress, and manage server logs

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="${SERVER_DIR}/logs"
ARCHIVE_DIR="${LOGS_DIR}/archive"
MAX_LOG_AGE_DAYS=30
MAX_ARCHIVED_LOGS=50
LOG_SIZE_LIMIT_MB=100

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Initialize archive directory
init_archive() {
    mkdir -p "$ARCHIVE_DIR"
}

# Get file size in MB
get_size_mb() {
    local file="$1"
    if [ -f "$file" ]; then
        local size_kb=$(du -k "$file" | cut -f1)
        echo $((size_kb / 1024))
    else
        echo "0"
    fi
}

# Rotate current log file
rotate_log() {
    local log_file="$1"
    local log_name=$(basename "$log_file")

    if [ ! -f "$log_file" ]; then
        log_warning "Log file not found: $log_file"
        return 1
    fi

    local size_mb=$(get_size_mb "$log_file")
    if [ "$size_mb" -eq 0 ]; then
        log_info "Log file is empty: $log_name"
        return 0
    fi

    log_info "Rotating log: $log_name (${size_mb}MB)"

    # Create timestamped filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archived_name="${log_name%.log}_${timestamp}.log"

    # Move and compress
    cp "$log_file" "${ARCHIVE_DIR}/${archived_name}"
    gzip "${ARCHIVE_DIR}/${archived_name}"

    # Clear original log (don't delete, just truncate)
    : > "$log_file"

    log_success "Log rotated and compressed: ${archived_name}.gz (${size_mb}MB)"
}

# Rotate all server logs
rotate_all_logs() {
    log_info "Rotating all server logs..."

    init_archive

    # Rotate main server log
    if [ -f "${LOGS_DIR}/latest.log" ]; then
        rotate_log "${LOGS_DIR}/latest.log"
    fi

    # Rotate debug log
    if [ -f "${LOGS_DIR}/debug.log" ]; then
        rotate_log "${LOGS_DIR}/debug.log"
    fi

    # Rotate watchdog log
    if [ -f "${LOGS_DIR}/watchdog.log" ]; then
        local size_mb=$(get_size_mb "${LOGS_DIR}/watchdog.log")
        if [ "$size_mb" -gt "$LOG_SIZE_LIMIT_MB" ]; then
            rotate_log "${LOGS_DIR}/watchdog.log"
        fi
    fi

    # Rotate dated logs (e.g., 2025-11-19-1.log.gz)
    find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f | while read -r log_file; do
        local size_mb=$(get_size_mb "$log_file")
        if [ "$size_mb" -gt "$LOG_SIZE_LIMIT_MB" ]; then
            rotate_log "$log_file"
        fi
    done

    log_success "Log rotation complete"
}

# Compress old uncompressed logs
compress_old_logs() {
    log_info "Compressing old uncompressed logs..."

    local count=0

    # Compress logs in main logs directory
    find "$LOGS_DIR" -maxdepth 1 -name "*.log" -type f -mtime +1 | while read -r log_file; do
        if [ "$(basename "$log_file")" != "latest.log" ] && \
           [ "$(basename "$log_file")" != "debug.log" ] && \
           [ "$(basename "$log_file")" != "watchdog.log" ]; then
            log_info "Compressing: $(basename "$log_file")"
            gzip "$log_file"
            ((count++))
        fi
    done

    # Compress logs in archive directory
    find "$ARCHIVE_DIR" -name "*.log" -type f | while read -r log_file; do
        log_info "Compressing: $(basename "$log_file")"
        gzip "$log_file"
        ((count++))
    done

    if [ "$count" -gt 0 ]; then
        log_success "Compressed $count log files"
    else
        log_info "No logs to compress"
    fi
}

# Clean old logs
clean_old_logs() {
    log_info "Cleaning logs older than ${MAX_LOG_AGE_DAYS} days..."

    init_archive

    local count=0

    # Delete old logs from main directory
    find "$LOGS_DIR" -maxdepth 1 \( -name "*.log.gz" -o -name "*.log" \) -type f -mtime +${MAX_LOG_AGE_DAYS} | while read -r log_file; do
        log_info "Deleting old log: $(basename "$log_file")"
        rm -f "$log_file"
        ((count++))
    done

    # Delete old logs from archive
    find "$ARCHIVE_DIR" -name "*.log.gz" -type f -mtime +${MAX_LOG_AGE_DAYS} | while read -r log_file; do
        log_info "Deleting old archive: $(basename "$log_file")"
        rm -f "$log_file"
        ((count++))
    done

    if [ "$count" -gt 0 ]; then
        log_success "Deleted $count old log files"
    else
        log_info "No old logs to delete"
    fi
}

# Limit number of archived logs
limit_archived_logs() {
    log_info "Limiting archived logs to ${MAX_ARCHIVED_LOGS} most recent..."

    if [ ! -d "$ARCHIVE_DIR" ]; then
        return 0
    fi

    local count=$(find "$ARCHIVE_DIR" -name "*.log.gz" -type f | wc -l)

    if [ "$count" -le "$MAX_ARCHIVED_LOGS" ]; then
        log_info "Archive count ($count) within limit"
        return 0
    fi

    log_info "Found $count archived logs, removing oldest..."

    # Delete oldest logs
    find "$ARCHIVE_DIR" -name "*.log.gz" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -${MAX_ARCHIVED_LOGS} | cut -d' ' -f2- | \
        while read -r log_file; do
            log_info "Removing: $(basename "$log_file")"
            rm -f "$log_file"
        done

    log_success "Archive cleaned"
}

# Show log statistics
show_stats() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "           Log Management Statistics"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Current logs
    if [ -d "$LOGS_DIR" ]; then
        local current_count=$(find "$LOGS_DIR" -maxdepth 1 -name "*.log*" -type f | wc -l)
        local current_size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)
        echo "Current Logs:"
        echo "  Count: $current_count"
        echo "  Total Size: $current_size"
        echo ""

        # Show active logs
        echo "Active Logs:"
        for log in latest.log debug.log watchdog.log; do
            if [ -f "${LOGS_DIR}/${log}" ]; then
                local size=$(du -h "${LOGS_DIR}/${log}" 2>/dev/null | cut -f1)
                local lines=$(wc -l < "${LOGS_DIR}/${log}")
                echo "  - ${log}: ${size} (${lines} lines)"
            fi
        done
        echo ""
    fi

    # Archived logs
    if [ -d "$ARCHIVE_DIR" ]; then
        local archive_count=$(find "$ARCHIVE_DIR" -name "*.log.gz" -type f | wc -l)
        local archive_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
        echo "Archived Logs:"
        echo "  Count: $archive_count"
        echo "  Total Size: $archive_size"
        echo ""

        # Show newest archives
        echo "Recent Archives:"
        find "$ARCHIVE_DIR" -name "*.log.gz" -type f -printf '%T@ %p\n' | \
            sort -rn | head -5 | while read -r timestamp path; do
                local size=$(du -h "$path" 2>/dev/null | cut -f1)
                local date=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S')
                echo "  - $(basename "$path") (${size}, ${date})"
            done
        echo ""
    fi

    # Crash reports
    if [ -d "${SERVER_DIR}/crash-reports" ]; then
        local crash_count=$(find "${SERVER_DIR}/crash-reports" -name "crash-*.txt" -type f | wc -l)
        if [ "$crash_count" -gt 0 ]; then
            echo "Crash Reports: $crash_count"
            echo "  Location: crash-reports/"
            echo ""
        fi
    fi

    echo "═══════════════════════════════════════════════════════════"
}

# View log file
view_log() {
    local log_name="${1:-latest.log}"
    local lines="${2:-50}"

    local log_path="${LOGS_DIR}/${log_name}"

    if [ ! -f "$log_path" ]; then
        log_error "Log file not found: $log_name"
        return 1
    fi

    log_info "Showing last $lines lines of $log_name:"
    echo ""
    tail -n "$lines" "$log_path"
}

# Search logs
search_logs() {
    local pattern="$1"
    local log_name="${2:-latest.log}"

    local log_path="${LOGS_DIR}/${log_name}"

    if [ ! -f "$log_path" ]; then
        log_error "Log file not found: $log_name"
        return 1
    fi

    log_info "Searching for '$pattern' in $log_name:"
    echo ""
    grep --color=auto -i "$pattern" "$log_path" || log_warning "No matches found"
}

# Full maintenance - rotate, compress, clean
full_maintenance() {
    log_info "Starting full log maintenance..."
    echo ""

    rotate_all_logs
    echo ""

    compress_old_logs
    echo ""

    clean_old_logs
    echo ""

    limit_archived_logs
    echo ""

    show_stats
}

# Show usage
show_usage() {
    cat << EOF
Minecraft Server Log Management Tool

Usage: $(basename "$0") [command] [options]

Commands:
    rotate                      Rotate current logs
    compress                    Compress old logs
    clean [days]               Clean logs older than N days (default: 30)
    limit [count]              Keep only N most recent archives (default: 50)
    maintenance                 Full maintenance (rotate + compress + clean)
    stats                       Show log statistics
    view [log] [lines]         View log file (default: latest.log, 50 lines)
    search <pattern> [log]     Search in log file
    help                        Show this help message

Options:
    --max-age <days>           Maximum log age in days (default: 30)
    --max-archives <count>     Maximum archived logs to keep (default: 50)
    --size-limit <mb>          Log size limit for rotation (default: 100)

Examples:
    $(basename "$0") rotate                    # Rotate all logs
    $(basename "$0") clean 14                  # Clean logs older than 14 days
    $(basename "$0") maintenance               # Full maintenance
    $(basename "$0") stats                     # Show statistics
    $(basename "$0") view latest.log 100       # View last 100 lines
    $(basename "$0") search "error" latest.log # Search for errors

EOF
}

# Main function
main() {
    local command="${1:-help}"

    # Parse global options
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-age)
                MAX_LOG_AGE_DAYS="$2"
                shift 2
                ;;
            --max-archives)
                MAX_ARCHIVED_LOGS="$2"
                shift 2
                ;;
            --size-limit)
                LOG_SIZE_LIMIT_MB="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        rotate)
            rotate_all_logs
            ;;
        compress)
            compress_old_logs
            ;;
        clean)
            MAX_LOG_AGE_DAYS="${1:-$MAX_LOG_AGE_DAYS}"
            clean_old_logs
            ;;
        limit)
            MAX_ARCHIVED_LOGS="${1:-$MAX_ARCHIVED_LOGS}"
            limit_archived_logs
            ;;
        maintenance)
            full_maintenance
            ;;
        stats)
            show_stats
            ;;
        view)
            view_log "${1:-latest.log}" "${2:-50}"
            ;;
        search)
            if [ -z "${1:-}" ]; then
                log_error "Please provide search pattern"
                exit 1
            fi
            search_logs "$1" "${2:-latest.log}"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
