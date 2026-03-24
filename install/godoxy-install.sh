#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/yusing/godoxy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  make \
  libcap2-bin
msg_ok "Installed Dependencies"

GO_VERSION="1.24" setup_go

msg_info "Installing Bun"
export BUN_INSTALL="/root/.bun"
curl -fsSL https://bun.sh/install | $STD bash
ln -sf /root/.bun/bin/bun /usr/local/bin/bun
msg_ok "Installed Bun"

fetch_and_deploy_gh_release "godoxy" "yusing/godoxy" "tarball" "latest" "/opt/godoxy-src"

msg_info "Building GoDoxy (Patience)"
export PATH="/usr/local/go/bin:/root/.bun/bin:$PATH"
cd /opt/godoxy-src
sed -i '/^module github\.com\/yusing\/godoxy/!{/github\.com\/yusing\/godoxy/d}' go.mod
sed -i '/^module github\.com\/yusing\/goutils/!{/github\.com\/yusing\/goutils/d}' go.mod
$STD make build
cp /opt/godoxy-src/bin/godoxy /usr/local/bin/godoxy
msg_ok "Built GoDoxy"

msg_info "Configuring GoDoxy"
mkdir -p /opt/godoxy/{config,data/metrics,certs}
JWT_SECRET=$(openssl rand -base64 32)
GODOXY_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
cat <<EOF >/opt/godoxy/.env
TZ=UTC
GODOXY_HTTP_ADDR=:80
GODOXY_HTTPS_ADDR=:443
GODOXY_API_ADDR=0.0.0.0:8888
GODOXY_API_JWT_SECURE=false
GODOXY_API_JWT_SECRET=${JWT_SECRET}
GODOXY_API_USER=admin
GODOXY_API_PASSWORD=${GODOXY_PASS}
EOF
cat <<EOF >/opt/godoxy/config/config.yml
entrypoint:
  support_proxy_protocol: false

defaults:
  healthcheck:
    interval: 5s
    timeout: 15s
    retries: 3

providers:
  include: []

homepage:
  use_default_categories: true

timeout_shutdown: 5
EOF
msg_ok "Configured GoDoxy"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/godoxy.service
[Unit]
Description=GoDoxy Reverse Proxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/godoxy
EnvironmentFile=/opt/godoxy/.env
ExecStart=/usr/local/bin/godoxy
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now godoxy
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

echo -e "${TAB}${GATEWAY}${BGN}WebUI:${CL}    http://${LOCAL_IP}:8888"
echo -e "${TAB}${GATEWAY}${BGN}Username:${CL} admin"
echo -e "${TAB}${GATEWAY}${BGN}Password:${CL} ${GODOXY_PASS}"
