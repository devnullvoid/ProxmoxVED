#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

APP="LocalAGI"
var_tags="${var_tags:-ai;agents}"
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

  if [[ ! -d /opt/localagi || ! -f /etc/systemd/system/localagi.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "localagi" "mudler/LocalAGI"; then
    msg_info "Stopping LocalAGI Service"
    systemctl stop localagi
    msg_ok "Stopped LocalAGI Service"

    msg_info "Backing up Environment"
    local env_backup
    env_backup="$(mktemp /tmp/localagi.env.XXXXXX)"
    chmod 600 "$env_backup"
    cp /opt/localagi/.env "$env_backup" 2>/dev/null || true
    msg_ok "Backed up Environment"

    msg_info "Updating LocalAGI"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
    msg_ok "Updated LocalAGI"

    if [[ -n "${env_backup:-}" && -f "$env_backup" ]]; then
      msg_info "Restoring Environment"
      cp "$env_backup" /opt/localagi/.env
      rm -f "$env_backup"
      msg_ok "Restored Environment"
    fi

    msg_ok "Backend mode: external-llm"
    if [[ ! -f /opt/localagi/.env ]]; then
      msg_warn "Missing /opt/localagi/.env. Recreate by running install script again."
      exit 1
    fi

    if grep -q '^LOCALAGI_LLM_API_URL=http://127.0.0.1:8081$' /opt/localagi/.env; then
      if grep -q '^LOCALAGI_LLM_API_URL=' /opt/localagi/.env; then
        sed -i 's|^LOCALAGI_LLM_API_URL=.*|LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1|' /opt/localagi/.env
      else
        echo "LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1" >>/opt/localagi/.env
      fi
      msg_warn "Migrated LOCALAGI_LLM_API_URL from 127.0.0.1:8081 to 127.0.0.1:11434/v1"
    fi

    NODE_VERSION="24" setup_nodejs
    setup_go
    msg_info "Installing Bun"
    $STD npm install -g bun
    msg_ok "Installed Bun"

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
    systemctl restart localagi || {
      msg_error "Failed to start LocalAGI service"
      exit 1
    }
    msg_ok "Started LocalAGI (external-llm)"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"

if [[ -z "${IP:-}" ]]; then
  IP=$(pct exec "$CTID" -- sh -c "hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | head -n1")
fi
if [[ -z "${IP:-}" ]]; then
  IP=$(pct exec "$CTID" -- sh -c "hostname -I 2>/dev/null | tr ' ' '\n' | grep -E ':' | head -n1")
fi

URL_HOST="${IP:-}"
if [[ -n "${URL_HOST}" && "${URL_HOST}" == *:* ]]; then
  URL_HOST="[${URL_HOST}]"
fi
if [[ -z "${URL_HOST}" ]]; then
  msg_warn "Unable to determine container IP automatically"
  echo -e "${TAB}${GATEWAY}${BGN}http://<container-ip>:3000${CL}"
else
  echo -e "${TAB}${GATEWAY}${BGN}http://${URL_HOST}:3000${CL}"
fi
