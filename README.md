# MinecraftServerInstall

This repository contains a universal Bash script for installing and configuring a Minecraft server on Linux.
It has been tested with the **Forge** and **Fabric** mod loaders and helps convert server packs or client exports from CurseForge/Modrinth into a fully functional dedicated server.

## Features

* Sets up a Minecraft server for a specified version
* Supports both **Forge** and **Fabric**
* Automatically installs the correct Java version (OpenJDK)
* Creates `eula.txt`, startup scripts, and basic server configuration
* Detects and uses existing `mods/` and `config/` folders
* Automatically starts the server after installation

## Quick config (edit at top of the script)

The setup script now has a clear CONFIG section at the top with common settings:

- ZIP: path to the modpack zip to install (can still be provided as CLI arg)
- OP_USERNAME: player name to grant operator rights to automatically (optional)
- OP_LEVEL: operator permission level (1-4, default 4)
- AUTO_ACCEPT_EULA: yes/no default used when no terminal is attached
- AUTO_FIRST_RUN: yes/no default used when no terminal is attached
- JAVA_ARGS: optional custom JVM args (else memory is sized dynamically)
- MEMORY_PERCENT, MIN_MEMORY_MB, MAX_MEMORY_MB: control dynamic memory sizing

## Requirements

* Linux system or VPS with enough storage and an open port `25565`
* Installed **bash** and **curl/wget**
* Write permissions in the working directory

## Installation & Usage

1. Clone this repository or download the script:

   ```bash
   git clone https://github.com/Nirlau64/MinecraftServerInstall.git
   cd MinecraftServerInstall
   ```
2. Adjust the script (Minecraft version, RAM allocation, mod loader, etc.)
3. Manually copy mods and configuration files into the respective folders:

   * `mods/` → all `.jar` mod files
   * `config/` → all configuration files

   > These files must be copied manually because the script cannot download mods automatically due to **CurseForge API** restrictions.
4. **Provide the Modpack ZIP:**
   When running the script, the ZIP file of the desired modpack must be passed as an argument. Example:

   ```bash
   ./universalServerSetup\ -\ Working.sh Modpack.zip
   ```

   The script will automatically unpack the ZIP file, detect its structure, and configure the server accordingly.
5. After completion, the server will start automatically.

---

## Example Directory Structure

### Before the First Script Execution

```
MinecraftServerInstall/
├── universalServerSetup - Working.sh
├── Modpack.zip
├── README.md
```

*(The ZIP file typically contains the following structure:)*

```
Modpack.zip
├── manifest.json
├── overrides/
│   ├── config/
│   │   ├── ...
│   └── mods/
│       ├── ...
```

---

### After the First Script Execution

```
MinecraftServerInstall/
├── universalServerSetup - Working.sh
├── eula.txt
├── server.properties
├── start.sh
├── mods/
│   ├── <all .jar files from Modpack>
├── config/
│   ├── <all configuration files from Modpack>
├── libraries/
├── logs/
├── world/
├── forge-1.xx.x-installer.jar   (or fabric-server-launch.jar)
├── Modpack.zip
└── README.md
```

After the first run, all necessary server files are created, and the server can be started directly via the startup script or run in the background using a process manager (e.g., `screen` or `tmux`).

---

## Notes

* The script has been successfully tested with **Forge** and **Fabric**.
* When using the CurseForge client, the generated `mods/` and `config/` folders must be **manually** copied into the server directory.
* Changing mods or configurations requires a server restart.
* It is strongly recommended to create a backup before making major changes.

## Support

For issues, suggestions, or contributions, please open an **Issue** or **Pull Request** on GitHub.
