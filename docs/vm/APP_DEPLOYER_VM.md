# App Deployer VM

Deploy LXC applications inside a full Virtual Machine instead of an LXC container.

## Overview

The App Deployer VM bridges the gap between CT install scripts (`install/*.sh`) and VM infrastructure. It leverages the existing install scripts — originally designed for LXC containers — and runs them inside a full VM via a first-boot systemd service.

### Supported Operating Systems

| OS | Version | Codename | Cloud-Init |
| ---- | --------- | ---------- | ------------ |
| Debian | 13 | Trixie | Optional |
| Debian | 12 | Bookworm | Optional |
| Ubuntu | 24.04 LTS | Noble | Required |
| Ubuntu | 22.04 LTS | Jammy | Required |

## Usage

### Create a new App VM (interactive)

```bash
bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/vm/app-deployer-vm.sh)"
```

### Pre-select application

```bash
APP_SELECT=yamtrack bash -c "$(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/vm/app-deployer-vm.sh)"
```

### Update the application later (inside the VM)

```bash
bash /opt/community-scripts/update-app.sh
```

## How It Works

### Installation Flow

```
┌─────────────────────────────────────┐
│  Proxmox Host                       │
│                                     │
│  1. Select app (e.g. Yamtrack)      │
│  2. Select OS (e.g. Debian 13)      │
│  3. Configure VM resources          │
│  4. Download cloud image            │
│  5. virt-customize:                 │
│     - Install base packages         │
│     - Inject install.func           │
│     - Inject tools.func             │
│     - Inject install script         │
│     - Create first-boot service     │
│     - Inject update mechanism       │
│  6. Create VM (qm create)          │
│  7. Import customized disk          │
│  8. Start VM                        │
└────────────┬────────────────────────┘
             │ First Boot
┌────────────▼────────────────────────┐
│  VM (Debian/Ubuntu)                 │
│                                     │
│  app-install.service (oneshot):     │
│  1. Wait for network                │
│  2. Set environment variables       │
│     (FUNCTIONS_FILE_PATH, etc.)     │
│  3. Run install/<app>-install.sh    │
│  4. Mark as installed               │
│                                     │
│  → Application running in VM!       │
└─────────────────────────────────────┘
```

### Update Flow

```
┌─────────────────────────────────────┐
│  Inside the VM (SSH or console)     │
│                                     │
│  bash /opt/community-scripts/       │
│       update-app.sh                 │
│                                     │
│  → Downloads ct/<app>.sh            │
│  → start() detects no pveversion    │
│  → Shows update/settings menu       │
│  → Runs update_script()             │
└─────────────────────────────────────┘
```

The update mechanism reuses the existing CT script logic. Since `pveversion` is not available inside the VM, the `start()` function automatically enters the update/settings mode — the same path it takes inside LXC containers.

## Architecture

### Files

| File | Purpose |
| ------ | --------- |
| `vm/app-deployer-vm.sh` | Main user-facing script |
| `misc/vm-app.func` | Core library for VM app deployment |
| `misc/vm-core.func` | Shared VM functions (colors, spinner, etc.) |
| `misc/cloud-init.func` | Cloud-Init configuration (optional) |

### Key Design Decisions

1. **Install scripts run unmodified** — The same `install/*.sh` scripts that work in LXC containers work inside VMs. The environment (`FUNCTIONS_FILE_PATH`, exports) is replicated identically.

2. **Image customization via `virt-customize`** — All files are injected into the qcow2 image before the VM boots. No SSH or guest agent required during setup.

3. **First-boot systemd service** — The install script runs automatically on first boot. Progress can be monitored via `/var/log/app-install.log`.

4. **Update via CT script** — The existing CT script's `start()` → `update_script()` flow works in VMs without modification.

### Environment Variables (set during first-boot)

| Variable | Description |
| ---------- | ------------- |
| `FUNCTIONS_FILE_PATH` | Full contents of `install.func` |
| `APPLICATION` | App display name (e.g. "Yamtrack") |
| `app` | App identifier (e.g. "yamtrack") |
| `VERBOSE` | "no" (silent mode) |
| `SSH_ROOT` | "yes" |
| `PCT_OSTYPE` | OS type (debian/ubuntu) |
| `PCT_OSVERSION` | OS version (12/13/22.04/24.04) |
| `COMMUNITY_SCRIPTS_URL` | Repository base URL |
| `DEPLOY_TARGET` | "vm" (distinguishes from LXC) |

### VM Directory Structure

```
/opt/community-scripts/
├── install.func              # Function library
├── tools.func                # Helper functions
├── install/
│   └── <app>-install.sh      # Application install script
├── ct/
│   └── (downloaded on update) # CT script for updates
└── update-app.sh             # Update wrapper script
```

## Limitations

- **Alpine-based apps**: Currently only Debian/Ubuntu VMs are supported. Alpine install scripts are not compatible.
- **LXC-specific features**: Some CT features (FUSE, TUN, GPU passthrough) are configured differently in VMs.
- **First-boot timing**: The app installation happens after the VM boots, so the application is not immediately available (monitor `/var/log/app-install.log`).
- **`cleanup_lxc`**: This function works fine in VMs (it only cleans package caches), but the name is LXC-centric.

## Troubleshooting

### Check installation progress

```bash
# From inside the VM
tail -f /var/log/app-install.log

# From the Proxmox host (via guest agent)
qm guest exec <VMID> -- cat /var/log/app-install.log
```

### Re-run installation

```bash
# Remove the installed marker and reboot
rm /root/.app-installed
systemctl start app-install.service
```

### Check if installation completed

```bash
test -f /root/.app-installed && echo "Installed" || echo "Not yet installed"
```
