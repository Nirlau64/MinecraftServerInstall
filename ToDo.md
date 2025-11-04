# ToDo – Verbesserungen für das Setup-Skript

Dieses Dokument beschreibt eigenständig und vollständig die anstehenden Verbesserungen am Bash-Skript zur automatisierten Einrichtung eines modded Minecraft-Servers. Es ist ohne weitere Referenzen verständlich.

Zentrale Skripte/Dateien:
- Hauptskript: `universalServerSetup.sh`
- Startskript: `start.sh` (wird vom Hauptskript erzeugt/aktualisiert)
- Optional: `tools/cf_downloader.py` (Python-Helfer für Mod-Downloads)

---

## Kurzreferenz: Flags & Umgebungsvariablen (geplant)

- Unattended/Prompts:
  - `--yes` (alle Prompts = Ja), `--assume-no` (alle Prompts = Nein)
  - `--no-eula-prompt` in Kombination mit `--eula=true|false`
  - `--force` (überschreibt/ersetzt ohne Rückfragen)
  - `--dry-run` (nur anzeigen, keine Änderungen)
- RAM:
  - `--ram <SIZE>` (z. B. `4G`, `8192M`), ENV: `RAM=<SIZE>`
- Logging:
  - `--verbose`, `--quiet`, `--log-file <pfad>`
- Betrieb:
  - `--systemd` (Unit-Datei erzeugen), `--tmux` (tmux-Session starten)
- Welten/Backups:
  - `--world <name>`, `--restore <zip>`, optional `--pre-backup`
- Mods:
  - `--auto-download-mods` (automatischer Download aus `manifest.json`)
- EULA/Non-TTY Defaults (ENV):
  - `AUTO_YES=1`, `EULA=true|false`

---

## 1) Nicht-interaktiver/Automatik-Modus

Ziel: Das Skript muss unbeaufsichtigt (z. B. in CI, Cron oder ohne TTY) zuverlässig durchlaufen.

- [x] Flags implementieren: `--yes`, `--assume-no`, `--no-eula-prompt` + `--eula=true|false`, `--force`, `--dry-run`.
- [x] Prompts über zentrale Funktion steuern, die TTY, Flags und ENV berücksichtigt.
- [x] ENV-Fallbacks unterstützen: `AUTO_YES=1`, `EULA=true|false`.

Akzeptanzkriterien:
- Ausführung mit `--yes --eula=true --force` läuft ohne Nutzereingaben durch (für Server-Pack und Client-Export).
- Ohne TTY werden keine Prompts angezeigt; Defaults/Flags/ENV greifen korrekt.

---

## 2) Konfigurierbare RAM‑Zuteilung

Ziel: RAM nicht nur dynamisch (75 %), sondern auch explizit konfigurierbar.

- [x] Flag `--ram <SIZE>` (z. B. `6G`, `8192M`) und ENV `RAM=<SIZE>` respektieren.
- [x] Validierung: Einheit `G`/`M`, Minimum 1G, konfigurierbares Maximum (Default 32G).
- [x] `start.sh` nutzt dieselbe Quelle/Logik, um Doppelimplementierung zu vermeiden.

Akzeptanzkriterien:
- `--ram 6G` führt zu `-Xms6G -Xmx6G` (Erstlauf und `start.sh`).
- Ohne Angaben bleibt die 75-%-Erkennung aktiv.

---

## 3) Besseres Logging (Datei + Farbe)

Ziel: Höhere Transparenz bei Installation, Fehlern und Warnungen.

- [x] Logger mit Zeitstempeln (`[YYYY-MM-DD HH:MM:SS] LEVEL: Nachricht`).
- [x] Logdatei in `logs/install-YYYYmmdd-HHMMSS.log` (Verzeichnis automatisch anlegen).
- [x] Farbige Konsole (grün=OK, gelb=Warn, rot=Fehler), ohne TTY automatisch deaktiviert.
- [x] Loggt Kernschritte: Java-Setup, Loader-Installation, Datei-Kopien, EULA, First-Run.

Akzeptanzkriterien:
- Bei jedem Lauf entsteht ein vollständiges Log; Fehler/Warnungen sind farblich markiert (sofern TTY).
- `--quiet` reduziert, `--verbose` erhöht die Detailtiefe.

---

## 4) systemd/tmux‑Integration (optional)


Ziel: Betrieb als Dienst oder in einer abgekoppelten Session vereinfachen.

