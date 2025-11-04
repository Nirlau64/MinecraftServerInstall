#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Minecraft Server Management GUI
===============================
A lightweight graphical interface for managing Minecraft servers created
with the universalServerSetup.sh script.

Features:
- Server configuration and setup
- World management (create, backup, restore)
- Server start/stop/restart controls
- Log viewer
- Mod management
- Real-time server status monitoring

Requirements:
- Python 3.6+
- tkinter (usually included with Python)
- Server setup script must be in parent directory

Usage:
    python3 server_gui.py [server_directory]
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog, scrolledtext
import os
import sys
import subprocess
import threading
import json
import time
import glob
from datetime import datetime
from pathlib import Path
import tempfile
import shutil
import re

class MinecraftServerGUI:
    def __init__(self, root, server_dir=None):
        self.root = root
        self.root.title("Minecraft Server Manager")
        self.root.geometry("1000x700")
        
        # Determine server directory
        if server_dir:
            self.server_dir = Path(server_dir).resolve()
        else:
            # Default to current directory or parent if we're in tools/
            current_dir = Path.cwd()
            if current_dir.name == 'tools':
                self.server_dir = current_dir.parent
            else:
                self.server_dir = current_dir
        
        # Path to setup script
        self.setup_script = self.server_dir / "universalServerSetup.sh"
        
        # Server status tracking
        self.server_process = None
        self.server_status = "stopped"
        
        # Initialize GUI components
        self.setup_ui()
        self.load_current_config()
        self.update_status()
        
        # Start status monitoring
        self.monitor_server()
    
    def setup_ui(self):
        """Create the main user interface"""
        # Create notebook for tabs
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill='both', expand=True, padx=10, pady=10)
        
        # Create tabs
        self.create_setup_tab()
        self.create_server_tab()
        self.create_worlds_tab()
        self.create_mods_tab()
        self.create_logs_tab()
        
        # Status bar at bottom
        self.create_status_bar()
    
    def create_setup_tab(self):
        """Server Setup & Configuration Tab"""
        setup_frame = ttk.Frame(self.notebook)
        self.notebook.add(setup_frame, text="Setup & Configuration")
        
        # Create scrollable frame
        canvas = tk.Canvas(setup_frame)
        scrollbar = ttk.Scrollbar(setup_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)
        
        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Server Properties Section
        props_frame = ttk.LabelFrame(scrollable_frame, text="Server Properties", padding=10)
        props_frame.grid(row=0, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
        
        row = 0
        
        # MOTD
        ttk.Label(props_frame, text="MOTD (Message of the Day):").grid(row=row, column=0, sticky='w', pady=2)
        self.motd_var = tk.StringVar(value="Modded Minecraft Server")
        ttk.Entry(props_frame, textvariable=self.motd_var, width=40).grid(row=row, column=1, sticky='ew', pady=2)
        row += 1
        
        # Difficulty
        ttk.Label(props_frame, text="Difficulty:").grid(row=row, column=0, sticky='w', pady=2)
        self.difficulty_var = tk.StringVar(value="normal")
        difficulty_combo = ttk.Combobox(props_frame, textvariable=self.difficulty_var, 
                                       values=["peaceful", "easy", "normal", "hard"], state="readonly")
        difficulty_combo.grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        # PVP
        ttk.Label(props_frame, text="PVP Enabled:").grid(row=row, column=0, sticky='w', pady=2)
        self.pvp_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(props_frame, variable=self.pvp_var).grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        # Max Players
        ttk.Label(props_frame, text="Max Players:").grid(row=row, column=0, sticky='w', pady=2)
        self.max_players_var = tk.StringVar(value="20")
        ttk.Spinbox(props_frame, from_=1, to=100, textvariable=self.max_players_var, width=10).grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        # View Distance
        ttk.Label(props_frame, text="View Distance:").grid(row=row, column=0, sticky='w', pady=2)
        self.view_distance_var = tk.StringVar(value="10")
        ttk.Spinbox(props_frame, from_=3, to=32, textvariable=self.view_distance_var, width=10).grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        # World Name
        ttk.Label(props_frame, text="World Name:").grid(row=row, column=0, sticky='w', pady=2)
        self.world_name_var = tk.StringVar(value="world")
        ttk.Entry(props_frame, textvariable=self.world_name_var, width=30).grid(row=row, column=1, sticky='ew', pady=2)
        row += 1
        
        # World Seed
        ttk.Label(props_frame, text="World Seed (optional):").grid(row=row, column=0, sticky='w', pady=2)
        self.world_seed_var = tk.StringVar()
        ttk.Entry(props_frame, textvariable=self.world_seed_var, width=30).grid(row=row, column=1, sticky='ew', pady=2)
        row += 1
        
        # World Type
        ttk.Label(props_frame, text="World Type:").grid(row=row, column=0, sticky='w', pady=2)
        self.world_type_var = tk.StringVar(value="default")
        world_type_combo = ttk.Combobox(props_frame, textvariable=self.world_type_var,
                                       values=["default", "flat", "largeBiomes", "amplified"], state="readonly")
        world_type_combo.grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        # White List
        ttk.Label(props_frame, text="Enable Whitelist:").grid(row=row, column=0, sticky='w', pady=2)
        self.whitelist_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(props_frame, variable=self.whitelist_var).grid(row=row, column=1, sticky='w', pady=2)
        row += 1
        
        props_frame.columnconfigure(1, weight=1)
        
        # Memory Configuration Section
        memory_frame = ttk.LabelFrame(scrollable_frame, text="Memory & Performance", padding=10)
        memory_frame.grid(row=1, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
        
        # RAM Allocation
        ttk.Label(memory_frame, text="RAM Allocation:").grid(row=0, column=0, sticky='w', pady=2)
        self.ram_var = tk.StringVar()
        ram_frame = ttk.Frame(memory_frame)
        ram_frame.grid(row=0, column=1, sticky='w', pady=2)
        
        self.ram_auto_var = tk.BooleanVar(value=True)
        ttk.Radiobutton(ram_frame, text="Auto (75% of system RAM)", 
                       variable=self.ram_auto_var, value=True).grid(row=0, column=0, sticky='w')
        
        manual_frame = ttk.Frame(ram_frame)
        manual_frame.grid(row=1, column=0, sticky='w', pady=(5,0))
        
        ttk.Radiobutton(manual_frame, text="Manual:", 
                       variable=self.ram_auto_var, value=False).grid(row=0, column=0, sticky='w')
        ttk.Entry(manual_frame, textvariable=self.ram_var, width=10).grid(row=0, column=1, padx=(5,0))
        ttk.Label(manual_frame, text="(e.g., 4G, 8192M)").grid(row=0, column=2, padx=(5,0))
        
        # Installation Options Section
        install_frame = ttk.LabelFrame(scrollable_frame, text="Installation Options", padding=10)
        install_frame.grid(row=2, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
        
        # EULA
        self.eula_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(install_frame, text="Accept Minecraft EULA (required)", 
                       variable=self.eula_var).grid(row=0, column=0, sticky='w', pady=2)
        
        # Auto download mods
        self.auto_download_mods_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(install_frame, text="Auto-download mods from manifest.json", 
                       variable=self.auto_download_mods_var).grid(row=1, column=0, sticky='w', pady=2)
        
        # Create backup
        self.pre_backup_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(install_frame, text="Create backup before installation", 
                       variable=self.pre_backup_var).grid(row=2, column=0, sticky='w', pady=2)
        
        # Force overwrite
        self.force_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(install_frame, text="Force overwrite existing files", 
                       variable=self.force_var).grid(row=3, column=0, sticky='w', pady=2)
        
        # Service Options
        service_frame = ttk.LabelFrame(scrollable_frame, text="Service Options", padding=10)
        service_frame.grid(row=3, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
        
        self.systemd_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(service_frame, text="Generate systemd service file", 
                       variable=self.systemd_var).grid(row=0, column=0, sticky='w', pady=2)
        
        self.tmux_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(service_frame, text="Start server in tmux session", 
                       variable=self.tmux_var).grid(row=1, column=0, sticky='w', pady=2)
        
        # Modpack Selection and Actions
        modpack_frame = ttk.LabelFrame(scrollable_frame, text="Modpack Installation", padding=10)
        modpack_frame.grid(row=4, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
        
        # Modpack file selection
        ttk.Label(modpack_frame, text="Modpack ZIP:").grid(row=0, column=0, sticky='w', pady=2)
        self.modpack_var = tk.StringVar()
        modpack_entry_frame = ttk.Frame(modpack_frame)
        modpack_entry_frame.grid(row=0, column=1, sticky='ew', pady=2)
        
        ttk.Entry(modpack_entry_frame, textvariable=self.modpack_var).grid(row=0, column=0, sticky='ew')
        ttk.Button(modpack_entry_frame, text="Browse", command=self.browse_modpack).grid(row=0, column=1, padx=(5,0))
        modpack_entry_frame.columnconfigure(0, weight=1)
        
        # Action buttons
        button_frame = ttk.Frame(scrollable_frame)
        button_frame.grid(row=5, column=0, columnspan=2, pady=20)
        
        ttk.Button(button_frame, text="Run Setup", command=self.run_setup).grid(row=0, column=0, padx=5)
        ttk.Button(button_frame, text="Save Configuration", command=self.save_config).grid(row=0, column=1, padx=5)
        ttk.Button(button_frame, text="Load Configuration", command=self.load_config).grid(row=0, column=2, padx=5)
        ttk.Button(button_frame, text="Reset to Defaults", command=self.reset_config).grid(row=0, column=3, padx=5)
        
        # Configure column weights for proper expansion
        scrollable_frame.columnconfigure(0, weight=1)
        scrollable_frame.columnconfigure(1, weight=1)
    
    def create_server_tab(self):
        """Server Control Tab"""
        server_frame = ttk.Frame(self.notebook)
        self.notebook.add(server_frame, text="Server Control")
        
        # Server Status Section
        status_frame = ttk.LabelFrame(server_frame, text="Server Status", padding=10)
        status_frame.pack(fill='x', padx=10, pady=5)
        
        self.status_label = ttk.Label(status_frame, text="Status: Stopped", font=("TkDefaultFont", 12, "bold"))
        self.status_label.pack(anchor='w')
        
        self.players_label = ttk.Label(status_frame, text="Players: 0/20")
        self.players_label.pack(anchor='w')
        
        # Control Buttons
        control_frame = ttk.Frame(server_frame)
        control_frame.pack(fill='x', padx=10, pady=5)
        
        ttk.Button(control_frame, text="Start Server", command=self.start_server).pack(side='left', padx=5)
        ttk.Button(control_frame, text="Stop Server", command=self.stop_server).pack(side='left', padx=5)
        ttk.Button(control_frame, text="Restart Server", command=self.restart_server).pack(side='left', padx=5)
        ttk.Button(control_frame, text="Force Kill", command=self.kill_server).pack(side='left', padx=5)
        
        # Console Section
        console_frame = ttk.LabelFrame(server_frame, text="Server Console", padding=10)
        console_frame.pack(fill='both', expand=True, padx=10, pady=5)
        
        # Console output
        self.console_text = scrolledtext.ScrolledText(console_frame, height=20, state='disabled')
        self.console_text.pack(fill='both', expand=True, pady=(0, 5))
        
        # Console input
        input_frame = ttk.Frame(console_frame)
        input_frame.pack(fill='x')
        
        ttk.Label(input_frame, text="Command:").pack(side='left')
        self.command_var = tk.StringVar()
        command_entry = ttk.Entry(input_frame, textvariable=self.command_var)
        command_entry.pack(side='left', fill='x', expand=True, padx=(5, 0))
        command_entry.bind('<Return>', self.send_command)
        
        ttk.Button(input_frame, text="Send", command=self.send_command).pack(side='right', padx=(5, 0))
    
    def create_worlds_tab(self):
        """World Management Tab"""
        worlds_frame = ttk.Frame(self.notebook)
        self.notebook.add(worlds_frame, text="World Management")
        
        # Current World Section
        current_frame = ttk.LabelFrame(worlds_frame, text="Current World", padding=10)
        current_frame.pack(fill='x', padx=10, pady=5)
        
        self.current_world_label = ttk.Label(current_frame, text="Current World: world")
        self.current_world_label.pack(anchor='w')
        
        world_control_frame = ttk.Frame(current_frame)
        world_control_frame.pack(fill='x', pady=(10, 0))
        
        ttk.Button(world_control_frame, text="Create Backup", command=self.backup_world).pack(side='left', padx=5)
        ttk.Button(world_control_frame, text="Delete World", command=self.delete_world).pack(side='left', padx=5)
        
        # Available Worlds Section
        available_frame = ttk.LabelFrame(worlds_frame, text="Available Worlds", padding=10)
        available_frame.pack(fill='x', padx=10, pady=5)
        
        # World list
        list_frame = ttk.Frame(available_frame)
        list_frame.pack(fill='x')
        
        self.worlds_listbox = tk.Listbox(list_frame, height=6)
        self.worlds_listbox.pack(side='left', fill='both', expand=True)
        
        worlds_scroll = ttk.Scrollbar(list_frame, orient='vertical', command=self.worlds_listbox.yview)
        worlds_scroll.pack(side='right', fill='y')
        self.worlds_listbox.configure(yscrollcommand=worlds_scroll.set)
        
        worlds_buttons = ttk.Frame(available_frame)
        worlds_buttons.pack(fill='x', pady=(10, 0))
        
        ttk.Button(worlds_buttons, text="Switch To", command=self.switch_world).pack(side='left', padx=5)
        ttk.Button(worlds_buttons, text="Refresh List", command=self.refresh_worlds).pack(side='left', padx=5)
        
        # Backups Section
        backup_frame = ttk.LabelFrame(worlds_frame, text="Backups", padding=10)
        backup_frame.pack(fill='both', expand=True, padx=10, pady=5)
        
        # Backup list
        backup_list_frame = ttk.Frame(backup_frame)
        backup_list_frame.pack(fill='both', expand=True)
        
        self.backups_listbox = tk.Listbox(backup_list_frame)
        self.backups_listbox.pack(side='left', fill='both', expand=True)
        
        backup_scroll = ttk.Scrollbar(backup_list_frame, orient='vertical', command=self.backups_listbox.yview)
        backup_scroll.pack(side='right', fill='y')
        self.backups_listbox.configure(yscrollcommand=backup_scroll.set)
        
        backup_buttons = ttk.Frame(backup_frame)
        backup_buttons.pack(fill='x', pady=(10, 0))
        
        ttk.Button(backup_buttons, text="Restore Backup", command=self.restore_backup).pack(side='left', padx=5)
        ttk.Button(backup_buttons, text="Delete Backup", command=self.delete_backup).pack(side='left', padx=5)
        ttk.Button(backup_buttons, text="Import Backup", command=self.import_backup).pack(side='left', padx=5)
        ttk.Button(backup_buttons, text="Refresh List", command=self.refresh_backups).pack(side='left', padx=5)
        
        # Load initial data
        self.refresh_worlds()
        self.refresh_backups()
    
    def create_mods_tab(self):
        """Mod Management Tab"""
        mods_frame = ttk.Frame(self.notebook)
        self.notebook.add(mods_frame, text="Mod Management")
        
        # Mod List Section
        list_frame = ttk.LabelFrame(mods_frame, text="Installed Mods", padding=10)
        list_frame.pack(fill='both', expand=True, padx=10, pady=5)
        
        # Mod list with scrollbar
        mod_list_frame = ttk.Frame(list_frame)
        mod_list_frame.pack(fill='both', expand=True)
        
        self.mods_listbox = tk.Listbox(mod_list_frame)
        self.mods_listbox.pack(side='left', fill='both', expand=True)
        
        mod_scroll = ttk.Scrollbar(mod_list_frame, orient='vertical', command=self.mods_listbox.yview)
        mod_scroll.pack(side='right', fill='y')
        self.mods_listbox.configure(yscrollcommand=mod_scroll.set)
        
        # Mod action buttons
        mod_buttons = ttk.Frame(list_frame)
        mod_buttons.pack(fill='x', pady=(10, 0))
        
        ttk.Button(mod_buttons, text="Refresh List", command=self.refresh_mods).pack(side='left', padx=5)
        ttk.Button(mod_buttons, text="Add Mod File", command=self.add_mod_file).pack(side='left', padx=5)
        ttk.Button(mod_buttons, text="Remove Selected", command=self.remove_mod).pack(side='left', padx=5)
        
        # Mod Download Section
        download_frame = ttk.LabelFrame(mods_frame, text="Mod Download", padding=10)
        download_frame.pack(fill='x', padx=10, pady=5)
        
        ttk.Button(download_frame, text="Auto-Download from manifest.json", 
                  command=self.auto_download_mods).pack(side='left', padx=5)
        
        # Load mod list
        self.refresh_mods()
    
    def create_logs_tab(self):
        """Logs & Monitoring Tab"""
        logs_frame = ttk.Frame(self.notebook)
        self.notebook.add(logs_frame, text="Logs & Monitoring")
        
        # Log selection
        log_select_frame = ttk.Frame(logs_frame)
        log_select_frame.pack(fill='x', padx=10, pady=5)
        
        ttk.Label(log_select_frame, text="Log File:").pack(side='left')
        self.log_file_var = tk.StringVar()
        log_combo = ttk.Combobox(log_select_frame, textvariable=self.log_file_var, state='readonly')
        log_combo.pack(side='left', fill='x', expand=True, padx=(5, 0))
        
        ttk.Button(log_select_frame, text="Refresh", command=self.refresh_logs).pack(side='right', padx=(5, 0))
        ttk.Button(log_select_frame, text="Open in Editor", command=self.open_log_in_editor).pack(side='right')
        
        # Log content
        log_content_frame = ttk.LabelFrame(logs_frame, text="Log Content", padding=10)
        log_content_frame.pack(fill='both', expand=True, padx=10, pady=5)
        
        self.log_text = scrolledtext.ScrolledText(log_content_frame, state='disabled')
        self.log_text.pack(fill='both', expand=True)
        
        # Log control buttons
        log_buttons = ttk.Frame(log_content_frame)
        log_buttons.pack(fill='x', pady=(10, 0))
        
        ttk.Button(log_buttons, text="Load Selected Log", command=self.load_selected_log).pack(side='left', padx=5)
        ttk.Button(log_buttons, text="Clear Display", command=self.clear_log_display).pack(side='left', padx=5)
        ttk.Button(log_buttons, text="Auto-scroll", command=self.toggle_auto_scroll).pack(side='left', padx=5)
        
        self.auto_scroll = False
        
        # Populate log files
        self.refresh_logs()
        
        # Bind log selection change
        log_combo.bind('<<ComboboxSelected>>', lambda e: self.load_selected_log())
    
    def create_status_bar(self):
        """Create status bar at bottom of window"""
        self.status_bar = ttk.Frame(self.root)
        self.status_bar.pack(side='bottom', fill='x', padx=10, pady=(0, 10))
        
        self.status_text = ttk.Label(self.status_bar, text="Ready")
        self.status_text.pack(side='left')
        
        # Server directory label
        dir_label = ttk.Label(self.status_bar, text=f"Server Directory: {self.server_dir}")
        dir_label.pack(side='right')
    
    # Configuration Methods
    def load_current_config(self):
        """Load current configuration from existing files"""
        try:
            # Load from server.properties if it exists
            props_file = self.server_dir / "server.properties"
            if props_file.exists():
                self.load_server_properties(props_file)
            
            # Load from .env if it exists
            env_file = self.server_dir / ".env"
            if env_file.exists():
                self.load_env_config(env_file)
                
        except Exception as e:
            self.log_message(f"Error loading configuration: {e}")
    
    def load_server_properties(self, props_file):
        """Load settings from server.properties file"""
        try:
            with open(props_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Map server.properties to our variables
                        if key == 'motd':
                            self.motd_var.set(value)
                        elif key == 'difficulty':
                            self.difficulty_var.set(value)
                        elif key == 'pvp':
                            self.pvp_var.set(value.lower() == 'true')
                        elif key == 'max-players':
                            self.max_players_var.set(value)
                        elif key == 'view-distance':
                            self.view_distance_var.set(value)
                        elif key == 'level-name':
                            self.world_name_var.set(value)
                        elif key == 'level-seed':
                            self.world_seed_var.set(value)
                        elif key == 'level-type':
                            self.world_type_var.set(value)
                        elif key == 'white-list':
                            self.whitelist_var.set(value.lower() == 'true')
                            
        except Exception as e:
            self.log_message(f"Error reading server.properties: {e}")
    
    def load_env_config(self, env_file):
        """Load settings from .env file"""
        try:
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"\'')
                        
                        if key == 'RAM' and value:
                            self.ram_var.set(value)
                            self.ram_auto_var.set(False)
                        elif key == 'EULA':
                            self.eula_var.set(value.lower() == 'true')
                            
        except Exception as e:
            self.log_message(f"Error reading .env file: {e}")
    
    def save_config(self):
        """Save current configuration to files"""
        try:
            # Save to .env file
            env_file = self.server_dir / ".env"
            with open(env_file, 'w') as f:
                f.write("# Minecraft Server Configuration\n")
                f.write("# Generated by Server GUI\n\n")
                
                # Server properties
                f.write(f'PROP_MOTD="{self.motd_var.get()}"\n')
                f.write(f'PROP_DIFFICULTY="{self.difficulty_var.get()}"\n')
                f.write(f'PROP_PVP="{str(self.pvp_var.get()).lower()}"\n')
                f.write(f'PROP_MAX_PLAYERS="{self.max_players_var.get()}"\n')
                f.write(f'PROP_VIEW_DISTANCE="{self.view_distance_var.get()}"\n')
                f.write(f'PROP_LEVEL_NAME="{self.world_name_var.get()}"\n')
                f.write(f'PROP_LEVEL_SEED="{self.world_seed_var.get()}"\n')
                f.write(f'PROP_LEVEL_TYPE="{self.world_type_var.get()}"\n')
                f.write(f'PROP_WHITE_LIST="{str(self.whitelist_var.get()).lower()}"\n')
                
                # Memory configuration
                if not self.ram_auto_var.get() and self.ram_var.get():
                    f.write(f'RAM="{self.ram_var.get()}"\n')
                
                # Other options
                f.write(f'EULA="{str(self.eula_var.get()).lower()}"\n')
                
            messagebox.showinfo("Success", f"Configuration saved to {env_file}")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save configuration: {e}")
    
    def load_config(self):
        """Load configuration from a file"""
        file_path = filedialog.askopenfilename(
            title="Load Configuration",
            defaultextension=".env",
            filetypes=[("Environment files", "*.env"), ("All files", "*.*")]
        )
        
        if file_path:
            try:
                self.load_env_config(Path(file_path))
                messagebox.showinfo("Success", "Configuration loaded successfully")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to load configuration: {e}")
    
    def reset_config(self):
        """Reset configuration to defaults"""
        if messagebox.askyesno("Reset Configuration", "Reset all settings to defaults?"):
            # Reset to default values
            self.motd_var.set("Modded Minecraft Server")
            self.difficulty_var.set("normal")
            self.pvp_var.set(True)
            self.max_players_var.set("20")
            self.view_distance_var.set("10")
            self.world_name_var.set("world")
            self.world_seed_var.set("")
            self.world_type_var.set("default")
            self.whitelist_var.set(False)
            self.ram_auto_var.set(True)
            self.ram_var.set("")
            self.eula_var.set(True)
            self.auto_download_mods_var.set(False)
            self.pre_backup_var.set(False)
            self.force_var.set(False)
            self.systemd_var.set(False)
            self.tmux_var.set(False)
    
    def browse_modpack(self):
        """Browse for modpack ZIP file"""
        file_path = filedialog.askopenfilename(
            title="Select Modpack ZIP",
            defaultextension=".zip",
            filetypes=[("ZIP files", "*.zip"), ("All files", "*.*")]
        )
        
        if file_path:
            self.modpack_var.set(file_path)
    
    def run_setup(self):
        """Run the server setup script with current configuration"""
        if not self.setup_script.exists():
            messagebox.showerror("Error", f"Setup script not found: {self.setup_script}")
            return
        
        # Build command line arguments
        cmd = ["bash", str(self.setup_script)]
        
        # Add flags based on GUI settings
        if self.eula_var.get():
            cmd.extend(["--eula=true", "--no-eula-prompt"])
        else:
            cmd.append("--eula=false")
        
        if self.force_var.get():
            cmd.append("--force")
        
        if self.pre_backup_var.get():
            cmd.append("--pre-backup")
        
        if self.auto_download_mods_var.get():
            cmd.append("--auto-download-mods")
        
        if self.systemd_var.get():
            cmd.append("--systemd")
        
        if self.tmux_var.get():
            cmd.append("--tmux")
        
        if not self.ram_auto_var.get() and self.ram_var.get():
            cmd.extend(["--ram", self.ram_var.get()])
        
        # Server properties
        cmd.extend([f"--motd={self.motd_var.get()}"])
        cmd.extend([f"--difficulty={self.difficulty_var.get()}"])
        cmd.extend([f"--pvp={str(self.pvp_var.get()).lower()}"])
        cmd.extend([f"--max-players={self.max_players_var.get()}"])
        cmd.extend([f"--view-distance={self.view_distance_var.get()}"])
        cmd.extend([f"--level-name={self.world_name_var.get()}"])
        if self.world_seed_var.get():
            cmd.extend([f"--level-seed={self.world_seed_var.get()}"])
        cmd.extend([f"--level-type={self.world_type_var.get()}"])
        cmd.extend([f"--white-list={str(self.whitelist_var.get()).lower()}"])
        
        # Add modpack file if specified
        if self.modpack_var.get():
            cmd.append(self.modpack_var.get())
        
        # Run setup in separate thread
        def run_setup_thread():
            try:
                self.log_message("Starting server setup...")
                self.log_message(f"Command: {' '.join(cmd)}")
                
                process = subprocess.Popen(
                    cmd,
                    cwd=str(self.server_dir),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    universal_newlines=True,
                    bufsize=1
                )
                
                # Read output line by line
                for line in process.stdout:
                    self.root.after(0, lambda l=line: self.log_message(l.rstrip()))
                
                process.wait()
                
                if process.returncode == 0:
                    self.root.after(0, lambda: self.log_message("Setup completed successfully!"))
                    self.root.after(0, lambda: messagebox.showinfo("Success", "Server setup completed successfully!"))
                else:
                    self.root.after(0, lambda: self.log_message(f"Setup failed with exit code {process.returncode}"))
                    self.root.after(0, lambda: messagebox.showerror("Error", f"Setup failed with exit code {process.returncode}"))
                
            except Exception as e:
                self.root.after(0, lambda: self.log_message(f"Setup error: {e}"))
                self.root.after(0, lambda: messagebox.showerror("Error", f"Setup failed: {e}"))
        
        threading.Thread(target=run_setup_thread, daemon=True).start()
    
    # Server Control Methods
    def start_server(self):
        """Start the Minecraft server"""
        start_script = self.server_dir / "start.sh"
        if not start_script.exists():
            messagebox.showerror("Error", "start.sh not found. Run setup first.")
            return
        
        if self.server_process and self.server_process.poll() is None:
            messagebox.showwarning("Warning", "Server is already running")
            return
        
        try:
            self.server_process = subprocess.Popen(
                ["bash", str(start_script)],
                cwd=str(self.server_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )
            
            self.server_status = "starting"
            self.log_message("Server starting...")
            
            # Start reading server output
            self.read_server_output()
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to start server: {e}")
    
    def stop_server(self):
        """Stop the Minecraft server gracefully"""
        if not self.server_process or self.server_process.poll() is not None:
            messagebox.showwarning("Warning", "Server is not running")
            return
        
        try:
            # Send stop command to server
            self.server_process.stdin.write("stop\n")
            self.server_process.stdin.flush()
            
            # Wait for graceful shutdown
            try:
                self.server_process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.server_process.terminate()
                self.server_process.wait(timeout=10)
            
            self.server_status = "stopped"
            self.log_message("Server stopped.")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to stop server: {e}")
    
    def restart_server(self):
        """Restart the Minecraft server"""
        self.stop_server()
        time.sleep(2)
        self.start_server()
    
    def kill_server(self):
        """Force kill the server process"""
        if not self.server_process or self.server_process.poll() is not None:
            messagebox.showwarning("Warning", "Server is not running")
            return
        
        try:
            self.server_process.terminate()
            try:
                self.server_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.server_process.kill()
                self.server_process.wait()
            
            self.server_status = "stopped"
            self.log_message("Server force killed.")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to kill server: {e}")
    
    def send_command(self, event=None):
        """Send command to server console"""
        command = self.command_var.get().strip()
        if not command:
            return
        
        if not self.server_process or self.server_process.poll() is not None:
            messagebox.showwarning("Warning", "Server is not running")
            return
        
        try:
            self.server_process.stdin.write(f"{command}\n")
            self.server_process.stdin.flush()
            self.command_var.set("")
            self.log_console_message(f"> {command}")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to send command: {e}")
    
    def read_server_output(self):
        """Read server output in separate thread"""
        def read_output():
            try:
                for line in self.server_process.stdout:
                    self.root.after(0, lambda l=line: self.log_console_message(l.rstrip()))
                    
                    # Check for server ready message
                    if "Done (" in line and "For help, type" in line:
                        self.root.after(0, lambda: setattr(self, 'server_status', 'running'))
                
                # Server process ended
                self.root.after(0, lambda: setattr(self, 'server_status', 'stopped'))
                
            except Exception as e:
                self.root.after(0, lambda: self.log_message(f"Error reading server output: {e}"))
        
        threading.Thread(target=read_output, daemon=True).start()
    
    def log_console_message(self, message):
        """Log message to console display"""
        self.console_text.config(state='normal')
        self.console_text.insert('end', f"{message}\n")
        if self.auto_scroll:
            self.console_text.see('end')
        self.console_text.config(state='disabled')
    
    # World Management Methods
    def refresh_worlds(self):
        """Refresh the list of available worlds"""
        self.worlds_listbox.delete(0, 'end')
        
        try:
            # Look for world directories
            for item in self.server_dir.iterdir():
                if item.is_dir() and (item / "level.dat").exists():
                    self.worlds_listbox.insert('end', item.name)
                    
            # Update current world label
            current_world = self.world_name_var.get()
            self.current_world_label.config(text=f"Current World: {current_world}")
            
        except Exception as e:
            self.log_message(f"Error refreshing worlds: {e}")
    
    def switch_world(self):
        """Switch to selected world"""
        selection = self.worlds_listbox.curselection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a world")
            return
        
        world_name = self.worlds_listbox.get(selection[0])
        
        if messagebox.askyesno("Switch World", f"Switch to world '{world_name}'?\nThis will stop the server if running."):
            # Stop server if running
            if self.server_process and self.server_process.poll() is None:
                self.stop_server()
            
            # Update configuration
            self.world_name_var.set(world_name)
            self.save_config()
            
            messagebox.showinfo("Success", f"Switched to world '{world_name}'. Restart server to apply changes.")
    
    def backup_world(self):
        """Create a backup of current world"""
        world_name = self.world_name_var.get()
        world_path = self.server_dir / world_name
        
        if not world_path.exists():
            messagebox.showerror("Error", f"World '{world_name}' not found")
            return
        
        try:
            # Create backups directory
            backup_dir = self.server_dir / "backups"
            backup_dir.mkdir(exist_ok=True)
            
            # Generate backup filename
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_name = f"{world_name}-{timestamp}.zip"
            backup_path = backup_dir / backup_name
            
            # Create backup
            self.log_message(f"Creating backup: {backup_name}")
            
            def create_backup():
                shutil.make_archive(
                    str(backup_path.with_suffix('')),
                    'zip',
                    str(world_path.parent),
                    world_name
                )
                self.root.after(0, lambda: messagebox.showinfo("Success", f"Backup created: {backup_name}"))
                self.root.after(0, self.refresh_backups)
            
            threading.Thread(target=create_backup, daemon=True).start()
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to create backup: {e}")
    
    def delete_world(self):
        """Delete the current world"""
        world_name = self.world_name_var.get()
        world_path = self.server_dir / world_name
        
        if not world_path.exists():
            messagebox.showerror("Error", f"World '{world_name}' not found")
            return
        
        if messagebox.askyesno("Delete World", 
                             f"Are you sure you want to delete world '{world_name}'?\nThis action cannot be undone!\n\nConsider creating a backup first."):
            try:
                # Stop server if running
                if self.server_process and self.server_process.poll() is None:
                    self.stop_server()
                
                shutil.rmtree(world_path)
                messagebox.showinfo("Success", f"World '{world_name}' deleted")
                self.refresh_worlds()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete world: {e}")
    
    def refresh_backups(self):
        """Refresh the list of available backups"""
        self.backups_listbox.delete(0, 'end')
        
        try:
            backup_dir = self.server_dir / "backups"
            if backup_dir.exists():
                backups = sorted(backup_dir.glob("*.zip"), reverse=True)
                for backup in backups:
                    self.backups_listbox.insert('end', backup.name)
                    
        except Exception as e:
            self.log_message(f"Error refreshing backups: {e}")
    
    def restore_backup(self):
        """Restore selected backup"""
        selection = self.backups_listbox.curselection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a backup")
            return
        
        backup_name = self.backups_listbox.get(selection[0])
        backup_path = self.server_dir / "backups" / backup_name
        
        # Extract world name from backup filename
        world_name = backup_name.split('-')[0]
        
        if messagebox.askyesno("Restore Backup", 
                             f"Restore backup '{backup_name}'?\nThis will overwrite the current '{world_name}' world!"):
            try:
                # Stop server if running
                if self.server_process and self.server_process.poll() is None:
                    self.stop_server()
                
                # Remove existing world
                world_path = self.server_dir / world_name
                if world_path.exists():
                    shutil.rmtree(world_path)
                
                # Extract backup
                shutil.unpack_archive(str(backup_path), str(self.server_dir))
                
                messagebox.showinfo("Success", f"Backup '{backup_name}' restored")
                self.refresh_worlds()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to restore backup: {e}")
    
    def delete_backup(self):
        """Delete selected backup"""
        selection = self.backups_listbox.curselection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a backup")
            return
        
        backup_name = self.backups_listbox.get(selection[0])
        backup_path = self.server_dir / "backups" / backup_name
        
        if messagebox.askyesno("Delete Backup", f"Delete backup '{backup_name}'?"):
            try:
                backup_path.unlink()
                messagebox.showinfo("Success", f"Backup '{backup_name}' deleted")
                self.refresh_backups()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete backup: {e}")
    
    def import_backup(self):
        """Import backup from external file"""
        file_path = filedialog.askopenfilename(
            title="Import Backup",
            defaultextension=".zip",
            filetypes=[("ZIP files", "*.zip"), ("All files", "*.*")]
        )
        
        if file_path:
            try:
                backup_dir = self.server_dir / "backups"
                backup_dir.mkdir(exist_ok=True)
                
                backup_name = Path(file_path).name
                dest_path = backup_dir / backup_name
                
                shutil.copy2(file_path, dest_path)
                messagebox.showinfo("Success", f"Backup imported: {backup_name}")
                self.refresh_backups()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to import backup: {e}")
    
    # Mod Management Methods
    def refresh_mods(self):
        """Refresh the list of installed mods"""
        self.mods_listbox.delete(0, 'end')
        
        try:
            mods_dir = self.server_dir / "mods"
            if mods_dir.exists():
                mods = sorted(mods_dir.glob("*.jar"))
                for mod in mods:
                    self.mods_listbox.insert('end', mod.name)
                    
        except Exception as e:
            self.log_message(f"Error refreshing mods: {e}")
    
    def add_mod_file(self):
        """Add mod file to mods directory"""
        file_paths = filedialog.askopenfilenames(
            title="Select Mod Files",
            defaultextension=".jar",
            filetypes=[("JAR files", "*.jar"), ("All files", "*.*")]
        )
        
        if file_paths:
            try:
                mods_dir = self.server_dir / "mods"
                mods_dir.mkdir(exist_ok=True)
                
                for file_path in file_paths:
                    mod_name = Path(file_path).name
                    dest_path = mods_dir / mod_name
                    shutil.copy2(file_path, dest_path)
                
                messagebox.showinfo("Success", f"Added {len(file_paths)} mod(s)")
                self.refresh_mods()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to add mods: {e}")
    
    def remove_mod(self):
        """Remove selected mod"""
        selection = self.mods_listbox.curselection()
        if not selection:
            messagebox.showwarning("Warning", "Please select a mod")
            return
        
        mod_name = self.mods_listbox.get(selection[0])
        mod_path = self.server_dir / "mods" / mod_name
        
        if messagebox.askyesno("Remove Mod", f"Remove mod '{mod_name}'?"):
            try:
                mod_path.unlink()
                messagebox.showinfo("Success", f"Mod '{mod_name}' removed")
                self.refresh_mods()
                
            except Exception as e:
                messagebox.showerror("Error", f"Failed to remove mod: {e}")
    
    def auto_download_mods(self):
        """Auto-download mods using the setup script"""
        manifest_path = self.server_dir / "manifest.json"
        if not manifest_path.exists():
            messagebox.showerror("Error", "manifest.json not found")
            return
        
        # Run the mod download using the setup script
        cmd = ["bash", str(self.setup_script), "--auto-download-mods", "--dry-run"]
        
        def download_thread():
            try:
                self.log_message("Starting automatic mod download...")
                
                process = subprocess.Popen(
                    cmd,
                    cwd=str(self.server_dir),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    universal_newlines=True,
                    bufsize=1
                )
                
                for line in process.stdout:
                    self.root.after(0, lambda l=line: self.log_message(l.rstrip()))
                
                process.wait()
                
                if process.returncode == 0:
                    self.root.after(0, lambda: messagebox.showinfo("Success", "Mod download completed"))
                    self.root.after(0, self.refresh_mods)
                else:
                    self.root.after(0, lambda: messagebox.showerror("Error", "Mod download failed"))
                
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("Error", f"Mod download failed: {e}"))
        
        threading.Thread(target=download_thread, daemon=True).start()
    
    # Log Management Methods
    def refresh_logs(self):
        """Refresh the list of available log files"""
        try:
            log_files = []
            
            # Server logs
            if (self.server_dir / "logs").exists():
                log_files.extend(str(f.relative_to(self.server_dir)) for f in (self.server_dir / "logs").glob("*.log"))
            
            # Installation logs
            if (self.server_dir / "logs").exists():
                log_files.extend(str(f.relative_to(self.server_dir)) for f in (self.server_dir / "logs").glob("install-*.log"))
            
            # Other relevant files
            for file_name in ["server.properties", "eula.txt", "ops.json", "whitelist.json"]:
                if (self.server_dir / file_name).exists():
                    log_files.append(file_name)
            
            # Update combobox
            log_combo = None
            for child in self.notebook.nametowidget(self.notebook.tabs()[-1]).winfo_children():
                if isinstance(child, ttk.Frame):
                    for widget in child.winfo_children():
                        if isinstance(widget, ttk.Combobox):
                            log_combo = widget
                            break
                    if log_combo:
                        break
            
            if log_combo:
                log_combo['values'] = log_files
                if log_files and not self.log_file_var.get():
                    self.log_file_var.set(log_files[0])
            
        except Exception as e:
            self.log_message(f"Error refreshing logs: {e}")
    
    def load_selected_log(self):
        """Load the selected log file"""
        log_file = self.log_file_var.get()
        if not log_file:
            return
        
        log_path = self.server_dir / log_file
        
        if not log_path.exists():
            self.log_text.config(state='normal')
            self.log_text.delete(1.0, 'end')
            self.log_text.insert('end', f"Log file not found: {log_path}")
            self.log_text.config(state='disabled')
            return
        
        try:
            self.log_text.config(state='normal')
            self.log_text.delete(1.0, 'end')
            
            with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                self.log_text.insert('end', content)
            
            self.log_text.config(state='disabled')
            
        except Exception as e:
            self.log_text.config(state='normal')
            self.log_text.delete(1.0, 'end')
            self.log_text.insert('end', f"Error loading log file: {e}")
            self.log_text.config(state='disabled')
    
    def clear_log_display(self):
        """Clear the log display"""
        self.log_text.config(state='normal')
        self.log_text.delete(1.0, 'end')
        self.log_text.config(state='disabled')
    
    def toggle_auto_scroll(self):
        """Toggle auto-scroll for logs"""
        self.auto_scroll = not self.auto_scroll
        status = "enabled" if self.auto_scroll else "disabled"
        self.log_message(f"Auto-scroll {status}")
    
    def open_log_in_editor(self):
        """Open selected log in external editor"""
        log_file = self.log_file_var.get()
        if not log_file:
            return
        
        log_path = self.server_dir / log_file
        
        if not log_path.exists():
            messagebox.showerror("Error", f"Log file not found: {log_path}")
            return
        
        try:
            # Try to open with system default editor
            if os.name == 'nt':  # Windows
                os.startfile(str(log_path))
            elif os.name == 'posix':  # Linux/macOS
                subprocess.run(['xdg-open', str(log_path)], check=True)
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to open log file: {e}")
    
    # Status and Monitoring
    def update_status(self):
        """Update server status display"""
        if self.server_process and self.server_process.poll() is None:
            if self.server_status == "running":
                status_color = "green"
                status_text = "Running"
            else:
                status_color = "orange"
                status_text = "Starting"
        else:
            status_color = "red"
            status_text = "Stopped"
            self.server_status = "stopped"
        
        self.status_label.config(text=f"Status: {status_text}")
        
        # Update players (placeholder - would need server query for real data)
        self.players_label.config(text=f"Players: 0/{self.max_players_var.get()}")
    
    def monitor_server(self):
        """Monitor server status periodically"""
        self.update_status()
        self.root.after(5000, self.monitor_server)  # Check every 5 seconds
    
    def log_message(self, message):
        """Log a message to status bar"""
        self.status_text.config(text=message)
        print(f"[GUI] {message}")  # Also log to console for debugging

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Minecraft Server Management GUI')
    parser.add_argument('server_dir', nargs='?', help='Server directory path')
    parser.add_argument('--no-gui', action='store_true', help='Disable GUI (for testing)')
    
    args = parser.parse_args()
    
    if args.no_gui:
        print("GUI disabled")
        return
    
    # Check if we have a display (for headless servers)
    if os.name == 'posix' and not os.environ.get('DISPLAY'):
        print("No display available, GUI disabled")
        return
    
    try:
        root = tk.Tk()
        app = MinecraftServerGUI(root, args.server_dir)
        root.mainloop()
        
    except Exception as e:
        print(f"Failed to start GUI: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())