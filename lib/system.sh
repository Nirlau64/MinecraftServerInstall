#!/usr/bin/env bash
# System Integration Module
# ========================
# This module handles system-level integrations including:
# - systemd service generation and management
# - tmux session management
# - Service collision detection
# - System service monitoring

# -----------------------------------------------------------------------------
# SYSTEMD SERVICE MANAGEMENT
# -----------------------------------------------------------------------------

# Generate systemd service file for the Minecraft server
# Usage: create_systemd_service [service_name] [service_user] [working_dir] [start_script]
create_systemd_service() {
    local service_name="${1:-minecraft}"
    local service_user="${2:-$(id -un)}"
    local working_dir="${3:-$(pwd)}"
    local start_script="${4:-$working_dir/start.sh}"
    local java_args="${5:-${JAVA_ARGS:-$(get_memory_args 2>/dev/null || echo "-Xmx2G")}}"
    
    log_info "Generating systemd service file for '$service_name'..."
    
    # Ensure dist directory exists
    mkdir -p dist
    local service_path="dist/${service_name}.service"
    
    # Validate inputs
    if [[ ! -f "$start_script" ]]; then
        log_warn "Start script not found: $start_script"
        log_info "Service file will be created but may need adjustment"
    fi
    
    # Generate service file
    cat > "$service_path" <<EOF
[Unit]
Description=Minecraft Server ($service_name)
After=network.target
Wants=network.target

[Service]
Type=simple
User=$service_user
Group=$service_user
WorkingDirectory=$working_dir
ExecStart=$start_script
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="JAVA_ARGS=$java_args"

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$working_dir

# Resource limits (adjust as needed)
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "systemd service file created: $service_path"
    log_info "To install the service:"
    log_info "  sudo cp '$service_path' '/etc/systemd/system/${service_name}.service'"
    log_info "  sudo systemctl daemon-reload"
    log_info "  sudo systemctl enable '$service_name'"
    log_info "  sudo systemctl start '$service_name'"
    
    return 0
}

# Check for systemd service conflicts and status
# Usage: check_systemd_service [service_name]
check_systemd_service() {
    local service_name="${1:-minecraft}"
    
    # Check if systemctl is available
    if ! command -v systemctl >/dev/null 2>&1; then
        log_debug "systemctl not available - systemd not in use"
        return 0
    fi
    
    log_info "Checking systemd service status for '$service_name'..."
    
    # Check if service is active
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_warn "systemd service '$service_name' is already active."
        local status_info
        status_info=$(systemctl status "$service_name" --no-pager -l | head -n 10)
        log_info "Service status:\n$status_info"
        return 1
    # Check if service is enabled but not active
    elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log_warn "systemd service '$service_name' is enabled but not active."
        log_info "Use 'sudo systemctl start $service_name' to start it."
        return 0
    # Check if service file exists but not enabled
    elif systemctl list-unit-files "$service_name.service" --no-pager 2>/dev/null | grep -q "$service_name"; then
        log_info "systemd service '$service_name' exists but is not enabled."
        return 0
    else
        log_debug "No existing systemd service found for '$service_name'"
        return 0
    fi
}

