#!/usr/bin/env python3
"""
Advanced Configuration Manager for Minecraft Server Setup
========================================================

This Python tool handles complex configuration management tasks including:
- JSON/YAML configuration parsing and manipulation
- Template processing for configuration files
- Advanced server.properties handling
- Configuration validation and migration
- Multi-format configuration support

Usage:
    python3 config_manager.py <command> [options]

Commands:
    validate-properties <file>     - Validate server.properties file
    merge-configs <base> <overlay> - Merge two configuration files
    template-process <template> <vars> - Process configuration template
    convert-format <input> <output> - Convert between config formats
    extract-schema <file>          - Extract configuration schema
"""

import json
import sys
import os
import argparse
import logging
from pathlib import Path
from typing import Dict, Any, Optional, Union, List
import re
from dataclasses import dataclass, asdict
from enum import Enum


# =============================================================================
# CONFIGURATION CLASSES AND TYPES
# =============================================================================

class ConfigFormat(Enum):
    """Supported configuration formats"""
    PROPERTIES = "properties"
    JSON = "json"
    YAML = "yaml"
    ENV = "env"


@dataclass
class ServerConfig:
    """Minecraft server configuration structure"""
    # Server Identity
    motd: str = "A Minecraft Server"
    server_port: int = 25565
    server_ip: str = ""
    
    # World Settings
    level_name: str = "world"
    level_seed: str = ""
    level_type: str = "default"
    difficulty: str = "normal"
    spawn_protection: int = 16
    
    # Player Settings
    max_players: int = 20
    pvp: bool = True
    white_list: bool = False
    online_mode: bool = True
    
    # Performance Settings
    view_distance: int = 10
    allow_nether: bool = True
    enable_command_block: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary with server.properties format"""
        return {
            "motd": self.motd,
            "server-port": str(self.server_port),
            "server-ip": self.server_ip,
            "level-name": self.level_name,
            "level-seed": self.level_seed,
            "level-type": self.level_type,
            "difficulty": self.difficulty,
            "spawn-protection": str(self.spawn_protection),
            "max-players": str(self.max_players),
            "pvp": str(self.pvp).lower(),
            "white-list": str(self.white_list).lower(),
            "online-mode": str(self.online_mode).lower(),
            "view-distance": str(self.view_distance),
            "allow-nether": str(self.allow_nether).lower(),
            "enable-command-block": str(self.enable_command_block).lower(),
        }


# =============================================================================
# CONFIGURATION PARSER
# =============================================================================

class ConfigParser:
    """Multi-format configuration parser"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
    
    def detect_format(self, file_path: Path) -> ConfigFormat:
        """Auto-detect configuration file format"""
        suffix = file_path.suffix.lower()
        name = file_path.name.lower()
        
        if name == "server.properties" or suffix == ".properties":
            return ConfigFormat.PROPERTIES
        elif suffix in [".json"]:
            return ConfigFormat.JSON
        elif suffix in [".yml", ".yaml"]:
            return ConfigFormat.YAML
        elif name == ".env" or suffix == ".env":
            return ConfigFormat.ENV
        else:
            # Try to detect by content
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                    if content.startswith('{') and content.endswith('}'):
                        return ConfigFormat.JSON
                    elif '=' in content and not content.startswith('---'):
                        return ConfigFormat.PROPERTIES
                    else:
                        return ConfigFormat.YAML
            except Exception:
                return ConfigFormat.PROPERTIES
    
    def parse_properties(self, file_path: Path) -> Dict[str, str]:
        """Parse Java properties file format"""
        config = {}
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    
                    # Skip comments and empty lines
                    if not line or line.startswith('#') or line.startswith('!'):
                        continue
                    
                    # Parse key=value
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Handle escaped characters
                        value = value.replace('\\n', '\n').replace('\\r', '\r').replace('\\t', '\t')
                        
                        config[key] = value
                    else:
                        self.logger.warning(f"Invalid property line {line_num}: {line}")
                        
        except Exception as e:
            self.logger.error(f"Failed to parse properties file {file_path}: {e}")
            raise
        
        return config
    
    def parse_json(self, file_path: Path) -> Dict[str, Any]:
        """Parse JSON configuration file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            self.logger.error(f"Failed to parse JSON file {file_path}: {e}")
            raise
    
    def parse_yaml(self, file_path: Path) -> Dict[str, Any]:
        """Parse YAML configuration file"""
        try:
            import yaml
            with open(file_path, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f) or {}
        except ImportError:
            self.logger.error("PyYAML not installed. Install with: pip install PyYAML")
            raise
        except Exception as e:
            self.logger.error(f"Failed to parse YAML file {file_path}: {e}")
            raise
    
    def parse_env(self, file_path: Path) -> Dict[str, str]:
        """Parse .env file format"""
        config = {}
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    
                    # Skip comments and empty lines
                    if not line or line.startswith('#'):
                        continue
                    
                    # Parse KEY=value
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Remove quotes if present
                        if (value.startswith('"') and value.endswith('"')) or \
                           (value.startswith("'") and value.endswith("'")):
                            value = value[1:-1]
                        
                        config[key] = value
                    else:
                        self.logger.warning(f"Invalid env line {line_num}: {line}")
                        
        except Exception as e:
            self.logger.error(f"Failed to parse env file {file_path}: {e}")
            raise
        
        return config
    
    def parse_file(self, file_path: Path) -> Dict[str, Any]:
        """Parse configuration file based on format"""
        format_type = self.detect_format(file_path)
        
        if format_type == ConfigFormat.PROPERTIES:
            return self.parse_properties(file_path)
        elif format_type == ConfigFormat.JSON:
            return self.parse_json(file_path)
        elif format_type == ConfigFormat.YAML:
            return self.parse_yaml(file_path)
        elif format_type == ConfigFormat.ENV:
            return self.parse_env(file_path)
        else:
            raise ValueError(f"Unsupported format: {format_type}")


# =============================================================================
# CONFIGURATION WRITER
# =============================================================================

class ConfigWriter:
    """Multi-format configuration writer"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
    
    def write_properties(self, config: Dict[str, Any], file_path: Path):
        """Write Java properties file format"""
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write("# Minecraft server properties\n")
                f.write(f"# Generated by config_manager.py at {self._get_timestamp()}\n")
                f.write("#\n")
                
                for key, value in sorted(config.items()):
                    # Escape special characters
                    escaped_value = str(value).replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
                    f.write(f"{key}={escaped_value}\n")
                    
        except Exception as e:
            self.logger.error(f"Failed to write properties file {file_path}: {e}")
            raise
    
    def write_json(self, config: Dict[str, Any], file_path: Path):
        """Write JSON configuration file"""
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            self.logger.error(f"Failed to write JSON file {file_path}: {e}")
            raise
    
    def write_yaml(self, config: Dict[str, Any], file_path: Path):
        """Write YAML configuration file"""
        try:
            import yaml
            with open(file_path, 'w', encoding='utf-8') as f:
                yaml.safe_dump(config, f, default_flow_style=False, allow_unicode=True)
        except ImportError:
            self.logger.error("PyYAML not installed. Install with: pip install PyYAML")
            raise
        except Exception as e:
            self.logger.error(f"Failed to write YAML file {file_path}: {e}")
            raise
    
    def write_env(self, config: Dict[str, Any], file_path: Path):
        """Write .env file format"""
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write("# Environment configuration\n")
                f.write(f"# Generated by config_manager.py at {self._get_timestamp()}\n")
                f.write("\n")
                
                for key, value in sorted(config.items()):
                    # Quote values with spaces or special characters
                    str_value = str(value)
                    if ' ' in str_value or any(c in str_value for c in ['$', '"', "'", '\\', '`']):
                        str_value = f'"{str_value}"'
                    f.write(f"{key}={str_value}\n")
                    
        except Exception as e:
            self.logger.error(f"Failed to write env file {file_path}: {e}")
            raise
    
    def write_file(self, config: Dict[str, Any], file_path: Path, format_type: Optional[ConfigFormat] = None):
        """Write configuration file based on format"""
        if format_type is None:
            parser = ConfigParser()
            format_type = parser.detect_format(file_path)
        
        if format_type == ConfigFormat.PROPERTIES:
            self.write_properties(config, file_path)
        elif format_type == ConfigFormat.JSON:
            self.write_json(config, file_path)
        elif format_type == ConfigFormat.YAML:
            self.write_yaml(config, file_path)
        elif format_type == ConfigFormat.ENV:
            self.write_env(config, file_path)
        else:
            raise ValueError(f"Unsupported format: {format_type}")
    
    def _get_timestamp(self) -> str:
        """Get formatted timestamp"""
        from datetime import datetime
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')


