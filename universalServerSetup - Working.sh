
#!/usr/bin/env bash
# Universal Minecraft Server Setup Script
# ---------------------------------------
# This script automates the installation and configuration of a modded Minecraft server.
# It supports Forge, NeoForge, Fabric, and Quilt loaders, and can handle both server packs and client exports.
#
# Usage:
#   ./universalServerSetup - Working.sh [Modpack.zip]
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
# CONFIGURATION SECTION (User-editable)
# -----------------------------------------------------------------------------

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


# Installation directories
# SRVDIR: Server directory (default: current directory)
# WORK: Temporary working directory
SRVDIR="${SRVDIR:-$(pwd)}"
WORK="${WORK:-${SRVDIR}/_work}"


# -----------------------------------------------------------------------------
# Runtime flags (populated via CLI/env)
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

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log()       { printf '%s\n' "$*"; }
log_info()  { printf '[INFO] %s\n' "$*"; }
log_warn()  { printf '[WARN] %s\n' "$*" >&2; }
log_err()   { printf '[ERROR] %s\n' "$*" >&2; }
LOG_LEVEL="info"   # info, warn, error
LOG_VERBOSE=1      # 0=quiet, 1=normal, 2=verbose
LOG_FILE=""
LOG_TTY=1

# Detect TTY for color
if [ ! -t 1 ]; then LOG_TTY=0; fi

# Color codes
CLR_RESET="\033[0m"
CLR_INFO="\033[32m"   # green
CLR_WARN="\033[33m"   # yellow
CLR_ERR="\033[31m"    # red

# Timestamp
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Logging core
log_msg() {
  local level="$1" msg="$2" color="" prefix="" out="";
  case "$level" in
    info)  color="$CLR_INFO"; prefix="INFO";;
    warn)  color="$CLR_WARN"; prefix="WARN";;
    error) color="$CLR_ERR"; prefix="ERROR";;
    *)     color="$CLR_RESET"; prefix="LOG";;
  esac
  out="[$(timestamp)] $prefix: $msg"
  # Console output
  if [ "$LOG_TTY" = "1" ]; then
    printf "%b%s%b\n" "$color" "$out" "$CLR_RESET"
  else
    printf "%s\n" "$out"
  fi
  # Log file output
  if [ -n "$LOG_FILE" ]; then
    printf "%s\n" "$out" >> "$LOG_FILE"
  fi
}

log()      { log_msg info "$*"; }
log_info() { [ "$LOG_VERBOSE" -ge 1 ] && log_msg info "$*"; }
log_warn() { [ "$LOG_VERBOSE" -ge 0 ] && log_msg warn "$*"; }
log_err()  { log_msg error "$*"; }

# Set up log file (logs/install-YYYYmmdd-HHMMSS.log)
setup_log_file() {
  local logdir="logs"
  mkdir -p "$logdir"
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"
  LOG_FILE="$logdir/install-$ts.log"
}

# Parse verbosity/log flags
for arg in "$@"; do
  case "$arg" in
    --verbose) LOG_VERBOSE=2 ;;
    --quiet)   LOG_VERBOSE=0 ;;
    --log-file)
      shift; LOG_FILE="$1" ;;
    --log-file=*)
      LOG_FILE="${arg#--log-file=}" ;;
  esac
done

setup_log_file

# -----------------------------------------------------------------------------
# Utility helpers
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

######################################
# Argument parsing
######################################
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
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
      *)
        # Unknown or positional argument
        ;;
    esac
    shift
  done
    case "$1" in
      --ram)
        shift; RAM_SIZE="$1" ;;
      --ram=*)
        RAM_SIZE="${1#--ram=}" ;;
      --yes) ASSUME_YES=1 ;;
      --assume-no) ASSUME_NO=1 ;;
      --no-eula-prompt) NO_EULA_PROMPT=1 ;;
      --eula=*) EULA_VALUE="${1#--eula=}" ;;
      --force) FORCE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --) shift; break ;;
      -*) log_err "Unknown option: $1"; exit 2 ;;
      *)
        # Accept positional ZIP argument if not overridden
        if [ -z "$ZIP_OVERRIDE" ] && [ -z "$ZIP" ]; then
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

