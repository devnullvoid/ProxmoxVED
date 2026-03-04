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

set_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    echo "${key}=${value}" >>"$env_file"
  fi
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

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  ca-certificates \
  git \
  jq \
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
