#!/usr/bin/env bash
# =============================================================================
# Core Module - Universal Minecraft Server Setup Script
# =============================================================================
# This module provides core functionality, constants, and utility functions
# for the Minecraft server setup script.

# Prevent multiple sourcing
if [[ "${CORE_LIB_LOADED:-0}" == "1" ]]; then
  return 0
fi
readonly CORE_LIB_LOADED=1

# -----------------------------------------------------------------------------
# EXIT CODES (Consistent error handling)
# -----------------------------------------------------------------------------
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL=1
readonly EXIT_PREREQ=2
readonly EXIT_DOWNLOAD=3
readonly EXIT_INSTALL=4
readonly EXIT_EULA=5
readonly EXIT_START=6

# -----------------------------------------------------------------------------
# CORE CONSTANTS
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="universalServerSetup.sh"
readonly SCRIPT_VERSION="2.0.0-refactored"

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------

# Function: is_command_available
# Description: Check if a command is available in PATH
# Parameter: $1 - command name
# Returns: 0 if available, 1 if not
is_command_available() {
  command -v "$1" >/dev/null 2>&1
}

# Function: get_timestamp  
# Description: Get current timestamp in standardized format
# Returns: timestamp string (YYYY-mm-dd HH:MM:SS)
get_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Function: get_file_timestamp
# Description: Get current timestamp for filenames
# Returns: timestamp string (YYYYmmdd-HHMMSS)
get_file_timestamp() {
  date '+%Y%m%d-%H%M%S'
}

# Function: ensure_directory
# Description: Create directory if it doesn't exist
# Parameter: $1 - directory path
ensure_directory() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

# Function: is_tty_available
# Description: Check if script is running in a TTY (terminal)
# Returns: 0 if TTY available, 1 if not
is_tty_available() {
  [[ -t 1 ]]
}

# Function: cleanup_temp_files
# Description: Clean up temporary files with given pattern
# Parameter: $1 - file pattern (optional, default: .temp_*)
cleanup_temp_files() {
  local pattern="${1:-.temp_*}"
  rm -f $pattern 2>/dev/null || true
}

# Function: safe_exit
# Description: Exit with proper cleanup
# Parameter: $1 - exit code (optional, default: 0)
safe_exit() {
  local exit_code="${1:-0}"
  cleanup_temp_files
  exit "$exit_code"
}

# -----------------------------------------------------------------------------
# DRY RUN UTILITIES
# -----------------------------------------------------------------------------

# Function: dry_run
# Description: Execute command if not in dry-run mode, otherwise log it
# Parameters: $* - command to execute
dry_run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "[DRY-RUN] $*"
    return 0
  else
    "$@"
  fi
}

# Function: dry_run_write
# Description: Write to file if not in dry-run mode, otherwise log it
# Parameters: $1 - file path, $2.. - content
dry_run_write() {
  local path="$1"; shift
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "[DRY-RUN] write to $path"
    return 0
  else
    printf '%s' "$*" > "$path"
  fi
}

# Function: dry_run_append
# Description: Append to file if not in dry-run mode, otherwise log it
# Parameters: $1 - file path, $2.. - content
dry_run_append() {
  local path="$1"; shift
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "[DRY-RUN] append to $path"
    return 0
  else
    printf '%s' "$*" >> "$path"
  fi
}

# -----------------------------------------------------------------------------
# USER INTERACTION UTILITIES
# -----------------------------------------------------------------------------

# Function: ask_yes_no
# Description: Prompt user for yes/no confirmation with defaults and unattended support
# Parameters: $1 - prompt message, $2 - default answer ('yes' or 'no')
# Returns: 0 for yes, 1 for no
ask_yes_no() {
  local prompt="${1:-Proceed?}"
  local default="${2:-no}"
  
  # Respect unattended flags first
  if [ "${ASSUME_YES:-0}" = "1" ]; then return 0; fi
  if [ "${ASSUME_NO:-0}" = "1" ]; then return 1; fi
  
  if [ -t 0 ]; then
    # Interactive mode: prompt user
    while true; do
      read -r -p "$prompt [y/N]: " ans
      case "$ans" in
        y|Y|yes|YES|j|J|ja|JA) return 0 ;;
        n|N|no|NO|nein|NEIN) return 1 ;;
        "")
          if [ "$default" = "yes" ]; then return 0; else return 1; fi ;;
        *) echo "Please answer with y or n.";;
      esac
    done
  else
    # Non-interactive mode: use default value
    if [ "$default" = "yes" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# -----------------------------------------------------------------------------
# CROSS-PLATFORM COMPATIBILITY
# -----------------------------------------------------------------------------

# Function: detect_os
# Description: Detect operating system
# Returns: "linux", "darwin", "windows", or "unknown"
detect_os() {
  case "$(uname -s)" in
    Linux*)     echo "linux" ;;
    Darwin*)    echo "darwin" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    *)          echo "unknown" ;;
  esac
}

# Function: get_available_space_mb
# Description: Get available disk space in MB (cross-platform)
# Parameter: $1 - path to check (optional, default: current directory)
# Returns: available space in MB or empty string if unavailable
get_available_space_mb() {
  local path="${1:-.}"
  local available_mb=""
  
  if is_command_available df; then
    # Try different df formats for cross-platform compatibility
    if df -BM "$path" >/dev/null 2>&1; then
      # GNU df with block size
      available_mb=$(df -BM "$path" | awk 'NR==2 {gsub(/M/, "", $4); print int($4)}')
    elif df -m "$path" >/dev/null 2>&1; then
      # Some systems use -m for MB
      available_mb=$(df -m "$path" | awk 'NR==2 {print int($4)}')
    elif df -Pm "$path" >/dev/null 2>&1; then
      # POSIX-style df
      available_mb=$(df -Pm "$path" | awk 'NR==2 {print $4}')
    else
      # Fallback: assume 1K blocks and convert to MB
      available_mb=$(df "$path" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    fi
  fi
  
  echo "$available_mb"
}

# -----------------------------------------------------------------------------
# MODULE INITIALIZATION
# -----------------------------------------------------------------------------

# Export functions that should be available globally
export -f is_command_available
export -f get_timestamp
export -f get_file_timestamp
export -f ensure_directory
export -f is_tty_available
export -f cleanup_temp_files
export -f safe_exit
export -f detect_os
export -f get_available_space_mb
export -f dry_run
export -f dry_run_write
export -f dry_run_append
export -f ask_yes_no

# Set core variables
readonly DETECTED_OS="$(detect_os)"
readonly HAS_TTY="$(is_tty_available && echo 1 || echo 0)"

# Export core constants
export EXIT_SUCCESS EXIT_GENERAL EXIT_PREREQ EXIT_DOWNLOAD EXIT_INSTALL EXIT_EULA EXIT_START
export SCRIPT_NAME SCRIPT_VERSION DETECTED_OS HAS_TTY