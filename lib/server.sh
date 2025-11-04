#!/usr/bin/env bash
################################################################################
# Server Management Module
# Part of Universal Minecraft Server Setup Script
#
# This module handles:
# - Server JAR detection and selection
# - Modloader downloads (Forge, NeoForge, Fabric, Quilt)
# - Start script generation
# - Server functions file creation
# - Memory management for server startup
################################################################################

# Ensure this module is not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This is a library module and should not be executed directly."
  exit 1
fi

################################################################################
# Function: detect_server_jar
# Description: Robust server jar detection with priority order
# Returns:
#   Echoes the path to the best server JAR file found
# Priority:
#   1) forge/fabric/quilt specific server jars
#   2) named modded jars (run.jar etc)
#   3) other server jars excluding vanilla
################################################################################
detect_server_jar() {
  local j
  
  # Priority 1: Explicit modloader server JARs
  # Forge (classic and new versions)
  j=$(ls -1 forge-*-server*.jar forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 neoforge-*-server*.jar neoforge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 fabric-server-launch.jar fabric-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 quilt-server-launch.jar quilt-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 *forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 run*.jar 2>/dev/null | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Priority 2: Server JARs (excluding vanilla minecraft_server)
  j=$(ls -1 *-server*.jar 2>/dev/null | grep -v "minecraft_server" | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Fallback: Largest JAR file (excluding installer)
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

################################################################################
# Function: get_memory_args
# Description: Calculate optimal JVM memory arguments based on system RAM
# Returns:
#   Echoes JVM memory arguments like "-Xms4G -Xmx8G"
# Uses:
#   MEMORY_PERCENT (default: 75%) - Percentage of RAM to allocate
#   MIN_MEMORY_MB (default: 4096) - Minimum memory in MB
#   MAX_MEMORY_MB (default: 32768) - Maximum memory in MB
################################################################################
get_memory_args() {
  local mem_kb mem_mb mem_target
  
  # Memory configuration constants
  local MEMORY_PERCENT="${MEMORY_PERCENT:-75}"
  local MIN_MEMORY_MB="${MIN_MEMORY_MB:-4096}"
  local MAX_MEMORY_MB="${MAX_MEMORY_MB:-32768}"
  
  if [ -r /proc/meminfo ]; then
    # Linux
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    # macOS
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    # Windows
    mem_mb=$(wmic computersystem get totalphysicalmemory 2>/dev/null | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    # Fallback
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  
  # Validation and calculation
  if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ]; then
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  
  mem_target=$((mem_mb * MEMORY_PERCENT / 100))
  [ "$mem_target" -lt "$MIN_MEMORY_MB" ] && mem_target="$MIN_MEMORY_MB"
  [ "$mem_target" -gt "$MAX_MEMORY_MB" ] && mem_target="$MAX_MEMORY_MB"
  
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

################################################################################
# Function: start_periodic_backups
# Description: Start background process for periodic world backups
# Parameters:
#   $1 - interval: Backup interval in hours
#   $2 - retention: Number of backups to keep
#   $3 - world_name: Name of the world directory to backup
################################################################################
start_periodic_backups() {
  local interval="$1" retention="$2" world_name="$3"
  local backup_dir="backups"
  mkdir -p "$backup_dir"
  
  (
    while true; do
      ts="$(date '+%Y%m%d-%H%M%S')"
      backup_zip="$backup_dir/${world_name}-$ts.zip"
      if [ -d "$world_name" ]; then
        zip -rq "$backup_zip" "$world_name"
        echo "[AUTO-BACKUP] Backup complete: $backup_zip"
        
        # Delete oldest backups if exceeding retention
        backups=( $(ls -1t "$backup_dir/${world_name}-"*.zip 2>/dev/null) )
        if [ "${#backups[@]}" -gt "$retention" ]; then
          for ((i=${retention}; i<${#backups[@]}; i++)); do
            rm -f "${backups[$i]}"
            echo "[AUTO-BACKUP] Deleted old backup: ${backups[$i]}"
          done
        fi
      else
        echo "[AUTO-BACKUP] World directory '$world_name' not found, skipping backup."
      fi
      sleep "$((interval*3600))"
    done
  ) &
}

################################################################################
# Function: download_forge
# Description: Downloads and installs Forge Server
# Parameters:
#   $1 - mc: Minecraft version (e.g. "1.20.1")
#   $2 - forge: Forge version (e.g. "47.2.0")
################################################################################
download_forge() {
  local mc="$1" forge="$2"
  local base="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-${forge}"
  local inst="forge-${mc}-${forge}-installer.jar"
  
  log_info "Downloading Forge installer: $inst"
  run curl -fL "${base}/${inst}" -o "$inst"
  
  log_info "Installing Forge server..."
  run java -jar "$inst" --installServer
}

################################################################################
# Function: download_neoforge
# Description: Downloads and installs NeoForge Server
# Parameters:
#   $1 - version: NeoForge version (e.g. "20.4.237")
################################################################################
download_neoforge() {
  local ver="$1"
  local base="https://maven.neoforged.net/releases/net/neoforged/forge/${ver}"
  local inst="forge-${ver}-installer.jar"
  
  log_info "Downloading NeoForge installer: $inst"
  run curl -fL "${base}/${inst}" -o "$inst"
  
  log_info "Installing NeoForge server..."
  run java -jar "$inst" --installServer
}

################################################################################
# Function: download_fabric
# Description: Downloads and installs Fabric Server
# Parameters:
#   $1 - mc_version: Minecraft version (e.g. "1.20.1")
################################################################################
download_fabric() {
  local mc_ver="$1"
  local INST="fabric-installer.jar"
  
  log_info "Fetching Fabric installer metadata..."
  run curl -fL "https://meta.fabricmc.net/v2/versions/installer" -o _fabric.json
  
  local URL
  URL=$(jq -r '[.[] | select(.stable==true)][0].url' _fabric.json)
  
  log_info "Downloading Fabric installer..."
  run curl -fL "$URL" -o "$INST"
  
  log_info "Installing Fabric server for MC $mc_ver..."
  run java -jar "$INST" server -mc-version "$mc_ver" -downloadMinecraft
}

################################################################################
# Function: setup_modloader
# Description: Install the appropriate modloader based on loader ID
# Parameters:
#   $1 - loader_id: Loader identifier (forge-X.X.X, neoforge-X.X.X, fabric, quilt)
#   $2 - mc_version: Minecraft version
# Returns:
#   Sets SRVJAR variable with the detected server jar path
################################################################################
setup_modloader() {
  local loader_id="$1"
  local mc_ver="$2"
  local SRVJAR=""
  
  case "$loader_id" in
    forge-*)
      # Forge (classic)
      FORGE_VER="${loader_id#forge-}"
      log_info "Installing Forge $FORGE_VER..."
      download_forge "$mc_ver" "$FORGE_VER"
      
      # Search for generated server JAR
      SRVJAR=$(ls -1 forge-*-server*.jar 2>/dev/null | head -n1 || true)
      [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar 2>/dev/null | head -n1 || true)
      ;;
    neoforge-*)
      # NeoForge (Forge fork for newer versions)
      NEO_VER="${loader_id#neoforge-}"
      log_info "Installing NeoForge $NEO_VER..."
      download_neoforge "$NEO_VER"
      
      SRVJAR=$(ls -1 neoforge-*-server*.jar 2>/dev/null | head -n1 || true)
      [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar 2>/dev/null | head -n1 || true)
      ;;
    fabric*)
      # Fabric
      log_info "Installing Fabric..."
      download_fabric "$mc_ver"
      SRVJAR="fabric-server-launch.jar"
      ;;
    quilt*|quilt)
      # Quilt (Fabric fork with extended features)
      log_info "Quilt loader detected."
      log_warn "Automatic Quilt installation not implemented."
      log_warn "If quilt-server-launch.jar is missing, please install Quilt manually."
      SRVJAR="quilt-server-launch.jar"
      ;;
    *)
      log_err "Unknown loader: $loader_id"
      return 1
      ;;
  esac
  
  # Export SRVJAR for use in calling code
  printf '%s' "$SRVJAR"
}

################################################################################
# Function: create_server_functions_file
# Description: Creates .server_functions.sh with shared functions for start scripts
################################################################################
create_server_functions_file() {
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] would write .server_functions.sh"
    return 0
  fi
  
  cat > .server_functions.sh <<"EOF_SHARED_FUNCS"
#!/usr/bin/env bash
# Shared functions for server management scripts
# Generated by universalServerSetup.sh

# Memory configuration constants
MEMORY_PERCENT="${MEMORY_PERCENT:-75}"
MIN_MEMORY_MB="${MIN_MEMORY_MB:-4096}"
MAX_MEMORY_MB="${MAX_MEMORY_MB:-32768}"

# Function to detect server jar
detect_server_jar() {
  local j
  # First priority: explicit modded server jars
  j=$(ls -1 forge-*-server*.jar forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 neoforge-*-server*.jar neoforge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 fabric-server-launch.jar fabric-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 quilt-server-launch.jar quilt-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 *forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 run*.jar 2>/dev/null | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Second priority: server jars excluding vanilla minecraft_server
  j=$(ls -1 *-server*.jar 2>/dev/null | grep -v "minecraft_server" | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Fallback: largest jar excluding installer jars
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

# Function to get memory arguments
get_memory_args() {
  local mem_kb mem_mb mem_target
  if [ -r /proc/meminfo ]; then
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    mem_mb=$(wmic computersystem get totalphysicalmemory 2>/dev/null | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ] && { echo "-Xms4G -Xmx8G"; return 0; }
  mem_target=$((mem_mb * MEMORY_PERCENT / 100))
  [ "$mem_target" -lt "$MIN_MEMORY_MB" ] && mem_target="$MIN_MEMORY_MB"
  [ "$mem_target" -gt "$MAX_MEMORY_MB" ] && mem_target="$MAX_MEMORY_MB"
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

# Periodic backup function
start_periodic_backups() {
  local interval="$1" retention="$2" world_name="$3"
  local backup_dir="backups"
  mkdir -p "$backup_dir"
  (
    while true; do
      ts="$(date '+%Y%m%d-%H%M%S')"
      backup_zip="$backup_dir/${world_name}-$ts.zip"
      if [ -d "$world_name" ]; then
        zip -rq "$backup_zip" "$world_name"
        echo "[AUTO-BACKUP] Backup complete: $backup_zip"
        # Delete oldest backups if exceeding retention
        backups=( $(ls -1t "$backup_dir/${world_name}-"*.zip 2>/dev/null) )
        if [ "${#backups[@]}" -gt "$retention" ]; then
          for ((i=${retention}; i<${#backups[@]}; i++)); do
            rm -f "${backups[$i]}"
            echo "[AUTO-BACKUP] Deleted old backup: ${backups[$i]}"
          done
        fi
      else
        echo "[AUTO-BACKUP] World directory '$world_name' not found, skipping backup."
      fi
      sleep "$((interval*3600))"
    done
  ) &
}
EOF_SHARED_FUNCS

  log_info "Created .server_functions.sh"
}

################################################################################
# Function: create_start_script
# Description: Creates the start.sh script for running the server
# Parameters:
#   $1 - server_jar: Path to the server JAR file
################################################################################
create_start_script() {
  local server_jar="$1"
  
  # Store the detected jar name in a file so start.sh can find it later
  echo "$server_jar" > .server_jar
  
  # Create shared functions file for start.sh to avoid code duplication
  create_server_functions_file
  
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] would write start.sh"
    return 0
  fi

  log_info "Creating start.sh script..."
  
  cat > start.sh <<"EOFMARKER"
#!/usr/bin/env bash
################################################################################
# Minecraft Server Start Script
# Generated by universalServerSetup.sh
################################################################################
set -euo pipefail
cd "$(dirname "$0")"

# Configuration
BACKUP_INTERVAL_HOURS="${BACKUP_INTERVAL_HOURS:-4}"
BACKUP_RETENTION="${BACKUP_RETENTION:-12}"
WORLD_NAME="${WORLD_NAME:-world}"

# Source shared functions (created by the setup script)
if [ -f ".server_functions.sh" ]; then
  source .server_functions.sh
else
  echo "ERROR: .server_functions.sh not found. Please re-run the setup script." >&2
  exit 1
fi

# Get server jar
if [ -r .server_jar ]; then
  JAR=$(cat .server_jar)
else
  JAR=$(detect_server_jar)
fi

# Start periodic backups in background
start_periodic_backups "$BACKUP_INTERVAL_HOURS" "$BACKUP_RETENTION" "$WORLD_NAME"

# Validate jar exists
if [ ! -f "$JAR" ]; then
  echo "ERROR: Server jar not found: $JAR" >&2
  echo "Trying to detect again..." >&2
  JAR=$(detect_server_jar)
  if [ ! -f "$JAR" ]; then
    echo "ERROR: Could not find a valid server jar." >&2
    echo "Please check your installation." >&2
    exit 1
  fi
  echo "$JAR" > .server_jar
fi

# Start server
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "========================================="
echo "Starting Minecraft Server"
echo "========================================="
echo "Server JAR: $JAR"
echo "Memory:     $JAVA_ARGS"
echo "========================================="
echo ""
exec java $JAVA_ARGS -jar "$JAR" nogui
EOFMARKER

  chmod +x start.sh
  log_info "Created executable start.sh"
}

################################################################################
# Function: download_server_jar
# Description: Downloads vanilla Minecraft server jar if needed
# Parameters:
#   $1 - mc_version: Minecraft version (e.g. "1.20.1")
################################################################################
download_server_jar() {
  local mc_version="$1"
  local server_jar="minecraft_server.${mc_version}.jar"
  
  if [ -f "$server_jar" ]; then
    log_info "Minecraft server JAR already exists: $server_jar"
    return 0
  fi
  
  log_info "Downloading Minecraft server JAR for version $mc_version..."
  
  # This would need to be implemented with the Mojang API
  # For now, just log that it would download
  log_warn "Vanilla server JAR download not implemented in module yet"
  log_info "Please download $server_jar manually from https://minecraft.net/download/server"
}

################################################################################
# Function: get_minecraft_version
# Description: Extract Minecraft version from existing server JAR
# Returns:
#   Echoes the Minecraft version if found, empty string otherwise
################################################################################
get_minecraft_version() {
  # Try to detect MC version from existing minecraft_server jar
  local mc_ver
  mc_ver=$(ls minecraft_server.*.jar 2>/dev/null | grep -o '[0-9.]*' | head -n1 || true)
  
  if [ -n "$mc_ver" ]; then
    printf '%s' "$mc_ver"
    return 0
  fi
  
  # Could be extended to parse from other sources like pack metadata
  return 1
}