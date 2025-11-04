# MinecraftServerInstall

This repository contains a comprehensive universal Bash script for installing and configuring modded Minecraft servers on Linux.
It supports **Forge**, **NeoForge**, **Fabric**, and **Quilt** loaders and can handle both server packs and client exports from CurseForge/Modrinth.

## Features

### Core Functionality
* **Universal mod loader support**: Forge, NeoForge, Fabric, and Quilt
* **Automatic Java detection**: Installs the correct Java version (8, 17, or 21) based on Minecraft version
* **Smart pack detection**: Handles both server packs and client exports automatically
* **Robust file handling**: Intelligent copying of mods, configs, and other assets
* **Dynamic memory allocation**: Automatically allocates 75% of system RAM (configurable)

### Advanced Features
* **Non-interactive mode**: Full automation support for CI/CD and unattended deployments
* **Comprehensive logging**: Timestamped logs with color output and file logging
* **Backup system**: Automatic world backups with configurable intervals and retention
* **Multi-world support**: Easy switching between different worlds
* **systemd integration**: Generate service files for automatic startup and management
* **tmux integration**: Run server in detached sessions
* **Server properties templating**: Smart configuration management with environment variable support
* **Operator management**: Automatic operator assignment and permission handling

## Quick Start

> 📖 **Für einen kompletten Workflow-Guide mit allen Möglichkeiten und Szenarien**, siehe: **[WORKFLOW_COMPLETE.md](WORKFLOW_COMPLETE.md)**

### GUI Mode (Recommended for beginners)
```bash
# Start the GUI - works even before server setup
./start_gui.sh

# Or use Python directly
python3 tools/server_gui.py

# GUI handles everything: configuration, setup, and management
```

### Command Line Mode
```bash
# Basic usage with a modpack
./universalServerSetup.sh MyModpack.zip

# Non-interactive installation
./universalServerSetup.sh --yes --eula=true MyModpack.zip

# Custom RAM allocation
./universalServerSetup.sh --ram 8G MyModpack.zip

# With systemd service generation
./universalServerSetup.sh --systemd MyModpack.zip
```

## Configuration Options

### Script Configuration (edit at top of script)

The setup script has a comprehensive CONFIG section at the top:

**Basic Settings:**
- `ZIP`: Path to the modpack zip file (can be overridden via CLI argument)
- `OP_USERNAME`: Minecraft username to grant operator rights automatically
- `OP_LEVEL`: Operator permission level (1-4, default: 4)
- `ALWAYS_OP_USERS`: Space-separated list of users to always grant OP status

**Non-interactive Defaults:**
- `AUTO_ACCEPT_EULA`: Accept EULA automatically when no terminal is available ("yes"/"no")
- `AUTO_FIRST_RUN`: Run server automatically after setup when no terminal is available ("yes"/"no")

**Memory Configuration:**
- `JAVA_ARGS`: Custom JVM arguments (overrides automatic memory sizing)
- `MEMORY_PERCENT`: Percentage of system RAM to allocate (default: 75%)
- `MIN_MEMORY_MB`: Minimum RAM allocation (default: 2048MB)
- `MAX_MEMORY_MB`: Maximum RAM allocation (default: 32768MB)

**Backup Settings:**
- `BACKUP_INTERVAL_HOURS`: Automatic backup interval (default: 4 hours)
- `BACKUP_RETENTION`: Number of backups to keep (default: 12)

**Server Properties Defaults:**
- `PROP_MOTD`: Server message of the day
- `PROP_DIFFICULTY`: Game difficulty (peaceful, easy, normal, hard)
- `PROP_PVP`: Enable PvP (true/false)
- `PROP_VIEW_DISTANCE`: Server view distance (default: 10)
- `PROP_MAX_PLAYERS`: Maximum number of players (default: 20)
- And many more server.properties options...

## Graphical User Interface (GUI)

### 🎮 Complete Server Management GUI

This project includes a **comprehensive graphical interface** that allows you to manage your entire Minecraft server without using the command line!

**Key Features:**
- **Complete Setup Wizard**: Configure and install servers entirely through GUI
- **Real-time Configuration**: Edit all server properties visually  
- **Server Control**: Start/Stop/Restart with live console output
- **World Management**: Create backups, restore worlds, switch between worlds
- **Mod Management**: View installed mods, add/remove mods, auto-download from modpacks
- **Log Viewer**: Browse all server logs and installation logs
- **Configuration Profiles**: Save/load different server configurations

