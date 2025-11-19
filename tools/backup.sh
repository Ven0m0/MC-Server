#!/usr/bin/env bash
# Minecraft Server Backup Tool
# Automated backup solution for worlds, configurations, and plugins

# Source common functions (SCRIPT_DIR is auto-initialized)
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

init_strict_mode

# Configuration
SERVER_DIR="$SCRIPT_DIR"
BACKUP_DIR="${SERVER_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_BACKUPS=10  # Keep last 10 backups

# Logging functions (wrapper around common.sh functions for consistency)
log_info() { print_info "$*"; }
log_success() { print_success "$*"; }
log_warning() { print_info "$*"; }  # common.sh doesn't have print_warning
log_error() { print_error "$*"; }

# Create backup directory structure
init_backup_dir() {
    mkdir -p "${BACKUP_DIR}/worlds"
    mkdir -p "${BACKUP_DIR}/configs"
    mkdir -p "${BACKUP_DIR}/temp"
}

# Backup world data
backup_world() {
    local backup_name="world_${TIMESTAMP}.tar.gz"
    local backup_path="${BACKUP_DIR}/worlds/${backup_name}"

    log_info "Backing up world data..."

    if [ -d "${SERVER_DIR}/world" ]; then
        cd "${SERVER_DIR}"
        tar -czf "${backup_path}" world/ world_nether/ world_the_end/ 2>/dev/null || \
            tar -czf "${backup_path}" world/ 2>/dev/null || {
                log_error "Failed to backup world data"
                return 1
            }

        local size=$(du -h "${backup_path}" | cut -f1)
        log_success "World backup created: ${backup_name} (${size})"
        return 0
    else
        log_warning "No world directory found, skipping world backup"
        return 1
    fi
}

# Backup configuration files
backup_configs() {
    local backup_name="config_${TIMESTAMP}.tar.gz"
    local backup_path="${BACKUP_DIR}/configs/${backup_name}"

    log_info "Backing up configuration files..."

    cd "${SERVER_DIR}"
    tar -czf "${backup_path}" \
        --exclude='*.jar' \
        --exclude='mods' \
        --exclude='world*' \
        --exclude='logs' \
        --exclude='crash-reports' \
        --exclude='backups' \
        config/ server.properties *.yml *.yaml *.toml *.ini *.json *.json5 2>/dev/null || {
            log_error "Failed to backup configuration files"
            return 1
        }

    local size=$(du -h "${backup_path}" | cut -f1)
    log_success "Config backup created: ${backup_name} (${size})"
    return 0
}

# Backup mods directory
backup_mods() {
    local backup_name="mods_${TIMESTAMP}.tar.gz"
    local backup_path="${BACKUP_DIR}/configs/${backup_name}"

    log_info "Backing up mods directory..."

    if [ -d "${SERVER_DIR}/mods" ]; then
        cd "${SERVER_DIR}"
        tar -czf "${backup_path}" mods/ || {
            log_error "Failed to backup mods"
            return 1
        }

        local size=$(du -h "${backup_path}" | cut -f1)
        log_success "Mods backup created: ${backup_name} (${size})"
        return 0
    else
        log_warning "No mods directory found, skipping mods backup"
        return 1
    fi
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last ${MAX_BACKUPS})..."

    # Clean old world backups
    if [ -d "${BACKUP_DIR}/worlds" ]; then
        local count=$(find "${BACKUP_DIR}/worlds" -name "world_*.tar.gz" | wc -l)
        if [ "$count" -gt "$MAX_BACKUPS" ]; then
            find "${BACKUP_DIR}/worlds" -name "world_*.tar.gz" -type f -printf '%T@ %p\n' | \
                sort -n | head -n -${MAX_BACKUPS} | cut -d' ' -f2- | xargs rm -f
            log_success "Removed old world backups"
        fi
    fi

    # Clean old config backups
    if [ -d "${BACKUP_DIR}/configs" ]; then
        local count=$(find "${BACKUP_DIR}/configs" -name "config_*.tar.gz" | wc -l)
        if [ "$count" -gt "$MAX_BACKUPS" ]; then
            find "${BACKUP_DIR}/configs" -name "config_*.tar.gz" -type f -printf '%T@ %p\n' | \
                sort -n | head -n -${MAX_BACKUPS} | cut -d' ' -f2- | xargs rm -f
            log_success "Removed old config backups"
        fi
    fi
}

