# Minecraft Server Management GUI

Eine lightweight grafische Benutzeroberfläche zur Verwaltung von Minecraft-Servern, die mit dem `universalServerSetup.sh` Skript erstellt wurden.

## Features

### 🛠️ Setup & Konfiguration
- Vollständige Konfiguration aller Server-Properties (MOTD, Schwierigkeit, PVP, etc.)
- Speicher-Management (automatisch oder manuell)
- EULA-Verwaltung und Installation-Optionen
- Service-Integration (systemd, tmux)
- Modpack-Installation mit Datei-Browser

### 🎮 Server-Steuerung
- Start/Stop/Restart/Force Kill Buttons
- Live-Server-Konsole mit Eingabe-Möglichkeit
- Echtzeit-Status-Monitoring
- Spieler-Anzeige

### 🌍 Welt-Management
- Liste aller verfügbaren Welten
- Welt-Wechsel mit automatischer Server-Integration
- Backup-Erstellung mit Zeitstempel
- Welt-Löschung mit Sicherheitsabfrage

### 💾 Backup-Management
- Automatische Backup-Liste mit Sortierung
- Backup-Wiederherstellung mit Bestätigung
- Backup-Import von externen Dateien
- Backup-Löschung

### 🔧 Mod-Management
- Übersicht aller installierten Mods
- Einzelne Mod-Dateien hinzufügen/entfernen
- Automatischer Mod-Download aus manifest.json
- Integration mit dem cf_downloader.py

### 📋 Logs & Monitoring
- Log-Viewer für alle verfügbaren Log-Dateien
- Umschaltung zwischen verschiedenen Logs (Server, Installation, etc.)
- Externe Editor-Integration
- Auto-Scroll-Funktion

## Installation & Systemanforderungen

### Anforderungen
- Python 3.6 oder höher
- tkinter (meist mit Python vorinstalliert)
- Server erstellt mit `universalServerSetup.sh`

### Installation auf verschiedenen Systemen

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install python3 python3-tk
```

#### CentOS/RHEL/Fedora
```bash
# Fedora/RHEL 8+
sudo dnf install python3 python3-tkinter

# CentOS/RHEL 7
sudo yum install python3 tkinter
```

#### Arch Linux
```bash
sudo pacman -S python python-tk
```

#### macOS (Homebrew)
```bash
brew install python-tk
```

#### Windows
Tkinter ist normalerweise bereits mit Python installiert. Falls nicht:
```bash
pip install tk
```

## Verwendung

### Automatischer Start nach Setup
Die GUI startet automatisch nach einem erfolgreichen Server-Setup:
```bash
./universalServerSetup.sh MyModpack.zip
# GUI startet automatisch am Ende
```

### GUI deaktivieren
```bash
# Via Flag
./universalServerSetup.sh --no-gui MyModpack.zip

# Via Umgebungsvariable
GUI=0 ./universalServerSetup.sh MyModpack.zip
```

### Manueller GUI-Start
```bash
# Aus dem Server-Verzeichnis
python3 tools/server_gui.py

# Mit spezifischem Server-Pfad
python3 tools/server_gui.py /path/to/server

