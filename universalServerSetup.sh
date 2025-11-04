
#!/usr/bin/env bash
# Universal Minecraft Server Setup Script
# ---------------------------------------
# This script automates the installation and configuration of a modded Minecraft server.
# It supports Forge, NeoForge, Fabric, and Quilt loaders, and can handle both server packs and client exports.
#
# Usage:
#   ./universalServerSetup.sh [Modpack.zip]
#
# Features:
#   - Automatic Java version detection and installation
#   - Dynamic RAM allocation (default: 75% of system RAM)
#   - EULA handling (interactive or unattended)
#   - Operator assignment
#   - Robust mod/config copy logic
#   - Generates a universal start.sh script
#
# Requirements:
#   - unzip, curl, jq, rsync
#   - sudo rights for Java installation
#   - Internet connection for downloads
#
# For more details, see README.md

set -euo pipefail

# -----------------------------------------------------------------------------
# MODULE LOADING
# -----------------------------------------------------------------------------
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core modules
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/logging.sh" 
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/java.sh"
source "$SCRIPT_DIR/lib/server.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/system.sh"

# Trap to ensure Python 3 cleanup on exit
cleanup_on_exit() {
  local exit_code=$?
  
  # Remove temporary work directory
  if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
    log_info "Cleaning up temporary directory: $WORK"
    rm -rf "$WORK" 2>/dev/null || true
  fi
  
  # Remove temporary files
  rm -f _fabric.json .temp_* 2>/dev/null || true
  
  # Clean up Python 3 if we installed it
  if [ "${PYTHON3_INSTALLED_BY_SCRIPT:-0}" = "1" ]; then
    echo "[INFO] Cleaning up Python 3 installed by script..."
    cleanup_python3_if_installed
  fi
  
  # Clean up GUI if it was started during an error
  if [ $exit_code -ne 0 ] && [ -f ".gui_pid" ]; then
    echo "[INFO] Stopping GUI due to script error..."
    stop_gui 2>/dev/null || true
  fi
  
  # Log cleanup completion
  if [ $exit_code -ne 0 ]; then
    log_warn "Script exited with error code $exit_code"
    log_info "Cleanup completed. Check logs for details: ${LOG_FILE:-logs/}"
  fi
  
  exit $exit_code
}
trap cleanup_on_exit EXIT INT TERM

# -----------------------------------------------------------------------------
# CONFIGURATION SECTION (User-editable)
# -----------------------------------------------------------------------------
# Configuration defaults are now handled by lib/config.sh module
# Use CLI arguments or .env file to override default values

# Path to the modpack ZIP file to install. Can be set via CLI argument or environment variable ZIP_OVERRIDE.
ZIP="${ZIP_OVERRIDE:-pack.zip}"


# Operator settings
# OP_USERNAME: Minecraft username to grant operator rights (leave empty to skip)
# OP_LEVEL: Operator permission level (1-4); 4 is admin
OP_USERNAME="${OP_USERNAME:-}"
OP_LEVEL="${OP_LEVEL:-4}"


# Space-separated list of usernames to always OP (default: repo owner)
ALWAYS_OP_USERS="${ALWAYS_OP_USERS:-lorol61}"


# Non-interactive defaults (used when no TTY). Values: "yes" or "no"
# AUTO_ACCEPT_EULA: Accept EULA automatically if no terminal
# AUTO_FIRST_RUN: Run server automatically after setup if no terminal
AUTO_ACCEPT_EULA="${AUTO_ACCEPT_EULA:-yes}"
AUTO_FIRST_RUN="${AUTO_FIRST_RUN:-yes}"


# Memory configuration for dynamic sizing (used when JAVA_ARGS is empty)
# MEMORY_PERCENT: Percent of system RAM to allocate to JVM
# MIN_MEMORY_MB: Minimum RAM in MB
# MAX_MEMORY_MB: Maximum RAM in MB
MEMORY_PERCENT="${MEMORY_PERCENT:-75}"
MIN_MEMORY_MB="${MIN_MEMORY_MB:-2048}"
MAX_MEMORY_MB="${MAX_MEMORY_MB:-32768}"


# Optional: force custom JVM args like "-Xms8G -Xmx8G"
JAVA_ARGS="${JAVA_ARGS:-}"

# Automatic backup configuration
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-4}"
BACKUP_RETENTION="${BACKUP_RETENTION:-12}"


# Installation directories
# SRVDIR: Server directory (default: current directory)
# WORK: Temporary working directory
SRVDIR="${SRVDIR:-$(pwd)}"
WORK="${WORK:-${SRVDIR}/_work}"

# -----------------------------------------------------------------------------
# PRE-FLIGHT CHECKS (Now handled by validation.sh module)
# -----------------------------------------------------------------------------
# All validation functions are now provided by lib/validation.sh

# -----------------------------------------------------------------------------
# Runtime flags (populated via CLI/env)
# -----------------------------------------------------------------------------
# CLI ARGUMENTS FOR SERVER.PROPERTIES
# -----------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --motd=*) PROP_MOTD="${arg#--motd=}" ;;
    --difficulty=*) PROP_DIFFICULTY="${arg#--difficulty=}" ;;
    --pvp=*) PROP_PVP="${arg#--pvp=}" ;;
    --view-distance=*) PROP_VIEW_DISTANCE="${arg#--view-distance=}" ;;
    --white-list=*) PROP_WHITE_LIST="${arg#--white-list=}" ;;
    --max-players=*) PROP_MAX_PLAYERS="${arg#--max-players=}" ;;
    --spawn-protection=*) PROP_SPAWN_PROTECTION="${arg#--spawn-protection=}" ;;
    --allow-nether=*) PROP_ALLOW_NETHER="${arg#--allow-nether=}" ;;
    --level-name=*) PROP_LEVEL_NAME="${arg#--level-name=}" ;;
    --level-seed=*) PROP_LEVEL_SEED="${arg#--level-seed=}" ;;
    --level-type=*) PROP_LEVEL_TYPE="${arg#--level-type=}" ;;
  esac
