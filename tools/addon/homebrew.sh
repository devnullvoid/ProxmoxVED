#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MorganCSIT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://brew.sh | Github: https://github.com/Homebrew/brew

if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR
load_functions
init_tool_telemetry "" "addon"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
VERBOSE=${var_verbose:-no}
APP="homebrew"
APP_TYPE="tools"
INSTALL_PATH="/home/linuxbrew/.linuxbrew"

# ==============================================================================
# OS DETECTION
# ==============================================================================
if [[ -f "/etc/alpine-release" ]]; then
  echo -e "${CROSS} Alpine is not supported by Homebrew. Exiting."
  exit 1
elif grep -qE 'ID=debian|ID=ubuntu' /etc/os-release; then
  OS="Debian"
else
  echo -e "${CROSS} Unsupported OS detected. Exiting."
  exit 1
fi

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling Homebrew"

  BREW_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
  if [[ -n "$BREW_USER" ]]; then
    BREW_USER_HOME=$(getent passwd "$BREW_USER" | cut -d: -f6)
    if [[ -f "$BREW_USER_HOME/.bashrc" ]]; then
      sed -i '/# Homebrew (Linuxbrew)/,/^fi$/d' "$BREW_USER_HOME/.bashrc"
    fi
  fi

  rm -rf /home/linuxbrew
  rm -f /etc/profile.d/homebrew.sh
  groupdel linuxbrew &>/dev/null || true

  msg_ok "Homebrew has been uninstalled"
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  msg_info "Detecting Non-Root User"
  BREW_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
  if [[ -z "$BREW_USER" ]]; then
    msg_error "No non-root user found (uid >= 1000). Homebrew cannot run as root. Create a user first."
    exit 1
  fi
  msg_ok "Detected User: $BREW_USER"

  msg_info "Installing Dependencies"
  $STD apt update
  $STD apt install -y build-essential git file procps
  msg_ok "Installed Dependencies"

  msg_info "Setting Up Homebrew Prefix"
  export PATH="/usr/sbin:$PATH"
  groupadd -f linuxbrew
  mkdir -p /home/linuxbrew/.linuxbrew
  chown -R "$BREW_USER":linuxbrew /home/linuxbrew
  chmod 2775 /home/linuxbrew
  chmod 2775 /home/linuxbrew/.linuxbrew
  usermod -aG linuxbrew "$BREW_USER"
  msg_ok "Set Up Homebrew Prefix"

  msg_info "Installing Homebrew"
  $STD su - "$BREW_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  msg_ok "Installed Homebrew"

  msg_info "Configuring Shell Integration"
  cat <<'EOF'> /etc/profile.d/homebrew.sh
#!/bin/bash
if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
  chmod +x /etc/profile.d/homebrew.sh

  BREW_USER_HOME=$(getent passwd "$BREW_USER" | cut -d: -f6)
  if ! grep -q 'linuxbrew' "$BREW_USER_HOME/.bashrc" 2>/dev/null; then
    cat >> "$BREW_USER_HOME/.bashrc" << 'EOF'

# Homebrew (Linuxbrew)
if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
  fi
  msg_ok "Configured Shell Integration"

  msg_info "Verifying Installation"
  $STD su - "$BREW_USER" -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew --version'
  msg_ok "Homebrew Verified"

  echo ""
  msg_ok "Homebrew installed successfully"
  msg_ok "Ready for user: ${BL}${BREW_USER}${CL}"
  msg_ok "Homebrew updates itself via: ${BL}brew update${CL}"
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info

if [[ -d "$INSTALL_PATH" ]]; then
  msg_warn "Homebrew is already installed."
  echo ""

  echo -n "${TAB}Uninstall Homebrew? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "Homebrew is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - Homebrew (Linuxbrew) package manager"
echo -e "${TAB}  - Shell integration for the detected non-root user"
echo ""

echo -n "${TAB}Install Homebrew? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