# Mit dem Launcher-Skript
python3 tools/start_gui.py
```

### Headless-Server
Auf servern ohne grafische Oberfläche wird die GUI automatisch deaktiviert:
- Keine DISPLAY-Umgebungsvariable → GUI deaktiviert
- SSH ohne X11-Forwarding → GUI deaktiviert
- Automatische Erkennung und graceful Fallback

## GUI-Bereiche im Detail

### Setup & Konfiguration Tab
Hier können alle Server-Einstellungen verwaltet werden:

**Server Properties:**
- MOTD (Message of the Day)
- Schwierigkeit (Peaceful, Easy, Normal, Hard)
- PVP aktiviert/deaktiviert
- Maximale Spielerzahl
- Sichtweite
- Weltname, Seed und Typ
- Whitelist aktiviert/deaktiviert

**Speicher & Performance:**
- Automatische RAM-Zuteilung (75% des System-RAM)
- Manuelle RAM-Eingabe (z.B. "4G", "8192M")

**Installation-Optionen:**
- EULA akzeptieren
- Automatischer Mod-Download
- Backup vor Installation
- Überschreiben erzwingen

**Service-Optionen:**
- systemd Service-Datei generieren
- tmux Session starten

### Server-Steuerung Tab
Komplette Server-Verwaltung:

**Status-Anzeige:**
- Aktueller Server-Status (Gestoppt/Startend/Laufend)
- Aktuelle Spielerzahl

**Steuerung:**
- Start Server: Startet den Server mit `start.sh`
- Stop Server: Graceful shutdown mit "stop" Befehl
- Restart Server: Stop + Start Kombination
- Force Kill: Sofortiges Beenden des Prozesses

**Live-Konsole:**
- Echtzeit-Ausgabe des Servers
- Befehls-Eingabe direkt an Server
- Scrollbare Historie

### Welt-Management Tab
Verwaltung von Minecraft-Welten:

**Aktuelle Welt:**
- Anzeige der aktuell konfigurierten Welt
- Backup-Erstellung für aktuelle Welt
- Welt-Löschung mit Bestätigung

**Verfügbare Welten:**
- Liste aller erkannten Welten (Ordner mit level.dat)
- Welt-Wechsel (stoppt Server automatisch)
- Automatische Aktualisierung

**Backup-Verwaltung:**
- Chronologisch sortierte Backup-Liste
- Wiederherstellung mit Bestätigung
- Import externer Backup-Dateien
- Backup-Löschung

### Mod-Management Tab
Verwaltung von Server-Mods:

**Installierte Mods:**
- Liste aller .jar Dateien im mods/ Verzeichnis
- Einzelne Mods entfernen
- Neue Mod-Dateien hinzufügen (via File-Browser)

**Automatischer Download:**
- Integration mit cf_downloader.py
- Download aus manifest.json (Client-Exports)
- Fortschritt und Fehler-Logging

### Logs & Monitoring Tab
Übersicht über alle Log-Dateien:

**Verfügbare Logs:**
- Server-Logs (logs/*.log)
- Installation-Logs (logs/install-*.log)
- Konfigurationsdateien (server.properties, eula.txt, etc.)
- Mod-Download-Logs (logs/missing-mods.txt)

**Viewer-Features:**
- Dropdown-Auswahl der Log-Datei
- Scrollbarer Text-Viewer
- Externe Editor-Integration
- Auto-Scroll für Live-Logs
- Anzeige löschen

## Konfigurationsverwaltung

### Speichern & Laden
- **Speichern:** Aktuelle GUI-Einstellungen → .env Datei
- **Laden:** .env Datei → GUI-Einstellungen
- **Reset:** Zurücksetzen auf Standard-Werte
- **Auto-Load:** Lädt Einstellungen beim GUI-Start

### .env Datei Format
```bash
# Minecraft Server Configuration
# Generated by Server GUI

PROP_MOTD="Mein Minecraft Server"
PROP_DIFFICULTY="normal"
PROP_PVP="true"
PROP_MAX_PLAYERS="20"
PROP_VIEW_DISTANCE="10"
PROP_LEVEL_NAME="world"
PROP_LEVEL_SEED=""
PROP_LEVEL_TYPE="default"
PROP_WHITE_LIST="false"
RAM="6G"
EULA="true"
```

## Integration mit Setup-Skript

### Automatische Parameter-Übergabe
Die GUI generiert die korrekten Kommandozeilen-Parameter für das Setup-Skript:

```bash
# Beispiel-generierter Befehl:
./universalServerSetup.sh \
  --eula=true \
  --no-eula-prompt \
  --ram 6G \
  --motd="Mein Server" \
  --difficulty=hard \
  --pvp=true \
  --max-players=25 \
  --auto-download-mods \
  --systemd \
  MyModpack.zip
