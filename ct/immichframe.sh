#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
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

  RELEASE=$(curl -s https://api.github.com/repos/immichFrame/ImmichFrame/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')
  if [[ ! -f /app/version.txt ]] || [[ "${RELEASE}" != "$(cat /app/version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"

    msg_info "Stopping ${APP} service"
    systemctl stop immichframe 2>/dev/null

    msg_info "Downloading source ${RELEASE}"
    curl -fsSL "https://github.com/immichFrame/ImmichFrame/archive/refs/tags/${RELEASE}.tar.gz" \
      -o /tmp/immichframe.tar.gz
    tar -xzf /tmp/immichframe.tar.gz -C /tmp/
    SRCDIR=$(ls -d /tmp/ImmichFrame-*)

    msg_info "Building backend"
    cd "${SRCDIR}"
    /opt/dotnet/dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
      --configuration Release \
      --runtime linux-x64 \
      --self-contained false \
      --output /app \
      &>/dev/null

    msg_info "Building frontend"
    cd "${SRCDIR}/immichFrame.Web"
    npm ci --silent &>/dev/null
    npm run build &>/dev/null
    rm -rf /app/wwwroot/*
    cp -r build/* /app/wwwroot

    echo "${RELEASE}" > /app/version.txt

    msg_info "Starting ${APP} service"
    service immichframe start &>/dev/null

    msg_ok "Updated ${APP} to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
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
