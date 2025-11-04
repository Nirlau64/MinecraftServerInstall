#!/usr/bin/env bash
# Configuration Management Module
# ==============================
# This module handles server configuration, environment loading,
# and server.properties management for the Minecraft server setup.

# -----------------------------------------------------------------------------
# SERVER.PROPERTIES DEFAULTS 
# -----------------------------------------------------------------------------
# These can be overridden by CLI arguments or environment variables
declare -g PROP_MOTD="${PROP_MOTD:-Modded Minecraft Server}"
declare -g PROP_DIFFICULTY="${PROP_DIFFICULTY:-normal}"
declare -g PROP_PVP="${PROP_PVP:-true}"
declare -g PROP_VIEW_DISTANCE="${PROP_VIEW_DISTANCE:-10}"
declare -g PROP_WHITE_LIST="${PROP_WHITE_LIST:-false}"
declare -g PROP_MAX_PLAYERS="${PROP_MAX_PLAYERS:-20}"
declare -g PROP_SPAWN_PROTECTION="${PROP_SPAWN_PROTECTION:-0}"
declare -g PROP_ALLOW_NETHER="${PROP_ALLOW_NETHER:-true}"
declare -g PROP_LEVEL_NAME="${PROP_LEVEL_NAME:-world}"
declare -g PROP_LEVEL_SEED="${PROP_LEVEL_SEED:-}"
declare -g PROP_LEVEL_TYPE="${PROP_LEVEL_TYPE:-default}"

# -----------------------------------------------------------------------------
# CONFIGURATION LOADING FUNCTIONS
# -----------------------------------------------------------------------------

# Load configuration from .env file if it exists
# Usage: load_env_config [env_file]
load_env_config() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        log_debug "No .env file found at $env_file, skipping env config loading"
        return 0
    fi
    
    log_info "Loading configuration from $env_file..."
    
    # Read .env file line by line
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        
        # Remove quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        # Set configuration variables
        case "$key" in
            MOTD) PROP_MOTD="$value" ;;
            DIFFICULTY) PROP_DIFFICULTY="$value" ;;
            PVP) PROP_PVP="$value" ;;
            VIEW_DISTANCE) PROP_VIEW_DISTANCE="$value" ;;
            WHITE_LIST) PROP_WHITE_LIST="$value" ;;
            MAX_PLAYERS) PROP_MAX_PLAYERS="$value" ;;
            SPAWN_PROTECTION) PROP_SPAWN_PROTECTION="$value" ;;
            ALLOW_NETHER) PROP_ALLOW_NETHER="$value" ;;
            LEVEL_NAME) PROP_LEVEL_NAME="$value" ;;
            LEVEL_SEED) PROP_LEVEL_SEED="$value" ;;
            LEVEL_TYPE) PROP_LEVEL_TYPE="$value" ;;
            WORLD_NAME) WORLD_NAME="$value" ;;
            OP_USERNAME) OP_USERNAME="$value" ;;
            OP_LEVEL) OP_LEVEL="$value" ;;
            *)
                # Store other variables for later use
                declare -g "ENV_$key"="$value"
                ;;
        esac
    done < "$env_file"
    
    log_info "Configuration loaded from $env_file"
}

# -----------------------------------------------------------------------------
# SERVER.PROPERTIES MANAGEMENT
# -----------------------------------------------------------------------------

# Create server.properties template with defaults
# Usage: create_server_properties_template [target_file]
create_server_properties_template() {
    local file="${1:-server.properties}"
    
    if [[ -f "$file" ]]; then
        log_info "$file already exists. Skipping template creation."
        return 0
    fi
    
    log_info "Creating $file template with sensible defaults..."
    
    # Create the server.properties file with defaults
    cat > "$file" <<EOF
# Minecraft server properties (auto-generated)
# For details see https://minecraft.fandom.com/wiki/Server.properties
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Server Identity
motd=$PROP_MOTD
server-port=25565

# World Settings
level-name=${WORLD_NAME:-$PROP_LEVEL_NAME}
level-seed=$PROP_LEVEL_SEED
level-type=$PROP_LEVEL_TYPE
difficulty=$PROP_DIFFICULTY
spawn-protection=$PROP_SPAWN_PROTECTION

# Player Settings
max-players=$PROP_MAX_PLAYERS
pvp=$PROP_PVP
white-list=$PROP_WHITE_LIST

# Performance Settings
view-distance=$PROP_VIEW_DISTANCE
allow-nether=$PROP_ALLOW_NETHER

# Other Settings
online-mode=true
enable-command-block=false
EOF
    
    log_info "$file template created successfully."
}

