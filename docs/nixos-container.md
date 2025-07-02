# NixOS LXC Container Setup

This document provides guidance on setting up and troubleshooting NixOS containers in Proxmox VE using the Proxmox Community Helper scripts.

## Prerequisites

- Proxmox VE 7.0 or later
- Internet access for downloading the NixOS template
- Sufficient storage space for the container

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/devnullvoid/ProxmoxVED.git
   cd ProxmoxVED
   git checkout nixos-ct
   ```

2. Run the NixOS container setup:
   ```bash
   CT_ID=199 \
   HOSTNAME=test-nixos \
   STORAGE=local-lvm \
   NIXOS_VERSION=25.05 \
   bash -x ct/nixos.sh
   ```

## Important Notes

### Initial Container Setup
- The NixOS container requires special initialization:
  - `/etc/set-environment` must be sourced to set up the PATH
  - Root password is removed by default to allow login
  - Only `sh` is available in PATH until the environment is sourced

### Customization
- The container is configured with minimal settings by default
- After creation, you can customize the NixOS configuration:
  ```bash
  nixos-container root-login $CTID
  nixos-rebuild switch
  ```

## Troubleshooting

### Container Fails to Start
- Verify the template was downloaded correctly
- Check container logs: `pct logs $CTID`
- Try starting the container manually: `pct start $CTID`

### Missing Commands
If commands are not found:
1. Source the environment:
   ```bash
   . /etc/set-environment
   ```
2. Install needed packages:
   ```bash
   nix-env -iA nixos.bash nixos.coreutils nixos.findutils nixos.gnugrep nixos.gnused nixos.gnutar nixos.gzip nixos.which
   ```

### Network Issues
- Verify the network interface is up: `ip a`
- Check network configuration: `cat /etc/systemd/network/10-eth0.network`
- Restart networking: `systemctl restart systemd-networkd`

## Advanced Configuration

### Custom NixOS Configuration
Create a custom `configuration.nix` and copy it to the container:

```bash
# Create a custom configuration
cat > configuration.nix << EOF
{ config, pkgs, ... }:

{
  # Your NixOS configuration here
  environment.systemPackages = with pkgs; [
    vim wget curl git
  ];
  
  # Enable SSH
  services.openssh.enable = true;
  
  # Allow root login with SSH key
  services.openssh.permitRootLogin = "prohibit-password";
}
EOF

# Copy to container
pct push $CTID configuration.nix /etc/nixos/configuration.nix

# Rebuild inside container
pct exec $CTID -- nixos-rebuild switch
```

### Persistent Storage
To add persistent storage to your NixOS container:

1. Create a storage mount point:
   ```bash
   pct set $CTID -mp0 /mnt/data,mp=/data
   ```

2. Add to your NixOS configuration:
   ```nix
   fileSystems."/data" = {
     device = "/mnt/data";
     fsType = "none";
     options = [ "bind" ];
   };
   ```

## Known Issues

### Shell Environment
- The container starts with a minimal shell environment
- Source `/etc/set-environment` to access Nix tools
- Consider adding this to your shell's rc file

### Systemd Services
Some services may require additional configuration in NixOS:
- Use `systemd.services` in your NixOS configuration
- Check service status: `systemctl status <service>`
- View logs: `journalctl -u <service>`

## Support

For issues and feature requests, please open an issue on GitHub:
https://github.com/devnullvoid/ProxmoxVED/issues
