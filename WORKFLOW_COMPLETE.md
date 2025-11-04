# Complete Minecraft Server Workflow

This comprehensive guide describes all available options for installing, configuring, and managing Minecraft servers with this tool.

## Table of Contents

1. [Overview of Available Modes](#overview-of-available-modes)
2. [Preparation & System Requirements](#preparation--system-requirements)
3. [Installation & Setup](#installation--setup)
   - [GUI Mode (Recommended for Beginners)](#gui-mode-recommended-for-beginners)
   - [Command Line Mode](#command-line-mode)
   - [Fully Automated Mode (CI/CD)](#fully-automated-mode-cicd)
4. [All Available Parameters](#all-available-parameters)
5. [Configuration Options](#configuration-options)
6. [Scenarios & Use Cases](#scenarios--use-cases)
7. [After Installation](#after-installation)
8. [Troubleshooting & Logs](#troubleshooting--logs)

---

## Overview of Available Modes

### 🎮 **GUI Mode** (Graphical User Interface)
- **Target Audience**: Beginners, local usage
- **Advantages**: Intuitive operation, visual configuration, live server management
- **Disadvantages**: Requires graphical interface

### ⌨️ **Command Line Mode** (Interactive)
- **Target Audience**: Experienced users, SSH connections
- **Advantages**: Flexible, works everywhere
- **Disadvantages**: Requires command line knowledge

### 🤖 **Fully Automated Mode** (Non-Interactive)
- **Target Audience**: CI/CD pipelines, automation
- **Advantages**: No user interaction required
- **Disadvantages**: All parameters must be configured in advance

---

## Preparation & System Requirements

### System Requirements
```bash
# Basic tools (automatically installed if missing)
- bash (4.0+)
- unzip
- curl
- jq
- rsync

# For GUI mode additionally
- Python 3.6+
- tkinter (usually pre-installed)

# System resources
- At least 2GB RAM (recommended: 4GB+)
- 1GB free disk space (more depending on modpack)
- Port 25565 available
- Internet connection for downloads
```

### Clone Repository
```bash
git clone https://github.com/Nirlau64/MinecraftServerInstall.git
cd MinecraftServerInstall
chmod +x universalServerSetup.sh
chmod +x start_gui.sh
```

---

## Installation & Setup

## GUI Mode (Recommended for Beginners)

### 🚀 **Easiest Way: Complete GUI Installation**

```bash
# Start GUI (works before and after server setup)
./start_gui.sh

# Or directly with Python
python3 tools/server_gui.py
```

**GUI Workflow Step-by-Step:**

1. **Start GUI**
   ```bash
   ./start_gui.sh
   ```

2. **Use Setup & Configuration Tab**
   - **Select Modpack**: Either choose ZIP file or leave empty for Vanilla
   - **Configure Server Settings**:
     - MOTD (Server message)
     - Difficulty (Peaceful, Easy, Normal, Hard)
     - PVP on/off
     - Maximum player count
     - View distance, world name, seed
   - **Memory Settings**:
     - Automatic (75% of system RAM)
     - Manual (e.g. "8G", "4096M")
   - **Installation Options**:
     - ✅ Accept EULA
     - ✅ Automatic mod download (for client exports)
     - ✅ Backup before installation
     - ✅ Overwrite files
   - **Service Options**:
     - ✅ Generate systemd service
     - ✅ Start tmux session

3. **Execute Installation**
   - Click "Run Server Setup" button
   - Follow progress in real-time
   - On errors: Check logs in "Logs & Monitoring" tab

4. **Manage Server** (after successful installation)
   - **Server Control Tab**: Start/Stop/Restart/Kill
   - **World Management Tab**: Switch worlds, create backups
   - **Backup Management Tab**: Restore, manage backups
   - **Mod Management Tab**: Add/remove mods
   - **Logs & Monitoring Tab**: Follow server logs live

### GUI-Specific Features

**Live Console:**
```bash
# Enter server commands directly in the GUI
say Hello World!
op PlayerName
list
stop
```

**World Management:**
- Create new worlds
- Switch between worlds
- Automatic backups with timestamp
- World import/export

**Backup System:**
- Automatic backups every X hours
- Manual backups at the click of a button
- Backup browser with preview
- Restoration with confirmation

---

## Command Line Mode

### 🎯 **Quick Standard Installation**

```bash
# Simplest usage
./universalServerSetup.sh MyModpack.zip

# The script will guide you through:
# 1. Modpack analysis
# 2. Java installation (if required)
# 3. EULA confirmation (interactive input)
# 4. Server installation
# 5. First run (optional)
# 6. GUI start (optional)
```

### 🔧 **With Specific Parameters**

```bash
# With custom server settings
./universalServerSetup.sh \
  --motd="My Awesome Server" \
  --difficulty=hard \
  --max-players=50 \
  --pvp=false \
  --ram=8G \
  MyModpack.zip

# With service integration
./universalServerSetup.sh \
  --systemd \
  --tmux \
  MyModpack.zip

# With automatic mod download (for client exports)
./universalServerSetup.sh \
  --auto-download-mods \
  --verbose \
  MyClientExport.zip
```

### 🔄 **Advanced Workflows**

**Backup & Restoration:**
```bash
# Create backup before changes
./universalServerSetup.sh --pre-backup MyModpack.zip

# Restore world from backup
./universalServerSetup.sh --restore backups/world-20241104-143022.zip

# With custom world name
./universalServerSetup.sh --world "survival" MyModpack.zip
```

**Development & Testing:**
```bash
# Dry-Run: Shows what would happen without making changes
./universalServerSetup.sh --dry-run --verbose MyModpack.zip

# With detailed logging
./universalServerSetup.sh --verbose --log-file debug.log MyModpack.zip

# Force mode: Overwrites all existing files
./universalServerSetup.sh --force MyModpack.zip
```

---

## Fully Automated Mode (CI/CD)

### 🤖 **Complete Automation**

```bash
# Fully automated installation
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

### 📝 **Via Environment Variables**

```bash
# Create .env file
cat > server.env << 'EOF'
# Automation
AUTO_ACCEPT_EULA=yes
AUTO_FIRST_RUN=yes
ASSUME_YES=1
NO_GUI=1

# Server configuration
PROP_MOTD=Production Minecraft Server
PROP_DIFFICULTY=normal
PROP_MAX_PLAYERS=30
PROP_PVP=false
PROP_VIEW_DISTANCE=12

# Operator settings
OP_USERNAME=admin
ALWAYS_OP_USERS="admin moderator1 moderator2"

# Memory configuration
MEMORY_PERCENT=80
MIN_MEMORY_MB=4096
MAX_MEMORY_MB=16384

# Backup settings
BACKUP_INTERVAL_HOURS=2
BACKUP_RETENTION=24

# Service integration
SYSTEMD=1
TMUX=1
EOF

# Execute with environment variables
source server.env
./universalServerSetup.sh MyModpack.zip
```

### 🐳 **Docker/Container Integration**

```bash
# Docker container-friendly execution
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

## All Available Parameters

### 📋 **Basic Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--yes` / `-y` | Answer all prompts with "Yes" | `--yes` |
| `--assume-no` | Answer all prompts with "No" | `--assume-no` |
| `--force` | Overwrite existing files | `--force` |
| `--dry-run` | Show actions without execution | `--dry-run` |

### 🔐 **EULA Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--eula=true` | Automatically accept EULA | `--eula=true` |
| `--eula=false` | Explicitly reject EULA | `--eula=false` |
| `--no-eula-prompt` | Skip EULA prompt | `--no-eula-prompt` |

### 💾 **Memory Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--ram <SIZE>` | Specific RAM allocation | `--ram 8G`, `--ram 4096M` |

### 📝 **Logging Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--verbose` | Increase log detail | `--verbose` |
| `--quiet` | Reduce log output | `--quiet` |
| `--log-file <path>` | Custom log file | `--log-file debug.log` |

### 🔧 **Service Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--systemd` | Generate systemd service | `--systemd` |
| `--tmux` | Start in tmux session | `--tmux` |

### 🌍 **World Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--world <name>` | Custom world name | `--world survival` |
| `--pre-backup` | Backup before installation | `--pre-backup` |
| `--restore <zip>` | Restore world from backup | `--restore backup.zip` |

### 🎮 **Server Properties Parameters**

| Parameter | Description | Values | Example |
|-----------|-------------|--------|----------|
| `--motd` | Server message | Text | `--motd="My Server"` |
| `--difficulty` | Difficulty | peaceful, easy, normal, hard | `--difficulty=hard` |
| `--pvp` | PVP enabled | true, false | `--pvp=false` |
| `--max-players` | Maximum players | Number | `--max-players=50` |
| `--view-distance` | View distance | 1-32 | `--view-distance=12` |
| `--white-list` | Whitelist enabled | true, false | `--white-list=true` |
| `--spawn-protection` | Spawn protection radius | 0-29999984 | `--spawn-protection=16` |
| `--allow-nether` | Nether allowed | true, false | `--allow-nether=true` |
| `--level-name` | World name | Text | `--level-name=world` |
| `--level-seed` | World seed | Number/Text | `--level-seed=12345` |
| `--level-type` | World type | default, flat, large_biomes | `--level-type=default` |

### 🤖 **Mod Download Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--auto-download-mods` | Automatic mod download | `--auto-download-mods` |

### 🖥️ **GUI Parameters**

| Parameter | Description | Example |
|-----------|-------------|----------|
| `--no-gui` | Disable GUI | `--no-gui` |

---

## Configuration Options

### 📄 **Script Configuration (Edit File)**

The most important settings can be changed directly in the `universalServerSetup.sh` script:

```bash
# Basic settings (Line ~68-80)
ZIP=""                          # Default modpack path
OP_USERNAME=""                  # Default operator
OP_LEVEL="4"                    # Operator level (1-4)
ALWAYS_OP_USERS=""              # Always-operator list

# Automation (Line ~82-84)
AUTO_ACCEPT_EULA="no"           # Accept EULA automatically
AUTO_FIRST_RUN="no"             # Start server automatically

# Memory configuration (Line ~104-112)
JAVA_ARGS=""                    # Custom JVM args
MEMORY_PERCENT=75               # RAM percentage
MIN_MEMORY_MB=2048              # Minimum RAM
MAX_MEMORY_MB=32768             # Maximum RAM

# Backup settings (Line ~116-118)
BACKUP_INTERVAL_HOURS=4         # Backup interval
BACKUP_RETENTION=12             # Number of backups to keep

# Server properties defaults (Line ~129-160)
PROP_MOTD="A Minecraft Server"  # Default MOTD
PROP_DIFFICULTY="easy"          # Default difficulty
PROP_PVP="true"                 # Default PVP
PROP_VIEW_DISTANCE="10"         # Default view distance
PROP_MAX_PLAYERS="20"           # Default player count
# ... and many more
```

### 🔄 **Environment Variables**

All configuration options can be overridden via environment variables:

```bash
# Server configuration
export PROP_MOTD="Production Server"
export PROP_DIFFICULTY="hard"
export PROP_MAX_PLAYERS="100"
export PROP_PVP="false"

# Memory settings
export MEMORY_PERCENT="90"
export MIN_MEMORY_MB="8192"

# Automation
export AUTO_ACCEPT_EULA="yes"
export ASSUME_YES="1"
```

### ⚙️ **Configuration Files**

The system also supports `.env` files:

```bash
# Create .env file
cat > .env << 'EOF'
PROP_MOTD=My Gaming Server
PROP_DIFFICULTY=normal
PROP_MAX_PLAYERS=25
MEMORY_PERCENT=80
BACKUP_INTERVAL_HOURS=6
EOF

# Automatically loaded at script start
./universalServerSetup.sh MyModpack.zip
```

---

## Scenarios & Use Cases

### 🎯 **Scenario 1: Beginners - First Minecraft Server**

**Goal**: Easy start with GUI
**Recommended Workflow**: GUI Mode

```bash
# 1. Clone repository
git clone https://github.com/Nirlau64/MinecraftServerInstall.git
cd MinecraftServerInstall

# 2. Download modpack (from CurseForge/Modrinth)
# Place MyModpack.zip in the directory

# 3. Start GUI
./start_gui.sh

# 4. In the GUI:
#    - Open Setup & Configuration tab
#    - Select modpack: MyModpack.zip
#    - Accept EULA
#    - Click "Run Server Setup"
#    - Wait until finished
#    - Use Server Control tab

# 5. Start server via GUI or:
./start.sh
```

### 🏢 **Scenario 2: Production Server**

**Goal**: Stable server with service integration
**Recommended Workflow**: Command line with systemd

```bash
# 1. Fully automated installation
./universalServerSetup.sh \
  --yes \
  --eula=true \
  --systemd \
  --ram=16G \
  --motd="Production Server [1.20.1]" \
  --difficulty=hard \
  --max-players=50 \
  --pvp=true \
  --view-distance=12 \
  --backup-interval=2 \
  MyProductionModpack.zip

# 2. Install systemd service
sudo cp dist/minecraft.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft

# 3. Monitor status
sudo systemctl status minecraft
sudo journalctl -u minecraft -f

# 4. Server management
sudo systemctl stop minecraft     # Stop
sudo systemctl start minecraft    # Start
sudo systemctl restart minecraft  # Restart
```

### 🔄 **Scenario 3: CI/CD Pipeline**

**Goal**: Automatic deployment
**Recommended Workflow**: Fully automated

```bash
# GitHub Actions / GitLab CI Example
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
        # Set environment variables
        export AUTO_ACCEPT_EULA=yes
        export AUTO_FIRST_RUN=no
        export NO_GUI=1
        export ASSUME_YES=1
        export SYSTEMD=1
        
        # Install server
        ./universalServerSetup.sh \
          --force \
          --ram=8G \
          --motd="CI/CD Server $(date)" \
          ModpackLatest.zip
        
        # Start service
        sudo systemctl restart minecraft
```

### 🧪 **Scenario 4: Development & Testing**

**Goal**: Quick test servers for mod development
**Recommended Workflow**: Dry-Run + Development Mode

```bash
# 1. Test setup without actual installation
./universalServerSetup.sh \
  --dry-run \
  --verbose \
  TestModpack.zip

# 2. Development server with debug logging
./universalServerSetup.sh \
  --yes \
  --eula=true \
  --ram=4G \
  --verbose \
  --log-file dev-install.log \
  --tmux \
  --motd="Dev Server - $(date +%Y%m%d)" \
  TestModpack.zip

# 3. Quick iteration
# Change modpack and reinstall
./universalServerSetup.sh \
  --force \
  --yes \
  --eula=true \
  TestModpack-v2.zip

# 4. Manage tmux session
tmux attach-session -t minecraft  # Attach to server
# Ctrl+B, D to detach
```

### 🌐 **Scenario 5: Multi-Server Setup**

**Goal**: Multiple servers on one system
**Recommended Workflow**: Separate directories

```bash
# 1. Basic setup
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
# Change service name: minecraft-survival

# 3. Server 2: Creative  
cd ~/minecraft-servers
git clone https://github.com/Nirlau64/MinecraftServerInstall.git creative-server
cd creative-server
# Change port in server.properties to 25566
./universalServerSetup.sh \
  --motd="Creative Server" \
  --difficulty=peaceful \
  --ram=4G \
  CreativeModpack.zip

# 4. Server 3: Modded
cd ~/minecraft-servers
git clone https://github.com/Nirlau64/MinecraftServerInstall.git modded-server
cd modded-server
# Change port to 25567
./universalServerSetup.sh \
  --motd="Modded Server" \
  --auto-download-mods \
  --ram=12G \
  HeavyModpack.zip
```

### 🔁 **Scenario 6: Server Migration & Backup**

**Goal**: Migrate existing server or restore
**Recommended Workflow**: Use backup system

```bash
# 1. Create backup from old server
# (if created with this tool)
./universalServerSetup.sh --pre-backup

# or manually
zip -r server-backup-$(date +%Y%m%d).zip \
  world* \
  server.properties \
  ops.json \
  whitelist.json \
  mods/ \
  config/

# 2. Install new server
./universalServerSetup.sh MyModpack.zip

# 3. Restore backup
./universalServerSetup.sh --restore server-backup-20241104.zip

# 4. Or selective restoration
unzip -j server-backup-20241104.zip world/* -d world/
unzip -j server-backup-20241104.zip server.properties
```

---

## After Installation

### 📁 **Understanding Generated Files**

After successful installation, the following structure is created:

```
MinecraftServerInstall/
├── universalServerSetup.sh     # Setup script
├── start.sh                    # Server start script ⭐
├── .server_functions.sh        # Internal functions
├── .server_jar                 # Server JAR cache
├── eula.txt                    # EULA acceptance
├── server.properties           # Server configuration ⭐
├── ops.json                    # Operator list
├── whitelist.json             # Whitelist (if enabled)
├── mods/                      # Mod files
│   ├── mod1.jar
│   └── mod2.jar
├── config/                    # Mod configurations
│   ├── forge-common.toml
│   └── various-mod-configs/
├── logs/                      # Log files ⭐
│   ├── install-20241104-143022.log
│   ├── latest.log
│   └── missing-mods.txt
├── backups/                   # Automatic backups ⭐
│   └── world-20241104-120000.zip
├── world/                     # Game world ⭐
├── libraries/                 # Mod loader libraries
├── forge-xx.x.x.jar          # Server JAR (Forge/Fabric/etc.)
└── dist/                      # Service files
    └── minecraft.service      # systemd service
```

### 🎮 **Server Management After Installation**

**Starting the server:**
```bash
# Via generated startup script (recommended)
./start.sh

# Via systemd (if --systemd was used)
sudo systemctl start minecraft

# Via tmux (if --tmux was used)
tmux attach-session -t minecraft

# Via GUI
./start_gui.sh
# → Server Control Tab → Start Button
```

**Stopping the server:**
```bash
# Graceful shutdown (in server console)
stop

# Via systemd
sudo systemctl stop minecraft

# Force kill (emergency)
pkill -f minecraft
```

**Changing server configuration:**
```bash
# Edit server.properties
nano server.properties

# Mod configurations
nano config/forge-common.toml

# Via GUI: Setup & Configuration Tab
```

### 🔧 **Maintenance & Updates**

**Update modpack:**
```bash
# Create backup
./universalServerSetup.sh --pre-backup

# Install new modpack
./universalServerSetup.sh --force NewModpackVersion.zip

# On problems: Restore backup
./universalServerSetup.sh --restore backups/world-YYYYMMDD-HHMMSS.zip
```

**Add individual mods:**
```bash
# Copy mod file to mods/ directory
cp NewMod.jar mods/

# Restart server
./start.sh
```

**Backup management:**
```bash
# Manual backup
zip -r "backup-$(date +%Y%m%d-%H%M%S).zip" world/

# Configure automatic backups (in script)
BACKUP_INTERVAL_HOURS=2  # Every 2 hours
BACKUP_RETENTION=24      # Keep 24 backups

# Clean up old backups
find backups/ -name "*.zip" -mtime +7 -delete  # Older than 7 days
```

---

## Troubleshooting & Logs

### 📊 **Understanding Log Files**

**Installation logs:**
```bash
# Latest installation log
ls -t logs/install-*.log | head -1

# View log
cat logs/install-20241104-143022.log

# Filter errors from log
grep -i error logs/install-20241104-143022.log
```

**Server logs:**
```bash
# Current server logs
tail -f logs/latest.log

# Search for specific events
grep -i "player\|error\|warn" logs/latest.log

# Crash reports
ls -la crash-reports/
```

**Mod download logs (with --auto-download-mods):**
```bash
# Failed downloads
cat logs/missing-mods.txt

# Download manually
python3 tools/cf_downloader.py manifest.json ./mods --verbose
```

### 🚨 **Common Problems & Solutions**

**Problem: Java not found**
```bash
# Check Java version
java -version

# Manually install Java (Ubuntu/Debian)
sudo apt update
sudo apt install openjdk-17-jre-headless

# For older Minecraft versions
sudo apt install openjdk-8-jre-headless

# For latest Minecraft versions
sudo apt install openjdk-21-jre-headless
```

**Problem: Port 25565 already in use**
```bash
# Check port usage
sudo ss -tlnp | grep :25565
sudo netstat -tlnp | grep :25565

# Kill process
sudo kill $(sudo lsof -t -i:25565)

# Use alternative port (server.properties)
server-port=25566
```

**Problem: Not enough memory**
```bash
# Check available RAM
free -h

# Adjust memory settings
./universalServerSetup.sh --ram 4G MyModpack.zip

# Or in configuration
export MEMORY_PERCENT=50
```

**Problem: Missing permissions**
```bash
# Set permissions
chmod +x universalServerSetup.sh start.sh

# Change owner
sudo chown -R $USER:$USER .

# For systemd service
sudo chown root:root dist/minecraft.service
```

**Problem: GUI won't start**
```bash
# Check tkinter installation
python3 -c "import tkinter; print('OK')"

# For headless server: X11 forwarding
ssh -X user@server

# Or disable GUI
./universalServerSetup.sh --no-gui MyModpack.zip
```

**Problem: Mods not compatible**
```bash
# Check mod compatibility
cat mods/mod-name.jar # Minecraft version in name

# Analyze manifest.json (for client exports)
cat manifest.json | jq '.minecraft.version'
cat manifest.json | jq '.minecraft.modLoaders'

# Remove individual problematic mods
mv mods/problematic-mod.jar mods/disabled/
```

### 🔍 **Using Debug Modes**

**Verbose Logging:**
```bash
# Detailed output
./universalServerSetup.sh --verbose MyModpack.zip

# With log file
./universalServerSetup.sh --verbose --log-file debug.log MyModpack.zip

# Analyze log
less debug.log
grep -C 3 -i error debug.log  # 3 lines context around errors
```

**Dry-Run for Testing:**
```bash
# Shows all actions without execution
./universalServerSetup.sh --dry-run --verbose MyModpack.zip

# Perfect for testing parameters
./universalServerSetup.sh --dry-run \
  --ram 16G \
  --systemd \
  --auto-download-mods \
  MyModpack.zip
```

**Step-by-Step Debugging:**
```bash
# 1. Validate modpack
unzip -t MyModpack.zip

# 2. Analyze manifest (if present)
unzip -p MyModpack.zip manifest.json | jq .

# 3. Check Java version for Minecraft version
# (done automatically by script)

# 4. Check available resources
df -h        # Disk space
free -h      # RAM
ss -tlnp | grep :25565  # Port availability
```

### 📞 **Getting Help**

**Community & Support:**
- GitHub Issues: Detailed bug reports with logs
- GitHub Discussions: General questions and tips
- README.md: Basic documentation

**Helpful information for support requests:**
```bash
# Gather system information
uname -a                    # System info
java -version              # Java version  
python3 --version          # Python version
cat /etc/os-release        # Distribution

# Provide log files
tar -czf support-logs.tar.gz logs/ *.log server.properties

# Share configuration (without sensitive data)
grep -v "password\|key\|token" universalServerSetup.sh | head -200
```

---

## Conclusion

This comprehensive tool offers three different approaches for every user type:

- **🎮 GUI Mode**: Perfect for beginners and visual management
- **⌨️ Command Line**: Flexible for experienced users and SSH environments  
- **🤖 Fully Automated**: Ideal for automation and CI/CD pipelines

With over 30 configuration parameters, automatic Java management, intelligent backup system, and comprehensive logging, it's equipped for every use case - from the first Minecraft server to production environments with multiple servers.

**Key Recommendations:**
- New users: Start with GUI mode
- Production servers: Use `--systemd` for service integration  
- Development: Use `--dry-run` for testing
- Automation: Configure environment variables
- Always: Create regular backups!