- [x] `--systemd` erzeugt `./dist/minecraft.service` (nur Schreiben ins Repo-Verzeichnis):
  - Enthält User, Arbeitsverzeichnis, `JAVA_ARGS`/`RAM`, Aufruf von `./start.sh`.
  - Hinweis zur Installation: `sudo cp`, `systemctl enable --now`.
- [x] `--tmux` startet/erstellt Session `minecraft` und führt `./start.sh` darin aus.
- [x] Kollisionserkennung: vorhandene tmux-Session/Dienst wird erkannt und gemeldet.

Akzeptanzkriterien:
- Mit `--systemd` entsteht eine funktionierende Unit-Datei; automatische Neustarts bei Crash sind konfiguriert.
- Mit `--tmux` läuft der Server in einer Session; `tmux attach -t minecraft` zeigt die Konsole.

---

## 5) `server.properties`‑Template und Konfigurationsquelle

Ziel: Sinnvolle Defaults und einfache Steuerung über Datei.

- [x] Falls `server.properties` fehlt: Template mit gängigen Einstellungen (difficulty, pvp, motd, view-distance, white-list, etc.).
- [x] Konfigurationsquellen: `.env` (KEY=VALUE) optional `server.yml`.
- [x] Parser (Bash/awk/kleines Helferskript) liest Werte und aktualisiert gezielt `server.properties` (idempotent).
- [x] Level-Name/Seed/World-Type abbilden (Übergang zu Multi-World).

Akzeptanzkriterien:
- Änderungen in `.env` (z. B. `DIFFICULTY=hard`) werden korrekt in `server.properties` übernommen.
- Erneuter Lauf überschreibt nur konfigurierte Keys, andere bleiben unverändert.

---

## 6) Multi‑World & Backups

Ziel: Mehrere Welten komfortabel verwalten und sichern.

- [x] Flag `--world <name>` bzw. ENV `WORLD=<name>` → setzt `level-name=<name>`.
- [x] Funktion `backup()` komprimiert `world/` bzw. `<name>/` nach `backups/<name>-YYYYmmdd-HHMMSS.zip`.
- [x] `--pre-backup` ermöglicht automatisches Backup vor größeren Änderungen (z. B. Mod-Updates).
- [x] `--restore <zip>` entpackt ZIP ins Ziel (mit Bestätigung/`--force`).

Akzeptanzkriterien:
- `--world creative1` nutzt/erzeugt die korrekte Welt.
- Backups haben konsistente Namen; Restore stellt die Welt zuverlässig wieder her.

---

## 7) Automatischer Mod‑Download (ohne offizielle CurseForge‑API)

Ziel: Mods aus `manifest.json` optional automatisiert herunterladen.

- [x] Python-Helfer `tools/cf_downloader.py`:
  - Liest `manifest.json` (Client-Export) und iteriert über `(projectID, fileID)`.
  - Versucht direkten Download unter
    `https://www.curseforge.com/api/v1/mods/{projectID}/files/{fileID}/download`.
  - Optional: Metadaten via `https://api.cfwidget.com/{projectID}` fürs Logging.
  - Fallback bei 404 auf „neuste kompatible Version" (heuristisch, mit deutlichem Log-Hinweis).
  - Fehlerbehandlung inkl. Backoff, Skip-/Resume-Liste.
- [x] Integration per Flag `--auto-download-mods` (nur wenn `manifest.json` vorhanden).
- [x] Ziel `./mods/`; fehlgeschlagene Downloads landen in `logs/missing-mods.txt`.
- [x] Fehler einzelner Mods brechen den Gesamtlauf nicht ab.

Akzeptanzkriterien:
- Für typische Client-Exports werden die meisten Mods automatisch nach `mods/` geladen.
- HTTP-/Strukturfehler werden protokolliert; der Rest des Prozesses bleibt konsistent.

Hinweis:
- Es werden bewusst inoffizielle, öffentlich erreichbare Endpunkte genutzt. Diese können sich ändern oder Ratenbegrenzungen haben; das Feature bleibt optional und dokumentiert.

