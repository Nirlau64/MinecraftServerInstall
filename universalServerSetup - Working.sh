#!/usr/bin/env bash
################################################################################
# Universal Minecraft Server Setup Script
################################################################################
#
# BESCHREIBUNG:
#   Automatisiert die Installation und Konfiguration von Minecraft-Servern
#   aus CurseForge/Modrinth Modpack-Exporten oder Server-Packs.
#
# VERWENDUNG:
#   ./universalServerSetup.sh [PACK.zip]
#
# ARGUMENTE:
#   PACK.zip  - Optional: Pfad zur Modpack-ZIP-Datei (Standard: pack.zip)
#
# FUNKTIONALITÄT:
#   - Erkennt automatisch Server-Packs vs. Client-Exporte
#   - Installiert die benötigte Java-Version (8 oder 17) automatisch
#   - Unterstützt Forge, NeoForge, Fabric und Quilt
#   - Konfiguriert Speicher automatisch (75% des verfügbaren RAM)
#   - Erstellt start.sh für einfachen Server-Start
#   - Interaktive EULA-Akzeptierung
#
# VORAUSSETZUNGEN:
#   - unzip, curl, jq, rsync müssen installiert sein
#   - sudo-Rechte für Java-Installation
#   - Internet-Verbindung für Downloads
#
# BEISPIELE:
#   ./universalServerSetup.sh                    # Verwendet pack.zip
#   ./universalServerSetup.sh mymodpack.zip      # Verwendet mymodpack.zip
#
# AUTOR: [Ihr Name]
# VERSION: 2.0
# DATUM: 2025-11-03
################################################################################

# Strikte Fehlerbehandlung aktivieren
# -e: Beendet Script bei Fehler
# -u: Beendet Script bei Verwendung undefinierter Variablen
# -o pipefail: Pipeline scheitert wenn ein Befehl fehlschlägt
set -euo pipefail

# Globale Variablen
ZIP="${1:-pack.zip}"         # ZIP-Datei (Standard: pack.zip)
SRVDIR="$(pwd)"              # Aktuelles Verzeichnis als Server-Verzeichnis
WORK="${SRVDIR}/_work"       # Temporäres Arbeitsverzeichnis

