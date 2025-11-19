#!/usr/bin/env bash
# Minecraft Server Watchdog - Automatic Restart and Crash Recovery
# Monitors server health and automatically restarts on crashes

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
SERVER_DIR="$SCRIPT_DIR"
SERVER_START_SCRIPT="${SERVER_DIR}/scripts/server-start.sh"
CHECK_INTERVAL=30  # seconds
MAX_RESTART_ATTEMPTS=3
RESTART_COOLDOWN=300  # 5 minutes
PID_FILE="${SERVER_DIR}/.server.pid"
LOG_FILE="${SERVER_DIR}/logs/watchdog.log"

# State tracking
RESTART_COUNT=0
LAST_RESTART_TIME=0

# Logging functions with file output
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
    print_info "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
    print_success "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*"
    print_info "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"
    print_error "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Initialize log directory
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# Check if server process is running
is_server_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi

    # Fallback: check for process by name
    if pgrep -f "fabric-server-launch.jar" > /dev/null; then
        return 0
    fi

    return 1
}

# Get current timestamp
get_timestamp() {
    date +%s
}

# Check if enough time has passed since last restart
can_restart() {
    local current_time=$(get_timestamp)
    local time_since_restart=$((current_time - LAST_RESTART_TIME))

    if [ "$time_since_restart" -lt "$RESTART_COOLDOWN" ]; then
        log_warning "Too soon to restart. Waiting $((RESTART_COOLDOWN - time_since_restart)) more seconds..."
        return 1
    fi

    if [ "$RESTART_COUNT" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        log_error "Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached. Manual intervention required."
        return 1
    fi

    return 0
}

# Create backup before restart
create_emergency_backup() {
    log_info "Creating emergency backup before restart..."

    if [ -x "${SCRIPT_DIR}/backup.sh" ]; then
        "${SCRIPT_DIR}/backup.sh" backup world --max-backups 5 || {
            log_warning "Emergency backup failed, continuing with restart..."
        }
    else
        log_warning "Backup script not found, skipping emergency backup"
    fi
}

# Start the server
start_server() {
    log_info "Starting Minecraft server..."

    if [ ! -x "$SERVER_START_SCRIPT" ]; then
        log_error "Server start script not found or not executable: $SERVER_START_SCRIPT"
        return 1
    fi

    cd "$SERVER_DIR"

    # Start server in screen session if available
    if command -v screen &> /dev/null; then
        screen -dmS minecraft bash -c "cd '$SERVER_DIR' && '$SERVER_START_SCRIPT'"
        log_success "Server started in screen session 'minecraft'"
    # Or use tmux if available
    elif command -v tmux &> /dev/null; then
        tmux new-session -d -s minecraft "cd '$SERVER_DIR' && '$SERVER_START_SCRIPT'"
        log_success "Server started in tmux session 'minecraft'"
    else
        # Start in background
        nohup "$SERVER_START_SCRIPT" > "${SERVER_DIR}/logs/server.log" 2>&1 &
        local pid=$!
        echo "$pid" > "$PID_FILE"
        log_success "Server started with PID: $pid"
    fi

    # Wait for server to initialize
    log_info "Waiting for server to start..."
    sleep 30

    if is_server_running; then
        log_success "Server started successfully"
        LAST_RESTART_TIME=$(get_timestamp)
        ((RESTART_COUNT++))
        return 0
    else
        log_error "Server failed to start"
        return 1
    fi
}

# Stop the server gracefully
stop_server() {
    log_info "Stopping server gracefully..."

    # Try sending stop command to screen/tmux session
    if screen -list 2>/dev/null | grep -q "minecraft"; then
        screen -S minecraft -X stuff "stop^M"
        log_info "Stop command sent to screen session"
    elif tmux list-sessions 2>/dev/null | grep -q "minecraft"; then
        tmux send-keys -t minecraft "stop" Enter
        log_info "Stop command sent to tmux session"
    fi

    # Wait for graceful shutdown
    local wait_time=0
    while is_server_running && [ $wait_time -lt 60 ]; do
        sleep 5
        ((wait_time += 5))
        log_info "Waiting for server to stop... (${wait_time}s)"
    done

    # Force kill if still running
    if is_server_running; then
        log_warning "Server did not stop gracefully, force killing..."
        pkill -9 -f "fabric-server-launch.jar" || true
        sleep 5
    fi

    if ! is_server_running; then
        log_success "Server stopped"
        return 0
    else
        log_error "Failed to stop server"
        return 1
    fi
}

# Restart the server
restart_server() {
    log_info "Initiating server restart..."

    if ! can_restart; then
        return 1
    fi

    # Create emergency backup
    create_emergency_backup

    # Stop server if running
    if is_server_running; then
        stop_server || {
            log_error "Failed to stop server, aborting restart"
            return 1
        }
    fi

    # Start server
    start_server
}

# Check server health
check_health() {
    if ! is_server_running; then
        log_error "Server is not running!"
        return 1
    fi

    # Check if server is responding (check log activity)
    local log_file="${SERVER_DIR}/logs/latest.log"
    if [ -f "$log_file" ]; then
        local last_log_time=$(stat -c %Y "$log_file" 2>/dev/null || echo "0")
        local current_time=$(get_timestamp)
        local time_since_log=$((current_time - last_log_time))

        # If no log activity for 5 minutes, server might be frozen
        if [ "$time_since_log" -gt 300 ]; then
            log_warning "No log activity for ${time_since_log} seconds - server may be frozen"
            return 1
        fi
    fi

    return 0
}

# Monitor mode - continuous monitoring with auto-restart
monitor_mode() {
    log_info "Starting watchdog monitor (Ctrl+C to stop)"
    log_info "Check interval: ${CHECK_INTERVAL}s, Max restart attempts: ${MAX_RESTART_ATTEMPTS}"

    while true; do
        if ! check_health; then
            log_error "Health check failed - attempting restart"

            if restart_server; then
                log_success "Server restarted successfully"

                # Reset restart count after successful cooldown period
                sleep "$RESTART_COOLDOWN"
                RESTART_COUNT=0
                log_info "Restart counter reset"
            else
                log_error "Failed to restart server"

                # If we've hit max attempts, wait longer before trying again
                if [ "$RESTART_COUNT" -ge "$MAX_RESTART_ATTEMPTS" ]; then
                    log_error "Maximum restart attempts reached. Waiting 30 minutes before retry..."
                    sleep 1800
                    RESTART_COUNT=0
                    LAST_RESTART_TIME=0
                fi
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Scheduled restart (with warning)
scheduled_restart() {
    local warning_time="${1:-300}"  # 5 minutes default

    log_info "Scheduled restart initiated. Warning time: ${warning_time}s"

    # Send warnings to players
    if screen -list 2>/dev/null | grep -q "minecraft"; then
        for time in 300 180 120 60 30 10; do
            if [ "$time" -le "$warning_time" ] && [ "$warning_time" -gt 0 ]; then
                screen -S minecraft -X stuff "say Server restart in ${time} seconds!^M"
                log_info "Sent ${time}s warning to players"

                if [ "$time" -eq "$warning_time" ]; then
                    sleep "$warning_time"
                    warning_time=0
                else
                    sleep $((warning_time - time + 10))
                    warning_time=$((time - 10))
                fi
            fi
        done
    fi

    # Perform restart
    restart_server
}

# Show usage
show_usage() {
    cat << EOF
Minecraft Server Watchdog - Automatic Restart and Crash Recovery

Usage: $(basename "$0") [command] [options]

Commands:
    monitor                Start watchdog monitor (auto-restart on crash)
    restart [warning_time] Schedule server restart with optional warning (seconds)
    start                  Start the server
    stop                   Stop the server
    status                 Check if server is running
    help                   Show this help message

Options:
    --interval <seconds>   Check interval for monitor mode (default: 30)
    --max-attempts <num>   Max restart attempts (default: 3)
    --cooldown <seconds>   Time between restart attempts (default: 300)

Examples:
    $(basename "$0") monitor           # Start watchdog
    $(basename "$0") restart 600       # Restart with 10min warning
    $(basename "$0") restart 0         # Restart immediately
    $(basename "$0") start             # Start server
    $(basename "$0") stop              # Stop server

Note: Monitor mode should be run in a screen/tmux session or as a service

EOF
}

# Main function
main() {
    init_logging

    local command="${1:-help}"

    # Parse global options
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --max-attempts)
                MAX_RESTART_ATTEMPTS="$2"
                shift 2
                ;;
            --cooldown)
                RESTART_COOLDOWN="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        monitor)
            monitor_mode
            ;;
        restart)
            scheduled_restart "${1:-300}"
            ;;
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        status)
            if is_server_running; then
                log_success "Server is running"
                exit 0
            else
                log_error "Server is not running"
                exit 1
            fi
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

# Handle Ctrl+C gracefully
trap 'log_info "Watchdog stopped by user"; exit 0' INT TERM

# Run main function
main "$@"
