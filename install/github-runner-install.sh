#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://docs.github.com/en/actions/hosting-your-own-runners

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "actions-runner" "actions/runner" "prebuild" "latest" "/opt/actions-runner" "actions-runner-linux-x64-*.tar.gz"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/actions-runner.service
[Unit]
Description=GitHub Actions self-hosted runner
Documentation=https://docs.github.com/en/actions/hosting-your-own-runners
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/actions-runner
ExecStart=/opt/actions-runner/run.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q actions-runner
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