# List available backups
list_backups() {
    log_info "Available backups:"
    echo ""

    if [ -d "${BACKUP_DIR}/worlds" ]; then
        echo "World Backups:"
        find "${BACKUP_DIR}/worlds" -name "world_*.tar.gz" -type f -printf '%T@ %p\n' | \
            sort -rn | while read -r timestamp path; do
                local size=$(du -h "$path" | cut -f1)
                local date=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S')
                echo "  - $(basename "$path") (${size}, ${date})"
            done
        echo ""
    fi

    if [ -d "${BACKUP_DIR}/configs" ]; then
        echo "Config Backups:"
        find "${BACKUP_DIR}/configs" -name "config_*.tar.gz" -type f -printf '%T@ %p\n' | \
            sort -rn | head -n 5 | while read -r timestamp path; do
                local size=$(du -h "$path" | cut -f1)
                local date=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S')
                echo "  - $(basename "$path") (${size}, ${date})"
            done
        echo ""
    fi
}

# Restore backup
restore_backup() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_warning "This will restore backup and may overwrite existing data!"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled"
        return 0
    fi

    log_info "Restoring backup: $(basename "$backup_file")"
    cd "${SERVER_DIR}"
    tar -xzf "$backup_file" || {
        log_error "Failed to restore backup"
        return 1
    }

    log_success "Backup restored successfully"
    return 0
}

# Send command to running server (requires screen or tmux)
send_server_command() {
    local cmd="$1"

    # Try screen first
    if screen -list | grep -q "minecraft"; then
        screen -S minecraft -X stuff "${cmd}^M"
        return 0
    fi

    # Try tmux
    if tmux list-sessions 2>/dev/null | grep -q "minecraft"; then
        tmux send-keys -t minecraft "${cmd}" Enter
        return 0
    fi

    return 1
}

# Create backup with server notifications
backup_with_notification() {
    local do_world="${1:-true}"
    local do_config="${2:-true}"
    local do_mods="${3:-false}"

    # Notify players if server is running
    if send_server_command "say Backup starting in 10 seconds..."; then
        log_info "Notified players, waiting 10 seconds..."
        sleep 10

        # Save world and disable auto-save
        send_server_command "save-all"
        sleep 2
        send_server_command "save-off"
        log_info "World saved, auto-save disabled"
    fi

    # Perform backups
    [ "$do_world" = true ] && backup_world
    [ "$do_config" = true ] && backup_configs
    [ "$do_mods" = true ] && backup_mods

    # Re-enable auto-save
    if send_server_command "save-on"; then
        send_server_command "say Backup complete!"
        log_success "Backup complete, auto-save re-enabled"
    fi

    # Cleanup old backups
    cleanup_old_backups
}

# Show usage
show_usage() {
    cat << EOF
Minecraft Server Backup Tool

Usage: $(basename "$0") [command] [options]

Commands:
    backup [world|config|mods|all]  Create backup (default: all)
    list                            List available backups
    restore <backup_file>           Restore from backup
    cleanup                         Clean old backups
    help                            Show this help message

Options:
    --max-backups <num>            Number of backups to keep (default: 10)

Examples:
    $(basename "$0") backup             # Backup everything
    $(basename "$0") backup world       # Backup only world
    $(basename "$0") list               # List all backups
    $(basename "$0") restore backups/worlds/world_20250119_120000.tar.gz
    $(basename "$0") cleanup            # Remove old backups

EOF
}

# Main function
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-backups)
                MAX_BACKUPS="$2"
                shift 2
                ;;
            backup)
                shift
                init_backup_dir

                case "${1:-all}" in
                    world)
                        backup_with_notification true false false
                        ;;
                    config)
                        backup_with_notification false true false
                        ;;
                    mods)
                        backup_with_notification false false true
                        ;;
                    all|*)
                        backup_with_notification true true true
                        ;;
                esac
                exit 0
                ;;
            list)
                list_backups
                exit 0
                ;;
            restore)
                if [ -z "${2:-}" ]; then
                    log_error "Please specify backup file to restore"
                    exit 1
                fi
                restore_backup "$2"
                exit 0
                ;;
            cleanup)
                cleanup_old_backups
                exit 0
                ;;
            help|--help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown command: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Default action
    show_usage
}

# Run main function
main "$@"
