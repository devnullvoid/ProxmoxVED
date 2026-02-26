#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/tclahr/ProxmoxVED/raw/branch/main}"
source <(curl -fsSL https://raw.githubusercontent.com/tclahr/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thiago Canozzo Lahr (tclahr)
# License: MIT | https://github.com/tclahr/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/immichFrame/ImmichFrame

APP="ImmichFrame"
var_tags="${var_tags:-photos;slideshow}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
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

  if [[ ! -d /app ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "immichframe" "immichFrame/ImmichFrame"; then
    msg_info "Stopping Service"
    systemctl stop immichframe
    msg_ok "Stopped Service"

    msg_info "Updating ImmichFrame"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "immichframe" "immichFrame/ImmichFrame" "tarball" "latest" "/app"
    msg_info "Building Application"
    cd /app
    $STD /opt/dotnet/dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
      --configuration Release \
      --runtime linux-x64 \
      --self-contained false \
      --output /app

    cd /app/immichFrame.Web
    $STD npm ci 
    $STD npm run build
    rm -rf /app/wwwroot/*
    cp -r build/* /app/wwwroot
    msg_ok "Application Built"

    msg_info "Starting Service"
    systemctl start immichframe
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"

  fi
  exit
 }

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Configuration file location:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/app/Config/Settings.yml${CL}"
echo -e "${INFO}${YW} Edit the config file and set ImmichServerUrl and ApiKey before use!${CL}"
