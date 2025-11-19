#!/usr/bin/env bash
# Minecraft Server Monitoring and Health Check Tool
# Monitor server health, performance, and player activity

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
SERVER_DIR="$SCRIPT_DIR"
LOG_FILE="${SERVER_DIR}/logs/latest.log"
SERVER_PORT=25565
CHECK_INTERVAL=60  # seconds

# Logging functions (wrapper around common.sh functions for consistency)
log_info() { print_info "$*"; }
log_success() { print_success "$*"; }
log_warning() { print_info "$*"; }  # common.sh doesn't have print_warning
log_error() { print_error "$*"; }

# Check if server process is running
check_process() {
    if pgrep -f "fabric-server-launch.jar" > /dev/null; then
        return 0
    fi
    return 1
}

# Check if server port is listening
check_port() {
    if command -v nc &> /dev/null; then
        if nc -z localhost "$SERVER_PORT" 2>/dev/null; then
            return 0
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":${SERVER_PORT} "; then
            return 0
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":${SERVER_PORT} "; then
            return 0
        fi
    fi
    return 1
}

# Get server status
get_server_status() {
    local status="UNKNOWN"
    local process_status="❌ Not Running"
    local port_status="❌ Not Listening"

    if check_process; then
        process_status="✅ Running"
        status="RUNNING"
    fi

    if check_port; then
        port_status="✅ Listening"
        if [ "$status" = "RUNNING" ]; then
            status="ONLINE"
        fi
    fi

    echo -e "${CYAN}Server Status:${NC}"
    echo "  Process: $process_status"
    echo "  Port $SERVER_PORT: $port_status"
    echo "  Overall: $([ "$status" = "ONLINE" ] && echo -e "${GREEN}$status${NC}" || echo -e "${RED}$status${NC}")"
    echo ""
}

# Get server memory usage
get_memory_usage() {
    if ! check_process; then
        echo -e "${YELLOW}Server not running${NC}"
        return 1
    fi

    local pid=$(pgrep -f "fabric-server-launch.jar" | head -1)
    if [ -n "$pid" ]; then
        local mem_kb=$(ps -p "$pid" -o rss= | awk '{print $1}')
        local mem_mb=$((mem_kb / 1024))
        local mem_gb=$(echo "scale=2; $mem_mb / 1024" | bc 2>/dev/null || echo "0")

        echo -e "${CYAN}Memory Usage:${NC}"
        echo "  Process ID: $pid"
        echo "  Memory: ${mem_mb} MB (${mem_gb} GB)"
        echo ""
    fi
}

# Get CPU usage
get_cpu_usage() {
    if ! check_process; then
        echo -e "${YELLOW}Server not running${NC}"
        return 1
    fi

    local pid=$(pgrep -f "fabric-server-launch.jar" | head -1)
    if [ -n "$pid" ] && command -v top &> /dev/null; then
        local cpu=$(top -b -n 1 -p "$pid" 2>/dev/null | tail -1 | awk '{print $9}')
        echo -e "${CYAN}CPU Usage:${NC}"
        echo "  Process ID: $pid"
        echo "  CPU: ${cpu}%"
        echo ""
    fi
}

# Get disk usage
get_disk_usage() {
    echo -e "${CYAN}Disk Usage:${NC}"

    if [ -d "${SERVER_DIR}/world" ]; then
        local world_size=$(du -sh "${SERVER_DIR}/world" 2>/dev/null | cut -f1)
        echo "  World: $world_size"
    fi

    if [ -d "${SERVER_DIR}/backups" ]; then
        local backup_size=$(du -sh "${SERVER_DIR}/backups" 2>/dev/null | cut -f1)
        echo "  Backups: $backup_size"
    fi

    if [ -d "${SERVER_DIR}/logs" ]; then
        local logs_size=$(du -sh "${SERVER_DIR}/logs" 2>/dev/null | cut -f1)
        echo "  Logs: $logs_size"
    fi

    local total_size=$(du -sh "${SERVER_DIR}" 2>/dev/null | cut -f1)
    echo "  Total: $total_size"
    echo ""
}

# Get player count from logs
get_player_count() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}Log file not found${NC}"
        return 1
    fi

    echo -e "${CYAN}Recent Player Activity:${NC}"

    # Count unique players who joined in the last 100 log lines
    local online_count=$(tail -n 100 "$LOG_FILE" 2>/dev/null | \
        grep -oP '\[\d+:\d+:\d+\] \[Server thread/INFO\]: \K[^ ]+(?= joined the game)' | \
        sort -u | wc -l)

    local left_count=$(tail -n 100 "$LOG_FILE" 2>/dev/null | \
        grep -oP '\[\d+:\d+:\d+\] \[Server thread/INFO\]: \K[^ ]+(?= left the game)' | \
        sort -u | wc -l)

    echo "  Players joined recently: $online_count"
    echo "  Players left recently: $left_count"
    echo ""

    # Show last 5 player events
    echo "  Last 5 player events:"
    tail -n 200 "$LOG_FILE" 2>/dev/null | \
        grep -E '(joined|left) the game' | \
        tail -5 | \
        sed 's/^/    /'
    echo ""
}