done
# -----------------------------------------------------------------------------
# These are set by command-line arguments or environment variables
ASSUME_YES=0
ASSUME_NO=0
NO_EULA_PROMPT=0
EULA_VALUE=""   # "true" or "false"
FORCE=0
DRY_RUN=0
SYSTEMD=0
TMUX=0
AUTO_DOWNLOAD_MODS=0
PYTHON3_INSTALLED_BY_SCRIPT=0  # Flag to track if we installed Python 3

# GUI options
GUI=1  # Enable GUI by default
NO_GUI=0

# -----------------------------------------------------------------------------
# LOGGING & COMMAND LINE PROCESSING (Now handled by modules)
# -----------------------------------------------------------------------------
# All logging functionality is now provided by lib/logging.sh
# Parse verbosity/log flags and setup logging
for arg in "$@"; do
  case "$arg" in
    --verbose) set_log_verbose 2 ;;
    --quiet)   quiet_logging ;;
    --log-file)
      shift; setup_log_file "$1" ;;
    --log-file=*)
      setup_log_file "${arg#--log-file=}" ;;
  esac
done

# Setup log file if not already configured
if [[ -z "$LOG_FILE" ]]; then
  setup_log_file
fi

# -----------------------------------------------------------------------------
# Utility helpers
# Backup world function: compress world/<name> to backups/<name>-YYYYmmdd-HHMMSS.zip
backup_world() {
  local name="${WORLD_NAME:-world}"
  local src="$name"
  [ -d "$src" ] || src="world"
  local ts="$(date '+%Y%m%d-%H%M%S')"
  local backup_dir="backups"
  local backup_zip="$backup_dir/${name}-$ts.zip"
  mkdir -p "$backup_dir"
  if [ -d "$src" ]; then
    log_info "Backing up world '$src' to $backup_zip"
    zip -rq "$backup_zip" "$src"
    log_info "Backup complete: $backup_zip"
  else
    log_warn "World directory '$src' not found, skipping backup."
  fi
}

# Restore world function: extract zip to world/<name> (with confirmation)
restore_world() {
  local zip="$RESTORE_ZIP"
  if [ ! -f "$zip" ]; then
    log_err "Restore zip not found: $zip"
    log_err "Please check the file path and try again."
    exit $EXIT_PREREQ
  fi
  local name="${WORLD_NAME:-world}"
  local target="$name"
  if [ -d "$target" ]; then
    if [ "$FORCE" = "1" ]; then
      log_warn "Overwriting existing world '$target' due to --force."
      rm -rf "$target"
    else
      if ! ask_yes_no "World '$target' exists. Overwrite with backup?" "no"; then
        log_warn "Restore cancelled by user."
        return 1
      fi
      rm -rf "$target"
    fi
  fi
  log_info "Restoring world from $zip to $target"
  unzip -q "$zip" -d .
  log_info "Restore complete."
}
# -----------------------------------------------------------------------------

# Returns 0 if argument is a truthy value (yes, true, 1, etc.), else 1
truthy() {
  case "${1:-}" in
    1|yes|true|on|y|Y|TRUE|YES) return 0;;
    *) return 1;;
  esac
}


# Runs a command, or logs it if DRY_RUN is enabled
run() {
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}


# Writes content to a file, or logs if DRY_RUN is enabled
write_file() {
  local path="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] write to $path"
  else
    printf '%s' "$*" > "$path"
  fi
}


# Appends content to a file, or logs if DRY_RUN is enabled
append_file() {
  local path="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] append to $path"
  else
    printf '%s' "$*" >> "$path"
  fi
}

# Periodic backup function (runs in background)
start_periodic_backups() {
  local interval="$1" retention="$2" world_name="${WORLD_NAME:-world}"
  local backup_dir="backups"
  mkdir -p "$backup_dir"
  (
    while true; do
      ts="$(date '+%Y%m%d-%H%M%S')"
      backup_zip="$backup_dir/${world_name}-$ts.zip"
      if [ -d "$world_name" ]; then
        zip -rq "$backup_zip" "$world_name"
        log_info "[AUTO-BACKUP] Backup complete: $backup_zip"
        # Delete oldest backups if exceeding retention
        backups=( $(ls -1t "$backup_dir/${world_name}-"*.zip 2>/dev/null) )
        if [ "${#backups[@]}" -gt "$retention" ]; then
          for ((i=${retention}; i<${#backups[@]}; i++)); do
            rm -f "${backups[$i]}"
            log_info "[AUTO-BACKUP] Deleted old backup: ${backups[$i]}"
          done
        fi
      else
        log_warn "[AUTO-BACKUP] World directory '$world_name' not found, skipping backup."
      fi
      sleep "$((interval*3600))"
    done
  ) &
}



######################################
# Help and usage information
######################################
show_help() {
  cat << EOF
Universal Minecraft Server Setup Script

Usage: $0 [OPTIONS] [MODPACK.zip]

OPTIONS:
  Unattended/Prompts:
    --yes                    Answer 'yes' to all prompts
    --assume-no              Answer 'no' to all prompts
    --no-eula-prompt         Skip EULA prompt (use with --eula)
    --eula=true|false        Set EULA acceptance explicitly
    --force                  Overwrite files without asking
    --dry-run                Show what would be done, don't make changes
    
  Memory:
    --ram SIZE               Set RAM allocation (e.g. 4G, 8192M)
    
  Logging:
    --verbose                Increase log verbosity
    --quiet                  Reduce log output
    --log-file PATH          Write logs to specific file
    
  Services:
    --systemd                Generate systemd service file
    --tmux                   Start server in tmux session
    
  Worlds/Backups:
    --world NAME             Set world name (default: world)
    --restore ZIP            Restore world from backup ZIP
    --pre-backup             Create backup before installation
    
  Mods:
    --auto-download-mods     Auto-download mods from manifest.json
    
  GUI:
    --gui                    Enable GUI after setup (default)
    --no-gui                 Disable GUI (for headless servers)
    
  Misc:
    --help                   Show this help message
    
ENVIRONMENT VARIABLES:
    AUTO_YES=1               Same as --yes
    EULA=true|false          Same as --eula
    RAM=SIZE                 Same as --ram SIZE
    GUI=0                    Same as --no-gui
    
EXAMPLES:
    # Interactive installation
    $0 MyModpack.zip
    
    # Unattended installation with 6GB RAM
    $0 --yes --eula=true --ram 6G MyModpack.zip
    
    # Install and start with systemd
    $0 --systemd --yes --eula=true MyModpack.zip
    
For more information, see README.md
EOF
}

######################################
# Argument parsing
######################################
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        show_help
        exit $EXIT_SUCCESS
        ;;
      --version)
        echo "Universal Minecraft Server Setup Script v1.0"
        exit $EXIT_SUCCESS
        ;;
      --systemd)
        SYSTEMD=1
        ;;
      --tmux)
        TMUX=1
        ;;
      --yes)
        ASSUME_YES=1
        ;;
      --assume-no)
        ASSUME_NO=1
        ;;
      --no-eula-prompt)
        NO_EULA_PROMPT=1
        ;;
      --eula=*)
        EULA_VALUE="${1#*=}"
        ;;
      --force)
        FORCE=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --ram)
        RAM_SIZE="$2"
        shift
        ;;
      --verbose)
        LOG_VERBOSE=2
        ;;
      --quiet)
        LOG_VERBOSE=0
        ;;
      --log-file)
        LOG_FILE="$2"
        shift
        ;;
      --world)
        WORLD_NAME="$2"
        shift
        ;;
      --restore)
        RESTORE_ZIP="$2"
        shift
        ;;
      --pre-backup)
        PRE_BACKUP=1
        ;;
      --auto-download-mods)
        AUTO_DOWNLOAD_MODS=1
        ;;
      --gui)
        GUI=1
        NO_GUI=0
        ;;
      --no-gui)
        GUI=0
        NO_GUI=1
        ;;
      --backup-interval=*)
        BACKUP_INTERVAL_HOURS="${1#--backup-interval=}"
        ;;
      --backup-retention=*)
        BACKUP_RETENTION="${1#--backup-retention=}"
        ;;
      --) 
        shift; break 
        ;;
      -*) 
        log_err "Unknown option: $1"
        log_err "Use --help for usage information"
        exit $EXIT_PREREQ 
        ;;
      *)
        # Accept positional ZIP argument if not overridden
        if [ -z "$ZIP_OVERRIDE" ] && [ "$ZIP" = "pack.zip" ]; then
          ZIP="$1"
        fi
        ;;
    esac
    shift
  done
}

