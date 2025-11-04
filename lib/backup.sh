#!/usr/bin/env bash
################################################################################
# Backup and Restore Module
# Part of Universal Minecraft Server Setup Script
#
# This module handles:
# - World backup and restore operations
# - Periodic backup scheduling
# - Backup file management and cleanup
################################################################################

# Prevent double-loading
if [[ "${BACKUP_MODULE_LOADED:-}" == "1" ]]; then
  return 0
fi
readonly BACKUP_MODULE_LOADED=1

# Load required dependencies
if [[ -z "${CORE_MODULE_LOADED:-}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
fi
if [[ -z "${LOGGING_MODULE_LOADED:-}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
fi

################################################################################
# Function: backup_world
# Description: Create a compressed backup of a world directory
# Parameters:
#   Uses WORLD_NAME environment variable (defaults to 'world')
# Returns:
#   0 on success, 1 on failure
################################################################################
backup_world() {
  local name="${WORLD_NAME:-world}"
  local src="$name"
  [ -d "$src" ] || src="world"
  local ts="$(get_file_timestamp)"
  local backup_dir="backups"
  local backup_zip="$backup_dir/${name}-$ts.zip"
  
  ensure_directory "$backup_dir"
  
  if [ -d "$src" ]; then
    log_info "Backing up world '$src' to $backup_zip"
    if zip -rq "$backup_zip" "$src"; then
      log_success "Backup complete: $backup_zip"
      return 0
    else
      log_err "Failed to create backup: $backup_zip"
      return 1
    fi
  else
    log_warn "World directory '$src' not found, skipping backup."
    return 1
  fi
}

################################################################################
# Function: restore_world
# Description: Restore world from a backup ZIP file
# Parameters:
#   Uses RESTORE_ZIP environment variable
# Returns:
#   0 on success, 1 on failure
################################################################################
restore_world() {
  local zip="$RESTORE_ZIP"
  if [ ! -f "$zip" ]; then
    log_err "Backup ZIP not found: $zip"
    return 1
  fi

  local name="${WORLD_NAME:-world}"
  
  if [ -d "$name" ]; then
    log_warn "World directory '$name' already exists."
    if [ "${FORCE:-0}" != "1" ]; then
      if ! ask_yes_no "Overwrite existing world '$name'?"; then
        log_info "Restore cancelled."
        return 0
      fi
    fi
    log_info "Removing existing world directory..."
    rm -rf "$name"
  fi

  log_info "Restoring world from $zip to $name/"
  if unzip -q "$zip" -d .; then
    log_success "World restored successfully from $zip"
    return 0
  else
    log_err "Failed to restore world from $zip"
    return 1
  fi
}

################################################################################
# Function: start_periodic_backups
# Description: Start periodic world backups in background
# Parameters:
#   $1 - interval: Backup interval in hours
#   $2 - retention: Number of backups to keep
#   $3 - world_name: Name of the world directory to backup (optional)
# Returns:
#   0 on success
################################################################################
start_periodic_backups() {
  local interval="$1" 
  local retention="$2" 
  local world_name="${3:-${WORLD_NAME:-world}}"
  local backup_dir="backups"
  
  ensure_directory "$backup_dir"
  
  log_info "Starting periodic backups: every ${interval}h, keep ${retention} backups"
  
  (
    while true; do
      ts="$(get_file_timestamp)"
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
  
  log_info "Periodic backup process started in background (PID: $!)"
}

################################################################################
# Function: list_backups
# Description: List available backup files
# Parameters:
#   $1 - world_name: Name of the world (optional, defaults to current WORLD_NAME)
# Returns:
#   0 on success
################################################################################
list_backups() {
  local world_name="${1:-${WORLD_NAME:-world}}"
  local backup_dir="backups"
  
  log_info "Available backups for '$world_name':"
  
  if [ -d "$backup_dir" ]; then
    local backups=($(ls -1t "$backup_dir/${world_name}-"*.zip 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
      log_info "No backups found."
    else
      for backup in "${backups[@]}"; do
        local size=$(du -h "$backup" 2>/dev/null | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null || stat -f %Sm "$backup" 2>/dev/null || echo "unknown")
        log_info "  $(basename "$backup") (${size}, ${date})"
      done
    fi
  else
    log_info "No backup directory found."
  fi
}

# -----------------------------------------------------------------------------
# MODULE INITIALIZATION
# -----------------------------------------------------------------------------

# Export backup functions
export -f backup_world
export -f restore_world
export -f start_periodic_backups
export -f list_backups