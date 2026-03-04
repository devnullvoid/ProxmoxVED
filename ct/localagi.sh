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

compose_file_for_backend() {
  case "$1" in
  cu128)
    echo "docker-compose.nvidia.yaml"
    ;;
  rocm7.2)
    echo "docker-compose.amd.yaml"
    ;;
  *)
    echo "docker-compose.yaml"
    ;;
  esac
}

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    msg_error "Docker Compose is not available"
    return 1
  fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/localagi/docker-compose.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local update_performed="no"
  if check_for_gh_release "localagi" "mudler/LocalAGI"; then
    update_performed="yes"

    msg_info "Stopping LocalAGI Stack"
    cd /opt/localagi || exit
    CURRENT_COMPOSE_FILE="$(cat /opt/localagi/.compose_file 2>/dev/null || echo docker-compose.yaml)"
    run_compose -f "$CURRENT_COMPOSE_FILE" down || true
    msg_ok "Stopped LocalAGI Stack"

    msg_info "Updating LocalAGI"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
    msg_ok "Updated LocalAGI"
  fi

  BACKEND="$(resolve_backend)"
  COMPOSE_FILE="$(compose_file_for_backend "$BACKEND")"

  if [[ ! -f "/opt/localagi/${COMPOSE_FILE}" ]]; then
    msg_warn "Compose profile ${COMPOSE_FILE} not found, falling back to CPU profile"
    BACKEND="cpu"
    COMPOSE_FILE="docker-compose.yaml"
  fi

  echo "$BACKEND" >/opt/localagi/.backend
  echo "$COMPOSE_FILE" >/opt/localagi/.compose_file

  msg_info "Deploying LocalAGI (${BACKEND})"
  cd /opt/localagi || exit
  if ! run_compose -f "$COMPOSE_FILE" pull; then
    msg_error "Failed to pull LocalAGI images"
    exit
  fi
  if ! run_compose -f "$COMPOSE_FILE" up -d; then
    msg_error "Failed to start LocalAGI stack"
    exit
  fi
  msg_ok "Deployed LocalAGI (${BACKEND})"

  if [[ "$update_performed" == "yes" ]]; then
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. Reapplied compose profile successfully."
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
