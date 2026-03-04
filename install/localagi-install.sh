#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="LocalAGI"

# Load common UI/helpers and perform standard container bootstrap lifecycle.
# - `color`, `verb_ip6`, `catch_errors`: logging/error behavior
# - `setting_up_container`, `network_check`, `update_os`: baseline prep/update
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
header_info "$APP"

# Decide which runtime backend label to use for LocalAGI.
# Priority:
# 1) Explicit user choice (`var_localagi_backend` or `var_torch_backend`)
# 2) Auto-detection when GPU passthrough is enabled:
#    - NVIDIA device nodes => `cu128`
#    - AMD KFD node => `rocm7.2`
# 3) Fallback => `cpu`
resolve_backend() {
  local requested="${var_localagi_backend:-${var_torch_backend:-auto}}"
  local backend="cpu"
  local gpu_type="${GPU_TYPE:-unknown}"
  local has_nvidia="no"
  local has_kfd="no"
  local has_amd_pci="no"
  local has_amd_vendor="no"

  [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]] && has_nvidia="yes"
  [[ -e /dev/kfd ]] && has_kfd="yes"
  lspci 2>/dev/null | grep -qiE 'AMD|Radeon' && has_amd_pci="yes"
  grep -qEi '0x1002|0x1022' /sys/class/drm/renderD*/device/vendor /sys/class/drm/card*/device/vendor 2>/dev/null && has_amd_vendor="yes"

  case "$requested" in
  cpu | cu128 | rocm7.2)
    backend="$requested"
    ;;
  *)
    if [[ "${var_gpu:-no}" == "yes" ]]; then
      if [[ "${gpu_type}" == "NVIDIA" || "${has_nvidia}" == "yes" ]]; then
        backend="cu128"
      elif [[ "${gpu_type}" == "AMD" || "${has_kfd}" == "yes" ]]; then
        backend="rocm7.2"
      elif [[ "${has_amd_pci}" == "yes" ]]; then
        backend="rocm7.2"
      elif [[ "${has_amd_vendor}" == "yes" ]]; then
        backend="rocm7.2"
      fi
    fi
    ;;
  esac

  RESOLVED_BACKEND="$backend"
  BACKEND_DETECTION_SUMMARY="requested=${requested}, var_gpu=${var_gpu:-no}, GPU_TYPE=${gpu_type}, nvidia=${has_nvidia}, kfd=${has_kfd}, amd_pci=${has_amd_pci}, amd_vendor=${has_amd_vendor}, selected=${backend}"
}

# Build LocalAGI from source using upstream workflow:
# - Build frontend in `webui/react-ui` with Bun
# - Build backend binary with Go to `/usr/local/bin/localagi`
build_localagi_source() {
  msg_info "Building LocalAGI from source"
  cd /opt/localagi/webui/react-ui || return 1
  $STD bun install || return 1
  $STD bun run build || return 1
  cd /opt/localagi || return 1
  $STD go build -o /usr/local/bin/localagi || return 1
  msg_ok "Built LocalAGI from source"
}