# Check for errors in logs
check_errors() {
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}Log file not found${NC}"
        return 1
    fi

    echo -e "${CYAN}Recent Errors/Warnings:${NC}"

    local error_count=$(tail -n 100 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo "0")
    local warn_count=$(tail -n 100 "$LOG_FILE" 2>/dev/null | grep -ci 'WARN' || echo "0")

    echo "  Errors in last 100 lines: $error_count"
    echo "  Warnings in last 100 lines: $warn_count"

    if [ "$error_count" -gt 0 ]; then
        echo ""
        echo "  Last 3 errors:"
        tail -n 100 "$LOG_FILE" 2>/dev/null | \
            grep -i 'ERROR\|SEVERE' | \
            tail -3 | \
            sed 's/^/    /'
    fi
    echo ""
}

# Get server TPS (Ticks Per Second) if available
get_tps() {
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    echo -e "${CYAN}Performance Metrics:${NC}"

    # Look for TPS information in logs (if Spark or similar is installed)
    local tps_line=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -i "TPS" | tail -1)
    if [ -n "$tps_line" ]; then
        echo "  $tps_line"
    else
        echo "  TPS info not available (install Spark for detailed metrics)"
    fi

    # Look for tick duration
    local tick_line=$(tail -n 50 "$LOG_FILE" 2>/dev/null | grep -i "Running.*behind\|tick" | tail -1)
    if [ -n "$tick_line" ]; then
        echo "  $tick_line"
    fi
    echo ""
}

# Get server uptime
get_uptime() {
    if ! check_process; then
        echo -e "${YELLOW}Server not running${NC}"
        return 1
    fi

    local pid=$(pgrep -f "fabric-server-launch.jar" | head -1)
    if [ -n "$pid" ]; then
        local uptime_seconds=$(ps -p "$pid" -o etimes= | tr -d ' ')
        local days=$((uptime_seconds / 86400))
        local hours=$(((uptime_seconds % 86400) / 3600))
        local minutes=$(((uptime_seconds % 3600) / 60))

        echo -e "${CYAN}Server Uptime:${NC}"
        echo "  ${days}d ${hours}h ${minutes}m"
        echo ""
    fi
}

# Comprehensive status report
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "           Minecraft Server Health Report"
    echo "           $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    get_server_status
    get_uptime
    get_memory_usage
    get_cpu_usage
    get_disk_usage
    get_player_count
    check_errors
    get_tps

    echo "═══════════════════════════════════════════════════════════"
}

# Watch mode - continuous monitoring
watch_mode() {
    echo "Starting continuous monitoring (Ctrl+C to stop)..."
    echo "Update interval: ${CHECK_INTERVAL} seconds"
    echo ""

    while true; do
        clear
        show_status
        sleep "$CHECK_INTERVAL"
    done
}

# Alert mode - check for critical issues
alert_mode() {
    log_info "Running health check..."

    local issues=0

    # Check if server is running
    if ! check_process; then
        log_error "Server process is not running!"
        ((issues++))
    fi

    # Check if port is listening
    if ! check_port; then
        log_error "Server is not listening on port $SERVER_PORT!"
        ((issues++))
    fi

    # Check for errors in logs
    if [ -f "$LOG_FILE" ]; then
        local recent_errors=$(tail -n 20 "$LOG_FILE" 2>/dev/null | grep -ci 'ERROR\|SEVERE' || echo "0")
        if [ "$recent_errors" -gt 5 ]; then
            log_error "High error rate detected: $recent_errors errors in last 20 log lines!"
            ((issues++))
        fi
    fi

    # Check disk space
    local disk_usage=$(df -h "${SERVER_DIR}" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_error "Disk usage is critical: ${disk_usage}%!"
        ((issues++))
    elif [ "$disk_usage" -gt 80 ]; then
        log_warning "Disk usage is high: ${disk_usage}%"
    fi

    if [ "$issues" -eq 0 ]; then
        log_success "All health checks passed!"
        return 0
    else
        log_error "Health check failed with $issues issue(s)"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Minecraft Server Monitoring Tool

Usage: $(basename "$0") [command] [options]

Commands:
    status          Show comprehensive server status (default)
    watch           Continuous monitoring mode
    alert           Run health check and alert on issues
    players         Show player activity
    errors          Show recent errors
    help            Show this help message

Options:
    --interval <seconds>    Update interval for watch mode (default: 60)

Examples:
    $(basename "$0")                    # Show status
    $(basename "$0") status             # Show detailed status
    $(basename "$0") watch              # Watch mode
    $(basename "$0") alert              # Health check
    $(basename "$0") players            # Show players

EOF
}

# Main function
main() {
    local command="${1:-status}"

    case "$command" in
        status)
            show_status
            ;;
        watch)
            if [ "${2:-}" = "--interval" ]; then
                CHECK_INTERVAL="${3:-60}"
            fi
            watch_mode
            ;;
        alert)
            alert_mode
            ;;
        players)
            get_player_count
            ;;
        errors)
            check_errors
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