# Arbeitsverzeichnis bereinigen und neu erstellen
rm -rf "$WORK"
mkdir -p "$WORK"

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
  
  # Prüfe ob ein interaktives Terminal verfügbar ist
  if [ -t 0 ]; then
    # Interaktiver Modus: Frage den Benutzer
    while true; do
      read -r -p "$prompt [y/N]: " ans
      case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0;;  # Ja
        [Nn]|"") return 1;;             # Nein oder leer
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

  echo "Minecraft $mc_ver benötigt Java $java_ver"
  
  # Prüfe ob bereits eine kompatible Java-Version installiert ist
  if command -v java >/dev/null 2>&1; then
    local java_output current_ver
    java_output=$(java -version 2>&1)
    echo "Java-Version-Ausgabe: $java_output"
    
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
    
    echo "Erkannte Java-Version: $current_ver"
    
    # Prüfe ob die installierte Version ausreichend ist (höhere Version ist OK)
    if [ "$current_ver" -ge "$java_ver" ] 2>/dev/null; then
      echo "Kompatible Java-Version $current_ver gefunden (benötigt: $java_ver)"
      return 0
    fi
    echo "Java $current_ver gefunden, aber Java $java_ver wird benötigt"
  fi

  # Installiere benötigte Java-Version basierend auf dem Package Manager
  echo "Installiere Java $java_ver..."
  
  if command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu basierte Distributionen
    echo "Verwende apt-get für Java $java_ver Installation..."
    if [ "$java_ver" = "21" ]; then
      sudo apt-get update || { echo "FEHLER: apt-get update fehlgeschlagen" >&2; exit 1; }
      sudo apt-get install -y openjdk-21-jre-headless || { echo "FEHLER: Java 21 Installation fehlgeschlagen" >&2; exit 1; }
      # Setze Java 21 als Standard
      sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-*/bin/java 2>/dev/null || true
    elif [ "$java_ver" = "17" ]; then
      sudo apt-get update || { echo "FEHLER: apt-get update fehlgeschlagen" >&2; exit 1; }
      sudo apt-get install -y openjdk-17-jre-headless || { echo "FEHLER: Java 17 Installation fehlgeschlagen" >&2; exit 1; }
      # Setze Java 17 als Standard (Wildcard für Architektur-spezifische Pfade)
      sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-*/bin/java 2>/dev/null || true
    else
      sudo apt-get update || { echo "FEHLER: apt-get update fehlgeschlagen" >&2; exit 1; }
      sudo apt-get install -y openjdk-8-jre-headless || { echo "FEHLER: Java 8 Installation fehlgeschlagen" >&2; exit 1; }
      # Setze Java 8 als Standard
      sudo update-alternatives --set java /usr/lib/jvm/java-8-openjdk-*/jre/bin/java 2>/dev/null || true
    fi
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora/RHEL basierte Distributionen
    echo "Verwende dnf für Java $java_ver Installation..."
    if [ "$java_ver" = "21" ]; then
      sudo dnf install -y java-21-openjdk-headless || { echo "FEHLER: Java 21 Installation fehlgeschlagen" >&2; exit 1; }
    elif [ "$java_ver" = "17" ]; then
      sudo dnf install -y java-17-openjdk-headless || { echo "FEHLER: Java 17 Installation fehlgeschlagen" >&2; exit 1; }
    else
      sudo dnf install -y java-1.8.0-openjdk-headless || { echo "FEHLER: Java 8 Installation fehlgeschlagen" >&2; exit 1; }
    fi
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux basierte Distributionen
    echo "Verwende pacman für Java $java_ver Installation..."
    if [ "$java_ver" = "21" ]; then
      sudo pacman -Sy --noconfirm jre21-openjdk-headless || { echo "FEHLER: Java 21 Installation fehlgeschlagen" >&2; exit 1; }
    elif [ "$java_ver" = "17" ]; then
      sudo pacman -Sy --noconfirm jre17-openjdk-headless || { echo "FEHLER: Java 17 Installation fehlgeschlagen" >&2; exit 1; }
    else
      sudo pacman -Sy --noconfirm jre8-openjdk-headless || { echo "FEHLER: Java 8 Installation fehlgeschlagen" >&2; exit 1; }
    fi
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE basierte Distributionen
    echo "Verwende zypper für Java $java_ver Installation..."
    if [ "$java_ver" = "21" ]; then
      sudo zypper --non-interactive install java-21-openjdk-headless || { echo "FEHLER: Java 21 Installation fehlgeschlagen" >&2; exit 1; }
    elif [ "$java_ver" = "17" ]; then
      sudo zypper --non-interactive install java-17-openjdk-headless || { echo "FEHLER: Java 17 Installation fehlgeschlagen" >&2; exit 1; }
    else
      sudo zypper --non-interactive install java-1_8_0-openjdk-headless || { echo "FEHLER: Java 8 Installation fehlgeschlagen" >&2; exit 1; }
    fi
  else
    echo "FEHLER: Kein unterstützter Package Manager gefunden." >&2
    echo "Bitte installieren Sie Java $java_ver manuell." >&2
    exit 1
  fi

  # Verifiziere dass Java nach der Installation verfügbar ist
  if ! command -v java >/dev/null 2>&1; then
    echo "FEHLER: Java-Installation fehlgeschlagen." >&2
    echo "Bitte installieren Sie Java $java_ver manuell." >&2
    exit 1
  fi

  # Prüfe installierte Java-Version
  local java_output installed_ver
  java_output=$(java -version 2>&1)
  echo "Java-Version nach Installation: $java_output"
  
  # Erweiterte Versions-Erkennung (wie oben)
  if echo "$java_output" | grep -q "version \"1.8"; then
    installed_ver=8
  elif echo "$java_output" | grep -q "version \"1.1"; then
    installed_ver=11
  else
    installed_ver=$(echo "$java_output" | grep -i version | head -n1 | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
  fi
  
  # Verifiziere dass mindestens die benötigte Version installiert wurde
  if [ "$installed_ver" -lt "$java_ver" ] 2>/dev/null; then
    echo "FEHLER: Java-Versions-Konflikt nach Installation." >&2
    echo "Benötigt: Java $java_ver, Gefunden: Java $installed_ver" >&2
    echo "" >&2
    echo "Aktuelle alternatives-Einstellung:" >&2
    update-alternatives --display java 2>&1 || true
    echo "" >&2
    echo "Verfügbare Java-Installationen:" >&2
    ls -l /usr/lib/jvm/java-* 2>&1 || true
    echo "" >&2
    echo "Bitte korrigieren Sie die Java-Version manuell mit:" >&2
    echo "  sudo update-alternatives --config java" >&2
    exit 1
  fi

  echo "Java $installed_ver erfolgreich installiert und verifiziert (benötigt: $java_ver)"
}