# ENV fallbacks
[ -n "${AUTO_YES:-}" ] && truthy "$AUTO_YES" && ASSUME_YES=1
[ -n "${EULA:-}" ] && EULA_VALUE="${EULA}"
[ -n "${GUI:-}" ] && ! truthy "$GUI" && NO_GUI=1

# Parse CLI args now
parse_args "$@"

# Prepare working directory
# Pre-backup if requested
if [ "${PRE_BACKUP:-0}" = "1" ]; then
  backup_world
fi

# Restore if requested
if [ -n "${RESTORE_ZIP:-}" ]; then
  restore_world
fi
run rm -rf "$WORK"
run mkdir -p "$WORK"

################################################################################
# Funktion: ask_yes_no
# Beschreibung: Fragt den Benutzer interaktiv nach Ja/Nein-Antwort
# Parameter:
#   $1 - prompt: Die Frage an den Benutzer (Standard: "Proceed?")
#   $2 - default: Standard-Antwort für nicht-interaktive Nutzung ("yes"/"no")
# Rückgabe:
#   0 - Benutzer hat "Ja" gewählt oder default ist "yes"
#   1 - Benutzer hat "Nein" gewählt oder default ist "no"
################################################################################
ask_yes_no() {
  local prompt="${1:-Proceed?}"
  local default="${2:-no}"
  # Respect unattended flags first
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  if [ "$ASSUME_NO" = 1 ]; then return 1; fi
  if [ -t 0 ]; then
    # Interaktiver Modus: Frage den Benutzer
    while true; do
      read -r -p "$prompt [y/N]: " ans
      case "$ans" in
        y|Y|yes|YES|j|J|ja|JA) return 0 ;;
        n|N|no|NO|nein|NEIN) return 1 ;;
        "")
          if [ "$default" = "yes" ]; then return 0; else return 1; fi ;;
        *) echo "Bitte mit y oder n antworten.";;
      esac
    done
  else
    # Nicht-interaktiver Modus: Verwende Default-Wert
    if [ "$default" = "yes" ]; then
      return 0
    else
      return 1
    fi
  fi
}

################################################################################
# Funktion: require_cmd
# Beschreibung: Prüft ob alle benötigten Befehle verfügbar sind und gibt OS-spezifische Installationshinweise
# Parameter:
#   $@ - Liste der zu prüfenden Befehle
# Rückgabe:
#   0 - Alle Befehle sind verfügbar
#   exit EXIT_PREREQ - Mindestens ein Befehl fehlt
################################################################################

# Function to get installation command for missing tools
get_install_hint() {
  local cmd="$1"
  local hint=""
  
  # Detect package manager and provide appropriate install command
  if command -v apt-get >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="sudo apt-get install unzip" ;;
      curl) hint="sudo apt-get install curl" ;;
      jq) hint="sudo apt-get install jq" ;;
      rsync) hint="sudo apt-get install rsync" ;;
      java) hint="sudo apt-get install openjdk-17-jdk" ;;
      *) hint="sudo apt-get install $cmd" ;;
    esac
  elif command -v dnf >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="sudo dnf install unzip" ;;
      curl) hint="sudo dnf install curl" ;;
      jq) hint="sudo dnf install jq" ;;
      rsync) hint="sudo dnf install rsync" ;;
      java) hint="sudo dnf install java-17-openjdk-devel" ;;
      *) hint="sudo dnf install $cmd" ;;
    esac
  elif command -v yum >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="sudo yum install unzip" ;;
      curl) hint="sudo yum install curl" ;;
      jq) hint="sudo yum install jq" ;;
      rsync) hint="sudo yum install rsync" ;;
      java) hint="sudo yum install java-17-openjdk-devel" ;;
      *) hint="sudo yum install $cmd" ;;
    esac
  elif command -v pacman >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="sudo pacman -S unzip" ;;
      curl) hint="sudo pacman -S curl" ;;
      jq) hint="sudo pacman -S jq" ;;
      rsync) hint="sudo pacman -S rsync" ;;
      java) hint="sudo pacman -S jdk17-openjdk" ;;
      *) hint="sudo pacman -S $cmd" ;;
    esac
  elif command -v zypper >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="sudo zypper install unzip" ;;
      curl) hint="sudo zypper install curl" ;;
      jq) hint="sudo zypper install jq" ;;
      rsync) hint="sudo zypper install rsync" ;;
      java) hint="sudo zypper install java-17-openjdk-devel" ;;
      *) hint="sudo zypper install $cmd" ;;
    esac
  elif command -v brew >/dev/null 2>&1; then
    case "$cmd" in
      unzip) hint="brew install unzip" ;;
      curl) hint="curl is usually pre-installed on macOS" ;;
      jq) hint="brew install jq" ;;
      rsync) hint="rsync is usually pre-installed on macOS" ;;
      java) hint="brew install openjdk@17" ;;
      *) hint="brew install $cmd" ;;
    esac
  else
    hint="Please install $cmd using your system's package manager"
  fi
  
  printf '%s' "$hint"
}