**Starting the GUI:**
```bash
# Easy launcher (recommended)
./start_gui.sh

# Direct Python execution  
python3 tools/server_gui.py [server_directory]

# From any directory
python3 /path/to/tools/start_gui.py /path/to/server
```

**GUI Workflow:**
1. **Start GUI** before or after server setup
2. **Configure Settings** in the "Setup & Configuration" tab
3. **Select Modpack** (optional) or leave empty for vanilla
4. **Run Setup** - GUI executes the setup script with your settings
5. **Manage Server** using the other tabs after setup

The GUI **automatically handles**:
- ✅ Server setup validation and error checking
- ✅ Progress tracking with visual feedback  
- ✅ Configuration persistence (saves to `.env` files)
- ✅ Live server console with command input
- ✅ Automatic refresh after setup completion
- ✅ Headless server detection (disables GUI appropriately)

**GUI Requirements:**
- Python 3.6+ with tkinter (usually included)
- For headless servers: X11 forwarding (`ssh -X`) or local display

## Requirements

* Linux system or VPS with sufficient storage and port `25565` available
* Required tools: `bash`, `unzip`, `curl`, `jq`, `rsync`
* `sudo` rights for Java installation (if needed)
* Internet connection for downloads
* Write permissions in the working directory
* **For GUI**: Python 3.6+ with tkinter (auto-detected)

## Installation & Usage

### Basic Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Nirlau64/MinecraftServerInstall.git
   cd MinecraftServerInstall
   ```

2. **Run with a modpack:**
   ```bash
   ./universalServerSetup.sh MyModpack.zip
   ```

The script will automatically:
- Detect if the ZIP contains a server pack or client export
- Install the appropriate Java version for the Minecraft version
- Download and install the correct mod loader (Forge/NeoForge/Fabric/Quilt)
- Copy all mods, configs, and other assets
- Generate startup scripts and configuration files
- Optionally run the server for initial setup

### Command Line Options

#### Essential Flags
- `--yes` / `-y`: Answer "yes" to all prompts (non-interactive mode)
- `--assume-no`: Answer "no" to all prompts
- `--force`: Overwrite existing files without asking
- `--dry-run`: Show what would be done without making changes

#### EULA Handling
- `--eula=true|false`: Set EULA acceptance explicitly
- `--no-eula-prompt`: Skip EULA prompt (use with `--eula`)

#### Memory Configuration
- `--ram <SIZE>`: Set specific RAM amount (e.g., `--ram 8G`, `--ram 4096M`)
- Environment: `JAVA_ARGS="-Xms8G -Xmx8G"`

#### Logging
- `--verbose`: Increase logging detail
- `--quiet`: Reduce logging output
- `--log-file <path>`: Custom log file location

#### Service Integration
- `--systemd`: Generate systemd service file
- `--tmux`: Start server in tmux session

#### Automatic Mod Download (Experimental)
- `--auto-download-mods`: Automatically download mods from manifest.json using unofficial CurseForge endpoints

#### World & Backup Management
- `--world <name>`: Use specific world name
- `--pre-backup`: Create backup before installation
- `--restore <backup.zip>`: Restore world from backup

#### Server Properties
You can override any server property via command line:
```bash
--motd="My Awesome Server" --difficulty=hard --max-players=50 --pvp=false
```

### Environment Variables

All configuration can be controlled via environment variables:

```bash
# Non-interactive setup
export AUTO_ACCEPT_EULA=yes
export AUTO_FIRST_RUN=yes
export ASSUME_YES=1

# Memory configuration
export MEMORY_PERCENT=80
export MIN_MEMORY_MB=4096
export MAX_MEMORY_MB=16384

# Operator settings
export OP_USERNAME=myplayer
export ALWAYS_OP_USERS="admin1 admin2 moderator1"

# Server properties
export PROP_DIFFICULTY=hard
export PROP_MAX_PLAYERS=50
export PROP_MOTD="My Server"

# Run the script
./universalServerSetup\ -\ Working.sh MyModpack.zip
```

## Usage Examples

### Interactive Installation
```bash
# Standard interactive setup
./universalServerSetup.sh MyModpack.zip
```
The script will prompt for EULA acceptance and first run confirmation.

### Automated/CI Installation
```bash
# Fully automated setup for CI/CD
./universalServerSetup.sh --yes --eula=true --force MyModpack.zip

