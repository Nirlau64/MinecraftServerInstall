#!/usr/bin/env bash
# =============================================================================
# Logging Module - Universal Minecraft Server Setup Script  
# =============================================================================
# This module provides comprehensive logging functionality with support for
# different log levels, file logging, and colored console output.

# Prevent multiple sourcing
if [[ "${LOGGING_LIB_LOADED:-0}" == "1" ]]; then
  return 0
fi
readonly LOGGING_LIB_LOADED=1

# Source core module if not already loaded
if [[ "${CORE_LIB_LOADED:-0}" != "1" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
fi

# -----------------------------------------------------------------------------
# LOGGING CONFIGURATION
# -----------------------------------------------------------------------------

# Log levels: 0=quiet, 1=normal, 2=verbose
LOG_VERBOSE="${LOG_VERBOSE:-1}"
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_FILE="${LOG_FILE:-}"
LOG_TTY="${LOG_TTY:-$HAS_TTY}"

# Color codes for console output
readonly CLR_RESET="\033[0m"
readonly CLR_INFO="\033[32m"    # green
readonly CLR_WARN="\033[33m"    # yellow
readonly CLR_ERR="\033[31m"     # red
readonly CLR_DEBUG="\033[36m"   # cyan

# -----------------------------------------------------------------------------
# CORE LOGGING FUNCTIONS
# -----------------------------------------------------------------------------

# Function: log_msg
# Description: Core logging function with level-based output
# Parameters: $1 - log level, $2 - message
log_msg() {
  local level="$1" 
  local msg="$2" 
  local color="" 
  local prefix="" 
  local out=""
  
  case "$level" in
    info)  color="$CLR_INFO"; prefix="INFO";;
    warn)  color="$CLR_WARN"; prefix="WARN";;
    error) color="$CLR_ERR"; prefix="ERROR";;
    debug) color="$CLR_DEBUG"; prefix="DEBUG";;
    *)     color="$CLR_RESET"; prefix="LOG";;
  esac
  
  out="[$(get_timestamp)] $prefix: $msg"
  
  # Console output with color support
  if [[ "$LOG_TTY" == "1" ]]; then
    printf "%b%s%b\n" "$color" "$out" "$CLR_RESET"
  else
    printf "%s\n" "$out"
  fi
  
  # File logging (always without colors)
  if [[ -n "$LOG_FILE" ]]; then
    printf "%s\n" "$out" >> "$LOG_FILE"
  fi
}

# Function: log
# Description: Generic log function (info level)
# Parameters: $* - message components
log() { 
  log_msg info "$*" 
}

# Function: log_info
# Description: Log info message (respects LOG_VERBOSE)
# Parameters: $* - message components
log_info() { 
  [[ "$LOG_VERBOSE" -ge 1 ]] && log_msg info "$*"
}

# Function: log_warn
# Description: Log warning message
# Parameters: $* - message components
log_warn() { 
  [[ "$LOG_VERBOSE" -ge 0 ]] && log_msg warn "$*"
}

# Function: log_err
# Description: Log error message
# Parameters: $* - message components  
log_err() { 
  log_msg error "$*"
}

# Function: log_error
# Description: Alias for log_err
# Parameters: $* - message components
log_error() {
  log_err "$*"
}

# Function: log_debug
# Description: Log debug message (only in verbose mode)
# Parameters: $* - message components
log_debug() {
  [[ "$LOG_VERBOSE" -ge 2 ]] && log_msg debug "$*"
}

# -----------------------------------------------------------------------------
# LOG FILE MANAGEMENT
# -----------------------------------------------------------------------------

# Function: setup_log_file
# Description: Set up log file in logs/ directory with timestamp
# Parameters: $1 - custom log file path (optional)
setup_log_file() {
  local custom_log="${1:-}"
  
  if [[ -n "$custom_log" ]]; then
    LOG_FILE="$custom_log"
    ensure_directory "$(dirname "$LOG_FILE")"
  else
    local logdir="logs"
    ensure_directory "$logdir"
    local timestamp
    timestamp="$(get_file_timestamp)"
    LOG_FILE="$logdir/install-$timestamp.log"
  fi
  
  # Create log file and write header
  {
    echo "==================================="
    echo "Minecraft Server Setup - Log File"
    echo "Started: $(get_timestamp)"
    echo "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "OS: $DETECTED_OS"
    echo "==================================="
  } > "$LOG_FILE"
  
  log_info "Log file created: $LOG_FILE"
}

# Function: log_section
# Description: Log a section header for better log organization
# Parameters: $1 - section name
log_section() {
  local section="$1"
  local separator="----------------------------------------"
  
  log_info "$separator"
  log_info "SECTION: $section"
  log_info "$separator"
}

# Function: log_step
# Description: Log a numbered step 
# Parameters: $1 - step number, $2 - step description
log_step() {
  local step_num="$1"
  local step_desc="$2"
  log_info "Step $step_num: $step_desc"
}

# Function: log_success
# Description: Log a success message with checkmark
# Parameters: $* - message components
log_success() {
  log_info "$* ✓"
}

# Function: log_failure
# Description: Log a failure message with X mark
# Parameters: $* - message components  
log_failure() {
  log_err "$* ✗"
}

# -----------------------------------------------------------------------------
# VERBOSITY CONTROL
# -----------------------------------------------------------------------------

# Function: set_log_verbose
# Description: Set logging verbosity level
# Parameters: $1 - verbosity level (0=quiet, 1=normal, 2=verbose)
set_log_verbose() {
  local level="$1"
  case "$level" in
    0|1|2) LOG_VERBOSE="$level" ;;
    *) log_warn "Invalid verbosity level: $level. Using default." ;;
  esac
}

# Function: enable_debug_logging
# Description: Enable debug logging (sets verbosity to 2)
enable_debug_logging() {
  LOG_VERBOSE=2
  log_debug "Debug logging enabled"
}

# Function: quiet_logging
# Description: Set logging to quiet mode (only errors and warnings)
quiet_logging() {
  LOG_VERBOSE=0
}

# -----------------------------------------------------------------------------
# LEGACY COMPATIBILITY
# -----------------------------------------------------------------------------

# Simple logging functions for compatibility with old code
log_legacy_info() { printf '[INFO] %s\n' "$*"; }
log_legacy_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_legacy_err() { printf '[ERROR] %s\n' "$*" >&2; }

# -----------------------------------------------------------------------------
# MODULE INITIALIZATION  
# -----------------------------------------------------------------------------

# Export logging functions
export -f log_msg log log_info log_warn log_err log_error log_debug
export -f setup_log_file log_section log_step log_success log_failure
export -f set_log_verbose enable_debug_logging quiet_logging

# Export legacy functions for backward compatibility
export -f log_legacy_info log_legacy_warn log_legacy_err

# Export logging variables
export LOG_VERBOSE LOG_LEVEL LOG_FILE LOG_TTY