# =============================================================================
# CONFIGURATION VALIDATOR
# =============================================================================

class ConfigValidator:
    """Configuration validation and schema checking"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.errors = []
        self.warnings = []
    
    def validate_server_properties(self, config: Dict[str, str]) -> bool:
        """Validate server.properties configuration"""
        self.errors.clear()
        self.warnings.clear()
        
        # Required properties
        required_props = ["server-port", "level-name"]
        for prop in required_props:
            if prop not in config:
                self.errors.append(f"Missing required property: {prop}")
        
        # Validate specific properties
        self._validate_server_port(config.get("server-port"))
        self._validate_difficulty(config.get("difficulty"))
        self._validate_boolean_properties(config)
        self._validate_numeric_properties(config)
        self._validate_string_properties(config)
        
        # Report results
        if self.errors:
            self.logger.error(f"Validation failed with {len(self.errors)} error(s):")
            for error in self.errors:
                self.logger.error(f"  - {error}")
        
        if self.warnings:
            self.logger.warning(f"Validation completed with {len(self.warnings)} warning(s):")
            for warning in self.warnings:
                self.logger.warning(f"  - {warning}")
        
        return len(self.errors) == 0
    
    def _validate_server_port(self, port_str: Optional[str]):
        """Validate server port"""
        if not port_str:
            return
        
        try:
            port = int(port_str)
            if port < 1 or port > 65535:
                self.errors.append(f"Invalid server port: {port} (must be 1-65535)")
            elif port < 1024:
                self.warnings.append(f"Server port {port} requires root privileges")
        except ValueError:
            self.errors.append(f"Invalid server port format: {port_str} (must be integer)")
    
    def _validate_difficulty(self, difficulty: Optional[str]):
        """Validate difficulty setting"""
        if not difficulty:
            return
        
        valid_difficulties = ["peaceful", "easy", "normal", "hard"]
        if difficulty not in valid_difficulties:
            self.errors.append(f"Invalid difficulty: {difficulty} (must be one of: {', '.join(valid_difficulties)})")
    
    def _validate_boolean_properties(self, config: Dict[str, str]):
        """Validate boolean properties"""
        bool_props = ["pvp", "white-list", "allow-nether", "online-mode", "enable-command-block"]
        
        for prop in bool_props:
            value = config.get(prop)
            if value and value not in ["true", "false"]:
                self.errors.append(f"Invalid boolean value for {prop}: {value} (must be 'true' or 'false')")
    
    def _validate_numeric_properties(self, config: Dict[str, str]):
        """Validate numeric properties"""
        numeric_props = {
            "max-players": (1, 2147483647),
            "view-distance": (3, 32),
            "spawn-protection": (0, 2147483647)
        }
        
        for prop, (min_val, max_val) in numeric_props.items():
            value = config.get(prop)
            if value:
                try:
                    num_val = int(value)
                    if num_val < min_val or num_val > max_val:
                        self.errors.append(f"Invalid {prop}: {num_val} (must be {min_val}-{max_val})")
                except ValueError:
                    self.errors.append(f"Invalid {prop} format: {value} (must be integer)")
    
    def _validate_string_properties(self, config: Dict[str, str]):
        """Validate string properties"""
        level_name = config.get("level-name", "")
        if level_name:
            # Check for invalid characters in level name
            invalid_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
            for char in invalid_chars:
                if char in level_name:
                    self.errors.append(f"Invalid character '{char}' in level-name: {level_name}")
                    break


# =============================================================================
# CONFIGURATION MERGER
# =============================================================================

class ConfigMerger:
    """Configuration merging and template processing"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
    
    def merge_configs(self, base_config: Dict[str, Any], overlay_config: Dict[str, Any]) -> Dict[str, Any]:
        """Merge two configurations with overlay taking precedence"""
        merged = base_config.copy()
        
        for key, value in overlay_config.items():
            if isinstance(value, dict) and key in merged and isinstance(merged[key], dict):
                # Recursively merge nested dictionaries
                merged[key] = self.merge_configs(merged[key], value)
            else:
                # Override with overlay value
                merged[key] = value
        
        return merged
    
    def process_template(self, template_config: Dict[str, Any], variables: Dict[str, Any]) -> Dict[str, Any]:
        """Process configuration template with variable substitution"""
        result = {}
        
        for key, value in template_config.items():
            if isinstance(value, str):
                # Substitute variables in string values
                result[key] = self._substitute_variables(value, variables)
            elif isinstance(value, dict):
                # Recursively process nested dictionaries
                result[key] = self.process_template(value, variables)
            else:
                # Keep other types as-is
                result[key] = value
        
        return result
    
    def _substitute_variables(self, template: str, variables: Dict[str, Any]) -> str:
        """Substitute variables in template string"""
        # Support ${VAR} and $VAR formats
        result = template
        
        for var_name, var_value in variables.items():
            # ${VAR} format
            result = result.replace(f"${{{var_name}}}", str(var_value))
            # $VAR format (word boundaries to avoid partial matches)
            result = re.sub(rf'\${var_name}\b', str(var_value), result)
        
        return result


# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

def setup_logging(verbose: bool = False):
    """Setup logging configuration"""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(levelname)s: %(message)s'
    )


def cmd_validate_properties(args):
    """Validate server.properties file"""
    file_path = Path(args.file)
    
    if not file_path.exists():
        print(f"Error: File not found: {file_path}")
        return 1
    
    parser = ConfigParser()
    validator = ConfigValidator()
    
    try:
        config = parser.parse_file(file_path)
        is_valid = validator.validate_server_properties(config)
        
        if is_valid:
            print("✓ Configuration is valid")
            return 0
        else:
            print("✗ Configuration validation failed")
            return 1
            
    except Exception as e:
        print(f"Error validating configuration: {e}")
        return 1


def cmd_merge_configs(args):
    """Merge two configuration files"""
    base_path = Path(args.base)
    overlay_path = Path(args.overlay)
    output_path = Path(args.output) if args.output else None
    
    parser = ConfigParser()
    writer = ConfigWriter()
    merger = ConfigMerger()
    
    try:
        base_config = parser.parse_file(base_path)
        overlay_config = parser.parse_file(overlay_path)
        
        merged_config = merger.merge_configs(base_config, overlay_config)
        
        if output_path:
            writer.write_file(merged_config, output_path)
            print(f"Merged configuration written to: {output_path}")
        else:
            print(json.dumps(merged_config, indent=2))
        
        return 0
        
    except Exception as e:
        print(f"Error merging configurations: {e}")
        return 1


