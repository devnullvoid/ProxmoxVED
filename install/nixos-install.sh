#!/bin/sh

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://nixos.org/

# This script is executed inside the NixOS container after it is created
# Note: NixOS uses a minimal shell environment, so we need to be careful with dependencies

# First, source the Nix environment to set up PATH and other variables
# This is CRITICAL for NixOS containers
if [ -f /etc/set-environment ]; then
    echo "Sourcing /etc/set-environment to initialize Nix environment..."
    . /etc/set-environment
else
    echo "WARNING: /etc/set-environment not found! Nix environment may not be properly initialized." >&2
fi

# Remove root password to allow login
# This is important for initial setup of the container
echo "Removing root password to allow login..."
passwd --delete root

# Set the hostname
if [ -n "$HOSTNAME" ]; then
    echo "Setting hostname to $HOSTNAME"
    hostname "$HOSTNAME"
    echo "$HOSTNAME" > /etc/hostname
    
    # Update /etc/hosts
    if ! grep -q "^127.0.1.1" /etc/hosts; then
        echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    fi
fi

# Set the timezone
if [ -n "$TZ" ]; then
    echo "Setting timezone to $TZ"
    ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# Configure networking (NixOS uses systemd-networkd by default)
if [ -n "$IP" ] && [ -n "$GATEWAY" ]; then
    echo "Configuring network with IP: $IP, Gateway: $GATEWAY"
    
    # Create systemd-networkd config
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/10-eth0.network << EOF
[Match]
Name=eth0

[Network]
Address=$IP
Gateway=$GATEWAY
DNS=${DNS1:-8.8.8.8}
DNS=${DNS2:-8.8.4.4}
EOF
    
    # Enable and start systemd-networkd
    ln -sf /etc/systemd/system/dbus-org.freedesktop.network1.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
    ln -sf /etc/systemd/system/sockets.target.wants/systemd-networkd.socket /etc/systemd/system/sockets.target.wants/systemd-networkd.socket
    systemctl enable systemd-networkd
    systemctl start systemd-networkd
fi

# Set root password if provided
if [ -n "$PASSWORD" ]; then
    echo "Setting root password"
    echo "root:$PASSWORD" | chpasswd
fi

# Enable SSH by default
if [ ! -f /etc/ssh/sshd_config ]; then
    mkdir -p /etc/ssh
    cat > /etc/ssh/sshd_config << 'EOF'
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin yes
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
X11Forwarding yes
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
UsePAM yes
EOF
    
    # Generate SSH host keys if they don't exist
    [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
    [ -f /etc/ssh/ssh_host_ecdsa_key ] || ssh-keygen -t ecdsa -b 256 -f /etc/ssh/ssh_host_ecdsa_key -N ""
    [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
    
    # Enable and start SSH
    systemctl enable sshd
    systemctl start sshd
fi

echo "NixOS container setup complete!"
echo "You can now connect to the container using: ssh root@$IP"

NIXOS_VERSION="25.05"
NIX_CHANNEL="nixos-${NIXOS_VERSION}"

msg_info "Starting NixOS configuration for Proxmox LXC"

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