################################################################################
# Funktion: get_memory_args
# Beschreibung: Erkennt System-RAM und gibt JVM-Speicher-Argumente zurück
# Parameter: Keine
# Rückgabe:
#   String mit JVM-Argumenten (z.B. "-Xms6G -Xmx6G")
# Logik:
#   - Verwendet 75% des verfügbaren System-RAMs
#   - Minimum: 4GB, Maximum: 32GB
#   - Fallback: 4-8GB wenn Erkennung fehlschlägt
################################################################################
get_memory_args() {
  local mem_kb mem_mb mem_target
  
  # Versuche verschiedene Methoden zur RAM-Erkennung
  if [ -r /proc/meminfo ]; then
    # Linux: Lese aus /proc/meminfo
    mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_mb=$((mem_kb / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    # macOS und BSD: Verwende sysctl
    mem_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}' || echo 0)
  elif command -v wmic >/dev/null 2>&1; then
    # Windows (WSL): Verwende wmic
    mem_mb=$(wmic computersystem get totalphysicalmemory 2>/dev/null | grep -v Total | awk '{print int($1/1024/1024)}' || echo 0)
  else
    # Fallback: Verwende konservative Standard-Werte
    echo "-Xms4G -Xmx8G"
    return 0
  fi

  # Wenn Erkennung fehlschlug oder ungültiger Wert, verwende Standard
  if [ -z "$mem_mb" ] || [ "$mem_mb" -lt 1024 ]; then
    echo "-Xms4G -Xmx8G"
    return 0
  fi

  # Berechne Ziel-Speicher (75% des Gesamt-RAMs)
  mem_target=$((mem_mb * 75 / 100))
  
  # Stelle sicher: Minimum 4GB, Maximum 32GB
  if [ "$mem_target" -lt 4096 ]; then
    mem_target=4096
  elif [ "$mem_target" -gt 32768 ]; then
    mem_target=32768
  fi

  # Gib formatierte JVM-Argumente zurück
  echo "-Xms${mem_target}M -Xmx${mem_target}M"
}

################################################################################
# Funktion: detect_server_jar
# Beschreibung: Findet die Server-JAR-Datei automatisch
# Parameter: Keine
# Rückgabe:
#   String mit JAR-Dateinamen oder leer wenn nicht gefunden
# Prioritäts-Reihenfolge:
#   1. Modloader-spezifische JARs (forge, neoforge, fabric, quilt)
#   2. Benannte Modded-JARs (run.jar etc.)
#   3. Andere Server-JARs (außer Vanilla minecraft_server)
#   4. Fallback: Größte JAR-Datei (außer Installer)
################################################################################
detect_server_jar() {
  local j
  
  # Priorität 1: Explizite Modloader-Server-JARs
  # Forge (klassisch und neue Versionen)
  j=$(ls -1 forge-*-server*.jar forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 neoforge-*-server*.jar neoforge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 fabric-server-launch.jar fabric-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 quilt-server-launch.jar quilt-server*.jar 2>/dev/null | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 *forge-*.jar 2>/dev/null | grep -v installer | head -n1 || true)
  [ -n "$j" ] || j=$(ls -1 run*.jar 2>/dev/null | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Priorität 2: Server-JARs (außer Vanilla minecraft_server)
  j=$(ls -1 *-server*.jar 2>/dev/null | grep -v "minecraft_server" | head -n1 || true)
  if [ -n "$j" ]; then printf '%s' "$j"; return 0; fi

  # Fallback: Größte JAR-Datei (außer Installer)
  j=$(ls -S *.jar 2>/dev/null | grep -v -i installer | head -n1 || true)
  printf '%s' "$j"
}

################################################################################
# HAUPT-SCRIPT BEGINNT HIER
################################################################################

# Schritt 0: Validierung der Eingabe-Datei
if [ ! -f "$ZIP" ]; then
  echo "FEHLER: ZIP-Datei nicht gefunden: $ZIP" >&2
  echo "Verwendung: $0 [PACK.zip]" >&2
  exit 1
fi

echo "========================================="
echo "Minecraft Server Setup"
echo "========================================="
echo "ZIP-Datei: $ZIP"
echo "Server-Verzeichnis: $SRVDIR"
echo ""

# Schritt 1: Prüfe benötigte Programme
echo "[1/7] Prüfe Voraussetzungen..."
require_cmd unzip curl jq rsync

# Schritt 2: Entpacke Modpack
echo "[2/7] Entpacke Modpack..."
if ! unzip -q "$ZIP" -d "$WORK"; then
  echo "FEHLER: Entpacken fehlgeschlagen" >&2
  exit 1
fi

################################################################################
# Pack-Typ-Erkennung: Server-Pack vs. Client-Export
################################################################################
# Server-Packs enthalten bereits Start-Scripts
# Client-Exports enthalten ein manifest.json und müssen konvertiert werden
HAS_START=$(grep -rilE 'startserver\.sh|start\.sh' "$WORK" 2>/dev/null || true)
HAS_MANIFEST=$(find "$WORK" -maxdepth 3 -name manifest.json 2>/dev/null | head -n1 || true)

################################################################################
# PFAD 1: Server-Pack Installation
################################################################################
if [ -n "$HAS_START" ]; then
  echo "[3/7] Server-Pack erkannt - Direkte Installation..."
  
  # Versuche Minecraft-Version zu erkennen für Java-Setup
  # Reihenfolge: minecraft_server.jar -> manifest.json -> forge jar
  MC_VER=$(ls minecraft_server.*.jar 2>/dev/null | grep -o '[0-9.]*' | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(find "$WORK" -name manifest.json -exec jq -r '.minecraft.version // empty' {} \; 2>/dev/null | head -n1 || true)
  [ -z "$MC_VER" ] && MC_VER=$(ls forge-*.jar 2>/dev/null | grep -o '1\.[0-9.]*' | head -n1 || true)
  
  # Setup Java basierend auf erkannter MC-Version
  if [ -n "$MC_VER" ]; then
    setup_java "$MC_VER"
  else
    echo "WARNUNG: Minecraft-Version konnte nicht erkannt werden." >&2
    echo "Möglicherweise müssen Sie die korrekte Java-Version manuell installieren." >&2
  fi
  
  # Kopiere Server-Inhalte ins aktuelle Verzeichnis
  echo "Kopiere Server-Dateien..."
  if ! rsync -a "$WORK"/ ./; then
    echo "FEHLER: Kopieren der Server-Dateien fehlgeschlagen" >&2
    exit 1
  fi
  rm -rf "$WORK"

  # Mache alle Shell-Scripts ausführbar
  echo "Setze Ausführungsrechte für Scripts..."
  find . -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

  # EULA-Akzeptierung (interaktiv oder automatisch)
  echo ""
  echo "[4/7] EULA-Akzeptierung..."
  if ask_yes_no "Minecraft EULA akzeptieren? (https://account.mojang.com/documents/minecraft_eula)" "yes"; then
    echo "eula=true" > eula.txt
    echo "EULA akzeptiert und in eula.txt gespeichert"
  else
    echo "eula=false" > eula.txt
    echo "FEHLER: EULA wurde nicht akzeptiert. Installation abgebrochen." >&2
    exit 1
  fi

  # Operator-Rechte für Standard-Benutzer
  echo ""
  echo "Setze Operator-Rechte..."
  if [ ! -f ops.json ]; then
    echo '[
  {
    "uuid": "",
    "name": "lorol61",
    "level": 4,
    "bypassesPlayerLimit": false
  }
]' > ops.json
    echo "✓ Operator-Rechte für lorol61 gesetzt (Level 4)"
  else
    echo "ops.json existiert bereits - wird nicht überschrieben"
  fi

  # Erster Server-Start zur Finalisierung (optional)
  echo ""
  echo "[5/7] Finalisierung..."
  if ask_yes_no "Server jetzt einmal starten um Setup abzuschließen (empfohlen)?" "yes"; then
    if [ -f ./startserver.sh ]; then
      echo "Starte Server mit startserver.sh..."
      ./startserver.sh || true
    elif [ -f ./start.sh ]; then
      echo "Starte Server mit start.sh..."
      ./start.sh || true
    else
      echo "Kein Start-Script gefunden, versuche JAR direkt zu starten..."
      JAR=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
      if [ -n "$JAR" ]; then 
        java -jar "$JAR" nogui || true
      else
        echo "WARNUNG: Keine JAR-Datei gefunden" >&2
      fi
    fi
  else
    echo "Erster Start übersprungen. Starten Sie den Server später mit ./start.sh"
  fi

  # Erstelle universelles start.sh Script
  # Dieses Script bevorzugt existierende Start-Scripts, kann aber auch die JAR direkt starten
  echo ""
  echo "[6/7] Erstelle start.sh Script..."
  SRVJAR="$(detect_server_jar)"
  
  # Speichere erkannte JAR-Datei für spätere Verwendung
  if [ -n "$SRVJAR" ]; then
    echo "$SRVJAR" > .server_jar
    echo "Server-JAR erkannt: $SRVJAR"
  else
    echo "WARNUNG: Keine Server-JAR erkannt" >&2
  fi
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

  echo ""
  echo "[7/7] Server-Pack Installation abgeschlossen!"
  echo "========================================="
  echo "Der Server ist bereit."
  echo "Starten mit: ./start.sh"
  echo "========================================="
  exit 0
fi

################################################################################
# PFAD 2: Client-Export Konvertierung
################################################################################
if [ -z "$HAS_MANIFEST" ]; then
  echo "FEHLER: Weder Server-Dateien noch manifest.json gefunden." >&2
  echo "Bitte stellen Sie sicher, dass Sie ein gültiges Modpack-ZIP verwenden." >&2
  exit 1
fi

echo "[3/7] Client-Export erkannt - Konvertiere zu Server..."
echo "Lese manifest.json..."
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

echo ""
echo "Erkannte Konfiguration:"
echo "  Minecraft-Version: $MC_VER"
echo "  Modloader:         $LOADER_ID"
echo ""

# Wechsle ins Server-Verzeichnis für Installation
cd "$SRVDIR"
echo "[4/7] Installiere Server-Modloader..."

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
  
  echo "Lade Forge-Installer herunter: $inst"
  if ! curl -fL "${base}/${inst}" -o "$inst"; then
    echo "FEHLER: Forge-Download fehlgeschlagen" >&2
    exit 1
  fi
  
  echo "Installiere Forge-Server..."
  if ! java -jar "$inst" --installServer; then
    echo "FEHLER: Forge-Installation fehlgeschlagen" >&2
    exit 1
  fi
}

################################################################################
# Funktion: download_neoforge
# Beschreibung: Lädt und installiert NeoForge Server
# Parameter:
#   $1 - ver: NeoForge-Version (z.B. "20.6.120")
################################################################################
download_neoforge() {
  local ver="$1"
  local base="https://maven.neoforged.net/releases/net/neoforged/forge/${ver}"
  local inst="forge-${ver}-installer.jar"
  
  echo "Lade NeoForge-Installer herunter: $inst"
  if ! curl -fL "${base}/${inst}" -o "$inst"; then
    echo "FEHLER: NeoForge-Download fehlgeschlagen" >&2
    exit 1
  fi
  
  echo "Installiere NeoForge-Server..."
  if ! java -jar "$inst" --installServer; then
    echo "FEHLER: NeoForge-Installation fehlgeschlagen" >&2
    exit 1
  fi
}

################################################################################
# Funktion: download_fabric
# Beschreibung: Lädt und installiert Fabric Server
# Parameter:
#   $1 - mc_ver: Minecraft-Version
################################################################################
download_fabric() {
  local mc_ver="$1"
  local INST="fabric-installer.jar"
  
  echo "Lade Fabric-Installer-Informationen..."
  if ! curl -fL "https://meta.fabricmc.net/v2/versions/installer" -o _fabric.json; then
    echo "FEHLER: Fabric-Versions-Download fehlgeschlagen" >&2
    exit 1
  fi
  
  local URL
  URL=$(jq -r '[.[] | select(.stable==true)][0].url' _fabric.json 2>/dev/null)
  if [ -z "$URL" ] || [ "$URL" = "null" ]; then
    echo "FEHLER: Konnte Fabric-Installer-URL nicht ermitteln" >&2
    exit 1
  fi
  
  echo "Lade Fabric-Installer herunter..."
  if ! curl -fL "$URL" -o "$INST"; then
    echo "FEHLER: Fabric-Installer-Download fehlgeschlagen" >&2
    exit 1
  fi
  
  echo "Installiere Fabric-Server für Minecraft $mc_ver..."
  if ! java -jar "$INST" server -mcversion "$mc_ver" -downloadMinecraft; then
    echo "FEHLER: Fabric-Installation fehlgeschlagen" >&2
    exit 1
  fi
}

# Modloader-Installation basierend auf erkanntem Typ
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
    echo "FEHLER: Unbekannter Modloader: $LOADER_ID" >&2
    echo "Unterstützte Loader: forge, neoforge, fabric, quilt" >&2
    exit 1
    ;;
esac

# Verifiziere dass Server-JAR gefunden wurde
if [ -z "$SRVJAR" ] || [ ! -f "$SRVJAR" ]; then
  echo "WARNUNG: Server-JAR nicht gefunden oder nicht erstellt" >&2
  echo "Dies kann normal sein wenn der Installer die Datei anders benennt." >&2
fi

echo ""
echo "[5/7] Kopiere Mods und Konfigurationen..."

# Debug-Ausgabe zur Fehlersuche
if [ "${DEBUG:-0}" = "1" ]; then
  echo "DEBUG: Arbeitsverzeichnis-Inhalt:"
  ls -la "$WORK" 2>/dev/null || true
  if [ -d "$WORK/overrides" ]; then
    echo "DEBUG: Overrides-Verzeichnis-Inhalt:"
    ls -la "$WORK/overrides" 2>/dev/null || true
  fi
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
    echo "  Kopiere $type von $src..."
    if rsync -a "$src/" "$dst/" 2>/dev/null; then
      local count=$(find "$dst" -type f 2>/dev/null | wc -l)
      echo "  ✓ $type kopiert ($count Dateien)"
    else
      echo "  ⚠ Warnung: Kopieren von $type fehlgeschlagen" >&2
    fi
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

# Kopiere zusätzliche häufige Verzeichnisse
echo "Kopiere zusätzliche Verzeichnisse:"
for d in kubejs defaultconfigs scripts libraries resourcepacks; do
  # Erstelle Verzeichnis falls Quelle existiert
  if [ -d "$WORK/overrides/$d" ] || [ -d "$WORK/$d" ] || [ -d "$WORK/server-overrides/$d" ]; then
    mkdir -p "./$d"
  fi
  
  # Kopiere aus allen möglichen Quellen
  copy_with_log "$WORK/overrides/$d" "./$d" "$d (overrides)"
  copy_with_log "$WORK/$d" "./$d" "$d (top-level)"
  copy_with_log "$WORK/server-overrides/$d" "./$d" "$d (server-overrides)"
done

# Verifiziere dass Mods kopiert wurden
echo ""
echo "Verifiziere Installation..."
MOD_COUNT=$(find ./mods -type f -name "*.jar" 2>/dev/null | wc -l)
if [ "$MOD_COUNT" -eq 0 ]; then
  echo "⚠ WARNUNG: Keine Mods im mods-Verzeichnis gefunden!" >&2
  echo "Modpack-Struktur:" >&2
  find "$WORK" -name "*.jar" -type f 2>/dev/null | head -20 || true
else
  echo "✓ $MOD_COUNT Mods installiert"
fi

echo ""
echo "[6/7] EULA-Akzeptierung..."
# Interaktive EULA-Akzeptierung
if ask_yes_no "Minecraft EULA akzeptieren? (https://account.mojang.com/documents/minecraft_eula)" "yes"; then
  echo "eula=true" > eula.txt
  echo "✓ EULA akzeptiert"
else
  echo "eula=false" > eula.txt
  echo "FEHLER: EULA wurde nicht akzeptiert. Installation abgebrochen." >&2
  exit 1
fi

# Operator-Rechte für Standard-Benutzer
echo ""
echo "Setze Operator-Rechte..."
if [ ! -f ops.json ]; then
  echo '[
  {
    "uuid": "",
    "name": "lorol61",
    "level": 4,
    "bypassesPlayerLimit": false
  }
]' > ops.json
  echo "✓ Operator-Rechte für lorol61 gesetzt (Level 4)"
