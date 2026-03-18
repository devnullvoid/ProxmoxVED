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
setup_meilisearch
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_tag "librechat" "danny-avila/LibreChat"

msg_info "Installing Dependencies"
cd /opt/librechat
$STD npm ci
msg_ok "Installed Dependencies"

msg_info "Building Frontend"
$STD npm run frontend
$STD npm prune --production
$STD npm cache clean --force
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
DOMAIN_CLIENT=http://${LOCAL_IP}:3080
DOMAIN_SERVER=http://${LOCAL_IP}:3080
NO_INDEX=true
TRUST_PROXY=1
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
SESSION_EXPIRY=1000 * 60 * 15
REFRESH_TOKEN_EXPIRY=(1000 * 60 * 60 * 24) * 7
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}
ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_PASSWORD_RESET=false
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
SEARCH=true
MEILI_NO_ANALYTICS=true
MEILI_HOST=http://127.0.0.1:7700
MEILI_MASTER_KEY=${MEILISEARCH_MASTER_KEY}
APP_TITLE=LibreChat
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
