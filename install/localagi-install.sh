#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
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

LOCALAGI_SERVICE_NEEDS_RECOVERY=0

function cleanup_localagi_service() {
  if [[ "${LOCALAGI_SERVICE_NEEDS_RECOVERY:-0}" == "1" ]] && ! systemctl is-active -q localagi; then
    msg_warn "LocalAGI service is not active; attempting recovery start"
    if systemctl start localagi; then
      msg_ok "Recovered LocalAGI service"
    else
      msg_error "Failed to recover LocalAGI service"
    fi
  fi
}

trap cleanup_localagi_service EXIT

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
setup_go

msg_info "Installing Bun"
$STD npm install -g bun
msg_ok "Installed Bun"

msg_info "Fetching LocalAGI Source"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
msg_ok "Fetched LocalAGI Source"

BACKEND="external-llm"
mkdir -p /opt/localagi/pool
msg_ok "Configured LocalAGI backend mode: ${BACKEND}"

msg_info "Configuring LocalAGI"
cat <<EOF >/opt/localagi/.env
LOCALAGI_MODEL=gemma-3-4b-it-qat
LOCALAGI_MULTIMODAL_MODEL=moondream2-20250414
LOCALAGI_IMAGE_MODEL=sd-1.5-ggml
LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1
LOCALAGI_STATE_DIR=/opt/localagi/pool
LOCALAGI_TIMEOUT=5m
LOCALAGI_ENABLE_CONVERSATIONS_LOGGING=false
EOF
chmod 600 /opt/localagi/.env
msg_ok "Configured LocalAGI"

msg_info "Building LocalAGI from source"
if ! (
  cd /opt/localagi/webui/react-ui &&
    $STD bun install &&
    $STD bun run build &&
    cd /opt/localagi &&
    $STD go build -o /usr/local/bin/localagi
); then
  msg_error "Failed to build LocalAGI from source"
  exit 1
fi
msg_ok "Built LocalAGI from source"

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
LOCALAGI_SERVICE_NEEDS_RECOVERY=1
systemctl enable -q --now localagi
msg_ok "Created Service"

if ! systemctl is-active -q localagi; then
  msg_error "Failed to start LocalAGI service"
  exit 1
fi
LOCALAGI_SERVICE_NEEDS_RECOVERY=0
msg_ok "Started LocalAGI (${BACKEND})"

motd_ssh
customize
cleanup_lxc
