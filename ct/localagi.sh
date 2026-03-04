#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-${COMMUNITY_SCRIPT_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

APP="LocalAGI"
var_tags="${var_tags:-ai;agents}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

resolve_backend() {
  local requested="${var_localagi_backend:-${var_torch_backend:-auto}}"
  local backend="cpu"

  case "$requested" in
  cpu | cu128 | rocm7.2)
    backend="$requested"
    ;;
  *)
    if [[ "${var_gpu:-no}" == "yes" ]]; then
      if [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]]; then
        backend="cu128"
      elif [[ -e /dev/kfd ]]; then
        backend="rocm7.2"
      fi
    fi
    ;;
  esac

  echo "$backend"
}

set_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    echo "${key}=${value}" >>"$env_file"
  fi
}

build_localagi_source() {
  msg_info "Building LocalAGI from source"
  cd /opt/localagi/webui/react-ui || return 1
  $STD bun install || return 1
  $STD bun run build || return 1
  cd /opt/localagi || return 1
  $STD go build -o /usr/local/bin/localagi || return 1
  msg_ok "Built LocalAGI from source"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/localagi || ! -f /etc/systemd/system/localagi.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local update_performed="no"
  if check_for_gh_release "localagi" "mudler/LocalAGI"; then
    update_performed="yes"

    msg_info "Stopping LocalAGI Service"
    systemctl stop localagi
    msg_ok "Stopped LocalAGI Service"

    msg_info "Backing up Environment"
    cp /opt/localagi/.env /tmp/localagi.env.backup 2>/dev/null || true
    msg_ok "Backed up Environment"

    msg_info "Updating LocalAGI"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
    msg_ok "Updated LocalAGI"

    if [[ -f /tmp/localagi.env.backup ]]; then
      msg_info "Restoring Environment"
      cp /tmp/localagi.env.backup /opt/localagi/.env
      rm -f /tmp/localagi.env.backup
      msg_ok "Restored Environment"
    fi
  fi

  BACKEND="$(resolve_backend)"
  if [[ ! -f /opt/localagi/.env ]]; then
    msg_warn "Missing /opt/localagi/.env. Recreate by running install script again."
    exit
  fi

  NODE_VERSION="24" setup_nodejs
  GO_VERSION="latest" setup_go
  if ! command -v bun >/dev/null 2>&1; then
    msg_info "Installing Bun"
    $STD npm install -g bun
    msg_ok "Installed Bun"
  fi

  set_env_var /opt/localagi/.env "LOCALAGI_GPU_BACKEND" "$BACKEND"
  if ! build_localagi_source; then
    msg_error "Failed to build LocalAGI from source"
    exit
  fi

  msg_info "Starting LocalAGI Service"
  if ! systemctl restart localagi; then
    msg_error "Failed to start LocalAGI service"
    exit
  fi
  msg_ok "Started LocalAGI (${BACKEND})"

  if [[ "$update_performed" == "yes" ]]; then
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. Rebuilt source and restarted service."
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
