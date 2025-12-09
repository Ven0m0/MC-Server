#!/usr/bin/env bash
# systemd-service.sh: Minecraft server systemd service management
# Extracted from mcctl and modernized

# Source common library
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Service configuration
SERVICE_NAME="minecraft-server"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

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

# Performance
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0
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

# Create Infrarust proxy systemd service
create_infrarust_service(){
  local infrarust_dir="${1:-/opt/infrarust}"
  local run_user="${2:-minecraft}"

  check_root || return 1

  print_header "Setting up Infrarust Minecraft Proxy"

  # Install infrarust if not already installed
  if ! has_command infrarust; then
    print_info "Installing infrarust via cargo..."
    check_dependencies cargo || return 1
    cargo install --locked infrarust || {
      print_error "Failed to install infrarust"
      return 1
    }
    print_success "Infrarust installed successfully"
  else
    print_info "Infrarust already installed"
  fi

  # Create working directory
  if [[ $EUID -eq 0 ]]; then
    mkdir -p "$infrarust_dir"
    chown "$run_user:$run_user" "$infrarust_dir" 2>/dev/null || true
  else
    sudo mkdir -p "$infrarust_dir"
    sudo chown "$run_user:$run_user" "$infrarust_dir" 2>/dev/null || true
  fi

  # Detect infrarust binary location
  local infrarust_bin
  infrarust_bin="$(command -v infrarust 2>/dev/null || echo '/usr/local/bin/infrarust')"

  print_info "Creating infrarust systemd service..."
  print_info "User: ${run_user}"
  print_info "Working directory: ${infrarust_dir}"
  print_info "Binary: ${infrarust_bin}"

  # Create service file
  local service_content
  read -r -d '' service_content <<EOF || true
[Unit]
Description=Infrarust Minecraft Proxy
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${run_user}
WorkingDirectory=${infrarust_dir}
ExecStart=${infrarust_bin}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Performance
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0

[Install]
WantedBy=multi-user.target
EOF

  local infrarust_service="/etc/systemd/system/infrarust.service"

  if [[ $EUID -eq 0 ]]; then
    printf '%s\n' "$service_content" > "$infrarust_service"
    systemctl daemon-reload
  else
    printf '%s\n' "$service_content" | sudo tee "$infrarust_service" >/dev/null
    sudo systemctl daemon-reload
  fi

  print_success "Infrarust service created"
  print_info "Enable with: sudo systemctl enable infrarust"
  print_info "Start with: sudo systemctl start infrarust"
  print_info "Check status with: sudo systemctl status infrarust"
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
    create-infrarust [dir] [user]  Create Infrarust proxy service
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
    $0 create-infrarust /opt/infrarust minecraft
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
    - create-infrarust also installs infrarust via cargo if needed
EOF
}

# Command dispatcher
case "${1:-help}" in
  create) create_service "${2:-}" "${3:-}" "${4:-}" ;;
  create-infrarust) create_infrarust_service "${2:-}" "${3:-}" ;;
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