def cmd_convert_format(args):
    """Convert between configuration formats"""
    input_path = Path(args.input)
    output_path = Path(args.output)
    
    parser = ConfigParser()
    writer = ConfigWriter()
    
    try:
        config = parser.parse_file(input_path)
        
        # Determine output format
        output_format = None
        if args.format:
            output_format = ConfigFormat(args.format.lower())
        
        writer.write_file(config, output_path, output_format)
        print(f"Configuration converted: {input_path} -> {output_path}")
        
        return 0
        
    except Exception as e:
        print(f"Error converting configuration: {e}")
        return 1


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Advanced Configuration Manager for Minecraft Server Setup"
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Validate command
    validate_parser = subparsers.add_parser("validate", help="Validate server.properties file")
    validate_parser.add_argument("file", help="Path to server.properties file")
    
    # Merge command
    merge_parser = subparsers.add_parser("merge", help="Merge two configuration files")
    merge_parser.add_argument("base", help="Base configuration file")
    merge_parser.add_argument("overlay", help="Overlay configuration file")
    merge_parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    
    # Convert command
    convert_parser = subparsers.add_parser("convert", help="Convert between config formats")
    convert_parser.add_argument("input", help="Input configuration file")
    convert_parser.add_argument("output", help="Output configuration file")
    convert_parser.add_argument("-f", "--format", choices=["properties", "json", "yaml", "env"],
                                help="Force output format (default: auto-detect)")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    setup_logging(args.verbose)
    
    # Execute command
    if args.command == "validate":
        return cmd_validate_properties(args)
    elif args.command == "merge":
        return cmd_merge_configs(args)
    elif args.command == "convert":
        return cmd_convert_format(args)
    else:
        print(f"Unknown command: {args.command}")
        return 1


if __name__ == "__main__":
    sys.exit(main())