#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://nixos.org/

set -euo pipefail

# Source helper functions
if [ -n "${FUNCTIONS_FILE_PATH:-}" ] && [ -f "$FUNCTIONS_FILE_PATH" ]; then
    source "$FUNCTIONS_FILE_PATH"
    color
    verb_ip6
    catch_errors
    setting_up_container
    network_check
    update_os
else
    # Fallback if functions aren't available
    msg_info() { echo "[INFO] $*"; }
    msg_ok() { echo "[OK] $*"; }
    msg_error() { echo "[ERROR] $*" >&2; exit 1; }
    STD() { echo "[RUN] $*"; "$@"; }
fi

# Set variables
NIXOS_VERSION="25.05"
NIX_CHANNEL="nixos-${NIXOS_VERSION}"

msg_info "Starting NixOS configuration for Proxmox LXC"

# Ensure NixOS configuration directory exists
mkdir -p /etc/nixos

# Create NixOS configuration for Proxmox LXC
cat > /etc/nixos/configuration.nix << 'EOF'
{ config, modulesPath, pkgs, lib, ... }:

{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  # Enable flakes support
  nix = {
    package = pkgs.nixFlakes;
    extraOptions = "experimental-features = nix-command flakes";
    settings = {
      sandbox = false;
      trusted-users = [ "root" "@wheel" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Proxmox LXC specific settings
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  # SSH configuration
  security.pam.services.sshd.allowNullPassword = true;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
      PermitEmptyPasswords = true;
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = true;
      GatewayPorts = false;
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
    sudo
    nix-output-monitor
    tmux
    file
    lsof
    psmisc
    procps
    util-linux
  ];

  # Set time zone
  time.timeZone = "Etc/UTC";

  # Systemd services
  systemd.services.nixos-upgrade = {
    description = "NixOS Upgrade";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/nixos-rebuild switch --upgrade";
    };
  };

  # Allow passwordless sudo for root
  security.sudo.wheelNeedsPassword = false;

  # Set empty root password (login without password)
  users.users.root.initialHashedPassword = "";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "${NIXOS_VERSION}";
}
EOF

# Generate hardware configuration
msg_info "Generating hardware configuration..."
if ! $STD nixos-generate-config --root /; then
    msg_error "Failed to generate hardware configuration"
    exit 1
fi

# Update NixOS channel
msg_info "Updating NixOS channel to ${NIX_CHANNEL}..."
if ! $STD nix-channel --add "https://nixos.org/channels/${NIX_CHANNEL}" nixos; then
    msg_error "Failed to add NixOS channel"
    exit 1
fi

if ! $STD nix-channel --update; then
    msg_error "Failed to update NixOS channel"
    exit 1
fi

# Install initial system
msg_info "Building NixOS system (this may take a while)..."
if ! $STD nixos-rebuild switch; then
    msg_error "Failed to build NixOS system"
    exit 1
fi

# Clean up nix store to reduce image size
msg_info "Cleaning up Nix store..."
nix-collect-garbage --delete-older-than 7d
nix-store --optimise

# Set up MOTD
cat > /etc/motd << 'MOTD_EOF'

  _  _ _  _  _ _  _  _  _  _
 | \| | || \| || |  \| || |
 |  ` | ||  ` || | |\  || |__
 |_|\__|_||_|\__|_|_\_|____|

 Welcome to NixOS in Proxmox LXC!

 * NixOS Documentation: https://nixos.org/learn/
 * NixOS Manual: https://nixos.org/manual/nixos/stable/
 * Nix Pills: https://nixos.org/guides/nix-pills/

MOTD_EOF

# Run any customizations if available
if [ "$(type -t customize)" = "function" ]; then
    msg_info "Running customizations..."
    customize
fi

msg_ok "NixOS installation complete!"
msg_info "You can now log in as root without a password."
msg_info "To set a root password, run: passwd"
msg_info "To update your system: nixos-rebuild switch --upgrade"
