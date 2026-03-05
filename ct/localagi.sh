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

  msg_info "Stopping LocalAGI Service"
  systemctl stop localagi
  msg_ok "Stopped LocalAGI Service"

  msg_info "Backing up Environment"
  local env_backup_file
  env_backup_file=""
  if [[ -f /opt/localagi/.env ]]; then
    local tmp
    tmp=$(mktemp) || tmp=""
    if [[ -n "$tmp" ]] && cp /opt/localagi/.env "$tmp"; then
      env_backup_file="$tmp"
      msg_ok "Backed up Environment to ${env_backup_file}"
    else
      [[ -n "$tmp" ]] && rm -f "$tmp"
      msg_warn "Failed to back up environment file"
    fi
  else
    msg_warn "No /opt/localagi/.env to back up"
  fi

  msg_info "Updating LocalAGI"
  cd /opt
  rm -rf localagi
  fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
  msg_ok "Updated LocalAGI"

  msg_info "Restoring Environment"
  if [[ -n "$env_backup_file" && -s "$env_backup_file" ]]; then
    cp "$env_backup_file" /opt/localagi/.env
    rm -f "$env_backup_file"
    msg_ok "Restored Environment from ${env_backup_file}"
  fi

  msg_info "Building LocalAGI from source"
  (
    cd /opt/localagi/webui/react-ui &&
      $STD bun install &&
      $STD bun run build &&
      cd /opt/localagi &&
      $STD go build -o /usr/local/bin/localagi
  ) || {
    msg_error "Failed to build LocalAGI from source"
    exit 1
  }
  msg_ok "Built LocalAGI from source"

  msg_info "Starting LocalAGI Service"
  systemctl restart localagi
  msg_ok "Started LocalAGI"

  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
