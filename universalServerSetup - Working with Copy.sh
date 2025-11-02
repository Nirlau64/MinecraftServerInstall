#!/usr/bin/env bash
set -euo pipefail

ZIP="${1:-pack.zip}"         # default name
SRVDIR="$(pwd)"
WORK="${SRVDIR}/_work"
rm -rf "$WORK"
mkdir -p "$WORK"

# Ask helper: prompt user in terminal; when no terminal is available, use provided default (yes/no)
ask_yes_no() {
  local prompt="${1:-Proceed?}"
  local default="${2:-no}"
  if [ -t 0 ]; then
    while true; do
      read -r -p "$prompt [y/N]: " ans
      case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0;;
        [Nn]|"") return 1;;
        *) echo "Bitte mit y oder n antworten.";;
      esac
    done
  else
    # No interactive terminal; fall back to default
    if [ "$default" = "yes" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# Check required commands are available
require_cmd() {
  local missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "Required command not found: $c" >&2
      missing=1
    fi
  done
  [ $missing -eq 0 ] || exit 1
}

# Detect required Java version and install if needed
setup_java() {
  local mc_ver="$1"
  local java_ver
  
  # Function to compare version strings
  ver_compare() {
    printf '%s\n' "$1" "$2" | sort -V | head -n1 | grep -q "^$1$"
  }

  # Function to get required Java version for Minecraft version
  get_required_java() {
    local mcver="$1"
    # Minecraft version to Java version mapping
    if ver_compare "1.21" "$mcver"; then
      echo "21"  # MC 1.21+ requires Java 21
    elif ver_compare "1.20.4" "$mcver"; then
      echo "21"  # MC 1.20.4+ requires Java 21
    elif ver_compare "1.17" "$mcver"; then
      echo "17"  # MC 1.17-1.20.3 requires Java 17
    elif ver_compare "1.12" "$mcver"; then
      echo "8"   # MC 1.12-1.16.5 requires Java 8
    else
      echo "8"   # Default to Java 8 for older versions
    fi
  }

  java_ver=$(get_required_java "$mc_ver")
  echo "Minecraft $mc_ver requires Java $java_ver"
  
  # Check if correct Java is already installed
  if command -v java >/dev/null 2>&1; then
    local java_output current_ver
    java_output=$(java -version 2>&1)
    echo "Java version output: $java_output"
    
    # Enhanced version detection for different formats
    if echo "$java_output" | grep -q "version \"1.8"; then
      current_ver=8
    elif echo "$java_output" | grep -q "version \"1.1"; then
      current_ver=11
    else
      current_ver=$(echo "$java_output" | grep version | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
    fi
    
    echo "Detected Java version: $current_ver"
    if [ "$current_ver" = "$java_ver" ]; then
      echo "Found compatible Java $current_ver"
      return 0
    fi
    echo "Found Java $current_ver, but Java $java_ver is required"
  fi

  # Function to install Java on different package managers
  install_java() {
    local ver="$1"
    local pm="$2"

    case "$pm" in
      apt)
        sudo apt-get update
        sudo apt-get install -y "openjdk-${ver}-jre-headless"
        if [ "$ver" = "8" ]; then
          java_path="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
        else
          java_path="/usr/lib/jvm/java-${ver}-openjdk-amd64/bin/java"
        fi
        if [ -f "$java_path" ]; then
          sudo update-alternatives --install /usr/bin/java java "$java_path" 1000
          sudo update-alternatives --set java "$java_path"
        else
          echo "Warning: Java binary not found at expected path: $java_path"
          echo "Searching for Java binary..."
          java_path=$(find /usr/lib/jvm -name java | grep -E "java-${ver}-openjdk[^/]*/bin/java" | head -n1)
          if [ -n "$java_path" ]; then
            echo "Found Java binary at: $java_path"
            sudo update-alternatives --install /usr/bin/java java "$java_path" 1000
            sudo update-alternatives --set java "$java_path"
          else
            echo "Error: Could not find Java binary"
            return 1
          fi
        fi
        ;;
      dnf)
        if [ "$ver" = "8" ]; then
          sudo dnf install -y "java-1.${ver}.0-openjdk-headless"
        else
          sudo dnf install -y "java-${ver}-openjdk-headless"
        fi
        ;;
      pacman)
        sudo pacman -Sy --noconfirm "jre${ver}-openjdk-headless"
        ;;
      zypper)
        if [ "$ver" = "8" ]; then
          sudo zypper --non-interactive install "java-1_${ver}_0-openjdk-headless"
        else
          sudo zypper --non-interactive install "java-${ver}-openjdk-headless"
        fi
        ;;
    esac
  }

  # Install required Java version
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Java $java_ver via apt..."
    install_java "$java_ver" "apt"
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora/RHEL
    echo "Installing Java $java_ver via dnf..."
    install_java "$java_ver" "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    echo "Installing Java $java_ver via pacman..."
    install_java "$java_ver" "pacman"
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE
    echo "Installing Java $java_ver via zypper..."
    install_java "$java_ver" "zypper"
  else
    echo "Could not detect package manager. Please install Java $java_ver manually." >&2
    exit 1
  fi

  # Verify installation
  if ! command -v java >/dev/null 2>&1; then
    echo "Java installation failed. Please install Java $java_ver manually." >&2
    exit 1
  fi

  local java_output installed_ver
  java_output=$(java -version 2>&1)
  echo "Post-install Java version output: $java_output"
  
  # Enhanced version detection (same as above)
  if echo "$java_output" | grep -q "version \"1.8"; then
    installed_ver=8
  elif echo "$java_output" | grep -q "version \"1.1"; then
    installed_ver=11
  else
    installed_ver=$(echo "$java_output" | grep version | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
  fi
  
  if [ "$installed_ver" != "$java_ver" ]; then
    echo "ERROR: Java version mismatch after installation." >&2
    echo "Expected Java $java_ver but found Java $installed_ver" >&2
    echo "Current alternatives setting:" >&2
    update-alternatives --display java >&2
    echo "Available Java installations:" >&2
    ls -l /usr/lib/jvm/java-* >&2
    exit 1
  fi

  echo "Successfully installed Java $java_ver"
}

