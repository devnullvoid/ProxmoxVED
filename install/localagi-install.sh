#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="LocalAGI"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
header_info "$APP"

resolve_backend() {
  local requested="${var_localagi_backend:-${var_torch_backend:-auto}}"
  local backend="cpu"

  case "$requested" in
  cpu | cu128 | rocm7.2)
    backend="$requested"
    ;;
  *)
    if [[ "${var_gpu:-no}" == "yes" ]]; then
      if [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]]; then
        backend="cu128"
      elif [[ -e /dev/kfd ]]; then
        backend="rocm7.2"
      fi
    fi
    ;;
  esac

  echo "$backend"
}

build_localagi_source() {
  msg_info "Building LocalAGI from source"
  cd /opt/localagi/webui/react-ui || return 1
  $STD bun install || return 1
  $STD bun run build || return 1
  cd /opt/localagi || return 1
  $STD go build -o /usr/local/bin/localagi || return 1
  msg_ok "Built LocalAGI from source"
}

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

apt_recover_indexes() {
  rm -rf /var/lib/apt/lists/partial/* /var/lib/apt/lists/* 2>/dev/null || true
  $STD apt clean
  $STD apt update
}

install_apt_packages_resilient() {
  if retry_cmd 3 5 env STD="$STD" bash -lc '$STD apt install -y "$@"' _ "$@"; then
    return 0
  fi

  msg_warn "APT install failed; attempting index recovery and retry"
  if ! retry_cmd 2 5 apt_recover_indexes; then
    return 1
  fi

  retry_cmd 2 5 env STD="$STD" bash -lc '$STD apt install -y --fix-missing "$@"' _ "$@"
}

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

  msg_info "Installing ROCm runtime packages"
  retry_cmd 3 5 env STD="$STD" bash -lc '$STD apt update' || return 1
  install_apt_packages_resilient rocm || return 1
  ldconfig || true
  msg_ok "Installed ROCm runtime packages"
}

msg_info "Installing Dependencies"
install_apt_packages_resilient \
  curl \
  ca-certificates \
  git \
  jq \
  gnupg \
  build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
GO_VERSION="latest" setup_go

msg_info "Installing Bun"
if ! command -v bun >/dev/null 2>&1; then
  $STD npm install -g bun
fi
msg_ok "Installed Bun"

msg_info "Fetching LocalAGI Source"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
msg_ok "Fetched LocalAGI Source"

BACKEND="$(resolve_backend)"
mkdir -p /opt/localagi/pool

if [[ "${BACKEND}" == "rocm7.2" ]]; then
  install_rocm_runtime_debian || msg_warn "ROCm runtime package installation failed"
fi

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

if ! build_localagi_source; then
  msg_error "Failed to build LocalAGI from source"
  exit 1
fi

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

if ! systemctl is-active -q localagi; then
  msg_error "Failed to start LocalAGI service"
  exit 1
fi
msg_ok "Started LocalAGI (${BACKEND})"

motd_ssh
customize
cleanup_lxc
