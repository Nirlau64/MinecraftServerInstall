# Kompletter Minecraft Server Workflow

Diese umfassende Anleitung beschreibt alle verfügbaren Möglichkeiten zur Installation, Konfiguration und Verwaltung von Minecraft-Servern mit diesem Tool.

## Inhaltsverzeichnis

1. [Übersicht der verfügbaren Modi](#übersicht-der-verfügbaren-modi)
2. [Vorbereitung & Systemanforderungen](#vorbereitung--systemanforderungen)
3. [Installation & Setup](#installation--setup)
   - [GUI-Modus (Empfohlen für Anfänger)](#gui-modus-empfohlen-für-anfänger)
   - [Kommandozeilen-Modus](#kommandozeilen-modus)
   - [Vollautomatischer Modus (CI/CD)](#vollautomatischer-modus-cicd)
4. [Alle verfügbaren Parameter](#alle-verfügbaren-parameter)
5. [Konfigurationsmöglichkeiten](#konfigurationsmöglichkeiten)
6. [Szenarien & Anwendungsfälle](#szenarien--anwendungsfälle)
7. [Nach der Installation](#nach-der-installation)
8. [Troubleshooting & Logs](#troubleshooting--logs)

---

## Übersicht der verfügbaren Modi

### 🎮 **GUI-Modus** (Grafische Benutzeroberfläche)
- **Zielgruppe**: Anfänger, lokale Nutzung
- **Vorteile**: Intuitive Bedienung, visuelle Konfiguration, Live-Server-Management
- **Nachteile**: Benötigt grafische Oberfläche

### ⌨️ **Kommandozeilen-Modus** (Interaktiv)
- **Zielgruppe**: Erfahrene Benutzer, SSH-Verbindungen
- **Vorteile**: Flexibel, funktioniert überall
- **Nachteile**: Erfordert Kommandozeilenkenntnisse

### 🤖 **Vollautomatischer Modus** (Non-Interactive)
- **Zielgruppe**: CI/CD-Pipelines, Automatisierung
- **Vorteile**: Keine Benutzerinteraktion erforderlich
- **Nachteile**: Alle Parameter müssen vorab konfiguriert werden

---

## Vorbereitung & Systemanforderungen

### Systemanforderungen
```bash
# Grundlegende Tools (automatisch installiert wenn fehlend)
- bash (4.0+)
- unzip
- curl
- jq
- rsync

# Für GUI-Modus zusätzlich
- Python 3.6+
- tkinter (meist vorinstalliert)

# Systemressourcen
- Mindestens 2GB RAM (empfohlen: 4GB+)
- 1GB freier Speicherplatz (mehr je nach Modpack)
- Port 25565 verfügbar
- Internetverbindung für Downloads
```

### Repository klonen
```bash
git clone https://github.com/Nirlau64/MinecraftServerInstall.git
cd MinecraftServerInstall
chmod +x universalServerSetup.sh
chmod +x start_gui.sh
```

---

## Installation & Setup

## GUI-Modus (Empfohlen für Anfänger)

### 🚀 **Einfachster Weg: Komplette GUI-Installation**

```bash
# GUI starten (funktioniert vor und nach Server-Setup)
./start_gui.sh

# Oder direkt mit Python
python3 tools/server_gui.py
```

**GUI-Workflow Schritt-für-Schritt:**

1. **GUI starten**
   ```bash
   ./start_gui.sh
   ```

2. **Setup & Konfiguration Tab verwenden**
   - **Modpack auswählen**: Entweder ZIP-Datei auswählen oder leer lassen für Vanilla
   - **Server-Einstellungen konfigurieren**:
     - MOTD (Servernachricht)
     - Schwierigkeit (Peaceful, Easy, Normal, Hard)
     - PVP ein/aus
     - Maximale Spieleranzahl
     - Sichtweite, Weltname, Seed
   - **Speicher-Einstellungen**:
     - Automatisch (75% des System-RAM)
     - Manuell (z.B. "8G", "4096M")
   - **Installation-Optionen**:
     - ✅ EULA akzeptieren
     - ✅ Automatischer Mod-Download (für Client-Exports)
     - ✅ Backup vor Installation
     - ✅ Dateien überschreiben
   - **Service-Optionen**:
     - ✅ systemd Service generieren
     - ✅ tmux Session starten

3. **Installation ausführen**
   - Button "Server Setup ausführen" klicken
   - Fortschritt in Echtzeit verfolgen
   - Bei Fehlern: Logs im "Logs & Monitoring" Tab prüfen

4. **Server verwalten** (nach erfolgreicher Installation)
   - **Server-Steuerung Tab**: Start/Stop/Restart/Kill
   - **Welt-Management Tab**: Welten wechseln, Backups erstellen
   - **Backup-Management Tab**: Backups wiederherstellen, verwalten
   - **Mod-Management Tab**: Mods hinzufügen/entfernen
   - **Logs & Monitoring Tab**: Server-Logs live verfolgen

### GUI-spezifische Features

**Live-Konsole:**
```bash
# Server-Kommandos direkt in der GUI eingeben
say Hallo Welt!
op SpielerName
list
stop
```

**Welt-Management:**
- Neue Welten erstellen
- Zwischen Welten wechseln
- Automatische Backups mit Zeitstempel
- Welt-Import/Export

**Backup-System:**
- Automatische Backups alle X Stunden
- Manuelle Backups auf Knopfdruck
- Backup-Browser mit Vorschau
- Wiederherstellung mit Bestätigung

---

## Kommandozeilen-Modus

### 🎯 **Schnelle Standard-Installation**

```bash
# Einfachste Verwendung
./universalServerSetup.sh MyModpack.zip

# Das Skript führt Sie durch:
# 1. Modpack-Analyse
# 2. Java-Installation (falls erforderlich)
# 3. EULA-Bestätigung (interaktive Eingabe)
# 4. Server-Installation
# 5. Erste Ausführung (optional)
# 6. GUI-Start (optional)
```

### 🔧 **Mit spezifischen Parametern**

```bash
# Mit benutzerdefinierten Server-Einstellungen
./universalServerSetup.sh \
  --motd="Mein Awesome Server" \
  --difficulty=hard \
  --max-players=50 \
  --pvp=false \
  --ram=8G \
  MyModpack.zip

# Mit Service-Integration
./universalServerSetup.sh \
  --systemd \
  --tmux \
  MyModpack.zip

# Mit automatischem Mod-Download (für Client-Exports)
./universalServerSetup.sh \
  --auto-download-mods \
  --verbose \
  MyClientExport.zip
```

### 🔄 **Erweiterte Workflows**

**Backup & Wiederherstellung:**
```bash
# Backup vor Änderungen erstellen
./universalServerSetup.sh --pre-backup MyModpack.zip

# Welt aus Backup wiederherstellen
./universalServerSetup.sh --restore backups/world-20241104-143022.zip

# Mit benutzerdefiniertem Weltnamen
./universalServerSetup.sh --world "survival" MyModpack.zip
```

**Entwicklung & Testing:**
```bash
# Dry-Run: Zeigt was passieren würde, ohne Änderungen
./universalServerSetup.sh --dry-run --verbose MyModpack.zip

# Mit detailliertem Logging
./universalServerSetup.sh --verbose --log-file debug.log MyModpack.zip

# Force-Mode: Überschreibt alle existierenden Dateien
./universalServerSetup.sh --force MyModpack.zip
```

---

## Vollautomatischer Modus (CI/CD)

### 🤖 **Komplette Automatisierung**

```bash
# Vollständig automatisierte Installation
./universalServerSetup.sh \
  --yes \
  --eula=true \
  --force \
  --no-gui \
  --systemd \
  --motd="Production Server" \
  --difficulty=normal \
  --max-players=20 \
  --ram=16G \
  MyModpack.zip
```

### 📝 **Via Umgebungsvariablen**

```bash
# .env Datei erstellen
cat > server.env << 'EOF'
# Automatisierung
AUTO_ACCEPT_EULA=yes
AUTO_FIRST_RUN=yes
ASSUME_YES=1
NO_GUI=1

# Server-Konfiguration
PROP_MOTD=Production Minecraft Server
PROP_DIFFICULTY=normal
PROP_MAX_PLAYERS=30
PROP_PVP=false
PROP_VIEW_DISTANCE=12

# Operator-Einstellungen
OP_USERNAME=admin
ALWAYS_OP_USERS="admin moderator1 moderator2"

# Speicher-Konfiguration
MEMORY_PERCENT=80
MIN_MEMORY_MB=4096
MAX_MEMORY_MB=16384

# Backup-Einstellungen
BACKUP_INTERVAL_HOURS=2
BACKUP_RETENTION=24

# Service-Integration
SYSTEMD=1
TMUX=1
EOF

# Mit Umgebungsvariablen ausführen
source server.env
./universalServerSetup.sh MyModpack.zip
```

### 🐳 **Docker/Container-Integration**

```bash
# Docker-Container-freundliche Ausführung
docker run -v $(pwd):/workspace ubuntu:latest bash -c "
  cd /workspace
  export AUTO_ACCEPT_EULA=yes
  export AUTO_FIRST_RUN=no
  export NO_GUI=1
  export ASSUME_YES=1
  ./universalServerSetup.sh MyModpack.zip
"
```

---

## Alle verfügbaren Parameter

### 📋 **Basis-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--yes` / `-y` | Beantwortet alle Prompts mit "Ja" | `--yes` |
| `--assume-no` | Beantwortet alle Prompts mit "Nein" | `--assume-no` |
| `--force` | Überschreibt existierende Dateien | `--force` |
| `--dry-run` | Zeigt Aktionen ohne Ausführung | `--dry-run` |

### 🔐 **EULA-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--eula=true` | EULA automatisch akzeptieren | `--eula=true` |
| `--eula=false` | EULA explizit ablehnen | `--eula=false` |
| `--no-eula-prompt` | Überspringe EULA-Eingabeaufforderung | `--no-eula-prompt` |

### 💾 **Speicher-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--ram <SIZE>` | Spezifische RAM-Zuteilung | `--ram 8G`, `--ram 4096M` |

### 📝 **Logging-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--verbose` | Erhöht Log-Detail | `--verbose` |
| `--quiet` | Reduziert Log-Ausgabe | `--quiet` |
| `--log-file <path>` | Benutzerdefinierte Log-Datei | `--log-file debug.log` |

### 🔧 **Service-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--systemd` | Generiere systemd Service | `--systemd` |
| `--tmux` | Starte in tmux Session | `--tmux` |

### 🌍 **Welt-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--world <name>` | Benutzerdefinierter Weltname | `--world survival` |
| `--pre-backup` | Backup vor Installation | `--pre-backup` |
| `--restore <zip>` | Welt aus Backup wiederherstellen | `--restore backup.zip` |

### 🎮 **Server-Properties Parameter**

| Parameter | Beschreibung | Werte | Beispiel |
|-----------|-------------|-------|----------|
| `--motd` | Server-Nachricht | Text | `--motd="Mein Server"` |
| `--difficulty` | Schwierigkeit | peaceful, easy, normal, hard | `--difficulty=hard` |
| `--pvp` | PVP aktiviert | true, false | `--pvp=false` |
| `--max-players` | Maximale Spieler | Zahl | `--max-players=50` |
| `--view-distance` | Sichtweite | 1-32 | `--view-distance=12` |
| `--white-list` | Whitelist aktiviert | true, false | `--white-list=true` |
| `--spawn-protection` | Spawn-Schutz-Radius | 0-29999984 | `--spawn-protection=16` |
| `--allow-nether` | Nether erlaubt | true, false | `--allow-nether=true` |
| `--level-name` | Weltname | Text | `--level-name=world` |
| `--level-seed` | Welt-Seed | Zahl/Text | `--level-seed=12345` |
| `--level-type` | Welttyp | default, flat, large_biomes | `--level-type=default` |

### 🤖 **Mod-Download-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--auto-download-mods` | Automatischer Mod-Download | `--auto-download-mods` |

### 🖥️ **GUI-Parameter**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|----------|
| `--no-gui` | GUI deaktivieren | `--no-gui` |

---

## Konfigurationsmöglichkeiten

### 📄 **Skript-Konfiguration (Datei bearbeiten)**

Die wichtigsten Einstellungen können direkt im Skript `universalServerSetup.sh` geändert werden:

```bash
# Basis-Einstellungen (Zeile ~68-80)
ZIP=""                          # Standard-Modpack-Pfad
OP_USERNAME=""                  # Standard-Operator
OP_LEVEL="4"                    # Operator-Level (1-4)
ALWAYS_OP_USERS=""              # Immer-Operator-Liste

# Automatisierung (Zeile ~82-84)
AUTO_ACCEPT_EULA="no"           # EULA automatisch akzeptieren
AUTO_FIRST_RUN="no"             # Server automatisch starten

# Speicher-Konfiguration (Zeile ~104-112)
JAVA_ARGS=""                    # Benutzerdefinierte JVM-Args
MEMORY_PERCENT=75               # RAM-Prozentsatz
MIN_MEMORY_MB=2048              # Minimum RAM
MAX_MEMORY_MB=32768             # Maximum RAM

# Backup-Einstellungen (Zeile ~116-118)
BACKUP_INTERVAL_HOURS=4         # Backup-Intervall
BACKUP_RETENTION=12             # Anzahl zu behaltender Backups

# Server-Properties-Defaults (Zeile ~129-160)
PROP_MOTD="A Minecraft Server"  # Standard-MOTD
PROP_DIFFICULTY="easy"          # Standard-Schwierigkeit
PROP_PVP="true"                 # Standard-PVP
PROP_VIEW_DISTANCE="10"         # Standard-Sichtweite
PROP_MAX_PLAYERS="20"           # Standard-Spielerzahl
# ... und viele weitere
```

### 🔄 **Umgebungsvariablen**

Alle Konfigurationsoptionen können via Umgebungsvariablen überschrieben werden:

```bash
# Server-Konfiguration
export PROP_MOTD="Produktions-Server"
export PROP_DIFFICULTY="hard"
export PROP_MAX_PLAYERS="100"
export PROP_PVP="false"

# Speicher-Einstellungen
export MEMORY_PERCENT="90"
export MIN_MEMORY_MB="8192"

# Automatisierung
export AUTO_ACCEPT_EULA="yes"
export ASSUME_YES="1"
```

### ⚙️ **Konfigurationsdateien**

Das System unterstützt auch `.env`-Dateien:

```bash
# .env Datei erstellen
cat > .env << 'EOF'
PROP_MOTD=Mein Gaming Server
PROP_DIFFICULTY=normal
PROP_MAX_PLAYERS=25
MEMORY_PERCENT=80
BACKUP_INTERVAL_HOURS=6
EOF

# Automatisch geladen beim Skript-Start
./universalServerSetup.sh MyModpack.zip
```

---

## Szenarien & Anwendungsfälle

### 🎯 **Szenario 1: Anfänger - Erste Minecraft-Server**

**Ziel**: Einfacher Start mit GUI
**Empfohlener Workflow**: GUI-Modus

```bash
# 1. Repository klonen
git clone https://github.com/Nirlau64/MinecraftServerInstall.git
cd MinecraftServerInstall

# 2. Modpack herunterladen (von CurseForge/Modrinth)
# MyModpack.zip in das Verzeichnis legen

# 3. GUI starten
./start_gui.sh

# 4. In der GUI:
#    - Setup & Konfiguration Tab öffnen
#    - Modpack auswählen: MyModpack.zip
#    - EULA akzeptieren
#    - "Server Setup ausführen" klicken
#    - Warten bis fertig
#    - Server-Steuerung Tab nutzen

# 5. Server starten über GUI oder:
./start.sh
```

### 🏢 **Szenario 2: Produktions-Server**

**Ziel**: Stabiler Server mit Service-Integration
**Empfohlener Workflow**: Kommandozeile mit systemd

```bash
# 1. Vollautomatische Installation
./universalServerSetup.sh \
  --yes \
  --eula=true \
  --systemd \
  --ram=16G \
  --motd="Produktions-Server [1.20.1]" \
  --difficulty=hard \
  --max-players=50 \
  --pvp=true \
  --view-distance=12 \
  --backup-interval=2 \
  MyProductionModpack.zip

# 2. systemd Service installieren
sudo cp dist/minecraft.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft

# 3. Status überwachen
sudo systemctl status minecraft
sudo journalctl -u minecraft -f

# 4. Server-Management
sudo systemctl stop minecraft     # Stoppen
sudo systemctl start minecraft    # Starten
sudo systemctl restart minecraft  # Neustarten
```

### 🔄 **Szenario 3: CI/CD-Pipeline**

**Ziel**: Automatische Bereitstellung
**Empfohlener Workflow**: Vollautomatisch

```bash
# GitHub Actions / GitLab CI Beispiel
name: Deploy Minecraft Server
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Deploy Server
      run: |
        # Umgebungsvariablen setzen
        export AUTO_ACCEPT_EULA=yes
        export AUTO_FIRST_RUN=no
        export NO_GUI=1
        export ASSUME_YES=1
        export SYSTEMD=1
        
        # Server installieren
        ./universalServerSetup.sh \
          --force \
          --ram=8G \
          --motd="CI/CD Server $(date)" \
          ModpackLatest.zip
        
        # Service starten
        sudo systemctl restart minecraft
```

### 🧪 **Szenario 4: Entwicklung & Testing**

**Ziel**: Schnelle Test-Server für Mod-Entwicklung
**Empfohlener Workflow**: Dry-Run + Development-Mode

```bash
# 1. Test-Setup ohne echte Installation
./universalServerSetup.sh \
  --dry-run \
  --verbose \
  TestModpack.zip

# 2. Entwicklungs-Server mit Debug-Logging
./universalServerSetup.sh \
  --yes \
  --eula=true \
  --ram=4G \
  --verbose \
  --log-file dev-install.log \
  --tmux \
  --motd="Dev Server - $(date +%Y%m%d)" \
  TestModpack.zip

# 3. Schnelle Iteration
# Modpack ändern und neu installieren
./universalServerSetup.sh \
  --force \
  --yes \
  --eula=true \
  TestModpack-v2.zip

# 4. tmux Session verwalten
tmux attach-session -t minecraft  # An Server anhängen
# Strg+B, D zum Trennen
```

### 🌐 **Szenario 5: Multi-Server-Setup**

**Ziel**: Mehrere Server auf einem System
**Empfohlener Workflow**: Separate Verzeichnisse

```bash
# 1. Basis-Setup
mkdir -p ~/minecraft-servers
cd ~/minecraft-servers

# 2. Server 1: Survival
git clone https://github.com/Nirlau64/MinecraftServerInstall.git survival-server
cd survival-server
./universalServerSetup.sh \
  --motd="Survival Server" \
  --difficulty=hard \
  --ram=8G \
  --systemd \
  SurvivalModpack.zip
# Service-Namen ändern: minecraft-survival

# 3. Server 2: Creative  
cd ~/minecraft-servers
git clone https://github.com/Nirlau64/MinecraftServerInstall.git creative-server
cd creative-server
# Port ändern in server.properties auf 25566
./universalServerSetup.sh \
  --motd="Creative Server" \
  --difficulty=peaceful \
  --ram=4G \
  CreativeModpack.zip

# 4. Server 3: Modded
cd ~/minecraft-servers
git clone https://github.com/Nirlau64/MinecraftServerInstall.git modded-server
cd modded-server
# Port ändern auf 25567
./universalServerSetup.sh \
  --motd="Modded Server" \
  --auto-download-mods \
  --ram=12G \
  HeavyModpack.zip
```

### 🔁 **Szenario 6: Server-Migration & Backup**

**Ziel**: Bestehenden Server migrieren oder wiederherstellen
**Empfohlener Workflow**: Backup-System nutzen

```bash
# 1. Backup vom alten Server erstellen
# (falls mit diesem Tool erstellt)
./universalServerSetup.sh --pre-backup

# oder manuell
zip -r server-backup-$(date +%Y%m%d).zip \
  world* \
  server.properties \
  ops.json \
  whitelist.json \
  mods/ \
  config/

# 2. Neuen Server installieren
./universalServerSetup.sh MyModpack.zip

# 3. Backup wiederherstellen
./universalServerSetup.sh --restore server-backup-20241104.zip

# 4. Oder selektive Wiederherstellung
unzip -j server-backup-20241104.zip world/* -d world/
unzip -j server-backup-20241104.zip server.properties
```

---

## Nach der Installation

### 📁 **Generierte Dateien verstehen**

Nach erfolgreicher Installation entsteht folgende Struktur:

```
MinecraftServerInstall/
├── universalServerSetup.sh     # Setup-Skript
├── start.sh                    # Server-Start-Skript ⭐
├── .server_functions.sh        # Interne Funktionen
├── .server_jar                 # Server-JAR-Cache
├── eula.txt                    # EULA-Akzeptierung
├── server.properties           # Server-Konfiguration ⭐
├── ops.json                    # Operator-Liste
├── whitelist.json             # Whitelist (falls aktiviert)
├── mods/                      # Mod-Dateien
│   ├── mod1.jar
│   └── mod2.jar
├── config/                    # Mod-Konfigurationen
│   ├── forge-common.toml
│   └── verschiedene-mod-configs/
├── logs/                      # Log-Dateien ⭐
│   ├── install-20241104-143022.log
│   ├── latest.log
│   └── missing-mods.txt
├── backups/                   # Automatische Backups ⭐
│   └── world-20241104-120000.zip
├── world/                     # Spielwelt ⭐
├── libraries/                 # Mod-Loader-Libraries
├── forge-xx.x.x.jar          # Server-JAR (Forge/Fabric/etc.)
└── dist/                      # Service-Dateien
    └── minecraft.service      # systemd Service
```

### 🎮 **Server-Management nach Installation**

**Server starten:**
```bash
# Via generiertem Startskript (empfohlen)
./start.sh

# Via systemd (falls --systemd verwendet)
sudo systemctl start minecraft

# Via tmux (falls --tmux verwendet)
tmux attach-session -t minecraft

# Via GUI
./start_gui.sh
# → Server-Steuerung Tab → Start-Button
```

**Server stoppen:**
```bash
# Graceful shutdown (in der Server-Konsole)
stop

# Via systemd
sudo systemctl stop minecraft

# Force kill (Notfall)
pkill -f minecraft
```

**Server-Konfiguration ändern:**
```bash
# server.properties bearbeiten
nano server.properties

# Mod-Konfigurationen
nano config/forge-common.toml

# Via GUI: Setup & Konfiguration Tab
```

### 🔧 **Wartung & Updates**

**Modpack updaten:**
```bash
# Backup erstellen
./universalServerSetup.sh --pre-backup

# Neues Modpack installieren
./universalServerSetup.sh --force NewModpackVersion.zip

# Bei Problemen: Backup wiederherstellen
./universalServerSetup.sh --restore backups/world-YYYYMMDD-HHMMSS.zip
```

**Einzelne Mods hinzufügen:**
```bash
# Mod-Datei in mods/ Verzeichnis kopieren
cp NewMod.jar mods/

# Server neustarten
./start.sh
```

**Backup-Management:**
```bash
# Manuelles Backup
zip -r "backup-$(date +%Y%m%d-%H%M%S).zip" world/

# Automatische Backups konfigurieren (im Skript)
BACKUP_INTERVAL_HOURS=2  # Alle 2 Stunden
BACKUP_RETENTION=24      # 24 Backups behalten

# Alte Backups aufräumen
find backups/ -name "*.zip" -mtime +7 -delete  # Älter als 7 Tage
```

---

## Troubleshooting & Logs

### 📊 **Log-Dateien verstehen**

**Installation-Logs:**
```bash
# Neuestes Installation-Log
ls -t logs/install-*.log | head -1

# Log anzeigen
cat logs/install-20241104-143022.log

# Fehlerfiltere Log
grep -i error logs/install-20241104-143022.log
```

**Server-Logs:**
```bash
# Aktuelle Server-Logs
tail -f logs/latest.log

# Bestimmte Events suchen
grep -i "player\|error\|warn" logs/latest.log

# Crash-Reports
ls -la crash-reports/
```

**Mod-Download-Logs (bei --auto-download-mods):**
```bash
# Fehlgeschlagene Downloads
cat logs/missing-mods.txt

# Manuell herunterladen
python3 tools/cf_downloader.py manifest.json ./mods --verbose
```

### 🚨 **Häufige Probleme & Lösungen**

**Problem: Java nicht gefunden**
```bash
# Java-Version prüfen
java -version

# Manuell Java installieren (Ubuntu/Debian)
sudo apt update
sudo apt install openjdk-17-jre-headless

# Für ältere Minecraft-Versionen
sudo apt install openjdk-8-jre-headless

# Für neueste Minecraft-Versionen
sudo apt install openjdk-21-jre-headless
```

**Problem: Port 25565 bereits belegt**
```bash
# Port-Nutzung prüfen
sudo ss -tlnp | grep :25565
sudo netstat -tlnp | grep :25565

# Prozess beenden
sudo kill $(sudo lsof -t -i:25565)

# Alternativen Port verwenden (server.properties)
server-port=25566
```

**Problem: Nicht genügend Speicher**
```bash
# Verfügbaren RAM prüfen
free -h

# Speicher-Einstellungen anpassen
./universalServerSetup.sh --ram 4G MyModpack.zip

# Oder in der Konfiguration
export MEMORY_PERCENT=50
```

**Problem: Fehlende Berechtigung**
```bash
# Berechtigungen setzen
chmod +x universalServerSetup.sh start.sh

# Besitzer ändern
sudo chown -R $USER:$USER .

# Für systemd Service
sudo chown root:root dist/minecraft.service
```

**Problem: GUI startet nicht**
```bash
# tkinter Installation prüfen
python3 -c "import tkinter; print('OK')"

# Bei Headless-Server: X11-Forwarding
ssh -X user@server

# Oder GUI deaktivieren
./universalServerSetup.sh --no-gui MyModpack.zip
```

**Problem: Mods nicht kompatibel**
```bash
# Mod-Kompatibilität prüfen
cat mods/mod-name.jar # Minecraft-Version im Namen

# manifest.json analysieren (bei Client-Exports)
cat manifest.json | jq '.minecraft.version'
cat manifest.json | jq '.minecraft.modLoaders'

# Einzelne problematische Mods entfernen
mv mods/problematic-mod.jar mods/disabled/
```

### 🔍 **Debug-Modi verwenden**

**Verbose Logging:**
```bash
# Detaillierte Ausgabe
./universalServerSetup.sh --verbose MyModpack.zip

# Mit Log-Datei
./universalServerSetup.sh --verbose --log-file debug.log MyModpack.zip

# Log analysieren
less debug.log
grep -C 3 -i error debug.log  # 3 Zeilen Kontext um Fehler
```

**Dry-Run für Tests:**
```bash
# Zeigt alle Aktionen ohne Ausführung
./universalServerSetup.sh --dry-run --verbose MyModpack.zip

# Perfekt zum Testen von Parametern
./universalServerSetup.sh --dry-run \
  --ram 16G \
  --systemd \
  --auto-download-mods \
  MyModpack.zip
```

**Schritt-für-Schritt-Debugging:**
```bash
# 1. Modpack validieren
unzip -t MyModpack.zip

# 2. Manifest analysieren (falls vorhanden)
unzip -p MyModpack.zip manifest.json | jq .

# 3. Java-Version für Minecraft-Version prüfen
# (wird automatisch vom Skript gemacht)

# 4. Verfügbare Ressourcen prüfen
df -h        # Speicherplatz
free -h      # RAM
ss -tlnp | grep :25565  # Port-Verfügbarkeit
```

### 📞 **Hilfe erhalten**

**Community & Support:**
- GitHub Issues: Detaillierte Bug-Reports mit Logs
- GitHub Discussions: Allgemeine Fragen und Tipps
- README.md: Grundlegende Dokumentation

**Hilfreiche Informationen für Support-Anfragen:**
```bash
# System-Informationen sammeln
uname -a                    # System-Info
java -version              # Java-Version  
python3 --version          # Python-Version
cat /etc/os-release        # Distribution

# Log-Dateien bereitstellen
tar -czf support-logs.tar.gz logs/ *.log server.properties

# Konfiguration teilen (ohne sensible Daten)
grep -v "password\|key\|token" universalServerSetup.sh | head -200
```

---

## Fazit

Dieses umfassende Tool bietet drei verschiedene Ansätze für jeden Nutzertyp:

- **🎮 GUI-Modus**: Perfekt für Einsteiger und visuelle Verwaltung
- **⌨️ Kommandozeile**: Flexibel für erfahrene Nutzer und SSH-Umgebungen  
- **🤖 Vollautomatisch**: Ideal für Automatisierung und CI/CD-Pipelines

Mit über 30 Konfigurationsparametern, automatischem Java-Management, intelligentem Backup-System und umfassendem Logging ist es für jeden Anwendungsfall gerüstet - vom ersten Minecraft-Server bis zur Produktions-Umgebung mit mehreren Servern.

**Wichtigste Empfehlungen:**
- Neue Nutzer: Beginnen Sie mit dem GUI-Modus
- Produktions-Server: Nutzen Sie `--systemd` für Service-Integration  
- Entwicklung: Verwenden Sie `--dry-run` zum Testen
- Automatisierung: Konfigurieren Sie Umgebungsvariablen
- Immer: Erstellen Sie regelmäßige Backups!