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

# Set NixOS as the OS type and version
var_os="nixos"
var_version="${NIXOS_VERSION:-25.05}"

# Set the installation script URL to point to our fork
var_install="https://raw.githubusercontent.com/devnullvoid/ProxmoxVED/refs/heads/nixos-ct/install/nixos-install.sh"

# Set the template URL and name for NixOS
custom_template_url="https://hydra.nixos.org/job/nixos/release-${NIXOS_VERSION:-25.05}/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball"
custom_template_name="nixos-${NIXOS_VERSION:-25.05}-x86_64-linux.tar.xz"

# Set the storage for the template (local or a specific storage ID)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"

# Set the storage for the container (local-lvm, local-zfs, etc.)
STORAGE="${STORAGE:-local-lvm}"

# NixOS-specific settings
export PCT_OSTYPE="nixos"
export PCT_OSVERSION="${NIXOS_VERSION:-25.05}"

# Disable bash-specific customizations that won't work with NixOS
export DISABLE_CUSTOMIZATION=1

# Configure custom template for build.func
# These variables are used by build.func when calling create_lxc.sh
export custom_template_url="$custom_template_url"
export custom_template_name="$custom_template_name"

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

# Set installation script from our fork
var_install="https://raw.githubusercontent.com/devnullvoid/ProxmoxVED/refs/heads/nixos-ct/install/nixos-install.sh"

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
