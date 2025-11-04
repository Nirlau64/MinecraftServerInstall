#!/usr/bin/env bash
################################################################################
# Java Management Module
# Part of Universal Minecraft Server Setup Script
# 
# This module handles:
# - Java version detection based on Minecraft version
# - Java installation using various package managers
# - Java version validation
################################################################################

# Ensure this module is not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This is a library module and should not be executed directly."
  exit 1
fi

################################################################################
# Function: detect_java_version
# Description: Detects current Java version from java -version output
# Parameters: None (uses java command if available)
# Returns:
#   0 - Java detected, sets CURRENT_JAVA_VERSION variable
#   1 - Java not found or version could not be parsed
################################################################################
detect_java_version() {
  if ! command -v java >/dev/null 2>&1; then
    return 1
  fi
  
  local java_output
  java_output=$(java -version 2>&1)
  log_info "Java version output: $java_output"
  
  # Extended version detection for different output formats
  # Format 1: "1.8.0_xxx" -> Java 8
  if echo "$java_output" | grep -q "version \"1.8"; then
    CURRENT_JAVA_VERSION=8
  # Format 2: "1.11.x" -> Java 11 (for compatibility)
  elif echo "$java_output" | grep -q "version \"1.1"; then
    CURRENT_JAVA_VERSION=11
  # Format 3: "17.0.x", "21.0.x" etc. -> extract major version
  else
    CURRENT_JAVA_VERSION=$(echo "$java_output" | grep -i version | head -n1 | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
  fi
  
  log_info "Detected Java version: $CURRENT_JAVA_VERSION"
  return 0
}

################################################################################
# Function: determine_required_java_version
# Description: Determines required Java version based on Minecraft version
# Parameters:
#   $1 - mc_ver: Minecraft version (e.g. "1.20.1")
# Returns:
#   Sets REQUIRED_JAVA_VERSION variable
# Logic:
#   - MC 1.20.5+ requires Java 21
#   - MC 1.17-1.20.4 requires Java 17
#   - MC <1.17 requires Java 8
################################################################################
determine_required_java_version() {
  local mc_ver="$1"
  
  # MC 1.20.5+ requires Java 21 (class file version 65.0)
  if printf '%s\n' "1.20.5" "$mc_ver" | sort -V | head -n1 | grep -q "^1.20.5"; then
    REQUIRED_JAVA_VERSION=21
  # MC 1.17-1.20.4 requires Java 17 (class file version 61.0)
  elif printf '%s\n' "1.17" "$mc_ver" | sort -V | head -n1 | grep -q "^1.17"; then
    REQUIRED_JAVA_VERSION=17
  # MC <1.17 requires Java 8
  else
    REQUIRED_JAVA_VERSION=8
  fi
  
  log_info "Minecraft $mc_ver requires Java $REQUIRED_JAVA_VERSION"
}

################################################################################
# Function: install_java_debian
# Description: Install Java on Debian/Ubuntu systems
# Parameters:
#   $1 - java_version: Java version to install (8, 17, 21)
################################################################################
install_java_debian() {
  local java_ver="$1"
  
  log_info "Installing Java $java_ver via apt..."
  
  case "$java_ver" in
    21)
      run sudo apt-get update
      run sudo apt-get install -y openjdk-21-jre-headless
      run sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-*/bin/java 2>/dev/null || true
      ;;
    17)
      run sudo apt-get update
      run sudo apt-get install -y openjdk-17-jre-headless
      run sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-*/bin/java 2>/dev/null || true
      ;;
    8)
      run sudo apt-get update
      run sudo apt-get install -y openjdk-8-jre-headless
      run sudo update-alternatives --set java /usr/lib/jvm/java-8-openjdk-*/jre/bin/java 2>/dev/null || true
      ;;
    *)
      log_err "Unsupported Java version for Debian/Ubuntu: $java_ver"
      return 1
      ;;
  esac
}

################################################################################
# Function: install_java_fedora
# Description: Install Java on Fedora/RHEL systems
# Parameters:
#   $1 - java_version: Java version to install (8, 17, 21)
################################################################################
install_java_fedora() {
  local java_ver="$1"
  
  log_info "Installing Java $java_ver via dnf..."
  
  case "$java_ver" in
    21)
      run sudo dnf install -y java-21-openjdk-headless
      ;;
    17)
      run sudo dnf install -y java-17-openjdk-headless
      ;;
    8)
      run sudo dnf install -y java-1.8.0-openjdk-headless
      ;;
    *)
      log_err "Unsupported Java version for Fedora/RHEL: $java_ver"
      return 1
      ;;
  esac
}

################################################################################
# Function: install_java_arch
# Description: Install Java on Arch Linux systems
# Parameters:
#   $1 - java_version: Java version to install (8, 17, 21)
################################################################################
install_java_arch() {
  local java_ver="$1"
  
  log_info "Installing Java $java_ver via pacman..."
  
  case "$java_ver" in
    21)
      run sudo pacman -Sy --noconfirm jre21-openjdk-headless
      ;;
    17)
      run sudo pacman -Sy --noconfirm jre17-openjdk-headless
      ;;
    8)
      run sudo pacman -Sy --noconfirm jre8-openjdk-headless
      ;;
    *)
      log_err "Unsupported Java version for Arch Linux: $java_ver"
      return 1
      ;;
  esac
}

