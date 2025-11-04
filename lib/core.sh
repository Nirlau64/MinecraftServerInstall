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

# Set core variables
readonly DETECTED_OS="$(detect_os)"
readonly HAS_TTY="$(is_tty_available && echo 1 || echo 0)"

# Export core constants
export EXIT_SUCCESS EXIT_GENERAL EXIT_PREREQ EXIT_DOWNLOAD EXIT_INSTALL EXIT_EULA EXIT_START
export SCRIPT_NAME SCRIPT_VERSION DETECTED_OS HAS_TTY