**Implementierungsdetails:**
- Separates Python-Skript `tools/cf_downloader.py` mit minimaler Abhängigkeit (nur Python 3 Standard Library)
- **Automatische Python 3 Installation**: Script installiert Python 3 automatisch falls nicht vorhanden und entfernt es nach Abschluss
- **Cleanup-Mechanismus**: Exit-Trap sorgt für Aufräumen von Python 3 auch bei unerwarteten Skript-Abbrüchen
- **Multi-Plattform Support**: Unterstützt apt, dnf, yum, pacman, zypper, und Homebrew für Python 3 Installation
- Graceful Fallback: Bei Fehlern (Python 3 Installation fehlschlägt, Skript nicht gefunden, Download-Fehler) wird der normale Installationspfad fortgesetzt
- Comprehensive Logging und Fehlerbehandlung mit detailliertem Reporting in `logs/missing-mods.txt`
- Rate Limiting und Retry-Logik für Stabilität
- Timeout-Schutz (30 Minuten) um hängende Downloads zu vermeiden

---

## 8) Verbesserte Fehlerbehandlung (robust)

Ziel: Frühzeitig typische Fehler erkennen, klar kommunizieren und sauber abbrechen.

- [x] Vorab-Prüfungen:
  - Freier Speicherplatz im Ziel (`df -Pm .`), ggf. Warnung/Abbruch.
  - ZIP-Validität (`unzip -tq`).
  - Port-Check 25565 (`ss -ltn | grep :25565`) bzw. bestehender Serverprozess.
- [x] `require_cmd` erweitert um OS-spezifische Install-Hinweise bei fehlenden Tools.
- [x] Cleanup-Routine bei Abbruch (Workdir/Tempdateien zuverlässig entfernen).
- [x] Konsistente Exit-Codes (z. B. 2=Prereq, 3=Download, 4=Install, 5=EULA, 6=Start).

Akzeptanzkriterien:
- Fehler führen zu klaren, farbigen Meldungen inkl. Ursache/Nächste Schritte; Details im Log.
- Temporäre Artefakte werden auch bei Abbruch entfernt.

**Implementiert:**
- **Pre-flight checks**: 
  - Disk space check (2GB minimum) with multiple df format support (GNU, POSIX, BSD)
  - ZIP integrity validation using `unzip -tq`
  - Port 25565 availability check using ss/netstat
  - Existing server process detection using pgrep/ps
- **Enhanced require_cmd**: OS-specific installation hints for missing tools supporting:
  - apt-get (Debian/Ubuntu)
  - dnf (Fedora/RHEL 8+)
  - yum (CentOS/RHEL 7)
  - pacman (Arch Linux)
  - zypper (openSUSE/SUSE)
  - brew (macOS/Homebrew)
- **Robust cleanup**: Enhanced EXIT trap that:
  - Removes temporary work directories safely
  - Cleans up temp files (_fabric.json, .temp_*)
  - Removes Python 3 if automatically installed by script
  - Preserves exit codes and logs cleanup status
- **Consistent exit codes**: 
  - EXIT_SUCCESS(0) - Normal completion
  - EXIT_GENERAL(1) - General errors
  - EXIT_PREREQ(2) - Prerequisites/validation failures
  - EXIT_DOWNLOAD(3) - Download failures
  - EXIT_INSTALL(4) - Installation failures
  - EXIT_EULA(5) - EULA related issues
  - EXIT_START(6) - Server startup failures
- **Help system**: 
  - Added --help/-h flag with comprehensive usage examples
  - --version flag for version information
  - Detailed parameter documentation and environment variables
- **Better error messages**: 
  - Contextual error information with specific next steps
  - OS-specific installation commands for missing dependencies
  - Detailed logging of error conditions and suggested solutions
  - Graceful fallbacks when system commands are unavailable

---

## Artefakte & Änderungen (Ergebnis der Implementierung)

- `universalServerSetup.sh`: Flags, Logging, Konfig-Parsing, Backups, Integrationen.
- `start.sh`: Einheitliche RAM/ENV-Handhabung, nutzt dieselbe Logik wie das Hauptskript.
- `tools/cf_downloader.py` (optional): Automatischer Mod-Download.
- `dist/minecraft.service` (optional): systemd-Unit-Template.
- `logs/install-*.log`, `logs/missing-mods.txt`: Protokolle.


---

## 9) Optionale GUI zur Serververwaltung ✅

Ziel: Eine kleine, optionale (standardmäßig aktivierte) grafische Oberfläche zur Verwaltung des Servers nach dem Start (Welten, Backups, Logs, Start/Stop, etc.).

