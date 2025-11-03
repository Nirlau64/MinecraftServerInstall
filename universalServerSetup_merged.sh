#!/usr/bin/env bash
set -euo pipefail

# universalServerSetup_merged.sh
# ---------------------------------------------------------------------------
# Small utility to convert a CurseForge client-export (or a server pack ZIP)
# into a runnable server directory. It combines two workflows:
#  - auto-download available mods from Modrinth using packwiz (if a modlist.html
#    is present in the export)
#  - install the correct server loader (Forge/NeoForge/Fabric), copy overrides
#    (mods/config/kubejs/etc.), create a portable start.sh and perform an
#    optional first-run to generate server files.
#
# Key features:
#  - Detects whether the ZIP is a server pack or a client export and runs the
#    appropriate path.
#  - If a modlist.html is present, extracts mod slugs and tries to install them
#    from Modrinth via packwiz. Missing mods are reported for manual import.
#  - Attempts to detect required Java version for the Minecraft version and
#    (optionally) install it with common package managers.
#  - Creates a convenient start.sh that detects the server jar and assigns
#    memory dynamically (75% of system RAM, capped between 4G and 32G).
#
# Requirements (recommended):
#  - bash, unzip, curl, jq, rsync, packwiz, java
#  - On Windows run inside WSL or Git Bash with the above available
#
# Usage:
#   ./universalServerSetup_merged.sh <pack.zip>
#   ./universalServerSetup_merged.sh --help
#
# Exit codes:
#  0  success
#  1  usage error or missing required command
#

ZIP="${1:-pack.zip}"
SRVDIR="$(pwd)"
WORK="${SRVDIR}/_work"

echo "Running merged universal server setup with Modrinth support"

# Helper: print in red (for warnings/errors)
echo_red() {
  local red="\033[0;31m"
  local reset="\033[0m"
  echo -e "${red}$*${reset}"
}

# Print a brief help message and exit
print_help() {
  cat <<'EOF'
Usage: universalServerSetup_merged.sh [PACK.ZIP]

This script converts a CurseForge client export (ZIP) or a server pack into a
runnable server directory. It will attempt to:
  - extract files from the ZIP
  - detect loader (Forge/Fabric/NeoForge) and install the server
  - copy mods and config overrides
  - if a modlist.html exists, query Modrinth and run `packwiz modrinth install`
  - create a portable start.sh and optionally perform a first run

Options:
  -h, --help      Show this help and exit

Notes:
  - The script requires unix-like tooling. On Windows, run it inside WSL/Git
    Bash where unzip, curl, jq, rsync, packwiz and java are available.
  - packwiz must be configured and on PATH for Modrinth installs to work.
EOF
}

# Show help early if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

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
    if [ "$default" = "yes" ]; then
      return 0
    else
      return 1
    fi
  fi
}

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

# Java setup and detection (adapted)
ver_compare() { printf '%s\n' "$1" "$2" | sort -V | head -n1 | grep -q "^$1$"; }
get_required_java() {
  local mcver="$1"
  if ver_compare "1.21" "$mcver"; then
    echo "21"
  elif ver_compare "1.20.4" "$mcver"; then
    echo "21"
  elif ver_compare "1.17" "$mcver"; then
    echo "17"
  elif ver_compare "1.12" "$mcver"; then
    echo "8"
  else
    echo "8"
  fi
}

setup_java() {
  local mc_ver="$1"
  local java_ver
  java_ver=$(get_required_java "$mc_ver")
  echo "Minecraft $mc_ver requires Java $java_ver"
  if command -v java >/dev/null 2>&1; then
    local java_output current_ver
    java_output=$(java -version 2>&1 || true)
    if echo "$java_output" | grep -q "version \"1.8"; then
      current_ver=8
    elif echo "$java_output" | grep -q "version \"1.1"; then
      current_ver=11
    else
      current_ver=$(echo "$java_output" | grep version | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}' || true)
    fi
    echo "Detected Java version: $current_ver"
    if [ "$current_ver" = "$java_ver" ]; then
      echo "Found compatible Java $current_ver"
      return 0
    fi
    echo "Found Java $current_ver, but Java $java_ver is required"
  fi

  # Try to auto-install using common package managers
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Java $java_ver via apt..."
    sudo apt-get update
    sudo apt-get install -y "openjdk-${java_ver}-jre-headless"
  elif command -v dnf >/dev/null 2>&1; then
    echo "Installing Java $java_ver via dnf..."
    if [ "$java_ver" = "8" ]; then
      sudo dnf install -y "java-1.${java_ver}.0-openjdk-headless"
    else
      sudo dnf install -y "java-${java_ver}-openjdk-headless"
    fi
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "jre${java_ver}-openjdk-headless"
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive install "java-${java_ver}-openjdk-headless"
  else
    echo "Could not detect package manager. Please install Java $java_ver manually." >&2
    return 1
  fi
  return 0
}

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
  if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ]; then
    echo "-Xms4G -Xmx8G"
    return 0
  fi
  mem_target=$((mem_mb * 75 / 100))
  if [ "$mem_target" -lt 4096 ]; then mem_target=4096; fi
  if [ "$mem_target" -gt 32768 ]; then mem_target=32768; fi
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