require_cmd() {
  local missing=0
  local missing_cmds=()
  
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing_cmds+=("$c")
      missing=1
    fi
  done
  
  if [ $missing -eq 1 ]; then
    log_err "Missing required commands: ${missing_cmds[*]}"
    echo ""
    log_err "Installation hints:"
    for c in "${missing_cmds[@]}"; do
      local hint
      hint=$(get_install_hint "$c")
      log_err "  For $c: $hint"
    done
    echo ""
    log_err "Please install the missing commands and try again."
    exit $EXIT_PREREQ
  fi
}

################################################################################
# Python 3 Management Functions
################################################################################

# Function: install_python3_if_needed
# Description: Checks for Python 3 and installs it if missing for mod downloads
# Returns: 0 if Python 3 is available, exit 1 if installation failed
install_python3_if_needed() {
  # Check if we're being run from GUI (Python 3 is already available)
  if [ "${GUI_LAUNCHED:-0}" = "1" ] || [ "${LAUNCHED_FROM_GUI:-0}" = "1" ]; then
    if command -v python3 >/dev/null 2>&1; then
      log_info "Python 3 detected (launched from GUI): $(python3 --version 2>&1)"
      # Don't set PYTHON3_INSTALLED_BY_SCRIPT since GUI needs it
      return 0
    else
      log_warn "GUI launched but Python 3 not found - this should not happen!"
    fi
  fi
  
  # Check if Python 3 is already available
  if command -v python3 >/dev/null 2>&1; then
    log_info "Python 3 is already available: $(python3 --version 2>&1)"
    return 0
  fi

  log_info "Python 3 not found, installing for automatic mod download..."
  
  # Set flag to remember we installed it
  PYTHON3_INSTALLED_BY_SCRIPT=1
  
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] would install Python 3"
    return 0
  fi

  # Install Python 3 based on package manager
  if command -v apt-get >/dev/null 2>&1; then
    log_info "Installing Python 3 via apt..."
    if sudo apt-get update && sudo apt-get install -y python3 python3-minimal; then
      log_info "Python 3 installed successfully via apt"
    else
      log_err "Failed to install Python 3 via apt"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    log_info "Installing Python 3 via dnf..."
    if sudo dnf install -y python3; then
      log_info "Python 3 installed successfully via dnf"
    else
      log_err "Failed to install Python 3 via dnf"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  elif command -v yum >/dev/null 2>&1; then
    log_info "Installing Python 3 via yum..."
    if sudo yum install -y python3; then
      log_info "Python 3 installed successfully via yum"
    else
      log_err "Failed to install Python 3 via yum"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  elif command -v pacman >/dev/null 2>&1; then
    log_info "Installing Python 3 via pacman..."
    if sudo pacman -S --noconfirm python; then
      log_info "Python 3 installed successfully via pacman"
    else
      log_err "Failed to install Python 3 via pacman"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  elif command -v zypper >/dev/null 2>&1; then
    log_info "Installing Python 3 via zypper..."
    if sudo zypper install -y python3; then
      log_info "Python 3 installed successfully via zypper"
    else
      log_err "Failed to install Python 3 via zypper"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  elif command -v brew >/dev/null 2>&1; then
    log_info "Installing Python 3 via Homebrew..."
    if brew install python@3.11; then
      log_info "Python 3 installed successfully via Homebrew"
    else
      log_err "Failed to install Python 3 via Homebrew"
      PYTHON3_INSTALLED_BY_SCRIPT=0
      return 1
    fi
  else
    log_err "No supported package manager found for Python 3 installation"
    log_err "Please install Python 3 manually and re-run with --auto-download-mods"
    PYTHON3_INSTALLED_BY_SCRIPT=0
    return 1
  fi

  # Verify installation
  if command -v python3 >/dev/null 2>&1; then
    log_info "Python 3 verification successful: $(python3 --version 2>&1)"
    return 0
  else
    log_err "Python 3 installation verification failed"
    PYTHON3_INSTALLED_BY_SCRIPT=0
    return 1
  fi
}

