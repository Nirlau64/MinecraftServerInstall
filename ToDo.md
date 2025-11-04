# ToDo – Verbesserungen für das Setup-Skript

Dieses Dokument beschreibt eigenständig und vollständig die anstehenden Verbesserungen am Bash-Skript zur automatisierten Einrichtung eines modded Minecraft-Servers. Es ist ohne weitere Referenzen verständlich.

Zentrale Skripte/Dateien:
- Hauptskript: `universalServerSetup - Working.sh`
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

- [ ] Flag `--world <name>` bzw. ENV `WORLD=<name>` → setzt `level-name=<name>`.
- [ ] Funktion `backup()` komprimiert `world/` bzw. `<name>/` nach `backups/<name>-YYYYmmdd-HHMMSS.zip`.
- [ ] `--pre-backup` ermöglicht automatisches Backup vor größeren Änderungen (z. B. Mod-Updates).
- [ ] `--restore <zip>` entpackt ZIP ins Ziel (mit Bestätigung/`--force`).

Akzeptanzkriterien:
- `--world creative1` nutzt/erzeugt die korrekte Welt.
- Backups haben konsistente Namen; Restore stellt die Welt zuverlässig wieder her.

---

## 7) Automatischer Mod‑Download (ohne offizielle CurseForge‑API)

Ziel: Mods aus `manifest.json` optional automatisiert herunterladen.

- [ ] Python-Helfer `tools/cf_downloader.py`:
  - Liest `manifest.json` (Client-Export) und iteriert über `(projectID, fileID)`.
  - Versucht direkten Download unter
    `https://www.curseforge.com/api/v1/mods/{projectID}/files/{fileID}/download`.
  - Optional: Metadaten via `https://api.cfwidget.com/{projectID}` fürs Logging.
  - Fallback bei 404 auf „neuste kompatible Version“ (heuristisch, mit deutlichem Log-Hinweis).
  - Fehlerbehandlung inkl. Backoff, Skip-/Resume-Liste.
- [ ] Integration per Flag `--auto-download-mods` (nur wenn `manifest.json` vorhanden).
- [ ] Ziel `./mods/`; fehlgeschlagene Downloads landen in `logs/missing-mods.txt`.
- [ ] Fehler einzelner Mods brechen den Gesamtlauf nicht ab.

Akzeptanzkriterien:
- Für typische Client-Exports werden die meisten Mods automatisch nach `mods/` geladen.
- HTTP-/Strukturfehler werden protokolliert; der Rest des Prozesses bleibt konsistent.

Hinweis:
- Es werden bewusst inoffizielle, öffentlich erreichbare Endpunkte genutzt. Diese können sich ändern oder Ratenbegrenzungen haben; das Feature bleibt optional und dokumentiert.

---

## 8) Verbesserte Fehlerbehandlung (robust)

Ziel: Frühzeitig typische Fehler erkennen, klar kommunizieren und sauber abbrechen.

- [ ] Vorab-Prüfungen:
  - Freier Speicherplatz im Ziel (`df -Pm .`), ggf. Warnung/Abbruch.
  - ZIP-Validität (`unzip -tq`).
  - Port-Check 25565 (`ss -ltn | grep :25565`) bzw. bestehender Serverprozess.
- [ ] `require_cmd` erweitert um OS-spezifische Install-Hinweise bei fehlenden Tools.
- [ ] Cleanup-Routine bei Abbruch (Workdir/Tempdateien zuverlässig entfernen).
- [ ] Konsistente Exit-Codes (z. B. 2=Prereq, 3=Download, 4=Install, 5=EULA, 6=Start).

Akzeptanzkriterien:
- Fehler führen zu klaren, farbigen Meldungen inkl. Ursache/Nächste Schritte; Details im Log.
- Temporäre Artefakte werden auch bei Abbruch entfernt.

---

## Artefakte & Änderungen (Ergebnis der Implementierung)

- `universalServerSetup - Working.sh`: Flags, Logging, Konfig-Parsing, Backups, Integrationen.
- `start.sh`: Einheitliche RAM/ENV-Handhabung, nutzt dieselbe Logik wie das Hauptskript.
- `tools/cf_downloader.py` (optional): Automatischer Mod-Download.
- `dist/minecraft.service` (optional): systemd-Unit-Template.
- `logs/install-*.log`, `logs/missing-mods.txt`: Protokolle.

## Dokumentation

- `README.md` ergänzen: neue Flags/ENV, Nutzung von systemd/tmux, Hinweise zum optionalen Mod-Download.
- Beispiele aufführen (interaktiv vs. unattended) und typische Fehlerbilder + Lösungen.