# Update server.properties from .env file
# Usage: update_server_properties_from_env [env_file] [prop_file]
update_server_properties_from_env() {
    local env_file="${1:-.env}"
    local prop_file="${2:-server.properties}"
    
    [[ -f "$env_file" ]] || return 0
    [[ -f "$prop_file" ]] || {
        log_warn "server.properties file not found: $prop_file"
        return 1
    }
    
    log_info "Updating $prop_file from $env_file..."
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        
        # Remove quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        # Only update known server.properties keys
        case "$key" in
            DIFFICULTY|PVP|MOTD|VIEW_DISTANCE|WHITE_LIST|MAX_PLAYERS|SPAWN_PROTECTION|ALLOW_NETHER|LEVEL_NAME|LEVEL_SEED|LEVEL_TYPE)
                # Map env key to server.properties key
                local prop_key
                case "$key" in
                    DIFFICULTY) prop_key="difficulty";;
                    PVP) prop_key="pvp";;
                    MOTD) prop_key="motd";;
                    VIEW_DISTANCE) prop_key="view-distance";;
                    WHITE_LIST) prop_key="white-list";;
                    MAX_PLAYERS) prop_key="max-players";;
                    SPAWN_PROTECTION) prop_key="spawn-protection";;
                    ALLOW_NETHER) prop_key="allow-nether";;
                    LEVEL_NAME) prop_key="level-name";;
                    LEVEL_SEED) prop_key="level-seed";;
                    LEVEL_TYPE) prop_key="level-type";;
                esac
                
                # Idempotent update: replace or add
                update_server_property "$prop_file" "$prop_key" "$value"
                ;;
        esac
    done < "$env_file"
    
    # Handle WORLD_NAME separately as it maps to level-name
    if [[ -n "${WORLD_NAME:-}" ]]; then
        update_server_property "$prop_file" "level-name" "$WORLD_NAME"
        log_info "Set level-name from WORLD_NAME: $WORLD_NAME"
    fi
}

# Update a single property in server.properties
# Usage: update_server_property <file> <key> <value>
update_server_property() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    [[ -f "$file" ]] || {
        log_error "Property file not found: $file"
        return 1
    }
    
    # Escape special characters in sed
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    if grep -q "^$key=" "$file"; then
        # Update existing property
        sed -i "s|^$key=.*|$key=$escaped_value|" "$file"
        log_debug "Updated property: $key=$value"
    else
        # Add new property
        echo "$key=$value" >> "$file"
        log_debug "Added property: $key=$value"
    fi
}

# Get property value from server.properties
# Usage: get_server_property <file> <key>
get_server_property() {
    local file="$1"
    local key="$2"
    
    [[ -f "$file" ]] || {
        log_error "Property file not found: $file"
        return 1
    }
    
    grep "^$key=" "$file" 2>/dev/null | cut -d'=' -f2- || return 1
}

# Validate server.properties configuration
# Usage: validate_server_properties [prop_file]
validate_server_properties() {
    local prop_file="${1:-server.properties}"
    local errors=0
    
    [[ -f "$prop_file" ]] || {
        log_error "server.properties file not found: $prop_file"
        return 1
    }
    
    log_info "Validating server.properties configuration..."
    
    # Check required properties exist
    local required_props=("server-port" "level-name" "difficulty")
    for prop in "${required_props[@]}"; do
        if ! get_server_property "$prop_file" "$prop" >/dev/null; then
            log_error "Missing required property: $prop"
            ((errors++))
        fi
    done
    
    # Validate difficulty values
    local difficulty
    difficulty=$(get_server_property "$prop_file" "difficulty")
    if [[ -n "$difficulty" ]]; then
        case "$difficulty" in
            peaceful|easy|normal|hard) ;;
            *)
                log_error "Invalid difficulty value: $difficulty (must be peaceful, easy, normal, or hard)"
                ((errors++))
                ;;
        esac
    fi
    
    # Validate boolean properties
    local bool_props=("pvp" "white-list" "allow-nether" "online-mode")
    for prop in "${bool_props[@]}"; do
        local value
        value=$(get_server_property "$prop_file" "$prop")
        if [[ -n "$value" && "$value" != "true" && "$value" != "false" ]]; then
            log_error "Invalid boolean value for $prop: $value (must be true or false)"
            ((errors++))
        fi
    done
    
    # Validate numeric properties
    local max_players
    max_players=$(get_server_property "$prop_file" "max-players")
    if [[ -n "$max_players" && ! "$max_players" =~ ^[0-9]+$ ]]; then
        log_error "Invalid max-players value: $max_players (must be a number)"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "server.properties validation passed"
        return 0
    else
        log_error "server.properties validation failed with $errors error(s)"
        return 1
    fi
}

# Apply CLI overrides to properties
# Usage: apply_cli_overrides
apply_cli_overrides() {
    log_debug "Configuration defaults applied from CLI overrides"
    # Properties are already set via PROP_* variables from CLI parsing
    # This function is here for extensibility and explicit documentation
    return 0
}

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------

# Display current configuration
# Usage: show_config
show_config() {
    log_info "Current server configuration:"
    echo "  MOTD: $PROP_MOTD"
    echo "  Difficulty: $PROP_DIFFICULTY" 
    echo "  PVP: $PROP_PVP"
    echo "  View Distance: $PROP_VIEW_DISTANCE"
    echo "  White List: $PROP_WHITE_LIST"
    echo "  Max Players: $PROP_MAX_PLAYERS"
    echo "  Spawn Protection: $PROP_SPAWN_PROTECTION"
    echo "  Allow Nether: $PROP_ALLOW_NETHER"
    echo "  Level Name: ${WORLD_NAME:-$PROP_LEVEL_NAME}"
    echo "  Level Seed: $PROP_LEVEL_SEED"
    echo "  Level Type: $PROP_LEVEL_TYPE"
}

# Export this module is loaded
declare -g CONFIG_MODULE_LOADED=1