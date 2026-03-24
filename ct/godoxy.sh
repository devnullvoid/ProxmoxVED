#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/yusing/godoxy

APP="GoDoxy"
var_tags="${var_tags:-reverse-proxy;go;webui}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -f /usr/local/bin/godoxy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "godoxy" "yusing/godoxy"; then
    msg_info "Stopping Service"
    systemctl stop godoxy
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "godoxy" "yusing/godoxy" "tarball" "latest" "/opt/godoxy-src"

    msg_info "Building GoDoxy (Patience)"
    export PATH="/usr/local/go/bin:/root/.bun/bin:$PATH"
    cd /opt/godoxy-src
    sed -i '/^module github\.com\/yusing\/godoxy/!{/github\.com\/yusing\/godoxy/d}' go.mod
    sed -i '/^module github\.com\/yusing\/goutils/!{/github\.com\/yusing\/goutils/d}' go.mod
    $STD make build
    cp /opt/godoxy-src/bin/godoxy /usr/local/bin/godoxy
    msg_ok "Built GoDoxy"

    msg_info "Starting Service"
    systemctl start godoxy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the WebUI using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8888${CL}"
