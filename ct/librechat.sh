#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/danny-avila/LibreChat

APP="LibreChat"
var_tags="${var_tags:-ai;chat}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/librechat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "librechat" "danny-avila/LibreChat" "v"; then
    msg_info "Stopping Service"
    systemctl stop librechat
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/librechat/.env /opt/librechat.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "librechat" "danny-avila/LibreChat"

    msg_info "Installing Dependencies"
    cd /opt/librechat
    $STD npm ci
    msg_ok "Installed Dependencies"

    msg_info "Building Frontend"
    $STD npm run frontend
    msg_ok "Built Frontend"

    msg_info "Restoring Configuration"
    cp /opt/librechat.env.bak /opt/librechat/.env
    rm -f /opt/librechat.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start librechat
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3080${CL}"
