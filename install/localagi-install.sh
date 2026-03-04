#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

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

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  ca-certificates \
  git \
  jq
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
setup_docker
msg_ok "Installed Docker"

msg_info "Installing LocalAGI"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
msg_ok "Installed LocalAGI"

BACKEND="$(resolve_backend)"
COMPOSE_FILE="$(compose_file_for_backend "$BACKEND")"
if [[ ! -f "/opt/localagi/${COMPOSE_FILE}" ]]; then
  msg_warn "Compose profile ${COMPOSE_FILE} not found, falling back to CPU profile"
  BACKEND="cpu"
  COMPOSE_FILE="docker-compose.yaml"
fi

echo "$BACKEND" >/opt/localagi/.backend
echo "$COMPOSE_FILE" >/opt/localagi/.compose_file

msg_info "Starting LocalAGI (${BACKEND})"
cd /opt/localagi || exit
if ! run_compose -f "$COMPOSE_FILE" pull; then
  msg_error "Failed to pull LocalAGI images"
  exit 1
fi
if ! run_compose -f "$COMPOSE_FILE" up -d; then
  msg_error "Failed to start LocalAGI stack"
  exit 1
fi
msg_ok "Started LocalAGI (${BACKEND})"

motd_ssh
customize
cleanup_lxc