# Parse CLI args now
parse_args "$@"

# Prepare working directory
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
# Beschreibung: Prüft ob alle benötigten Befehle verfügbar sind
# Parameter:
#   $@ - Liste der zu prüfenden Befehle
# Rückgabe:
#   0 - Alle Befehle sind verfügbar
#   exit 1 - Mindestens ein Befehl fehlt
################################################################################
require_cmd() {
  local missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "FEHLER: Benötigter Befehl nicht gefunden: $c" >&2
      echo "Bitte installieren Sie $c und versuchen Sie es erneut." >&2
      missing=1
    fi
  done
  [ $missing -eq 0 ] || exit 1
}

################################################################################
# Funktion: setup_java
# Beschreibung: Erkennt die benötigte Java-Version und installiert sie bei Bedarf
# Parameter:
#   $1 - mc_ver: Minecraft-Version (z.B. "1.20.1")
# Rückgabe:
#   0 - Java ist korrekt installiert
#   exit 1 - Installation fehlgeschlagen
# Logik:
#   - MC 1.20.5+ benötigt Java 21
#   - MC 1.17-1.20.4 benötigt Java 17
#   - MC <1.17 benötigt Java 8
################################################################################
setup_java() {
  local mc_ver="$1"
  local java_ver
  
  # Bestimme benötigte Java-Version basierend auf Minecraft-Version
  # MC 1.20.5+ benötigt Java 21 (class file version 65.0)
  if printf '%s\n' "1.20.5" "$mc_ver" | sort -V | head -n1 | grep -q "^1.20.5"; then
    java_ver=21
  # MC 1.17-1.20.4 benötigt Java 17 (class file version 61.0)
  elif printf '%s\n' "1.17" "$mc_ver" | sort -V | head -n1 | grep -q "^1.17"; then
    java_ver=17
  # MC <1.17 benötigt Java 8
  else
    java_ver=8
  fi

  log_info "Minecraft $mc_ver requires Java $java_ver"
  
  # Prüfe ob bereits eine kompatible Java-Version installiert ist
  if command -v java >/dev/null 2>&1; then
    local java_output current_ver
    java_output=$(java -version 2>&1)
  log_info "Java version output: $java_output"
    
    # Erweiterte Versions-Erkennung für verschiedene Ausgabeformate
    # Format 1: "1.8.0_xxx" -> Java 8
    if echo "$java_output" | grep -q "version \"1.8"; then
      current_ver=8
    # Format 2: "1.11.x" -> Java 11 (für Kompatibilität)
    elif echo "$java_output" | grep -q "version \"1.1"; then
      current_ver=11
    # Format 3: "17.0.x", "21.0.x" etc. -> Hauptversion extrahieren
    else
      current_ver=$(echo "$java_output" | grep -i version | head -n1 | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
    fi
    
    log_info "Detected Java version: $current_ver"
    if [ "$current_ver" = "$java_ver" ]; then
      log_info "Found compatible Java $current_ver"
      return 0
    fi
    log_warn "Found Java $current_ver, but Java $java_ver is required"
  fi

  # Installiere benötigte Java-Version basierend auf dem Package Manager
  echo "Installiere Java $java_ver..."
  
  if command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu
    log_info "Installing Java $java_ver via apt..."
    if [ "$java_ver" = "17" ]; then
      run sudo apt-get update
      run sudo apt-get install -y openjdk-17-jre-headless
      run sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-*/bin/java
    else
      run sudo apt-get update
      run sudo apt-get install -y openjdk-8-jre-headless
      run sudo update-alternatives --set java /usr/lib/jvm/java-8-openjdk-*/jre/bin/java
    fi
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora/RHEL
    log_info "Installing Java $java_ver via dnf..."
    if [ "$java_ver" = "17" ]; then
      run sudo dnf install -y java-17-openjdk-headless
    else
      run sudo dnf install -y java-1.8.0-openjdk-headless
    fi
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    log_info "Installing Java $java_ver via pacman..."
    if [ "$java_ver" = "17" ]; then
      run sudo pacman -Sy --noconfirm jre17-openjdk-headless
    else
      run sudo pacman -Sy --noconfirm jre8-openjdk-headless
    fi
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE
    log_info "Installing Java $java_ver via zypper..."
    if [ "$java_ver" = "17" ]; then
      run sudo zypper --non-interactive install java-17-openjdk-headless
    else
      run sudo zypper --non-interactive install java-1_8_0-openjdk-headless
    fi
  else
    log_err "Could not detect package manager. Please install Java $java_ver manually."
    exit 1
  fi

  # Verifiziere dass Java nach der Installation verfügbar ist
  if ! command -v java >/dev/null 2>&1; then
    log_err "Java installation failed. Please install Java $java_ver manually."
    exit 1
  fi

  # Prüfe installierte Java-Version
  local java_output installed_ver
  java_output=$(java -version 2>&1)
  log_info "Post-install Java version output: $java_output"
  
  # Erweiterte Versions-Erkennung (wie oben)
  if echo "$java_output" | grep -q "version \"1.8"; then
    installed_ver=8
  elif echo "$java_output" | grep -q "version \"1.1"; then
    installed_ver=11
  else
    installed_ver=$(echo "$java_output" | grep -i version | head -n1 | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
  fi
  
  if [ "$installed_ver" != "$java_ver" ]; then
    log_err "Java version mismatch after installation."
    log_err "Expected Java $java_ver but found Java $installed_ver"
    log_err "Current alternatives setting:"
    update-alternatives --display java >&2
    log_err "Available Java installations:"
    ls -l /usr/lib/jvm/java-* >&2
    exit 1
  fi

  log_info "Successfully installed Java $java_ver"
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
# Server jar detection
######################################

# Robust server jar detection. Preference order:
# 1) forge/fabric/quilt specific server jars
# 2) named modded jars (run.jar etc)
# 3) other server jars excluding vanilla
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

if [ ! -f "$ZIP" ]; then
  log_err "Zip not found: $ZIP"
  exit 1
fi

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

  # Ensure a neutral start.sh exists (overwrite/create). It will prefer existing startserver.sh or start.sh if executable,
  # otherwise it will start the detected server jar.
  SRVJAR="$(detect_server_jar)"
  # Store the detected jar name in a file so start.sh can find it later
  write_file .server_jar "$SRVJAR"
  if [ "$DRY_RUN" = 1 ]; then
    log_info "[DRY-RUN] would write start.sh (server-pack branch)"
  else
    cat > start.sh <<"EOFMARKER1"
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# If an existing startserver.sh exists and is executable, use it.
if [ -x ./startserver.sh ]; then
  exec ./startserver.sh "$@"
fi

# If there is a user-provided start.sh (this file may be overwritten intentionally), try to exec it if different.
if [ -x ./start.sh ] && [ "$(readlink -f "$0")" != "$(readlink -f ./start.sh)" ]; then
  exec ./start.sh "$@"
fi

# Function to detect server jar, copied from main script for standalone use
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

  # fallback: largest jar excluding installer jars
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

# First try to read the jar name from the stored file
if [ -r .server_jar ]; then
  JAR=$(cat .server_jar)
else
  # If file not found, detect it again
  JAR=$(detect_server_jar)
fi

# Validate jar exists
if [ ! -f "$JAR" ]; then
  echo "Server jar not found: $JAR" >&2
  echo "Trying to detect again..." >&2
  JAR=$(detect_server_jar)
  if [ ! -f "$JAR" ]; then
    echo "No valid server jar found!" >&2
    exit 1
  fi
  # Update the stored jar name
  echo "$JAR" > .server_jar
fi

# Use dynamic memory allocation (75% of system RAM) unless overridden
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
  mem_target=$((mem_mb * 75 / 100))
  [ "$mem_target" -lt 4096 ] && mem_target=4096
  [ "$mem_target" -gt 32768 ] && mem_target=32768
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Starting server with jar: $JAR"
echo "Memory settings: $JAVA_ARGS"
exec java $JAVA_ARGS -jar "$JAR" nogui
EOFMARKER1
  fi
  chmod +x start.sh

  echo ""
  echo "[7/7] Server-Pack Installation abgeschlossen!"
  echo "========================================="
  echo "Der Server ist bereit."
  echo "Starten mit: ./start.sh"
  echo "========================================="

  # --- SYSTEMD GENERATION ---
  if [ "$SYSTEMD" = 1 ]; then
    log_info "Generating systemd service file..."
    mkdir -p dist
    SERVICE_PATH="dist/minecraft.service"
    SERVICE_USER="$(id -un)"
    SERVICE_WORKDIR="$(pwd)"
    SERVICE_JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SERVICE_WORKDIR
ExecStart=$SERVICE_WORKDIR/start.sh
Restart=on-failure
Environment="JAVA_ARGS=$SERVICE_JAVA_ARGS"

[Install]
WantedBy=multi-user.target
EOF
    log_info "Service file written to $SERVICE_PATH"
    log_info "To install: sudo cp $SERVICE_PATH /etc/systemd/system/minecraft.service && sudo systemctl enable --now minecraft.service"
    # Collision detection for systemd
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl is-active --quiet minecraft; then
        log_warn "systemd service 'minecraft' is already active. Status: $(systemctl status minecraft | head -n 5)"
      elif systemctl is-enabled --quiet minecraft; then
        log_warn "systemd service 'minecraft' is enabled but not active."
      fi
    fi
  fi

  # --- TMUX GENERATION ---
  if [ "$TMUX" = 1 ]; then
    require_cmd tmux
    # Check if session exists
    if tmux has-session -t minecraft 2>/dev/null; then
      log_warn "tmux session 'minecraft' already exists. Attach with: tmux attach -t minecraft"
    else
      # Check if systemd service is active before starting tmux
      if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet minecraft; then
        log_warn "systemd service 'minecraft' is already running. Not starting tmux session to avoid conflict."
      else
        log_info "Starting server in new tmux session 'minecraft'..."
        tmux new-session -d -s minecraft "$(pwd)/start.sh"
        log_info "tmux session 'minecraft' started. Attach with: tmux attach -t minecraft"
      fi
    fi
  fi
  exit 0
fi
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
    # explicit value provided
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

  # Ask whether to run server once now to finish setup. If no tty, default to previous behavior (yes)
  if ask_yes_no "Run server once now to finish setup (recommended)?" "$AUTO_FIRST_RUN"; then
    if [ -f ./startserver.sh ]; then
      log_info "[3/7] Running startserver.sh once to finish setup..."
  run ./startserver.sh || true
    elif [ -f ./start.sh ]; then
      log_info "[3/7] Running start.sh once to finish setup..."
  run ./start.sh || true
    else
      log_warn "[3/7] No start script; starting any detected jar once..."
      JAR=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
  if [ -n "$JAR" ]; then run java -jar "$JAR" nogui || true; fi
    fi
  else
    log_warn "Skipping first run. You can start the server later with ./start.sh"
  fi

  # Optionally add OP
  op_user_if_configured || true

  # Ensure a neutral start.sh exists (overwrite/create). It will prefer existing startserver.sh or start.sh if executable,
  # otherwise it will start the detected server jar.
  SRVJAR="$(detect_server_jar)"
  # Store the detected jar name in a file so start.sh can find it later
  write_file .server_jar "$SRVJAR"
  if [ "$DRY_RUN" = 1 ]; then
    log_info "[DRY-RUN] would write start.sh (server-pack branch)"
  else
  cat > start.sh <<"EOFMARKER1"
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# If an existing startserver.sh exists and is executable, use it.
if [ -x ./startserver.sh ]; then
  exec ./startserver.sh "$@"
fi

# If there is a user-provided start.sh (this file may be overwritten intentionally), try to exec it if different.
if [ -x ./start.sh ] && [ "$(readlink -f "$0")" != "$(readlink -f ./start.sh)" ]; then
  exec ./start.sh "$@"
fi

# Function to detect server jar, copied from main script for standalone use
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

  # fallback: largest jar excluding installer jars
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

# First try to read the jar name from the stored file
if [ -r .server_jar ]; then
  JAR=$(cat .server_jar)
else
  # If file not found, detect it again
  JAR=$(detect_server_jar)
fi

# Validate jar exists
if [ ! -f "$JAR" ]; then
  echo "Server jar not found: $JAR" >&2
  echo "Trying to detect again..." >&2
  JAR=$(detect_server_jar)
  if [ ! -f "$JAR" ]; then
    echo "Could not find a valid server jar. Please check your installation." >&2
    exit 1
  fi
  # Update the stored jar name
  echo "$JAR" > .server_jar
fi

# Use dynamic memory allocation (75% of system RAM) unless overridden
get_memory_args() {
  local mem_kb mem_mb mem_target
  if [ -r /proc/meminfo ]; then
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    mem_mb=$(wmic computersystem get totalphysicalmemory | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ] && { echo "-Xms4G -Xmx8G"; return 0; }
  mem_target=$((mem_mb * 75 / 100))
  [ "$mem_target" -lt 4096 ] && mem_target=4096
  [ "$mem_target" -gt 32768 ] && mem_target=32768
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Starting server with jar: $JAR"
echo "Memory settings: $JAVA_ARGS"
exec java $JAVA_ARGS -jar "$JAR" nogui
EOFMARKER1
  fi
  chmod +x start.sh

  echo ""
  echo "[7/7] Server-Pack Installation abgeschlossen!"
  echo "========================================="
  echo "Der Server ist bereit."
  echo "Starten mit: ./start.sh"
  echo "========================================="
  exit 0
fi

################################################################################
# PATH 2: Client Export Conversion
################################################################################
if [ -z "$HAS_MANIFEST" ]; then
  echo "FEHLER: Weder Server-Dateien noch manifest.json gefunden." >&2
  echo "Bitte stellen Sie sicher, dass Sie ein gültiges Modpack-ZIP verwenden." >&2
  exit 1
fi

log_info "[2/7] Client export detected. Parsing manifest.json..."
MAN="$HAS_MANIFEST"

# Parse Manifest-Daten
MC_VER=$(jq -r '.minecraft.version' "$MAN" 2>/dev/null)
if [ -z "$MC_VER" ] || [ "$MC_VER" = "null" ]; then
  echo "FEHLER: Konnte Minecraft-Version nicht aus manifest.json lesen" >&2
  exit 1
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

################################################################################
# Funktion: download_forge
# Beschreibung: Lädt und installiert Forge Server
# Parameter:
#   $1 - mc: Minecraft-Version (z.B. "1.20.1")
#   $2 - forge: Forge-Version (z.B. "47.2.0")
################################################################################
download_forge() {
  local mc="$1" forge="$2"
  local base="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-${forge}"
  local inst="forge-${mc}-${forge}-installer.jar"
  log_info "Forge installer: $inst"
  run curl -fL "${base}/${inst}" -o "$inst"
  run java -jar "$inst" --installServer
}

download_neoforge() {
  local ver="$1"
  local base="https://maven.neoforged.net/releases/net/neoforged/forge/${ver}"
  local inst="forge-${ver}-installer.jar"
  log_info "NeoForge installer: $inst"
  run curl -fL "${base}/${inst}" -o "$inst"
  run java -jar "$inst" --installServer
}

download_fabric() {
  local mc_ver="$1"
  local INST="fabric-installer.jar"
  run curl -fL "https://meta.fabricmc.net/v2/versions/installer" -o _fabric.json
  local URL
  URL=$(jq -r '[.[] | select(.stable==true)][0].url' _fabric.json)
  run curl -fL "$URL" -o "$INST"
  run java -jar "$INST" server -mc-version "$1" -downloadMinecraft
}

case "$LOADER_ID" in
  forge-*)
    # Forge (klassisch)
    FORGE_VER="${LOADER_ID#forge-}"
    echo "Installiere Forge $FORGE_VER..."
    download_forge "$MC_VER" "$FORGE_VER"
    # Suche nach generierter Server-JAR
    SRVJAR=$(ls -1 forge-*-server*.jar 2>/dev/null | head -n1 || true)
    [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar 2>/dev/null | head -n1 || true)
    ;;
  neoforge-*)
    # NeoForge (Forge-Fork für neuere Versionen)
    NEO_VER="${LOADER_ID#neoforge-}"
    echo "Installiere NeoForge $NEO_VER..."
    download_neoforge "$NEO_VER"
    SRVJAR=$(ls -1 neoforge-*-server*.jar 2>/dev/null | head -n1 || true)
    [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar 2>/dev/null | head -n1 || true)
    ;;
  fabric*)
    # Fabric
    echo "Installiere Fabric..."
    download_fabric "$MC_VER"
    SRVJAR="fabric-server-launch.jar"
    ;;
  quilt*|quilt)
    # Quilt (Fabric-Fork mit erweiterten Features)
    echo "Quilt-Loader erkannt."
    echo "HINWEIS: Automatische Quilt-Installation nicht implementiert." >&2
    echo "Falls quilt-server-launch.jar fehlt, installieren Sie Quilt manuell." >&2
    SRVJAR="quilt-server-launch.jar"
    ;;
  *)
    log_err "Unknown loader: $LOADER_ID"
    exit 1
    ;;
