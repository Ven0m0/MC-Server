#!/usr/bin/env bash
# systemd-service.sh: Minecraft server systemd service management
# Extracted from mcctl and modernized

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

# Service configuration
SERVICE_NAME="minecraft-server"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Output formatting helpers
print_header(){ printf '\033[0;34m==>\033[0m %s\n' "$1"; }
print_success(){ printf '\033[0;32m✓\033[0m %s\n' "$1"; }
print_error(){ printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; }
print_info(){ printf '\033[1;33m→\033[0m %s\n' "$1"; }

# Check if command exists
has_command(){ command -v "$1" &>/dev/null; }

# Check if running as root or with sudo
check_root(){
  [[ $EUID -eq 0 ]] && return 0
  has_command sudo && {
    print_info "Root access required. Using sudo..."
    return 0
  }
  print_error "Root access required but sudo not available"
  return 1
}

# Detect Java command
detect_java(){
  local java_cmd="java"

  if has_command archlinux-java; then
    local sel_java
    sel_java="$(archlinux-java get 2>/dev/null || echo '')"
    [[ -n $sel_java ]] && java_cmd="/usr/lib/jvm/${sel_java}/bin/java"
  elif has_command mise; then
    java_cmd="$(mise which java 2>/dev/null || echo 'java')"
  fi

  [[ -x $java_cmd ]] || java_cmd="java"

  printf '%s' "$java_cmd"
}

# Create systemd service file
create_service(){
  local start_script="${1:-${SCRIPT_DIR}/scripts/server-start.sh}"
  local working_dir="${2:-${SCRIPT_DIR}}"
  local run_user="${3:-${user}}"

  check_root || return 1

  [[ ! -f $start_script ]] && {
    print_error "Start script not found: ${start_script}"
    return 1
  }

  print_header "Creating systemd service"

  local java_cmd
  java_cmd=$(detect_java)

  print_info "User: ${run_user}"
  print_info "Working directory: ${working_dir}"
  print_info "Start script: ${start_script}"
  print_info "Java: ${java_cmd}"

  # Create service file
  local service_content
  read -r -d '' service_content <<EOF || true
[Unit]
Description=Minecraft Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${run_user}
WorkingDirectory=${working_dir}
ExecStart=${start_script}
ExecStop=/bin/kill -SIGTERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Resource limits
MemoryMax=90%
CPUQuota=95%

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${working_dir}

# Allow network access
PrivateNetwork=false

[Install]
WantedBy=multi-user.target
EOF

  if [[ $EUID -eq 0 ]]; then
    printf '%s\n' "$service_content" > "$SERVICE_FILE"
  else
    printf '%s\n' "$service_content" | sudo tee "$SERVICE_FILE" >/dev/null
  fi

  # Reload systemd
  if [[ $EUID -eq 0 ]]; then
    systemctl daemon-reload
  else
    sudo systemctl daemon-reload
  fi

  print_success "Service created: ${SERVICE_NAME}"
  print_info "Enable with: sudo systemctl enable ${SERVICE_NAME}"
  print_info "Start with: sudo systemctl start ${SERVICE_NAME}"
}

# Remove systemd service
remove_service(){
  check_root || return 1

  print_header "Removing systemd service"

  # Stop service if running
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    print_info "Stopping service..."
    if [[ $EUID -eq 0 ]]; then
      systemctl stop "$SERVICE_NAME"
    else
      sudo systemctl stop "$SERVICE_NAME"
    fi
  fi

  # Disable service if enabled
  if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    print_info "Disabling service..."
    if [[ $EUID -eq 0 ]]; then
      systemctl disable "$SERVICE_NAME"
    else
      sudo systemctl disable "$SERVICE_NAME"
    fi
  fi

  # Remove service file
  [[ -f $SERVICE_FILE ]] && {
    if [[ $EUID -eq 0 ]]; then
      rm -f "$SERVICE_FILE"
    else
      sudo rm -f "$SERVICE_FILE"
    fi
  }

  # Reload systemd
  if [[ $EUID -eq 0 ]]; then
    systemctl daemon-reload
  else
    sudo systemctl daemon-reload
  fi

  print_success "Service removed"
}

# Enable service
enable_service(){
  check_root || return 1

  [[ ! -f $SERVICE_FILE ]] && {
    print_error "Service not found. Create it first with: $0 create"
    return 1
  }

  print_info "Enabling ${SERVICE_NAME}..."

  if [[ $EUID -eq 0 ]]; then
    systemctl enable "$SERVICE_NAME"
  else
    sudo systemctl enable "$SERVICE_NAME"
  fi

  print_success "Service enabled (will start on boot)"
}

# Start service
start_service(){
  check_root || return 1

  [[ ! -f $SERVICE_FILE ]] && {
    print_error "Service not found. Create it first with: $0 create"
    return 1
  }

  print_info "Starting ${SERVICE_NAME}..."

  if [[ $EUID -eq 0 ]]; then
    systemctl start "$SERVICE_NAME"
  else
    sudo systemctl start "$SERVICE_NAME"
  fi

  print_success "Service started"
}

# Stop service
stop_service(){
  check_root || return 1

  print_info "Stopping ${SERVICE_NAME}..."

  if [[ $EUID -eq 0 ]]; then
    systemctl stop "$SERVICE_NAME"
  else
    sudo systemctl stop "$SERVICE_NAME"
  fi

  print_success "Service stopped"
}

# Show service status
show_status(){
  if [[ ! -f $SERVICE_FILE ]]; then
    print_info "Service not installed"
    return 0
  fi

  systemctl status "$SERVICE_NAME" --no-pager || true
}

# Show logs
show_logs(){
  local lines="${1:-50}"

  [[ ! -f $SERVICE_FILE ]] && {
    print_error "Service not found"
    return 1
  }

  journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

# Follow logs
follow_logs(){
  [[ ! -f $SERVICE_FILE ]] && {
    print_error "Service not found"
    return 1
  }

  journalctl -u "$SERVICE_NAME" -f
}

# Show usage
show_usage(){
  cat <<EOF
Minecraft Server Systemd Service Management

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    create [script] [dir] [user]   Create systemd service
    remove                         Remove systemd service
    enable                         Enable service (auto-start on boot)
    start                          Start service
    stop                           Stop service
    restart                        Restart service
    status                         Show service status
    logs [lines]                   Show logs (default: 50 lines)
    follow                         Follow logs in real-time
    help                           Show this help

EXAMPLES:
    $0 create
    $0 create ./scripts/server-start.sh /opt/minecraft minecraft
    $0 enable
    $0 start
    $0 status
    $0 logs 100
    $0 follow

NOTES:
    - Requires root/sudo access
    - Service name: ${SERVICE_NAME}
    - Service file: ${SERVICE_FILE}
    - Logs via journalctl
EOF
}

# Command dispatcher
case "${1:-help}" in
  create) create_service "${2:-}" "${3:-}" "${4:-}" ;;
  remove) remove_service ;;
  enable) enable_service ;;
  start) start_service ;;
  stop) stop_service ;;
  restart)
    stop_service
    sleep 2
    start_service
    ;;
  status) show_status ;;
  logs) show_logs "${2:-50}" ;;
  follow) follow_logs ;;
  help | --help | -h) show_usage ;;
  *)
    print_error "Unknown command: $1"
    show_usage
    exit 1
    ;;
esac
