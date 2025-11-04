#!/bin/bash
# Simple GUI Launcher Script for Minecraft Server Manager
# Usage: ./start_gui.sh [server_directory]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_err() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    log_err "Python 3 not found!"
    log_info "Please install Python 3:"
    log_info "  Ubuntu/Debian: sudo apt-get install python3 python3-tk"
    log_info "  CentOS/RHEL:   sudo dnf install python3 python3-tkinter"
    log_info "  Arch Linux:    sudo pacman -S python python-tk"
    log_info "  macOS:         brew install python-tk"
    exit 1
fi

# Check if tkinter is available
if ! python3 -c "import tkinter" 2>/dev/null; then
    log_err "tkinter not found!"
    log_info "Please install tkinter:"
    log_info "  Ubuntu/Debian: sudo apt-get install python3-tk"
    log_info "  CentOS/RHEL:   sudo dnf install python3-tkinter"
    log_info "  Arch Linux:    sudo pacman -S tk"
    log_info "  macOS:         Usually included with Python"
    exit 1
fi

# Determine server directory
SERVER_DIR="${1:-$(pwd)}"

# Create server directory if it doesn't exist
if [ ! -d "$SERVER_DIR" ]; then
    log_info "Creating server directory: $SERVER_DIR"
    mkdir -p "$SERVER_DIR" || {
        log_err "Failed to create server directory: $SERVER_DIR"
        exit 1
    }
fi

# Find GUI script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_SCRIPT=""

# Try different possible locations
if [ -f "$SCRIPT_DIR/server_gui.py" ]; then
    GUI_SCRIPT="$SCRIPT_DIR/server_gui.py"
elif [ -f "$SCRIPT_DIR/tools/server_gui.py" ]; then
    GUI_SCRIPT="$SCRIPT_DIR/tools/server_gui.py"
elif [ -f "$(dirname "$SCRIPT_DIR")/server_gui.py" ]; then
    GUI_SCRIPT="$(dirname "$SCRIPT_DIR")/server_gui.py"
elif [ -f "$SERVER_DIR/tools/server_gui.py" ]; then
    GUI_SCRIPT="$SERVER_DIR/tools/server_gui.py"
else
    log_err "GUI script not found!"
    log_info "Make sure server_gui.py is in one of these locations:"
    log_info "  - Same directory as this script"
    log_info "  - tools/ subdirectory"
    log_info "  - Server directory/tools/"
    exit 1
fi

log_info "Found GUI script: $GUI_SCRIPT"
log_info "Server directory: $SERVER_DIR"

# Check if we have a display (for headless detection)
if [ -z "${DISPLAY:-}" ] && [ "$OSTYPE" != "msys" ] && [ "$OSTYPE" != "win32" ]; then
    log_warn "No DISPLAY variable set - GUI may not work on headless systems"
    log_info "For SSH connections, use: ssh -X username@hostname"
fi

# Start the GUI
log_info "Starting Minecraft Server Manager GUI..."
exec python3 "$GUI_SCRIPT" "$SERVER_DIR"