- [x] GUI-Framework auswählen: **Python/Tkinter** (lightweight, keine zusätzlichen Installationen)
- [x] Integration als separater Prozess, der nach dem Setup automatisch startet (deaktivierbar per Flag/ENV)
- [x] **Vollständige Server-Setup-Konfiguration:** GUI ermöglicht Änderung aller Setup-Parameter und Startparameter
- [x] Features:
  - [x] **Server Setup & Konfiguration:** Vollständige GUI für alle Setup-Parameter (server.properties, Speicher, EULA, etc.)
  - [x] **Server-Steuerung:** Start/Stop/Restart/Force Kill mit Konsolen-Integration
  - [x] **Weltverwaltung:** Wechseln, Backup erstellen, Löschen, Liste verfügbarer Welten
  - [x] **Backup-Management:** Erstellen, Wiederherstellen, Löschen, Import von externen Backups
  - [x] **Log-Viewer:** Anzeige aller Logs (install.log, missing-mods.txt, server.log, etc.)
  - [x] **Mod-Management:** Anzeige installierter Mods, Hinzufügen/Entfernen, Auto-Download aus manifest.json
  - [x] **Echtzeit-Serverstatus:** Status-Monitoring und Ressourcenverbrauch
  - [x] **Konfigurationsverwaltung:** Speichern/Laden von Konfigurationen, Reset zu Defaults
- [x] Kommunikation mit Server über Shell-Kommandos und Dateien
- [x] Headless-Erkennung: GUI startet nur, wenn Display verfügbar ist
- [x] Konfigurierbarkeit: Standardmäßig aktiv, aber per `--no-gui`/`GUI=0` deaktivierbar
- [x] Robuste Fehlerbehandlung und automatisches Cleanup bei Skript-Abbruch

**Implementierte GUI-Features:**
- **Tab-basierte Oberfläche** mit 5 Hauptbereichen:
  1. **Setup & Konfiguration:** Vollständige Konfiguration aller Server-Parameter
  2. **Server-Steuerung:** Live-Konsole mit Befehls-Input und Ausgabe
  3. **Welt-Management:** Verwaltung von Welten und Backups
  4. **Mod-Management:** Übersicht und Verwaltung installierter Mods
  5. **Logs & Monitoring:** Log-Viewer mit verschiedenen Log-Dateien
- **Vollständige Pre-Setup Integration:**
  - **Setup-Wizard:** GUI kann vor Server-Installation gestartet werden
  - **Intelligente Erkennung:** Unterscheidet zwischen neuer Installation und existierendem Server
  - **Welcome-Message:** Benutzerführung für neue Installationen
  - **Setup-Validation:** Validierung aller Einstellungen vor Setup-Start
  - **Visuelle Fortschrittsanzeige:** Progress-Bar und Status-Updates während Setup
  - **Automatische Aktualisierung:** Alle Tabs werden nach erfolgreichem Setup aktualisiert
- **Robuste Launchers:**
  - `start_gui.sh`: Bash-Skript mit Dependency-Checks und Fehlerbehebungshinweisen
  - `start_gui.py`: Python-Launcher mit automatischer Pfaderkennung
  - Automatische Verzeichniserstellung falls nicht vorhanden
- **Konfigurationsspeicherung:** Einstellungen werden in .env-Dateien gespeichert
- **Robuste Integration:** Automatischer Start nach Setup, Cleanup bei Fehlern
- **Cross-Platform:** Funktioniert auf Linux, macOS und Windows

Akzeptanzkriterien: ✅✅
- Nach dem Setup ist die GUI verfügbar und kann alle Verwaltungsaufgaben ausführen
- GUI ist optional und kann für reine Server-/CI-Nutzung deaktiviert werden
- **Zusätzlich:** GUI ermöglicht vollständige Rekonfiguration des Servers ohne Kommandozeile
- **🎯 VOLLSTÄNDIGE PRE-SETUP INTEGRATION:** GUI kann VOR dem Setup gestartet werden und das komplette Setup anstoßen
- **🚀 EINHEITLICHER WORKFLOW:** Benutzer können ausschließlich über die GUI arbeiten - von der ersten Installation bis zur laufenden Verwaltung

---

## Dokumentation

- `README.md` ergänzen: neue Flags/ENV, Nutzung von systemd/tmux, Hinweise zum optionalen Mod-Download und zur GUI.
- Beispiele aufführen (interaktiv vs. unattended) und typische Fehlerbilder + Lösungen.