# Detect system memory and return appropriate JVM args (75% of system RAM)
get_memory_args() {
  local mem_kb mem_mb mem_target
  # Try various methods to get system memory
  if [ -r /proc/meminfo ]; then
    # Linux
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    # macOS and BSD
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    # Windows
    mem_mb=$(wmic computersystem get totalphysicalmemory | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    # Fallback to default if we can't detect
    echo "-Xms4G -Xmx8G"
    return 0
  fi

  # If detection failed or returned 0, use conservative defaults
  if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ]; then
    echo "-Xms4G -Xmx8G"
    return 0
  fi

  # Calculate target (75% of total memory)
  mem_target=$((mem_mb * 75 / 100))
  
  # Ensure minimum of 4GB and maximum of 32GB
  if [ "$mem_target" -lt 4096 ]; then
    mem_target=4096
  elif [ "$mem_target" -gt 32768 ]; then
    mem_target=32768
  fi

  # Return formatted args
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

# Robust server jar detection. Preference order:
# 1) forge/fabric/quilt specific server jars
# 2) named modded jars (run.jar etc)
# 3) other server jars excluding vanilla
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

  # fallback: largest jar excluding installer jars
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

if [ ! -f "$ZIP" ]; then
  echo "Zip not found: $ZIP"
  exit 1
fi

echo "[1/7] Unzipping pack..."
require_cmd unzip curl jq rsync
unzip -q "$ZIP" -d "$WORK"

# Detect server-pack vs client-pack
HAS_START=$(grep -rilE 'startserver\.sh|start\.sh' "$WORK" || true)
HAS_MANIFEST=$(find "$WORK" -maxdepth 3 -name manifest.json | head -n1 || true)

if [ -n "$HAS_START" ]; then
  echo "[2/7] Server files detected."
  # Try to detect MC version from server jar name or manifest
  MC_VER=$(ls minecraft_server.*.jar 2>/dev/null | grep -o '[0-9.]*' | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(find . -name manifest.json -exec jq -r '.minecraft.version // empty' {} \; 2>/dev/null | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(ls forge-*.jar 2>/dev/null | grep -o '1\.[0-9.]*' | head -n1 || true)
  
  if [ -n "$MC_VER" ]; then
    setup_java "$MC_VER"
  else
    echo "Warning: Could not detect Minecraft version. You may need to install the correct Java version manually."
  fi
  # Move all server content up
  # Copy server content into current directory and remove workdir after success
  rsync -a "$WORK"/ ./ 2>/dev/null || true
  rm -rf "$WORK"

  # Make scripts executable
  find . -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;

  # Ask to accept EULA (interactive); if no tty, default to previous behavior (yes)
  if ask_yes_no "Accept EULA and write eula.txt? See https://account.mojang.com/documents/minecraft_eula" "yes"; then
    echo "eula=true" > eula.txt
  else
    echo "eula=false" > eula.txt
    echo "EULA not accepted. Aborting." >&2
    exit 1
  fi

  # Ask whether to run server once now to finish setup. If no tty, default to previous behavior (yes)
  if ask_yes_no "Run server once now to finish setup (recommended)?" "yes"; then
    if [ -f ./startserver.sh ]; then
      echo "[3/7] Running startserver.sh once to finish setup..."
      ./startserver.sh || true
    elif [ -f ./start.sh ]; then
      echo "[3/7] Running start.sh once to finish setup..."
      ./start.sh || true
    else
      echo "[3/7] No start script; starting any detected jar once..."
      JAR=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
      if [ -n "$JAR" ]; then java -jar "$JAR" nogui || true; fi
    fi
  else
    echo "Skipping first run. You can start the server later with ./start.sh" >&2
  fi

  # Ensure a neutral start.sh exists (overwrite/create). It will prefer existing startserver.sh or start.sh if executable,
  # otherwise it will start the detected server jar.
  SRVJAR="$(detect_server_jar)"
  # Store the detected jar name in a file so start.sh can find it later
  echo "$SRVJAR" > .server_jar
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
  chmod +x start.sh

  echo "[4/7] Server files path complete."
  exit 0
fi

if [ -z "$HAS_MANIFEST" ]; then
  echo "Neither server files nor manifest.json found. Aborting."
  exit 1
fi

echo "[2/7] Client export detected. Parsing manifest.json..."
MAN="$HAS_MANIFEST"
MC_VER=$(jq -r '.minecraft.version' "$MAN")

# Setup correct Java version for this MC version
setup_java "$MC_VER"

# manifest loader id parsing with fallbacks
LOADER_ID=$(jq -r '.minecraft.modLoaders[0].id // .modLoaders[0].id // .modLoaders[0].uid // .modLoader // ""' "$MAN" | tr '[:upper:]' '[:lower:]')
# LOADER_ID examples: "forge-47.2.0", "neoforge-20.6.120", "fabric"

echo "Minecraft: $MC_VER"
echo "Loader:    $LOADER_ID"

cd "$SRVDIR"
echo "[3/7] Installing server loader..."

download_forge() {
  local mc="$1" forge="$2"
  local base="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-${forge}"
  local inst="forge-${mc}-${forge}-installer.jar"
  echo "Forge installer: $inst"
  curl -fL "${base}/${inst}" -o "$inst"
  java -jar "$inst" --installServer
}

download_neoforge() {
  # NeoForge coordinates are just the single version string e.g. 20.6.120
  local ver="$1"
  local base="https://maven.neoforged.net/releases/net/neoforged/forge/${ver}"
  local inst="forge-${ver}-installer.jar"
  echo "NeoForge installer: $inst"
  curl -fL "${base}/${inst}" -o "$inst"
  java -jar "$inst" --installServer
}

download_fabric() {
  local mc_ver="$1"
  # Get latest stable installer
  local INST="fabric-installer.jar"
  curl -fL "https://meta.fabricmc.net/v2/versions/installer" -o _fabric.json
  local URL
  URL=$(jq -r '[.[] | select(.stable==true)][0].url' _fabric.json)
  curl -fL "$URL" -o "$INST"
  
  # Check if the version ends with .0 and remove it for compatibility
  if [[ "$mc_ver" =~ ^([0-9]+\.[0-9]+)\.0$ ]]; then
    mc_ver="${BASH_REMATCH[1]}"
  fi
  
  # Force specific minor version for compatibility with mods
  if [[ "$mc_ver" =~ ^1\.21(\.[0-9]+)?$ ]]; then
    mc_ver="1.21.1"
    echo "Forcing Minecraft version to $mc_ver for mod compatibility"
  fi

  # Get compatible Fabric Loader version
  curl -fL "https://meta.fabricmc.net/v2/versions/loader/$mc_ver" -o _fabric_versions.json
  local LOADER_VERSION
  LOADER_VERSION=$(jq -r '.[0].loader.version' _fabric_versions.json)
  
  echo "Installing Fabric $LOADER_VERSION for Minecraft $mc_ver"
  # Use specific command format to ensure version is respected
  java -jar "$INST" server -mcversion "$mc_ver" -loader "$LOADER_VERSION" -downloadMinecraft
  
  # Clean up temporary files
  rm -f _fabric.json _fabric_versions.json
}

case "$LOADER_ID" in
  forge-*)
    FORGE_VER="${LOADER_ID#forge-}"
    download_forge "$MC_VER" "$FORGE_VER"
    SRVJAR=$(ls -1 forge-*-server*.jar | head -n1 || true)
    [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar | head -n1 || true)
    ;;
  neoforge-*)
    NEO_VER="${LOADER_ID#neoforge-}"
    download_neoforge "$NEO_VER"
    SRVJAR=$(ls -1 neoforge-*-server*.jar | head -n1 || true)
    [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar | head -n1 || true)
    ;;
  fabric*)
    download_fabric "$MC_VER"
    SRVJAR="fabric-server-launch.jar"
    ;;
  quilt*|quilt)
    # Basic Quilt support: many packs ship quilt-server-launch.jar; automatic installer download not implemented.
    echo "Quilt loader detected. If installer is missing, you may need to install Quilt server manually." >&2
    SRVJAR="quilt-server-launch.jar"
    ;;
  *)
    echo "Unknown loader: $LOADER_ID"
    exit 1
    ;;
