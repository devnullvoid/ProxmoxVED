#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/devnullvoid/ProxmoxVED/refs/heads/nixos-ct/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://nixos.org/

# NixOS Container Configuration
APP="NixOS"
var_tags="${var_tags:-os;nixos}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"  # NixOS might need more RAM than Alpine
var_disk="${var_disk:-4}"   # NixOS typically needs more disk space

# We use 'alpine' as the base OS for validation, but will override the template
var_os="alpine"
var_version="3.20"  # Alpine version for validation only

# NixOS requires an unprivileged container with nesting enabled
var_unprivileged="${var_unprivileged:-0}"

# NixOS template configuration
NIXOS_VERSION="${NIXOS_VERSION:-25.05}"
NIXOS_TEMPLATE_URL="https://hydra.nixos.org/job/nixos/release-${NIXOS_VERSION}/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball"
NIXOS_TEMPLATE_NAME="nixos-${NIXOS_VERSION}-x86_64-linux.tar.xz"

# Configure custom template for build.func
# These variables are used by build.func when calling create_lxc.sh
export custom_template_url="$NIXOS_TEMPLATE_URL"
export custom_template_name="$NIXOS_TEMPLATE_NAME"

# Additional arguments to pass to create_lxc.sh
# These will be passed through by build.func
export create_lxc_args=(
    "--ostype" "nixos"
    "--features" "nesting=1"
    "--unprivileged" "0"
)

# Set default network configuration if not provided
if [ -z "${pct_nets[0]:-}" ]; then
    pct_nets[0]="name=eth0,bridge=vmbr0,ip=dhcp,ip6=auto,firewall=1"
fi

# Set default root filesystem size if not provided
if [ -z "${pct_rootfs:-}" ]; then
    pct_rootfs="${var_disk}G"
fi

# Set installation script
var_install="nixos-install"

# Set container options
pct_options=(
    "--features" "nesting=1,keyctl=1"
    "--unprivileged" "0"
)

header_info "$APP"
variables
color
catch_errors

function update_script() {
  UPD=$(
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUPPORT" --radiolist --cancel-button Exit-Script "Spacebar = Select" 11 58 1 \
      "1" "Update NixOS channels and upgrade packages" ON \
      3>&1 1>&2 2>&3
  )

  header_info
  if [ "$UPD" == "1" ]; then
    $STD nix-channel --update
    $STD nixos-rebuild switch --upgrade
    exit
  fi
}

start
build_container
description

msg_ok "Completed Successfully!\n"
