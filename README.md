universalServerSetup_merged.sh
================================

Overview
--------
This script merges two utilities:

- download_modrinth.sh — examines a CurseForge client export's `modlist.html`,
  queries Modrinth for matching projects and attempts to install available mods
  using `packwiz`.
- universalServerSetup (Working with Copy) — unpacks a client export, installs
  server loader (Forge/Fabric/NeoForge), copies overrides (mods/config/etc.),
  creates a portable `start.sh`, and optionally runs the server once to finish
  setup.

The merged script tries to run both flows as appropriate for the provided
archive.

Quick start
-----------
1. Open a bash-capable shell (Linux/macOS, or WSL/Git Bash on Windows).
2. Ensure required tools are installed and on PATH:
   - unzip, curl, jq, rsync, packwiz, java
3. Make the script executable (if needed):

   chmod +x "universalServerSetup_merged.sh"

4. Run the script with your pack export ZIP:

   ./universalServerSetup_merged.sh "MyPackExport.zip"

5. Follow interactive prompts (EULA acceptance, optional first run).

Help and options
----------------
Run with `-h` or `--help` to see a short usage message:

  ./universalServerSetup_merged.sh --help

Notes & troubleshooting
-----------------------
- On Windows, prefer running inside WSL or Git Bash with the required tools
  installed. Native PowerShell/CMD do not provide the required unix utilities.
- `packwiz` must be configured and accessible on PATH for Modrinth installs.
- The script tries to detect and install Java using common package managers on
  Linux (apt/dnf/pacman/zypper). If your environment doesn't support these,
  install the correct Java manually.
- The Modrinth step is best-effort: missing mods (not on Modrinth) are
  reported and must be imported manually (e.g., from CurseForge).

Safety
------
- The script intentionally uses `|| true` for non-fatal steps so one failing
  mod or optional install step won't completely abort the flow. Review output
  carefully and re-run specific steps manually if needed.

Contributing
------------
If you want changes (extra options, more robust packwiz cache detection, or
Windows-native support), tell me what you prefer and I can add it.
