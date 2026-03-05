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

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
setup_go

msg_info "Installing Bun"
curl -fsSL -o /tmp/bun-install.sh https://bun.sh/install && bash /tmp/bun-install.sh --no-chmod >/dev/null 2>&1
rm -f /tmp/bun-install.sh
msg_ok "Installed Bun (official installer)"
if [[ -x /root/.bun/bin/bun ]]; then
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
fi
fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"

msg_info "Recording installed version"
record_gh_release_version "localagi" "mudler/LocalAGI"
msg_ok "Recorded installed version"

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
msg_ok "Configured LocalAGI"

msg_info "Building LocalAGI from source"
cd /opt/localagi/webui/react-ui &&
  $STD bun install &&
  $STD bun run build &&
  cd /opt/localagi &&
  $STD go build -o /usr/local/bin/localagi
msg_ok "Built LocalAGI from source"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/localagi.service
[Unit]
Description=LocalAGI
After=network.target

[Service]
User=root
Type=simple
WorkingDirectory=/opt/localagi
ExecStart=/usr/local/bin/localagi
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now localagi
msg_ok "Started LocalAGI Service"

motd_ssh
customize
cleanup_lxc