# Function: cleanup_python3_if_installed
# Description: Removes Python 3 if it was installed by this script
cleanup_python3_if_installed() {
  if [ "$PYTHON3_INSTALLED_BY_SCRIPT" != "1" ]; then
    return 0  # We didn't install it, so don't remove it
  fi

  # Don't remove Python 3 if GUI is running or if we're in GUI mode
  if [ "${GUI_LAUNCHED:-0}" = "1" ] || [ -f ".gui_pid" ]; then
    log_info "Keeping Python 3 installed (GUI is running or was used)"
    return 0
  fi

  log_info "Cleaning up Python 3 that was installed by this script..."
  
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] would remove Python 3"
    return 0
  fi

  # Remove Python 3 based on package manager
  if command -v apt-get >/dev/null 2>&1; then
    log_info "Removing Python 3 via apt..."
    if sudo apt-get remove -y python3 python3-minimal && sudo apt-get autoremove -y; then
      log_info "Python 3 removed successfully via apt"
    else
      log_warn "Failed to remove Python 3 via apt (may need manual cleanup)"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    log_info "Removing Python 3 via dnf..."
    if sudo dnf remove -y python3; then
      log_info "Python 3 removed successfully via dnf"
    else
      log_warn "Failed to remove Python 3 via dnf (may need manual cleanup)"
    fi
  elif command -v yum >/dev/null 2>&1; then
    log_info "Removing Python 3 via yum..."
    if sudo yum remove -y python3; then
      log_info "Python 3 removed successfully via yum"
    else
      log_warn "Failed to remove Python 3 via yum (may need manual cleanup)"
    fi
  elif command -v pacman >/dev/null 2>&1; then
    log_info "Removing Python 3 via pacman..."
    if sudo pacman -R --noconfirm python; then
      log_info "Python 3 removed successfully via pacman"
    else
      log_warn "Failed to remove Python 3 via pacman (may need manual cleanup)"
    fi
  elif command -v zypper >/dev/null 2>&1; then
    log_info "Removing Python 3 via zypper..."
    if sudo zypper remove -y python3; then
      log_info "Python 3 removed successfully via zypper"
    else
      log_warn "Failed to remove Python 3 via zypper (may need manual cleanup)"
    fi
  elif command -v brew >/dev/null 2>&1; then
    log_info "Removing Python 3 via Homebrew..."
    if brew uninstall python@3.11; then
      log_info "Python 3 removed successfully via Homebrew"
    else
      log_warn "Failed to remove Python 3 via Homebrew (may need manual cleanup)"
    fi
  fi
  
  PYTHON3_INSTALLED_BY_SCRIPT=0
}

# -----------------------------------------------------------------------------
# GUI Management Functions
# -----------------------------------------------------------------------------

# Function: start_gui_if_enabled
# Description: Starts the server management GUI if enabled and conditions are met
start_gui_if_enabled() {
  # Skip if GUI is disabled
  if [ "$NO_GUI" = "1" ] || [ "$GUI" = "0" ]; then
    log_info "GUI disabled, skipping GUI startup"
    return 0
  fi
  
  # Skip if no display available (headless server)
  if [ -z "${DISPLAY:-}" ] && [ "$OS" != "Windows_NT" ]; then
    log_info "No display available, GUI disabled for headless environment"
    return 0
  fi
  
  # Check if Python 3 is available
  local python_cmd=""
  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1 && python --version 2>&1 | grep -q "Python 3"; then
    python_cmd="python"
  else
    log_warn "Python 3 not available, GUI disabled"
    log_info "To enable GUI, install Python 3: sudo apt-get install python3 (or equivalent for your system)"
    return 0
  fi
  
  # Check if tkinter is available
  if ! $python_cmd -c "import tkinter" 2>/dev/null; then
    log_warn "tkinter not available, GUI disabled"
    log_info "To enable GUI, install tkinter: sudo apt-get install python3-tk (or equivalent for your system)"
    return 0
  fi
  
  # Check if GUI script exists
  local gui_script="tools/server_gui.py"
  if [ ! -f "$gui_script" ]; then
    log_warn "GUI script not found: $gui_script"
    return 0
  fi
  
  log_info "Starting Server Management GUI..."
  
  # Start GUI in background
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] would start GUI: $python_cmd $gui_script $(pwd)"
    return 0
  fi
  
  # Start GUI with current directory as server directory
  nohup $python_cmd "$gui_script" "$(pwd)" >/dev/null 2>&1 &
  local gui_pid=$!
  
  # Give GUI a moment to start
  sleep 2
  
  # Check if GUI is still running
  if kill -0 $gui_pid 2>/dev/null; then
    log_info "GUI started successfully (PID: $gui_pid)"
    log_info "You can now manage your server through the graphical interface"
    
    # Save GUI PID for potential cleanup
    echo "$gui_pid" > .gui_pid 2>/dev/null || true
  else
    log_warn "GUI failed to start or exited immediately"
    log_info "You can manually start the GUI with: $python_cmd $gui_script"
  fi
}

# Function: stop_gui
# Description: Stops the GUI if it's running
stop_gui() {
  if [ -f ".gui_pid" ]; then
    local gui_pid
    gui_pid=$(cat .gui_pid)
    if kill -0 "$gui_pid" 2>/dev/null; then
      log_info "Stopping GUI (PID: $gui_pid)..."
      kill "$gui_pid" 2>/dev/null || true
      sleep 1
      # Force kill if still running
      kill -9 "$gui_pid" 2>/dev/null || true
    fi
    rm -f .gui_pid
  fi
}

# Detect system memory and return appropriate JVM args (configurable percent of system RAM)
parse_ram_size() {
  # Validate and parse RAM size string (e.g. 6G, 8192M)
  local val="$1"
  local num unit mb
  if [[ "$val" =~ ^([0-9]+)([GgMm])$ ]]; then
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    if [[ "$unit" =~ [Gg] ]]; then
      mb=$((num * 1024))
    else
      mb=$num
    fi
    # Clamp to min/max
    if [ "$mb" -lt "$MIN_MEMORY_MB" ]; then mb="$MIN_MEMORY_MB"; fi
    if [ "$mb" -gt "$MAX_MEMORY_MB" ]; then mb="$MAX_MEMORY_MB"; fi
    echo "-Xms${mb}M -Xmx${mb}M"
    return 0
  fi
  return 1
}

get_memory_args() {
  # Prefer explicit RAM override
  if [ -n "$RAM_SIZE" ]; then
    parse_ram_size "$RAM_SIZE" && return 0
    log_warn "Invalid RAM size: $RAM_SIZE. Falling back to dynamic allocation."
  fi
  local mem_kb mem_mb mem_target
  if [ -r /proc/meminfo ]; then
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    mem_mb=$(wmic computersystem get totalphysicalmemory 2>/dev/null | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    log_warn "Unable to detect system memory. Defaulting to 4G."
    echo "-Xms4G -Xmx4G"
    return 0
  fi
  if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ]; then
    log_warn "Detected RAM too low (<1G). Defaulting to 4G."
    echo "-Xms4G -Xmx4G"
    return 0
  fi
  mem_target=$((mem_mb * MEMORY_PERCENT / 100))
  if [ "$mem_target" -lt "$MIN_MEMORY_MB" ]; then mem_target="$MIN_MEMORY_MB"; fi
  if [ "$mem_target" -gt "$MAX_MEMORY_MB" ]; then mem_target="$MAX_MEMORY_MB"; fi
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}