esac

echo "[4/7] Copying mods and configs from client export..."
# Debug: Show contents of work directory
echo "Work directory contents:"
ls -la "$WORK"
if [ -d "$WORK/overrides" ]; then
  echo "Overrides directory contents:"
  ls -la "$WORK/overrides"
fi

# CurseForge client export puts overrides into /overrides or /overrides/<mods|config|kubejs|defaultconfigs>
# Some packs use /mods directly in the zip.
mkdir -p mods config

# Function to copy with verbose output
copy_with_log() {
  local src="$1"
  local dst="$2"
  local type="$3"
  if [ -d "$src" ]; then
    echo "Copying $type from $src"
    if rsync -av "$src/" "$dst/"; then
      echo "Successfully copied $type"
      ls -la "$dst"
    else
      echo "Warning: Failed to copy $type from $src"
    fi
  else
    echo "Info: $type directory $src not found"
  fi
}

# Priority: overrides first, then top-level detected folders
copy_with_log "$WORK/overrides/mods" "./mods" "mods (overrides)"
copy_with_log "$WORK/overrides/config" "./config" "config (overrides)"
copy_with_log "$WORK/mods" "./mods" "mods (top-level)"
copy_with_log "$WORK/config" "./config" "config (top-level)"

# Also copy server-overrides and client-overrides if present
copy_with_log "$WORK/server-overrides/mods" "./mods" "mods (server-overrides)"
copy_with_log "$WORK/server-overrides/config" "./config" "config (server-overrides)"