################################################################################
# Function: install_java_opensuse
# Description: Install Java on openSUSE systems
# Parameters:
#   $1 - java_version: Java version to install (8, 17, 21)
################################################################################
install_java_opensuse() {
  local java_ver="$1"
  
  log_info "Installing Java $java_ver via zypper..."
  
  case "$java_ver" in
    21)
      run sudo zypper --non-interactive install java-21-openjdk-headless
      ;;
    17)
      run sudo zypper --non-interactive install java-17-openjdk-headless
      ;;
    8)
      run sudo zypper --non-interactive install java-1_8_0-openjdk-headless
      ;;
    *)
      log_err "Unsupported Java version for openSUSE: $java_ver"
      return 1
      ;;
  esac
}

################################################################################
# Function: install_java_by_package_manager
# Description: Install Java using the appropriate package manager
# Parameters:
#   $1 - java_version: Java version to install (8, 17, 21)
################################################################################
install_java_by_package_manager() {
  local java_ver="$1"
  
  echo "Installing Java $java_ver..."
  
  if command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu
    install_java_debian "$java_ver"
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora/RHEL
    install_java_fedora "$java_ver"
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    install_java_arch "$java_ver"
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE
    install_java_opensuse "$java_ver"
  else
    log_err "Could not detect package manager. Please install Java $java_ver manually."
    log_err "Visit https://adoptium.net/ for installation instructions."
    return 1
  fi
}

################################################################################
# Function: verify_java_installation
# Description: Verifies that Java is correctly installed after installation
# Parameters:
#   $1 - expected_version: Expected Java version (8, 17, 21)
# Returns:
#   0 - Java is correctly installed
#   1 - Installation verification failed
################################################################################
verify_java_installation() {
  local expected_ver="$1"
  
  # Check if Java is available after installation
  if ! command -v java >/dev/null 2>&1; then
    log_err "Java installation failed. Please install Java $expected_ver manually."
    log_err "Visit https://adoptium.net/ for installation instructions."
    return 1
  fi

  # Check installed Java version
  local java_output installed_ver
  java_output=$(java -version 2>&1)
  log_info "Post-install Java version output: $java_output"
  
  # Extended version detection (same as detect_java_version)
  if echo "$java_output" | grep -q "version \"1.8"; then
    installed_ver=8
  elif echo "$java_output" | grep -q "version \"1.1"; then
    installed_ver=11
  else
    installed_ver=$(echo "$java_output" | grep -i version | head -n1 | awk -F '"' '{print $2}' | awk -F '[.|-]' '{print $1}')
  fi
  
  if [ "$installed_ver" != "$expected_ver" ]; then
    log_err "Java version mismatch after installation."
    log_err "Expected Java $expected_ver but found Java $installed_ver"
    log_err "Current alternatives setting:"
    update-alternatives --display java >&2 2>/dev/null || true
    log_err "Available Java installations:"
    ls -l /usr/lib/jvm/java-* 2>&1 || true
    log_err "You may need to set JAVA_HOME or update-alternatives manually."
    return 1
  fi

  log_info "Successfully installed Java $expected_ver"
  return 0
}

################################################################################
# Function: get_java_version
# Description: Get the current Java version as a number
# Returns:
#   Echoes the Java version number (8, 11, 17, 21, etc.)
#   Returns 1 if Java is not found
################################################################################
get_java_version() {
  if detect_java_version; then
    echo "$CURRENT_JAVA_VERSION"
    return 0
  else
    return 1
  fi
}

################################################################################
# Function: setup_java
# Description: Main function - detects required Java version and installs if needed
# Parameters:
#   $1 - mc_ver: Minecraft version (e.g. "1.20.1")
# Returns:
#   0 - Java is correctly installed
#   exit 1 - Installation failed
# Logic:
#   - MC 1.20.5+ requires Java 21
#   - MC 1.17-1.20.4 requires Java 17
#   - MC <1.17 requires Java 8
################################################################################
setup_java() {
  local mc_ver="$1"
  
  # Determine required Java version based on Minecraft version
  determine_required_java_version "$mc_ver"
  
  # Check if a compatible Java version is already installed
  if detect_java_version; then
    if [ "$CURRENT_JAVA_VERSION" = "$REQUIRED_JAVA_VERSION" ]; then
      log_info "Found compatible Java $CURRENT_JAVA_VERSION"
      return 0
    fi
    log_warn "Found Java $CURRENT_JAVA_VERSION, but Java $REQUIRED_JAVA_VERSION is required"
  fi

  # Install required Java version using package manager
  if ! install_java_by_package_manager "$REQUIRED_JAVA_VERSION"; then
    exit $EXIT_INSTALL
  fi

  # Verify installation was successful
  if ! verify_java_installation "$REQUIRED_JAVA_VERSION"; then
    exit $EXIT_INSTALL
  fi

  return 0
}