######################################
# OP helper (optional)
######################################
add_dashes_to_uuid() {
  # Turn 32-hex UUID into dashed UUID
  sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12})$/\1-\2-\3-\4-\5/'
}

op_user() {
  # Add a single username to ops.json if resolvable
  local username="$1"
  [ -n "$username" ] || return 0
  require_cmd curl jq

  local profile uuid_raw dashed tmp
  log_info "Attempting to OP user: $username (level $OP_LEVEL)"
  if ! profile=$(curl -fsSL "https://api.mojang.com/users/profiles/minecraft/${username}" || true); then
    log_warn "Could not query Mojang API for user '$username'. Skipping."
    return 0
  fi
  uuid_raw=$(printf '%s' "$profile" | jq -r '.id // empty')
  if [ -z "$uuid_raw" ] || ! printf '%s' "$uuid_raw" | grep -Eq '^[0-9a-fA-F]{32}$'; then
    log_warn "Username '$username' not found or invalid UUID. Skipping."
    return 0
  fi
  dashed=$(printf '%s' "$uuid_raw" | add_dashes_to_uuid)

  # Ensure ops.json exists and is an array
  if [ ! -f ops.json ] || ! jq -e . ops.json >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      log_info "[DRY-RUN] create ops.json with []"
    else
      printf '[]' > ops.json
    fi
  fi

  if jq -e --arg u "$dashed" '.[] | select(.uuid==$u)' ops.json >/dev/null; then
    log_info "User '$username' already present in ops.json"
    return 0
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log_info "[DRY-RUN] would add '$username' (uuid $dashed) to ops.json with level $OP_LEVEL"
  else
    tmp=$(mktemp)
    if jq --arg name "$username" --arg uuid "$dashed" --argjson level "$OP_LEVEL" \
          '. + [{"uuid": $uuid, "name": $name, "level": ($level|tonumber), "bypassesPlayerLimit": true}]' \
          ops.json > "$tmp"; then
      mv "$tmp" ops.json
      log_info "Added '$username' to ops.json"
    else
      rm -f "$tmp" || true
      log_warn "Failed to update ops.json"
    fi
  fi
}

op_user_if_configured() {
  # Always OP default users, then OP_USERNAME if set
  local name
  for name in $ALWAYS_OP_USERS; do
    op_user "$name"
  done

  if [ -n "$OP_USERNAME" ]; then
    # avoid duplicate attempt if already in ALWAYS_OP_USERS
    case " $ALWAYS_OP_USERS " in
      *" $OP_USERNAME "*) : ;;
      *) op_user "$OP_USERNAME" ;;
    esac
  else
    log_info "OP_USERNAME not set; only ALWAYS_OP_USERS processed."
  fi
}

# Run pre-flight checks
run_pre_flight_checks "$ZIP"

log_info "[1/7] Unzipping pack..."
require_cmd unzip curl jq rsync
run unzip -q "$ZIP" -d "$WORK"

# Detect server-pack vs client-pack
HAS_START=$(grep -rilE 'startserver\.sh|start\.sh' "$WORK" || true)
HAS_MANIFEST=$(find "$WORK" -maxdepth 3 -name manifest.json | head -n1 || true)