# With custom RAM and systemd service
./universalServerSetup.sh --yes --eula=true --ram 16G --systemd MyModpack.zip
```

### Development/Testing
```bash
# Dry run to see what would happen
./universalServerSetup.sh --dry-run MyModpack.zip

# Verbose logging for troubleshooting
./universalServerSetup.sh --verbose --log-file debug.log MyModpack.zip
```

### World Management
```bash
# Create backup before major changes
./universalServerSetup.sh --pre-backup --world survival MyModpack.zip

# Restore from backup
./universalServerSetup.sh --restore backups/survival-20241104-143022.zip
```

### Automatic Mod Download (Experimental)
```bash
# Enable automatic mod downloading (Python 3 auto-installed if needed)
./universalServerSetup.sh --auto-download-mods MyClientExport.zip

# Combined with other options
./universalServerSetup.sh --yes --eula=true --auto-download-mods --verbose MyClientExport.zip

# Manual download of specific mods (standalone usage)
python3 tools/cf_downloader.py manifest.json ./mods --verbose
```

**Note**: 
- Automatic mod download is experimental and uses unofficial CurseForge endpoints
- Python 3 is automatically installed if missing and removed after completion
- Failed downloads are logged to `logs/missing-mods.txt` with manual download links
- Requires `sudo` access for Python 3 installation if not already present

## Directory Structure

### Before Installation
```
MinecraftServerInstall/
├── universalServerSetup.sh
├── MyModpack.zip
├── README.md
└── ToDo.md
```

### After Installation
```
MinecraftServerInstall/
├── universalServerSetup.sh
├── start.sh                     # Generated startup script
├── .server_functions.sh         # Shared functions
├── .server_jar                  # Server jar name cache
├── eula.txt
├── server.properties            # Generated from template
├── ops.json                     # Generated if operators configured
├── mods/                        # All mod files from modpack
│   ├── mod1.jar
│   └── mod2.jar
├── config/                      # Configuration files
│   ├── forge-common.toml
│   └── mod-configs/
├── logs/                        # Server and installation logs
│   ├── install-20241104-143022.log
│   └── latest.log
├── backups/                     # Automatic world backups
│   └── world-20241104-120000.zip
├── world/                       # Default world (or custom name)
├── libraries/                   # Mod loader libraries
├── forge-xx.x.x-xx.x.x.jar    # Server jar (varies by loader)
└── dist/                        # Optional service files
    └── minecraft.service
```

## Generated Files

### start.sh
The generated startup script includes:
- Automatic server jar detection
- Dynamic memory allocation
- Periodic backup system
- Proper error handling and logging

### .server_functions.sh
Shared functions used by both the setup script and startup script:
- Memory calculation logic
- Server jar detection
- Backup functions
- Cross-platform compatibility helpers

### systemd Service (optional)
When using `--systemd`, generates `dist/minecraft.service` with:
- Proper user and working directory configuration
- Memory settings from installation
- Automatic restart on failure
- Integration with system logging

## Advanced Features

### Automatic Backup System
- Configurable backup intervals (default: every 4 hours)
- Automatic retention management (default: keep 12 backups)
- Backups are compressed ZIP files with timestamps
- World restoration from any backup with `--restore`

### Multi-World Support
- Easy switching between different worlds via `--world <name>`
- Automatic `server.properties` updates for world configuration
- Backup and restore operations work with any world name

### Service Integration
- **systemd**: Generate complete service files for production deployment
- **tmux**: Run in detached sessions with easy attachment
- Proper signal handling and graceful shutdown support

### Smart Configuration Management
- Template-based `server.properties` generation
- Environment variable integration for all settings
- Preservation of manual changes during script re-runs
- Command-line overrides for all server properties

### Automatic Mod Download (Experimental)
- **Optional mod downloading**: Use `--auto-download-mods` with client exports
- **Automatic Python 3 management**: Installs Python 3 if missing, removes it after completion
- **Unofficial CurseForge endpoints**: Downloads mods directly from project/file IDs in manifest.json
- **Intelligent fallback**: Falls back to latest compatible version if specific file not found
- **Robust error handling**: Failed downloads don't break installation, logged to `logs/missing-mods.txt`
- **Rate limiting**: Built-in delays and retry logic to avoid overwhelming servers
- **Clean system state**: Automatically removes Python 3 if installed by the script
- **Graceful degradation**: Falls back to manual installation if Python 3 installation fails
- **Requirements**: None (Python 3 auto-installed if needed using system package manager)

## Supported Configurations

### Mod Loaders
- ✅ **Forge** (all versions)
- ✅ **NeoForge** (1.20.1+)
- ✅ **Fabric** (all versions)  
- ✅ **Quilt** (all versions)

### Minecraft Versions
- ✅ **1.7.10 - 1.16.5**: Java 8 (auto-installed)
- ✅ **1.17 - 1.20.4**: Java 17 (auto-installed)
- ✅ **1.20.5+**: Java 21 (auto-installed)

### Pack Types
- ✅ **Server Packs**: Direct installation with existing startup scripts
- ✅ **Client Exports**: Automatic conversion from CurseForge/Modrinth exports
- ✅ **Manual Setups**: Works with custom mod configurations

### Operating Systems
- ✅ **Linux** (primary target)
- ✅ **macOS** (with Homebrew)
- ⚠️ **Windows** (WSL recommended)

## Troubleshooting

### Common Issues

**Java Installation Fails:**
```bash
# Check available Java versions
java -version
# Manual Java installation may be required on some systems
```

**Port 25565 Already in Use:**
```bash
# Check for existing Minecraft servers
ss -tlnp | grep :25565
# Stop existing servers before running the script
```

**Missing Dependencies:**
```bash
# Install required tools (Ubuntu/Debian)
sudo apt update
sudo apt install unzip curl jq rsync