```

### Echtzeit-Log-Integration
- Setup-Ausgabe wird live in der GUI angezeigt
- Fortschritt und Fehler werden farblich hervorgehoben
- Vollständiges Logging in Dateien

## Fehlerbehandlung & Robustheit

### Graceful Fallbacks
- Fehlende Python 3 Installation → Warnung + Hinweise
- Fehlende tkinter → Installation-Anweisungen
- Kein Display → Automatische Deaktivierung
- Fehlende Dateien → Informative Fehlermeldungen

### Cleanup-Mechanismen
- Automatisches GUI-Cleanup bei Skript-Abbruch
- PID-Tracking für GUI-Prozesse
- Temporäre Dateien werden aufgeräumt
- Exit-Traps für robustes Verhalten

### Fehler-Recovery
- Server-Prozess-Überwachung
- Backup-Validierung vor Wiederherstellung
- Konfiguration-Validierung vor Anwendung
- Rollback bei fehlgeschlagenen Operationen

## Erweiterte Features

### Multi-Platform Unterstützung
- **Linux:** Vollständige Unterstützung mit systemd/tmux Integration
- **macOS:** Native Unterstützung mit Homebrew-Integration  
- **Windows:** Grundlegende Unterstützung (ohne systemd/tmux)

### Skalierbarkeit
- Effiziente Behandlung großer Mod-Listen
- Streaming-Log-Anzeige für große Log-Dateien
- Async-Operations für Server-Steuerung
- Responsive UI auch bei langwierigen Operationen

### Sicherheit
- Bestätigungsdialoge für destruktive Operationen
- Backup-Erstellung vor kritischen Änderungen
- Validierung aller Benutzereingaben
- Sichere Prozess-Verwaltung

## Troubleshooting

### Häufige Probleme

**GUI startet nicht:**
```bash
# Überprüfen ob Python 3 verfügbar ist
python3 --version

# Überprüfen ob tkinter verfügbar ist
python3 -c "import tkinter; print('OK')"

# Display-Variable prüfen (Linux)
echo $DISPLAY
```

**Server-Steuerung funktioniert nicht:**
- Überprüfen ob `start.sh` existiert und ausführbar ist
- Server-Berechtigungen prüfen
- Port 25565 Verfügbarkeit prüfen

**Mods werden nicht angezeigt:**
- Überprüfen ob `mods/` Verzeichnis existiert
- Dateiberechtigungen prüfen
- GUI-Liste manuell aktualisieren

**Backups funktionieren nicht:**
- Schreibberechtigung für `backups/` Verzeichnis
- Genügend freier Speicherplatz
- ZIP-Tool Verfügbarkeit prüfen

### Debug-Modus
```bash
# GUI mit Debug-Ausgabe starten
python3 tools/server_gui.py --verbose

# Setup-Skript mit Verbose-Logging
./universalServerSetup.sh --verbose --log-file debug.log
```

### Log-Dateien
- `logs/install-*.log` - Setup-Protokolle
- `logs/missing-mods.txt` - Fehlgeschlagene Mod-Downloads
- `.gui_pid` - Aktuelle GUI-Prozess-ID
- Server-Console-Output in GUI - Live-Server-Ausgabe

## Entwicklung & Beitrag

### Code-Struktur
```
tools/
├── server_gui.py      # Haupt-GUI-Anwendung
├── start_gui.py       # Standalone-Launcher
└── cf_downloader.py   # Mod-Download-Helfer
```

### Erweiterungen
Die GUI ist modular aufgebaut und kann einfach erweitert werden:
- Neue Tabs hinzufügen
- Zusätzliche Server-Properties unterstützen
- Plugin-System für Mod-Management
- Erweiterte Monitoring-Features

### Testing
```bash
# GUI ohne Server testen
python3 tools/server_gui.py --test-mode

# Setup mit Dry-Run
./universalServerSetup.sh --dry-run --gui MyModpack.zip
```

## Lizenz

Diese GUI ist Teil des universalServerSetup.sh Projekts und steht unter derselben Lizenz.