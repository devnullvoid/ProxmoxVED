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

$STD apt install -y build-essential

NODE_VERSION="24" setup_nodejs
setup_go

$STD curl -fsSL -o /tmp/bun-install.sh https://bun.sh/install
$STD chmod +x /tmp/bun-install.sh
$STD bash /tmp/bun-install.sh
rm -f /tmp/bun-install.sh
[[ -x /root/.bun/bin/bun ]] && ln -sf /root/.bun/bin/bun /usr/local/bin/bun

fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"

mkdir -p /opt/localagi/pool
cat <<'EOF' >/opt/localagi/.env
LOCALAGI_MODEL=gemma-3-4b-it-qat
LOCALAGI_MULTIMODAL_MODEL=moondream2-20250414
LOCALAGI_IMAGE_MODEL=sd-1.5-ggml
LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1
LOCALAGI_STATE_DIR=/opt/localagi/pool
LOCALAGI_TIMEOUT=5m
LOCALAGI_ENABLE_CONVERSATIONS_LOGGING=false
EOF
chmod 600 /opt/localagi/.env

cd /opt/localagi/webui/react-ui &&
  $STD bun install &&
  $STD bun run build &&
  cd /opt/localagi &&
  $STD go build -o /usr/local/bin/localagi || {
  msg_error "Failed to build LocalAGI from source"
  exit 1
}

cat <<'EOF' >/etc/systemd/system/localagi.service
[Unit]
Description=LocalAGI
After=network.target

[Service]
User=root
Type=simple
EnvironmentFile=/opt/localagi/.env

WorkingDirectory=/opt/localagi
ExecStart=/usr/local/bin/localagi
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now localagi

motd_ssh
customize
cleanup_lxc