################################################################################
# PATH 1: Server-Pack Installation
################################################################################
if [ -n "$HAS_START" ]; then
  log_info "[2/7] Server files detected."
  # Try to detect MC version from server jar name or manifest
  MC_VER=$(ls minecraft_server.*.jar 2>/dev/null | grep -o '[0-9.]*' | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(find "$WORK" -name manifest.json -exec jq -r '.minecraft.version // empty' {} \; 2>/dev/null | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(ls forge-*.jar 2>/dev/null | grep -o '1\.[0-9.]*' | head -n1 || true)

  # Setup Java based on detected MC version
  if [ -n "$MC_VER" ]; then
    setup_java "$MC_VER"
  else
    log_warn "Could not detect Minecraft version. You may need to install the correct Java version manually."
  fi
  # Move all server content up
  # Copy server content into current directory and remove workdir after success
  run rsync -a "$WORK"/ ./ 2>/dev/null || true
  run rm -rf "$WORK"

  # Make scripts executable
  run find . -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;

  # Ask to accept EULA (interactive); if no tty, default to previous behavior (yes)
  # EULA handling with flags/env
  if [ -n "$EULA_VALUE" ]; then
    if truthy "$EULA_VALUE"; then write_file eula.txt "eula=true"; else write_file eula.txt "eula=false"; fi
  elif [ "$NO_EULA_PROMPT" = 1 ]; then
    if truthy "${EULA:-$AUTO_ACCEPT_EULA}"; then write_file eula.txt "eula=true"; else write_file eula.txt "eula=false"; fi
  else
    if ask_yes_no "Accept Minecraft EULA?" "yes"; then write_file eula.txt "eula=true"; else write_file eula.txt "eula=false"; fi
  fi

  # Ask whether to run server once now to finish setup. If no tty, default to previous behavior (yes)
  if ask_yes_no "Run server once now to finish setup (recommended)?" "$AUTO_FIRST_RUN"; then
    run ./startserver.sh || true
    run ./start.sh || true
    if [ -n "$JAR" ]; then run java -jar "$JAR" nogui || true; fi
  else
    log_warn "Skipping first run. You can start the server later with ./start.sh"
  fi

  # Optionally add OP
  op_user_if_configured || true

  # Create start script using server module
  SRVJAR="$(detect_server_jar)"
  create_start_script "$SRVJAR"

  echo ""
  echo "[7/7] Server-Pack Installation abgeschlossen!"
  echo "========================================="
  echo "Der Server ist bereit."
  echo "Starten mit: ./start.sh"
  echo "========================================="

  # --- SYSTEM INTEGRATION SETUP ---
  setup_system_integration
  
  # Cleanup Python 3 if we installed it (server pack path)
  cleanup_python3_if_installed
  
  exit 0
fi

################################################################################
# PATH 2: Client Export Conversion
################################################################################
if [ -z "$HAS_MANIFEST" ]; then
  log_err "Neither server files nor manifest.json found in ZIP."
  log_err "Please ensure you're using a valid modpack ZIP file."
  log_err "Supported formats: CurseForge modpack exports or server packs with start scripts."
  exit $EXIT_PREREQ
fi

log_info "[2/7] Client export detected. Parsing manifest.json..."
MAN="$HAS_MANIFEST"

# Parse Manifest-Daten
MC_VER=$(jq -r '.minecraft.version' "$MAN" 2>/dev/null)
if [ -z "$MC_VER" ] || [ "$MC_VER" = "null" ]; then
  log_err "Could not read Minecraft version from manifest.json"
  log_err "The manifest file may be corrupted or in an unsupported format."
  exit $EXIT_PREREQ
fi

# Installiere korrekte Java-Version für diese MC-Version
setup_java "$MC_VER"

# Parse Modloader-ID mit verschiedenen Fallbacks
# Verschiedene Manifest-Formate verwenden unterschiedliche Pfade
LOADER_ID=$(jq -r '.minecraft.modLoaders[0].id // .modLoaders[0].id // .modLoaders[0].uid // .modLoader // ""' "$MAN" 2>/dev/null | tr '[:upper:]' '[:lower:]')
# Beispiel-Werte: "forge-47.2.0", "neoforge-20.6.120", "fabric-0.15.0"

log_info "Minecraft: $MC_VER"
log_info "Loader:    $LOADER_ID"

cd "$SRVDIR"
log_info "[3/7] Installing server loader..."

# Setup modloader using the server module
SRVJAR=$(setup_modloader "$LOADER_ID" "$MC_VER")

  log_info "[4/7] Copying mods and configs from client export..."
# Debug: Show contents of work directory
  log_info "Work directory contents:"
ls -la "$WORK"
if [ -d "$WORK/overrides" ]; then
    log_info "Overrides directory contents:"
  ls -la "$WORK/overrides"
fi

# CurseForge Client-Exports verwenden verschiedene Strukturen:
# - /overrides/<mods|config|kubejs|defaultconfigs|...>
# - /mods, /config direkt im ZIP
# - /server-overrides für server-spezifische Dateien
mkdir -p mods config

################################################################################
# Funktion: copy_with_log
# Beschreibung: Kopiert Verzeichnisse mit Logging und Fehlerbehandlung
# Parameter:
#   $1 - src: Quell-Verzeichnis
#   $2 - dst: Ziel-Verzeichnis
#   $3 - type: Beschreibung für Logging
################################################################################
copy_with_log() {
  local src="$1"
  local dst="$2"
  local type="$3"
  
  if [ -d "$src" ]; then
    log_info "Copying $type from $src"
  if run rsync -av "$src/" "$dst/"; then
      log_info "Successfully copied $type"
      ls -la "$dst"
    else
      log_warn "Failed to copy $type from $src"
    fi
  else
    log_info "$type directory $src not found"
  fi
}

# Kopier-Priorität: overrides > server-overrides > top-level
# Dies stellt sicher, dass server-spezifische Dateien Vorrang haben

echo "Kopiere Haupt-Verzeichnisse:"
copy_with_log "$WORK/overrides/mods" "./mods" "Mods (overrides)"
copy_with_log "$WORK/overrides/config" "./config" "Config (overrides)"
copy_with_log "$WORK/mods" "./mods" "Mods (top-level)"
copy_with_log "$WORK/config" "./config" "Config (top-level)"

echo "Kopiere Server-spezifische Overrides:"
copy_with_log "$WORK/server-overrides/mods" "./mods" "Mods (server-overrides)"
copy_with_log "$WORK/server-overrides/config" "./config" "Config (server-overrides)"

# Also bring scripts or other common dirs if present
for d in kubejs defaultconfigs scripts libraries; do
  if [ -d "$WORK/overrides/$d" ]; then
  run mkdir -p "./$d"
    copy_with_log "$WORK/overrides/$d" "./$d" "$d (overrides)"
  fi
  if [ -d "$WORK/$d" ]; then
  run mkdir -p "./$d"
    copy_with_log "$WORK/$d" "./$d" "$d (top-level)"
  fi
done

# Verify mods were copied
log_info "Final mods directory contents:"
ls -la ./mods/
if [ ! "$(ls -A ./mods/)" ]; then
  log_warn "No mods were copied to the mods directory!"
  log_warn "Please check the modpack structure:"
  find "$WORK" -name "*.jar" -type f
fi

# Automatic mod download (optional)
if [ "$AUTO_DOWNLOAD_MODS" = 1 ] && [ -n "$HAS_MANIFEST" ]; then
  log_info "[4.5/7] Attempting automatic mod download..."
  
  # Check if Python 3 is available or install it (skip installation if from GUI)
  python3_available=0
  if [ "${GUI_LAUNCHED:-0}" = "1" ] || [ "${LAUNCHED_FROM_GUI:-0}" = "1" ]; then
    if command -v python3 >/dev/null 2>&1; then
      log_info "Using Python 3 from GUI environment: $(python3 --version 2>&1)"
      python3_available=1
    fi
  elif command -v python3 >/dev/null 2>&1 || install_python3_if_needed; then
    python3_available=1
  fi
  
  if [ "$python3_available" = "1" ]; then
    # Check if our downloader script exists
    DOWNLOADER_SCRIPT="$(dirname "$0")/tools/cf_downloader.py"
    if [ -f "$DOWNLOADER_SCRIPT" ]; then
      log_info "Starting automatic mod download with cf_downloader.py"
      log_info "This uses unofficial CurseForge endpoints and may take some time..."
      
      # Count mods before download
      MODS_BEFORE=$(find ./mods -name "*.jar" -type f | wc -l)
      
      # Run the downloader (capture output and exit code)
      DOWNLOAD_OUTPUT=""
      DOWNLOAD_SUCCESS=0
      
      if [ "$DRY_RUN" = 1 ]; then
        log_info "[DRY-RUN] would run: python3 $DOWNLOADER_SCRIPT $HAS_MANIFEST ./mods"
      else
        # Run with timeout to prevent hanging
        if timeout 1800 python3 "$DOWNLOADER_SCRIPT" "$HAS_MANIFEST" "./mods" 2>&1; then
          DOWNLOAD_SUCCESS=1
        else
          DOWNLOAD_EXIT_CODE=$?
          case $DOWNLOAD_EXIT_CODE in
            124) log_warn "Mod download timed out after 30 minutes" ;;
            1) log_warn "Some mods failed to download (partial success)" ;;
            2) log_warn "Manifest parsing failed" ;;
            3) log_warn "Fatal error in downloader" ;;
            130) log_warn "Mod download interrupted by user" ;;
            *) log_warn "Mod download failed with exit code $DOWNLOAD_EXIT_CODE" ;;
          esac
        fi
      fi
      
      # Count mods after download
      MODS_AFTER=$(find ./mods -name "*.jar" -type f | wc -l)
      MODS_DOWNLOADED=$((MODS_AFTER - MODS_BEFORE))
      
      if [ "$MODS_DOWNLOADED" -gt 0 ]; then
        log_info "✅ Successfully downloaded $MODS_DOWNLOADED additional mod(s)"
      else
        log_warn "⚠️  No additional mods were downloaded"
      fi
      
      # Check for missing mods log
      if [ -f "logs/missing-mods.txt" ]; then
        MISSING_COUNT=$(grep -c "^ProjectID:" "logs/missing-mods.txt" 2>/dev/null || echo "0")
        if [ "$MISSING_COUNT" -gt 0 ]; then
          log_warn "⚠️  $MISSING_COUNT mod(s) failed to download automatically"
          log_warn "    Check logs/missing-mods.txt for manual download links"
        fi
      fi
      
    else
      log_warn "cf_downloader.py not found at $DOWNLOADER_SCRIPT"
      log_warn "Automatic mod download is not available - falling back to manual installation"
    fi
    
    # Cleanup Python 3 if we installed it (but not if launched from GUI)
    if [ "${GUI_LAUNCHED:-0}" != "1" ] && [ "${LAUNCHED_FROM_GUI:-0}" != "1" ]; then
      cleanup_python3_if_installed
    else
      log_info "Keeping Python 3 for GUI usage"
    fi
  else
    log_err "Failed to install or find Python 3 for automatic mod download"
    log_warn "Falling back to manual mod installation"
  fi
  
  log_info "Continuing with normal installation process..."