esac

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
  log_err "Could not detect server jar. Check the directory.";
  exit 1
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

log_info "[7/7] Done. Use start.sh to run the server."
if [ "$DRY_RUN" = 1 ]; then
  log_info "[DRY-RUN] would write start.sh (client-export branch)"
else
cat > start.sh <<"EOFMARKER2"
#!/usr/bin/env bash
################################################################################
# Minecraft Server Start Script
# Automatisch generiert von universalServerSetup.sh
################################################################################
set -euo pipefail
cd "$(dirname "$0")"

################################################################################
# Funktion: detect_server_jar
# Beschreibung: Findet die Server-JAR-Datei (Kopie aus Haupt-Script)
################################################################################
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

  # fallback: largest jar excluding installer jars
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

################################################################################
# JAR-Datei ermitteln
################################################################################
# Versuche zuerst aus gespeicherter Datei zu lesen
if [ -r .server_jar ]; then
  JAR=$(cat .server_jar)
else
  # Falls nicht vorhanden, erneut erkennen
  JAR=$(detect_server_jar)
fi

# Validiere dass JAR existiert
if [ ! -f "$JAR" ]; then
  echo "FEHLER: Server-JAR nicht gefunden: $JAR" >&2
  echo "Versuche erneute Erkennung..." >&2
  JAR=$(detect_server_jar)
  if [ ! -f "$JAR" ]; then
    echo "FEHLER: Konnte keine gültige Server-JAR finden." >&2
    echo "Bitte überprüfen Sie die Installation." >&2
    exit 1
  fi
  # Aktualisiere gespeicherten JAR-Namen
  echo "$JAR" > .server_jar
fi

################################################################################
# Funktion: get_memory_args
# Beschreibung: Ermittelt optimale Speicher-Einstellungen
################################################################################
get_memory_args() {
  local mem_kb mem_mb mem_target
  if [ -r /proc/meminfo ]; then
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    mem_mb=$(wmic computersystem get totalphysicalmemory | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ] && { echo "-Xms4G -Xmx8G"; return 0; }
  mem_target=$((mem_mb * 75 / 100))
  [ "$mem_target" -lt 4096 ] && mem_target=4096
  [ "$mem_target" -gt 32768 ] && mem_target=32768
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

################################################################################
# Server starten
################################################################################
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "========================================="
echo "Starte Minecraft Server"
echo "========================================="
echo "Server-JAR: $JAR"
echo "Speicher:   $JAVA_ARGS"
echo "========================================="
echo ""
exec java $JAVA_ARGS -jar "$JAR" nogui
EOFMARKER2
fi
chmod +x start.sh

run rm -rf "$WORK" _fabric.json 2>/dev/null || true
log_info "Install complete. Edit server.properties, then run: ./start.sh"
