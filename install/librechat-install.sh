#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/danny-avila/LibreChat

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

MONGO_VERSION="8.0" setup_mongodb
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_tag "librechat" "danny-avila/LibreChat"

msg_info "Installing Dependencies"
cd /opt/librechat
$STD npm ci
msg_ok "Installed Dependencies"

msg_info "Building Frontend"
$STD npm run frontend
msg_ok "Built Frontend"

msg_info "Configuring LibreChat"
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
CREDS_KEY=$(openssl rand -hex 32)
CREDS_IV=$(openssl rand -hex 16)
cat <<EOF >/opt/librechat/.env
HOST=0.0.0.0
PORT=3080
MONGO_URI=mongodb://127.0.0.1:27017/LibreChat
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}
NODE_ENV=production
EOF
msg_ok "Configured LibreChat"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/librechat.service
[Unit]
Description=LibreChat
After=network.target mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/librechat
EnvironmentFile=/opt/librechat/.env
ExecStart=/usr/bin/npm run backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now librechat
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