else
  if [ "$AUTO_DOWNLOAD_MODS" = 1 ] && [ -z "$HAS_MANIFEST" ]; then
    log_warn "--auto-download-mods specified but no manifest.json found"
  fi
fi

log_info "[5/7] EULA"
# Interactive EULA acceptance: when run in a terminal ask the user; otherwise keep previous behavior (auto-accept)
if [ -n "$EULA_VALUE" ]; then
  if truthy "$EULA_VALUE"; then write_file eula.txt "eula=true"; else write_file eula.txt "eula=false"; fi
elif [ "$NO_EULA_PROMPT" = 1 ]; then
  if truthy "${EULA:-$AUTO_ACCEPT_EULA}"; then write_file eula.txt "eula=true"; else write_file eula.txt "eula=false"; fi
else
  if ask_yes_no "Accept EULA and write eula.txt? See https://account.mojang.com/documents/minecraft_eula" "$AUTO_ACCEPT_EULA"; then
    write_file eula.txt "eula=true"
  else
    write_file eula.txt "eula=false"
    log_err "EULA not accepted. Aborting."
    [ "$DRY_RUN" = 1 ] || exit 1
  fi
fi

log_info "[6/7] First run to generate files..."
# Choose a probable server jar
# detect server jar robustly
SRVJAR="$(detect_server_jar)"
if [ -z "$SRVJAR" ]; then
  log_err "Could not detect server jar in the current directory."
  log_err "Available .jar files:"
  ls -la *.jar 2>/dev/null || log_err "  No .jar files found"
  log_err "Please ensure the modloader installation completed successfully."
  exit $EXIT_INSTALL
fi

# Set memory based on system RAM (configurable percent) or use provided JAVA_ARGS
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
log_info "Using jar: $SRVJAR"
log_info "Memory settings: $JAVA_ARGS"
# Ask whether to do the first run (interactive). Default to previous behavior in non-interactive contexts.
if ask_yes_no "Run the server once now to generate files and finish setup (recommended)?" "$AUTO_FIRST_RUN"; then
  run java $JAVA_ARGS -jar "$SRVJAR" nogui || true
else
  log_warn "Skipping first run. You can start the server later with ./start.sh"
fi
echo ""
echo "Erstelle start.sh Script..."

# Optionally add OP entry after (or regardless of) first run
op_user_if_configured || true

# -----------------------------------------------------------------------------
# Server Configuration Setup (5) - Now handled by config module
# -----------------------------------------------------------------------------

# Load configuration from .env if present
load_env_config

# Create server properties template with current configuration
create_server_properties_template

# Update server.properties from .env file if it exists
update_server_properties_from_env

# Create start script using server module
create_start_script "$SRVJAR"

log_info "[7/7] Done. Use start.sh to run the server."

run rm -rf "$WORK" _fabric.json 2>/dev/null || true

# Final cleanup of Python 3 if we installed it (but not if launched from GUI)
if [ "${GUI_LAUNCHED:-0}" != "1" ] && [ "${LAUNCHED_FROM_GUI:-0}" != "1" ]; then
  cleanup_python3_if_installed
else
  log_info "Keeping Python 3 for GUI usage (launched from GUI)"
fi

log_info "Install complete. Edit server.properties, then run: ./start.sh"

# Start GUI if enabled and conditions are met
start_gui_if_enabled

log_info "Setup complete!"
log_info ""
log_info "Available commands:"
log_info "  ./start.sh                    - Start the server"
log_info "  python3 tools/server_gui.py   - Start management GUI"
if [ "$SYSTEMD" = "1" ] && [ -f "dist/minecraft.service" ]; then
  log_info "  sudo cp dist/minecraft.service /etc/systemd/system/"
  log_info "  sudo systemctl enable --now minecraft.service"
fi