# Install required tools (CentOS/RHEL)
sudo yum install unzip curl jq rsync
```

**Permission Issues:**
```bash
# Ensure proper permissions
chmod +x universalServerSetup.sh
# Run with appropriate user privileges
```

**Automatic Mod Download Issues:**
```bash
# Python 3 is automatically installed/removed as needed
# If installation fails, check system package manager access
sudo apt update  # or equivalent for your system

# Manual mod download if automatic fails
python3 tools/cf_downloader.py manifest.json ./mods --verbose

# Check failed downloads
cat logs/missing-mods.txt

# Force manual Python 3 installation if auto-install fails
sudo apt install python3  # Ubuntu/Debian
sudo dnf install python3  # Fedora
sudo yum install python3  # CentOS/RHEL
sudo pacman -S python     # Arch Linux
```

### Log Analysis
- Installation logs: `logs/install-YYYYMMDD-HHMMSS.log`
- Server logs: `logs/latest.log`
- Missing mods log: `logs/missing-mods.txt` (when using `--auto-download-mods`)
- Debug mode: Use `--verbose` for detailed output
- Dry run: Use `--dry-run` to preview changes

### Getting Help
- Check the comprehensive logs in the `logs/` directory
- Use `--verbose` mode for detailed debugging information
- Review the configuration section at the top of the script
- Consult the ToDo.md file for known limitations and planned features

## Notes & Best Practices

- **Testing**: Always test with `--dry-run` before production deployment
- **Backups**: Enable automatic backups for production servers (`BACKUP_INTERVAL_HOURS`)
- **Security**: Configure proper firewalls and user permissions
- **Performance**: Adjust `MEMORY_PERCENT` based on server usage patterns
- **Updates**: Re-run the script with new modpack versions to update existing installations
- **Monitoring**: Use systemd integration for production deployments with proper logging

## Contributing

We welcome contributions! Please:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Setup
```bash
# Clone your fork
git clone https://github.com/yourusername/MinecraftServerInstall.git
cd MinecraftServerInstall

# Test your changes
./universalServerSetup.sh --dry-run test-modpack.zip
```

## Support

- 🐛 **Bug Reports**: Open an issue with detailed logs and system information
- 💡 **Feature Requests**: Check ToDo.md first, then open an issue
- 📖 **Documentation**: Help improve this README or script comments
- 💬 **Questions**: Use GitHub Discussions for general questions

For urgent issues, include:
- Operating system and version
- Minecraft/modpack version
- Complete installation log
- Steps to reproduce the issue

---

## 📚 Umfassende Dokumentation

**[→ Kompletter Workflow-Guide (WORKFLOW_COMPLETE.md)](WORKFLOW_COMPLETE.md)**

Dieser detaillierte Guide enthält:
- ✅ Alle verfügbaren Modi (GUI, Kommandozeile, vollautomatisch)
- ✅ Schritt-für-Schritt-Anleitungen für jeden Anwendungsfall
- ✅ Komplette Parameterliste mit Beispielen
- ✅ Szenarien für Anfänger bis Produktions-Server
- ✅ Troubleshooting & Debug-Tipps
- ✅ CI/CD-Integration und Automatisierung