# Install and start systemd service
# Usage: install_systemd_service <service_file> [service_name]
install_systemd_service() {
    local service_file="$1"
    local service_name="${2:-minecraft}"
    
    [[ -f "$service_file" ]] || {
        log_error "Service file not found: $service_file"
        return 1
    }
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "sudo access required to install systemd service"
        log_info "Please run: sudo cp '$service_file' '/etc/systemd/system/${service_name}.service'"
        return 1
    fi
    
    log_info "Installing systemd service..."
    
    # Copy service file
    if sudo cp "$service_file" "/etc/systemd/system/${service_name}.service"; then
        log_info "Service file installed successfully"
    else
        log_error "Failed to install service file"
        return 1
    fi
    
    # Reload systemd daemon
    if sudo systemctl daemon-reload; then
        log_info "systemd daemon reloaded"
    else
        log_error "Failed to reload systemd daemon"
        return 1
    fi
    
    # Enable service
    if sudo systemctl enable "$service_name"; then
        log_info "Service enabled successfully"
    else
        log_error "Failed to enable service"
        return 1
    fi
    
    # Start service if requested
    if [[ "${AUTO_START_SERVICE:-0}" = "1" ]]; then
        if sudo systemctl start "$service_name"; then
            log_info "Service started successfully"
        else
            log_error "Failed to start service"
            return 1
        fi
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# TMUX SESSION MANAGEMENT  
# -----------------------------------------------------------------------------

# Create and start tmux session for the server
# Usage: create_tmux_session [session_name] [start_command] [working_dir]
create_tmux_session() {
    local session_name="${1:-minecraft}"
    local start_command="${2:-$(pwd)/start.sh}"
    local working_dir="${3:-$(pwd)}"
    
    # Check if tmux is available
    if ! command -v tmux >/dev/null 2>&1; then
        log_error "tmux is not installed. Please install tmux to use this feature."
        log_info "On Ubuntu/Debian: sudo apt install tmux"
        log_info "On CentOS/RHEL: sudo yum install tmux"
        return 1
    fi
    
    log_info "Setting up tmux session '$session_name'..."
    
    # Check if session already exists
    if tmux has-session -t "$session_name" 2>/dev/null; then
        log_warn "tmux session '$session_name' already exists."
        log_info "Attach with: tmux attach -t '$session_name'"
        log_info "Or kill existing session: tmux kill-session -t '$session_name'"
        return 1
    fi
    
    # Check for systemd service conflicts
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$session_name" 2>/dev/null; then
        log_warn "systemd service '$session_name' is already running."
        log_warn "Not starting tmux session to avoid conflict."
        log_info "Stop the service first: sudo systemctl stop '$session_name'"
        return 1
    fi
    
    # Validate start command
    if [[ ! -f "$start_command" ]]; then
        log_error "Start script not found: $start_command"
        return 1
    fi
    
    if [[ ! -x "$start_command" ]]; then
        log_warn "Start script is not executable: $start_command"
        log_info "Making it executable..."
        chmod +x "$start_command" || {
            log_error "Failed to make start script executable"
            return 1
        }
    fi
    
    # Create tmux session
    log_info "Starting server in new tmux session '$session_name'..."
    cd "$working_dir" || {
        log_error "Failed to change to working directory: $working_dir"
        return 1
    }
    
    if tmux new-session -d -s "$session_name" "$start_command"; then
        log_info "tmux session '$session_name' started successfully"
        log_info "Attach with: tmux attach -t '$session_name'"
        log_info "Detach with: Ctrl+B then D"
        return 0
    else
        log_error "Failed to create tmux session"
        return 1
    fi
}

# Check tmux session status
# Usage: check_tmux_session [session_name]
check_tmux_session() {
    local session_name="${1:-minecraft}"
    
    if ! command -v tmux >/dev/null 2>&1; then
        log_debug "tmux not available"
        return 0
    fi
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        log_info "tmux session '$session_name' is running"
        log_info "Attach with: tmux attach -t '$session_name'"
        return 0
    else
        log_debug "tmux session '$session_name' not found"
        return 1
    fi
}

# Stop tmux session
# Usage: stop_tmux_session [session_name]
stop_tmux_session() {
    local session_name="${1:-minecraft}"
    
    if ! command -v tmux >/dev/null 2>&1; then
        log_debug "tmux not available"
        return 0
    fi
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        log_info "Stopping tmux session '$session_name'..."
        if tmux kill-session -t "$session_name"; then
            log_info "tmux session stopped successfully"
            return 0
        else
            log_error "Failed to stop tmux session"
            return 1
        fi
    else
        log_debug "tmux session '$session_name' not running"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# SERVICE MANAGEMENT UTILITIES
# -----------------------------------------------------------------------------

# Setup system integration based on flags
# Usage: setup_system_integration
setup_system_integration() {
    local setup_systemd="${SYSTEMD:-0}"
    local setup_tmux="${TMUX:-0}"
    local service_name="${SERVICE_NAME:-minecraft}"
    
    # systemd service setup
    if [[ "$setup_systemd" = "1" ]]; then
        log_info "Setting up systemd integration..."
        
        if create_systemd_service "$service_name"; then
            # Check for conflicts after creation
            check_systemd_service "$service_name"
        else
            log_error "Failed to create systemd service"
        fi
    fi
    
    # tmux session setup
    if [[ "$setup_tmux" = "1" ]]; then
        log_info "Setting up tmux integration..."
        
        if create_tmux_session "$service_name"; then
            log_info "Server started in tmux session"
        else
            log_error "Failed to create tmux session"
        fi
    fi
    
    # If neither is requested, just log completion
    if [[ "$setup_systemd" != "1" && "$setup_tmux" != "1" ]]; then
        log_info "No system integration requested"
        log_info "Server setup complete. Start manually with: ./start.sh"
    fi
}

# Check all system integrations
# Usage: check_system_status [service_name]
check_system_status() {
    local service_name="${1:-minecraft}"
    
    log_info "Checking system integration status..."
    
    # Check systemd
    if check_systemd_service "$service_name"; then
        log_debug "systemd service check completed"
    fi
    
    # Check tmux
    if check_tmux_session "$service_name"; then
        log_debug "tmux session check completed" 
    fi
    
    # Check for port conflicts
    check_port_conflicts
}

# Check for port conflicts
# Usage: check_port_conflicts [port]
check_port_conflicts() {
    local port="${1:-25565}"
    
    log_info "Checking for port conflicts on port $port..."
    
    # Use different methods depending on available tools
    local port_check_result=""
    
    if command -v ss >/dev/null 2>&1; then
        port_check_result=$(ss -tlnp | grep ":$port ")
    elif command -v netstat >/dev/null 2>&1; then
        port_check_result=$(netstat -tlnp 2>/dev/null | grep ":$port ")
    elif command -v lsof >/dev/null 2>&1; then
        port_check_result=$(lsof -i ":$port" 2>/dev/null)
    else
        log_warn "No port checking tools available (ss, netstat, lsof)"
        return 0
    fi
    
    if [[ -n "$port_check_result" ]]; then
        log_warn "Port $port appears to be in use:"
        log_info "$port_check_result"
        return 1
    else
        log_info "Port $port is available"
        return 0
    fi
}

# Clean up system integrations
# Usage: cleanup_system_integration [service_name]
cleanup_system_integration() {
    local service_name="${1:-minecraft}"
    
    log_info "Cleaning up system integrations..."
    
    # Stop tmux session if running
    stop_tmux_session "$service_name"
    
    # Note: We don't automatically remove systemd services as they may be intentionally installed
    if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log_info "systemd service '$service_name' is installed and enabled"
        log_info "To remove: sudo systemctl disable --now '$service_name' && sudo rm '/etc/systemd/system/${service_name}.service'"
    fi
}

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------

# Get system information for integration setup
# Usage: get_system_info
get_system_info() {
    log_info "System Integration Information:"
    echo "  OS: $(uname -s)"
    echo "  User: $(id -un)"
    echo "  Working Directory: $(pwd)"
    echo "  systemctl Available: $(command -v systemctl >/dev/null && echo "Yes" || echo "No")"
    echo "  tmux Available: $(command -v tmux >/dev/null && echo "Yes" || echo "No")"
    
    # Check for existing services
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files "minecraft.service" --no-pager 2>/dev/null | grep -q minecraft; then
            echo "  Existing systemd service: Yes"
        else
            echo "  Existing systemd service: No"
        fi
    fi
    
    # Check for existing tmux sessions
    if command -v tmux >/dev/null 2>&1; then
        if tmux has-session -t minecraft 2>/dev/null; then
            echo "  Existing tmux session: Yes"
        else
            echo "  Existing tmux session: No"
        fi
    fi
}

# Export this module is loaded
declare -g SYSTEM_MODULE_LOADED=1