detect_server_jar() {
  local j
  j=$(ls -1 forge-*-server*.jar forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 neoforge-*-server*.jar neoforged-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 fabric-server-launch.jar fabric-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 quilt-server-launch.jar quilt-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 *forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 run*.jar 2>/dev/null | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi
  j=$(ls -1 *-server*.jar 2>/dev/null | grep -v "minecraft_server" | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

# Modrinth/packwiz integration (best-effort)
try_modrinth_install() {
  local search_dir="$1"
  # look for modlist.html in workdir or zip
  local modlist=""
  if [ -f "$search_dir/modlist.html" ]; then
    modlist="$search_dir/modlist.html"
  fi
  if [ -z "$modlist" ] && [ -f "$ZIP" ] && [[ "$ZIP" == *.zip ]]; then
    if unzip -l "$ZIP" | grep -q "modlist.html"; then
      mkdir -p "$WORK/modlist_extract"
      unzip -qq -j "$ZIP" "modlist.html" -d "$WORK/modlist_extract" || true
      if [ -f "$WORK/modlist_extract/modlist.html" ]; then
        modlist="$WORK/modlist_extract/modlist.html"
      fi
    fi
  fi

  if [ -z "$modlist" ]; then
    echo "No modlist.html found; skipping Modrinth auto-download."
    return 0
  fi

  echo "Found modlist: $modlist — attempting Modrinth lookup and packwiz install"
  require_cmd curl unzip packwiz awk grep sort

  mapfile -t SLUGS < <(grep -oE 'mc-mods/[^\"]+' "$modlist" | awk -F'/' '{print $2}' | sort -u)
  if [ ${#SLUGS[@]} -eq 0 ]; then
    echo "Keine Mods/Slugs in modlist.html gefunden."
    return 0
  fi

  echo "Gefundene Mods (${#SLUGS[@]}): ${SLUGS[*]}"
  MISSING=()
  AVAILABLE=()
  for slug in "${SLUGS[@]}"; do
    if curl -fsSL "https://api.modrinth.com/v2/project/${slug}" >/dev/null 2>&1; then
      AVAILABLE+=("$slug")
    else
      MISSING+=("$slug")
    fi
  done

  if [ ${#MISSING[@]} -gt 0 ]; then
    echo_red "Achtung: Einige Mods konnten nicht auf Modrinth gefunden werden: ${MISSING[*]}"
    echo_red "Diese Mods müssen Sie manuell importieren (z. B. von CurseForge)."
  fi

  # Ensure packwiz initialized
  if [ ! -f "pack.toml" ]; then
    echo "pack.toml nicht gefunden – initialisiere temporäres packwiz Modpack"
    packwiz init --modloader forge --version "1.16.5" || true
  fi

  for slug in "${AVAILABLE[@]}"; do
    echo "packwiz modrinth install $slug"
    packwiz modrinth install "$slug" || true
  done

  echo "Aktualisiere packwiz index und kopiere JARs in mods/"
  packwiz refresh || true

  # copy any downloads from packwiz cache into mods/ (packwiz places files under .pw-pack or similar)
  # Best-effort: if mods/ is empty, try to find .pw/mods or .pw-mods
  mkdir -p mods
  if [ -d ".pw" ]; then
    if [ -d ".pw/mods" ]; then
      cp -n .pw/mods/*.jar mods/ 2>/dev/null || true
    fi
  fi
  if [ -d ".pw-mods" ]; then
    cp -n .pw-mods/*.jar mods/ 2>/dev/null || true
  fi

  echo "Modrinth step finished."
}

# Loader installers
download_forge() {
  local mc="$1" forge="$2"
  local base="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-${forge}"
  local inst="forge-${mc}-${forge}-installer.jar"
  echo "Forge installer: $inst"
  curl -fL "${base}/${inst}" -o "$inst"
  java -jar "$inst" --installServer
}

download_neoforge() {
  local ver="$1"
  local base="https://maven.neoforged.net/releases/net/neoforged/forge/${ver}"
  local inst="forge-${ver}-installer.jar"
  echo "NeoForge installer: $inst"
  curl -fL "${base}/${inst}" -o "$inst"
  java -jar "$inst" --installServer
}

download_fabric() {
  local mc_ver="$1"
  local INST="fabric-installer.jar"
  curl -fL "https://meta.fabricmc.net/v2/versions/installer" -o _fabric.json
  local URL
  URL=$(jq -r '[.[] | select(.stable==true)][0].url' _fabric.json)
  curl -fL "$URL" -o "$INST"
  if [[ "$mc_ver" =~ ^([0-9]+\.[0-9]+)\.0$ ]]; then mc_ver="${BASH_REMATCH[1]}"; fi
  if [[ "$mc_ver" =~ ^1\.21(\.[0-9]+)?$ ]]; then mc_ver="1.21.1"; fi
  curl -fL "https://meta.fabricmc.net/v2/versions/loader/$mc_ver" -o _fabric_versions.json
  local LOADER_VERSION
  LOADER_VERSION=$(jq -r '.[0].loader.version' _fabric_versions.json)
  echo "Installing Fabric $LOADER_VERSION for Minecraft $mc_ver"
  java -jar "$INST" server -mcversion "$mc_ver" -loader "$LOADER_VERSION" -downloadMinecraft
  rm -f _fabric.json _fabric_versions.json
}

######## Main script flow
if [ ! -f "$ZIP" ]; then
  echo "Zip not found: $ZIP"
  exit 1
fi

echo "[1/8] Unzipping pack into $WORK..."
rm -rf "$WORK"
mkdir -p "$WORK"
require_cmd unzip curl jq rsync awk grep sort packwiz || true
unzip -q "$ZIP" -d "$WORK"

# Detect server-pack vs client-pack
HAS_START=$(grep -rilE 'startserver\.sh|start\.sh' "$WORK" || true)
HAS_MANIFEST=$(find "$WORK" -maxdepth 3 -name manifest.json | head -n1 || true)

if [ -n "$HAS_START" ]; then
  echo "[2/8] Server files detected in archive. Moving files to current directory."
  rsync -a "$WORK"/ ./ 2>/dev/null || true
  rm -rf "$WORK"
  find . -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;

  if ask_yes_no "Accept EULA and write eula.txt?" "yes"; then
    echo "eula=true" > eula.txt
  else
    echo "eula=false" > eula.txt
    echo "EULA not accepted. Aborting." >&2
    exit 1
  fi

  # Optionally try Modrinth step if modlist.html present in current dir
  try_modrinth_install "."

  if ask_yes_no "Run server once now to finish setup (recommended)?" "yes"; then
    if [ -f ./startserver.sh ]; then
      echo "[3/8] Running startserver.sh once to finish setup..."
      ./startserver.sh || true
    elif [ -f ./start.sh ]; then
      echo "[3/8] Running start.sh once to finish setup..."
      ./start.sh || true
    else
      echo "[3/8] No start script; starting any detected jar once..."
      JAR=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
      if [ -n "$JAR" ]; then java -jar "$JAR" nogui || true; fi
    fi
  else
    echo "Skipping first run. You can start the server later with ./start.sh" >&2
  fi

  SRVJAR="$(detect_server_jar)"
  echo "$SRVJAR" > .server_jar
  cat > start.sh <<'EOF_START'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -x ./startserver.sh ]; then exec ./startserver.sh "$@"; fi
if [ -r .server_jar ]; then JAR=$(cat .server_jar); else JAR=$(detect_server_jar); fi
if [ ! -f "$JAR" ]; then echo "Server jar not found: $JAR" >&2; exit 1; fi
get_memory_args() { if [ -r /proc/meminfo ]; then mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}'); mem_mb=$((mem_kb / 1024)); else echo "-Xms4G -Xmx8G"; return 0; fi; [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ] && { echo "-Xms4G -Xmx8G"; return 0; }; mem_target=$((mem_mb * 75 / 100)); [ "$mem_target" -lt 4096 ] && mem_target=4096; [ "$mem_target" -gt 32768 ] && mem_target=32768; echo "-Xms${mem_target}M -Xmx${mem_target}M"; }
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Starting server with jar: $JAR"
echo "Memory settings: $JAVA_ARGS"
exec java $JAVA_ARGS -jar "$JAR" nogui
EOF_START
  chmod +x start.sh

  echo "[4/8] Server files path complete."
  exit 0
fi

if [ -z "$HAS_MANIFEST" ]; then
  echo "Neither server files nor manifest.json found in archive. Aborting."
  exit 1
fi

echo "[2/8] Client export detected. Parsing manifest.json..."
MAN="$HAS_MANIFEST"
MC_VER=$(jq -r '.minecraft.version' "$MAN")
setup_java "$MC_VER" || true

LOADER_ID=$(jq -r '.minecraft.modLoaders[0].id // .modLoaders[0].id // .modLoaders[0].uid // .modLoader // ""' "$MAN" | tr '[:upper:]' '[:lower:]')
echo "Minecraft: $MC_VER"
echo "Loader:    $LOADER_ID"

cd "$SRVDIR"
echo "[3/8] Installing server loader..."

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
    SRVJAR=$(ls -1 neoforge-*-server*.jar 2>/dev/null | head -n1 || true)
    [ -z "$SRVJAR" ] && SRVJAR=$(ls -1 run-*.jar 2>/dev/null | head -n1 || true)
    ;;
  fabric*)
    download_fabric "$MC_VER"
    SRVJAR="fabric-server-launch.jar"
    ;;
  quilt*|quilt)
    echo "Quilt loader detected. If installer is missing, you may need to install Quilt server manually." >&2
    SRVJAR="quilt-server-launch.jar"
    ;;
  *)
    echo "Unknown loader: $LOADER_ID" >&2
    exit 1
    ;;
esac

echo "[4/8] Copying mods and configs from client export..."
mkdir -p mods config

copy_with_log() {
  local src="$1" dst="$2" type="$3"
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

copy_with_log "$WORK/overrides/mods" "./mods" "mods (overrides)"
copy_with_log "$WORK/overrides/config" "./config" "config (overrides)"
copy_with_log "$WORK/mods" "./mods" "mods (top-level)"
copy_with_log "$WORK/config" "./config" "config (top-level)"
copy_with_log "$WORK/server-overrides/mods" "./mods" "mods (server-overrides)"
copy_with_log "$WORK/server-overrides/config" "./config" "config (server-overrides)"

for d in kubejs defaultconfigs scripts libraries; do
  copy_with_log "$WORK/overrides/$d" "./$d" "$d (overrides)"
  copy_with_log "$WORK/$d" "./$d" "$d (top-level)"
done

echo "Final mods directory contents:"
ls -la ./mods/ || true
if [ ! "$(ls -A ./mods/ 2>/dev/null)" ]; then
  echo "WARNING: No mods were copied to the mods directory!"
  find "$WORK" -name "*.jar" -type f || true
fi

echo "[5/8] Attempt Modrinth auto-download (if modlist.html present)..."
try_modrinth_install "$WORK"

echo "[6/8] EULA"
if ask_yes_no "Accept EULA and write eula.txt?" "yes"; then
  echo "eula=true" > eula.txt
else
  echo "eula=false" > eula.txt
  echo "EULA not accepted. Aborting." >&2
  exit 1
fi

echo "[7/8] First run to generate files..."
SRVJAR="$(detect_server_jar)"
if [ -z "$SRVJAR" ]; then
  echo "Could not detect server jar. Check the directory."; exit 1
fi
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Using jar: $SRVJAR"
echo "Memory settings: $JAVA_ARGS"
if ask_yes_no "Run the server once now to generate files and finish setup (recommended)?" "yes"; then
  java $JAVA_ARGS -jar "$SRVJAR" nogui || true
else
  echo "Skipping first run. You can start the server later with ./start.sh" >&2
fi

echo "[8/8] Creating portable start.sh..."
cat > start.sh <<'EOF_START2'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
detect_server_jar() {
  local j
  j=$(ls -1 forge-*-server*.jar forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 neoforge-*-server*.jar neoforged-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 fabric-server-launch.jar fabric-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 quilt-server-launch.jar quilt-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 *forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 run*.jar 2>/dev/null | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi
  j=$(ls -1 *-server*.jar 2>/dev/null | grep -v "minecraft_server" | head -n1 || true)
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}
if [ -r .server_jar ]; then JAR=$(cat .server_jar); else JAR=$(detect_server_jar); fi
if [ ! -f "$JAR" ]; then echo "Server jar not found: $JAR" >&2; exit 1; fi
get_memory_args() { if [ -r /proc/meminfo ]; then mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}'); mem_mb=$((mem_kb / 1024)); else echo "-Xms4G -Xmx8G"; return 0; fi; [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ] && { echo "-Xms4G -Xmx8G"; return 0; }; mem_target=$((mem_mb * 75 / 100)); [ "$mem_target" -lt 4096 ] && mem_target=4096; [ "$mem_target" -gt 32768 ] && mem_target=32768; echo "-Xms${mem_target}M -Xmx${mem_target}M"; }
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Starting server with jar: $JAR"
echo "Memory settings: $JAVA_ARGS"
exec java $JAVA_ARGS -jar "$JAR" nogui
EOF_START2
chmod +x start.sh

rm -rf "$WORK" _fabric.json 2>/dev/null || true
echo "Install complete. Edit server.properties, then run: ./start.sh"
