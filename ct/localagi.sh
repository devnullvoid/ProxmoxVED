#!/usr/bin/env bash
source <(curl -sSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

APP="LocalAGI"
var_tags="${var_tags:-ai,agents}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  $STD systemctl stop localagi

  if [[ -f /opt/localagi/.env ]]; then
    msg_info "Backing up existing LocalAGI configuration"
    cp /opt/localagi/.env /tmp/localagi.env.backup
  fi

  msg_info "Fetching and deploying latest LocalAGI release"
  CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"

  msg_info "Restoring LocalAGI configuration"
  if [[ -f /tmp/localagi.env.backup ]]; then
  	msg_info "Restoring LocalAGI configuration"
    cp /tmp/localagi.env.backup /opt/localagi/.env
    rm -f /tmp/localagi.env.backup
  fi

  cd /opt/localagi/webui/react-ui &&
    $STD bun install &&
    $STD bun run build &&
    cd /opt/localagi &&
    $STD go build -o /usr/local/bin/localagi || {
    msg_error "Failed to build LocalAGI from source"
    exit 1
  }

  systemctl enable -q --now localagi

  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