# Also bring scripts or other common dirs if present
for d in kubejs defaultconfigs scripts libraries; do
  if [ -d "$WORK/overrides/$d" ]; then
    mkdir -p "./$d"
    copy_with_log "$WORK/overrides/$d" "./$d" "$d (overrides)"
  fi
  if [ -d "$WORK/$d" ]; then
    mkdir -p "./$d"
    copy_with_log "$WORK/$d" "./$d" "$d (top-level)"
  fi
done

# Verify mods were copied
echo "Final mods directory contents:"
ls -la ./mods/
if [ ! "$(ls -A ./mods/)" ]; then
  echo "WARNING: No mods were copied to the mods directory!"
  echo "Please check the modpack structure:"
  find "$WORK" -name "*.jar" -type f
fi

echo "[5/7] EULA"
# Interactive EULA acceptance: when run in a terminal ask the user; otherwise keep previous behavior (auto-accept)
if ask_yes_no "Accept EULA and write eula.txt? See https://account.mojang.com/documents/minecraft_eula" "yes"; then
  echo "eula=true" > eula.txt
else
  echo "eula=false" > eula.txt
  echo "EULA not accepted. Aborting." >&2
  exit 1
fi

echo "[6/7] First run to generate files..."
# Choose a probable server jar
# detect server jar robustly
SRVJAR="$(detect_server_jar)"
if [ -z "$SRVJAR" ]; then
  echo "Could not detect server jar. Check the directory.";
  exit 1
fi

# Set memory based on system RAM (75%) or use provided JAVA_ARGS
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Using jar: $SRVJAR"
echo "Memory settings: $JAVA_ARGS"
# Ask whether to do the first run (interactive). Default to previous behavior in non-interactive contexts.
if ask_yes_no "Run the server once now to generate files and finish setup (recommended)?" "yes"; then
  java $JAVA_ARGS -jar "$SRVJAR" nogui || true
else
  echo "Skipping first run. You can start the server later with ./start.sh" >&2
fi

echo "[7/7] Done. Use start.sh to run the server."
cat > start.sh <<"EOFMARKER2"
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

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

# Get memory args (copied from main script)
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
EOFMARKER2
chmod +x start.sh

rm -rf "$WORK" _fabric.json 2>/dev/null || true
echo "Install complete. Edit server.properties, then run: ./start.sh"