# Generic command retry helper with linear backoff.
# Usage: retry_cmd <attempts> <base_delay_seconds> <command> [args...]
retry_cmd() {
  local max_attempts="$1"
  local base_delay="$2"
  shift 2
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    if [[ $attempt -lt $max_attempts ]]; then
      msg_warn "Command failed (attempt ${attempt}/${max_attempts}): $*"
      sleep $((base_delay * attempt))
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# Recovery path for transient apt repository/index failures.
# Especially useful for Hash Sum mismatch and stale list states.
apt_recover_indexes() {
  rm -rf /var/lib/apt/lists/partial/* /var/lib/apt/lists/* 2>/dev/null || true
  $STD apt clean
  $STD apt update
}

# Small wrappers so retry helper executes apt commands in current shell context.
# This avoids subshell issues with helper wrappers like `$STD` (e.g. `silent`).
apt_update_cmd() {
  $STD apt update
}

apt_install_cmd() {
  $STD apt install -y "$@"
}

apt_install_fix_missing_cmd() {
  $STD apt install -y --fix-missing "$@"
}

# Resilient package install flow:
# 1) Retry normal install
# 2) If still failing, clean apt state + refresh indexes
# 3) Retry with `--fix-missing`
install_apt_packages_resilient() {
  if retry_cmd 3 5 apt_install_cmd "$@"; then
    return 0
  fi

  msg_warn "APT install failed; attempting index recovery and retry"
  if ! retry_cmd 2 5 apt_recover_indexes; then
    return 1
  fi

  retry_cmd 2 5 apt_install_fix_missing_cmd "$@"
}

# Install ROCm runtime via AMD Debian package-manager method.
# Steps:
# - Determine supported suite mapping for current Debian version
# - Install AMD signing key
# - Add ROCm and graphics repositories for 7.2
# - Pin AMD repo origin
# - Install `rocm` meta-package
install_rocm_runtime_debian() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
  fi

  local rocm_suite=""
  case "${VERSION_ID:-}" in
  13*) rocm_suite="noble" ;;
  12*) rocm_suite="jammy" ;;
  *)
    msg_warn "Unsupported Debian version for automatic ROCm repo setup"
    return 1
    ;;
  esac

  msg_info "Configuring ROCm apt repositories (${rocm_suite})"
  mkdir -p /etc/apt/keyrings
  if ! curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg; then
    msg_warn "Failed to add ROCm apt signing key"
    return 1
  fi

  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 ${rocm_suite} main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu ${rocm_suite} main
EOF

  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  msg_info "Installing ROCm runtime packages (this may take several minutes)"
  if ! retry_cmd 3 5 apt update; then
    msg_warn "ROCm apt repository update failed"
    return 1
  fi
  if ! retry_cmd 3 10 apt install -y rocm; then
    msg_warn "ROCm runtime package installation failed"
    return 1
  fi
  ldconfig || true
  msg_ok "Installed ROCm runtime packages"
}

# Install base tooling needed to fetch/build/run LocalAGI.
# `gnupg` is required for ROCm key import path.
msg_info "Installing Dependencies"
install_apt_packages_resilient \
  curl \
  ca-certificates \
  git \
  jq \
  gnupg \
  build-essential
msg_ok "Installed Dependencies"

# Install language/runtime toolchains used by LocalAGI source build.
# - Node.js: frontend/Bun ecosystem compatibility
# - Go: backend binary build
NODE_VERSION="24" setup_nodejs
GO_VERSION="latest" setup_go

# Install Bun package manager (if not already present).
msg_info "Installing Bun"
if ! command -v bun >/dev/null 2>&1; then
  $STD npm install -g bun
fi
msg_ok "Installed Bun"

# Pull latest LocalAGI source snapshot from GitHub release tarball.
msg_info "Fetching LocalAGI Source"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
msg_ok "Fetched LocalAGI Source"

# Resolve backend and prepare persistent state directory.
msg_info "Resolving LocalAGI backend"
resolve_backend
BACKEND="${RESOLVED_BACKEND:-cpu}"
msg_info "Backend detection: ${BACKEND_DETECTION_SUMMARY:-unavailable}"
mkdir -p /opt/localagi/pool
msg_ok "Resolved LocalAGI backend: ${BACKEND}"

# Only attempt ROCm runtime provisioning when AMD backend is selected.
if [[ "${BACKEND}" == "rocm7.2" ]]; then
  install_rocm_runtime_debian || msg_warn "ROCm runtime package installation failed"
else
  msg_warn "ROCm install skipped because selected backend is '${BACKEND}'"
fi

# Generate runtime configuration file used by systemd service.
# Note: `LOCALAGI_LLM_API_URL` points to an OpenAI-compatible backend endpoint.
msg_info "Configuring LocalAGI"
cat <<EOF >/opt/localagi/.env
LOCALAGI_MODEL=gemma-3-4b-it-qat
LOCALAGI_MULTIMODAL_MODEL=moondream2-20250414
LOCALAGI_IMAGE_MODEL=sd-1.5-ggml
LOCALAGI_LLM_API_URL=http://127.0.0.1:8081
LOCALAGI_STATE_DIR=/opt/localagi/pool
LOCALAGI_TIMEOUT=5m
LOCALAGI_ENABLE_CONVERSATIONS_LOGGING=false
LOCALAGI_GPU_BACKEND=${BACKEND}
EOF
msg_ok "Configured LocalAGI"

# Build source tree into executable binary.
if ! build_localagi_source; then
  msg_error "Failed to build LocalAGI from source"
  exit 1
fi

# Create and start systemd unit for LocalAGI.
# The service reads `/opt/localagi/.env` at runtime.
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/localagi.service
[Unit]
Description=LocalAGI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/localagi
EnvironmentFile=/opt/localagi/.env
ExecStart=/usr/local/bin/localagi
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now localagi
msg_ok "Created Service"

# Verify service health before exiting installer.
if ! systemctl is-active -q localagi; then
  msg_error "Failed to start LocalAGI service"
  exit 1
fi
msg_ok "Started LocalAGI (${BACKEND})"

# Standard post-install housekeeping from shared framework.
motd_ssh
customize
cleanup_lxc
