#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Minecraft Server GUI Launcher
=============================
Standalone launcher for the Minecraft Server Management GUI.

This script can be used to start the GUI independently of the setup script.
It will attempt to detect the server directory automatically or use the 
provided path.

Usage:
    python3 start_gui.py [server_directory]
    
    # From the server directory:
    python3 tools/start_gui.py
    
    # From elsewhere, specify server path:
    python3 /path/to/server/tools/start_gui.py /path/to/server
"""

import sys
import os
from pathlib import Path

def find_server_gui():
    """Find the server_gui.py script"""
    # Check if we're in tools/ directory
    current_dir = Path.cwd()
    
    # Try current directory first
    gui_script = current_dir / "server_gui.py"
    if gui_script.exists():
        return gui_script
    
    # Try tools/ subdirectory
    gui_script = current_dir / "tools" / "server_gui.py"
    if gui_script.exists():
        return gui_script
    
    # Try parent directory's tools/
    gui_script = current_dir.parent / "tools" / "server_gui.py"
    if gui_script.exists():
        return gui_script
    
    # Try same directory as this script
    script_dir = Path(__file__).parent
    gui_script = script_dir / "server_gui.py"
    if gui_script.exists():
        return gui_script
    
    return None

def main():
    """Main launcher function"""
    # Find the GUI script
    gui_script = find_server_gui()
    
    if not gui_script:
        print("Error: Could not find server_gui.py")
        print("Make sure you're running this from the server directory or tools/ directory")
        return 1
    
    # Determine server directory
    server_dir = None
    if len(sys.argv) > 1:
        server_dir = sys.argv[1]
    else:
        # Try to auto-detect server directory
        current_dir = Path.cwd()
        if current_dir.name == 'tools':
            server_dir = str(current_dir.parent)
        else:
            server_dir = str(current_dir)
    
    # Check if tkinter is available
    try:
        import tkinter
    except ImportError:
        print("Error: tkinter not available")
        print("Install tkinter with: sudo apt-get install python3-tk (or equivalent for your system)")
        return 1
    
    # Import and run the GUI
    try:
        sys.path.insert(0, str(gui_script.parent))
        from server_gui import main as gui_main
        
        # Override sys.argv to pass server directory
        original_argv = sys.argv[:]
        sys.argv = ['server_gui.py']
        if server_dir:
            sys.argv.append(server_dir)
        
        result = gui_main()
        
        # Restore original argv
        sys.argv = original_argv
        
        return result or 0
        
    except ImportError as e:
        print(f"Error importing GUI module: {e}")
        return 1
    except Exception as e:
        print(f"Error starting GUI: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())