else
  echo "ops.json existiert bereits - wird nicht überschrieben"
fi

echo ""
echo "[7/7] Finalisierung und erster Start..."

# Erkenne Server-JAR robust
SRVJAR="$(detect_server_jar)"
if [ -z "$SRVJAR" ] || [ ! -f "$SRVJAR" ]; then
  echo "FEHLER: Konnte Server-JAR nicht finden." >&2
  echo "Verfügbare JAR-Dateien:" >&2
  ls -1 *.jar 2>/dev/null || echo "  Keine JAR-Dateien gefunden"
  exit 1
fi

# Setze Speicher basierend auf System-RAM (75%) oder verwende JAVA_ARGS
JAVA_ARGS="${JAVA_ARGS:-$(get_memory_args)}"
echo "Server-JAR: $SRVJAR"
echo "Speicher-Einstellungen: $JAVA_ARGS"

# Frage ob erster Start durchgeführt werden soll
echo ""
if ask_yes_no "Server jetzt einmal starten um Dateien zu generieren (empfohlen)?" "yes"; then
  echo "Starte Server..."
  java $JAVA_ARGS -jar "$SRVJAR" nogui || true
else
  echo "Erster Start übersprungen."
fi
echo ""
echo "Erstelle start.sh Script..."

# Erstelle universelles Start-Script
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

# Mache Start-Script ausführbar
chmod +x start.sh

# Aufräumen
echo "Räume temporäre Dateien auf..."
rm -rf "$WORK" _fabric.json 2>/dev/null || true

echo ""
echo "========================================="
echo "✓ Installation abgeschlossen!"
echo "========================================="
echo ""
echo "Nächste Schritte:"
echo "  1. Bearbeiten Sie server.properties nach Bedarf"
echo "  2. Starten Sie den Server mit: ./start.sh"
echo ""
echo "Hinweise:"
echo "  - Erste Starts können länger dauern"
echo "  - Logs finden Sie in logs/latest.log"
echo "  - Port 25565 muss geöffnet sein (Firewall)"
echo "========================================="
