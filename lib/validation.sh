#!/usr/bin/env bash
# =============================================================================
# Validation Module - Universal Minecraft Server Setup Script
# =============================================================================  
# This module provides pre-flight checks and validation functions to ensure
# the system meets requirements before starting the installation process.

# Prevent multiple sourcing
if [[ "${VALIDATION_LIB_LOADED:-0}" == "1" ]]; then
  return 0
fi
readonly VALIDATION_LIB_LOADED=1

# Source required modules if not already loaded
if [[ "${CORE_LIB_LOADED:-0}" != "1" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
fi
if [[ "${LOGGING_LIB_LOADED:-0}" != "1" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
fi

# -----------------------------------------------------------------------------
# VALIDATION CONFIGURATION
# -----------------------------------------------------------------------------

# Minimum system requirements
readonly MIN_DISK_SPACE_MB=2048
readonly MINECRAFT_DEFAULT_PORT=25565
readonly RCON_DEFAULT_PORT=25575

# -----------------------------------------------------------------------------
# DISK SPACE VALIDATION
# -----------------------------------------------------------------------------

# Function: check_disk_space
# Description: Checks if there's enough free disk space
# Parameters: $1 - minimum space in MB (optional, default: 2048MB)
#            $2 - path to check (optional, default: current directory)
# Returns: 0 if OK, exits with EXIT_PREREQ if insufficient space
check_disk_space() {
  local min_space_mb="${1:-$MIN_DISK_SPACE_MB}"
  local path="${2:-.}"
  local available_mb
  
  log_debug "Checking disk space for path: $path (minimum: ${min_space_mb}MB)"
  
  available_mb="$(get_available_space_mb "$path")"
  
  if [[ -z "$available_mb" ]]; then
    log_warn "Cannot check disk space (df command not available or failed)"
    return 0
  fi
  
  if [[ "$available_mb" -lt "$min_space_mb" ]]; then
    log_err "Insufficient disk space: ${available_mb}MB available, ${min_space_mb}MB required"
    log_err "Please free up some disk space and try again."
    safe_exit $EXIT_PREREQ
  fi
  
  log_success "Disk space check: ${available_mb}MB available (${min_space_mb}MB required)"
}

# -----------------------------------------------------------------------------
# FILE VALIDATION
# -----------------------------------------------------------------------------

# Function: check_zip_validity
# Description: Validates that a ZIP file exists and is not corrupted
# Parameters: $1 - path to ZIP file
# Returns: 0 if valid, exits with EXIT_PREREQ if invalid
check_zip_validity() {
  local zip_file="$1"
  
  log_debug "Validating ZIP file: $zip_file"
  
  if [[ ! -f "$zip_file" ]]; then
    log_err "Modpack file not found: $zip_file"
    log_err "Please check the file path and try again."
    safe_exit $EXIT_PREREQ
  fi
  
  log_info "Validating ZIP file integrity..."
  
  if is_command_available unzip; then
    if ! unzip -tq "$zip_file" >/dev/null 2>&1; then
      log_err "ZIP file appears to be corrupted: $zip_file"
      log_err "Please re-download the modpack and try again."
      safe_exit $EXIT_PREREQ
    fi
    log_success "ZIP file validation: OK"
  else
    log_warn "Cannot validate ZIP file (unzip command not available)"
  fi
}

# Function: check_file_exists
# Description: Check if a file exists and is readable
# Parameters: $1 - file path, $2 - description (optional)
# Returns: 0 if exists, 1 if not
check_file_exists() {
  local file_path="$1"
  local description="${2:-file}"
  
  if [[ -f "$file_path" && -r "$file_path" ]]; then
    log_debug "$description exists and is readable: $file_path"
    return 0
  else
    log_warn "$description not found or not readable: $file_path"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# NETWORK VALIDATION
# -----------------------------------------------------------------------------

# Function: check_port_availability  
# Description: Check if a port is available (not in use)
# Parameters: $1 - port number (optional, default: 25565)
# Returns: 0 always, but warns if port is occupied
check_port_availability() {
  local port="${1:-$MINECRAFT_DEFAULT_PORT}"
  
  log_debug "Checking port availability: $port"
  
  if is_command_available ss; then
    if ss -ltn 2>/dev/null | grep -q ":${port}\\s"; then
      log_warn "Port $port appears to be in use by another process"
      log_warn "The server may fail to start or you may need to change the port in server.properties"
    else
      log_success "Port $port availability: OK"
    fi
  elif is_command_available netstat; then
    if netstat -ln 2>/dev/null | grep -q ":${port}\\s"; then
      log_warn "Port $port appears to be in use by another process"
      log_warn "The server may fail to start or you may need to change the port in server.properties"
    else
      log_success "Port $port availability: OK"
    fi
  else
    log_warn "Cannot check port availability (ss/netstat not available)"
  fi
}

# Function: check_internet_connectivity
# Description: Test internet connectivity for downloads
# Returns: 0 if connected, 1 if not
check_internet_connectivity() {
  log_debug "Testing internet connectivity..."
  
  # Try multiple methods to check connectivity
  local test_urls=(
    "8.8.8.8"           # Google DNS
    "1.1.1.1"           # Cloudflare DNS  
    "github.com"        # Common service
  )
  
  for url in "${test_urls[@]}"; do
    if is_command_available ping; then
      if ping -c 1 -W 3 "$url" >/dev/null 2>&1; then
        log_success "Internet connectivity: OK (tested with $url)"
        return 0
      fi
    fi
    
    if is_command_available curl; then
      if curl -s --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1; then
        log_success "Internet connectivity: OK (tested with $url)"
        return 0
      fi
    fi
  done
  
  log_warn "Internet connectivity test failed - downloads may not work"
  return 1
}

# -----------------------------------------------------------------------------
# PROCESS VALIDATION
# -----------------------------------------------------------------------------

# Function: check_existing_server
# Description: Check for existing Minecraft server processes
# Returns: 0 always, but warns if server processes found
check_existing_server() {
  log_debug "Checking for existing Minecraft server processes..."
  
  local server_patterns=(
    "minecraft.*server"
    "forge.*server"  
    "fabric.*server"
    "neoforge.*server"
    "quilt.*server"
  )
  
  local found_processes=0
  
  if is_command_available pgrep; then
    for pattern in "${server_patterns[@]}"; do
      if pgrep -f "$pattern" >/dev/null 2>&1; then
        found_processes=1
        log_warn "Found existing server process matching: $pattern"
      fi
    done
  elif is_command_available ps; then
    for pattern in "${server_patterns[@]}"; do
      if ps aux 2>/dev/null | grep -v grep | grep -q "$pattern"; then
        found_processes=1
        log_warn "Found existing server process matching: $pattern"
      fi
    done
  else
    log_warn "Cannot check for existing server processes (pgrep/ps not available)"
    return 0
  fi
  
  if [[ "$found_processes" -eq 1 ]]; then
    log_warn "Existing Minecraft server process(es) detected"
    log_warn "You may want to stop them before installing a new server"
  else
    log_success "Server process check: No conflicting processes"
  fi
}

# -----------------------------------------------------------------------------
# SYSTEM REQUIREMENTS VALIDATION
# -----------------------------------------------------------------------------

# Function: check_required_commands
# Description: Check if required system commands are available
# Parameters: $* - list of required commands
# Returns: 0 if all available, exits with EXIT_PREREQ if any missing
check_required_commands() {
  local missing_commands=()
  local command
  
  log_debug "Checking required commands: $*"
  
  for command in "$@"; do
    if ! is_command_available "$command"; then
      missing_commands+=("$command")
    fi
  done
  
  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    log_err "Missing required commands: ${missing_commands[*]}"
    log_err "Please install the missing commands and try again."
    
    # Provide installation hints based on detected OS
    case "$DETECTED_OS" in
      linux)
        log_err "On Ubuntu/Debian: apt-get install ${missing_commands[*]}"
        log_err "On RHEL/CentOS: yum install ${missing_commands[*]}"
        ;;
      darwin)
        log_err "On macOS: brew install ${missing_commands[*]}"
        ;;
      windows)
        log_err "On Windows: Install missing commands via package manager or WSL"
        ;;
    esac
    
    safe_exit $EXIT_PREREQ
  fi
  
  log_success "Required commands check: All commands available"
}

# Function: check_java_requirement
# Description: Check if Java is available (basic check)
# Returns: 0 always, but warns if Java not found
check_java_requirement() {
  log_debug "Checking Java availability..."
  
  if is_command_available java; then
    local java_version
    java_version=$(java -version 2>&1 | head -n1)
    log_success "Java found: $java_version"
  else
    log_warn "Java not found in PATH - will attempt to install or download later"
  fi
}

# -----------------------------------------------------------------------------
# COMPREHENSIVE PRE-FLIGHT CHECKS
# -----------------------------------------------------------------------------

# Function: run_pre_flight_checks
# Description: Run all pre-flight checks before installation
# Parameters: $1 - ZIP file path (required)
#            $2 - minimum disk space in MB (optional)
# Returns: 0 if all checks pass, exits on critical failures
run_pre_flight_checks() {
  local zip_file="$1"
  local min_space="${2:-$MIN_DISK_SPACE_MB}"
  
  if [[ -z "$zip_file" ]]; then
    log_err "ZIP file path is required for pre-flight checks"
    safe_exit $EXIT_PREREQ
  fi
  
  log_section "Running Pre-Flight Checks"
  
  # Essential system commands
  local required_commands=("unzip" "curl" "mkdir" "rm" "cp")
  check_required_commands "${required_commands[@]}"
  
  # System resource checks
  check_disk_space "$min_space"
  
  # File validation
  check_zip_validity "$zip_file"
  
  # Network and process checks  
  check_port_availability "$MINECRAFT_DEFAULT_PORT"
  check_port_availability "$RCON_DEFAULT_PORT"
  check_existing_server
  
  # Optional checks (non-critical)
  check_java_requirement
  check_internet_connectivity || true  # Don't fail on connectivity issues
  
  log_success "Pre-flight checks completed successfully"
}

# Function: run_basic_checks
# Description: Run only basic checks (for minimal validation)
# Parameters: $1 - ZIP file path (required)
# Returns: 0 if basic checks pass
run_basic_checks() {
  local zip_file="$1"
  
  log_info "Running basic validation checks..."
  
  check_zip_validity "$zip_file"
  check_disk_space
  
  log_success "Basic checks completed"
}

# -----------------------------------------------------------------------------
# MODULE INITIALIZATION
# -----------------------------------------------------------------------------

# Export validation functions
export -f check_disk_space check_zip_validity check_file_exists
export -f check_port_availability check_internet_connectivity check_existing_server  
export -f check_required_commands check_java_requirement
export -f run_pre_flight_checks run_basic_checks

# Export validation constants
export MIN_DISK_SPACE_MB MINECRAFT_DEFAULT_PORT RCON_DEFAULT_PORT