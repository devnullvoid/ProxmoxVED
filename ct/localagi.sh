#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/BillyOutlast/ProxmoxVED/LocalAGI/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
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

function health_check() {
  header_info

  if [[ ! -d /opt/localagi ]]; then
    msg_error "LocalAGI not found at /opt/localagi"
    return 1
  fi

  if ! systemctl is-active --quiet localagi; then
    msg_error "LocalAGI service not running"
    return 1
  fi

  msg_ok "Health check passed: LocalAGI installed and service running"
  return 0
}

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
    local env_backup_valid=0
    if [[ -s /opt/localagi/.env ]]; then
      env_backup="$(mktemp /tmp/localagi.env.XXXXXX)"
      chmod 600 "$env_backup"
      if cp /opt/localagi/.env "$env_backup" 2>/dev/null && [[ -s "$env_backup" ]]; then
        env_backup_valid=1
        msg_ok "Backed up Environment"
      else
        rm -f "$env_backup"
        env_backup=""
        msg_warn "Failed to create valid environment backup"
      fi
    else
      msg_warn "Skipping environment backup: /opt/localagi/.env missing or empty"
    fi

    msg_info "Checking latest LocalAGI release"
    # Determine installed version (if recorded)
    installed_version=""
    if [[ -f /opt/localagi/LOCALAGI_VERSION.txt ]]; then
      installed_version=$(grep -E '^Version:' /opt/localagi/LOCALAGI_VERSION.txt 2>/dev/null | head -n1 | awk -F': ' '{print $2}') || installed_version=""
    fi

    # Fetch latest tag from GitHub
    latest_tag=$(curl -fsSL "https://api.github.com/repos/mudler/LocalAGI/releases/latest" | grep -E '"tag_name"' | head -n1 | sed -E 's/[^\"]*"([^"]+)".*/\1/' 2>/dev/null || true)

    if [[ -n "$installed_version" && -n "$latest_tag" && "$installed_version" == "$latest_tag" ]]; then
      msg_ok "LocalAGI is already up-to-date (version: $installed_version). Skipping update."
    else
      msg_info "Updating LocalAGI to ${latest_tag:-latest}"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
      msg_ok "Updated LocalAGI"
    fi

    msg_info "Recording installed LocalAGI release tag"
    release_tag=$(curl -fsSL "https://api.github.com/repos/mudler/LocalAGI/releases/latest" | grep -E '"tag_name"' | head -n1 | sed -E 's/[^\"]*"([^"]+)".*/\1/' 2>/dev/null || true)
    if [[ -n "$release_tag" ]]; then
      cat >/opt/localagi/LOCALAGI_VERSION.txt <<EOF
Version: ${release_tag}
InstallDate: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
InstallMethod: ct
Source: mudler/LocalAGI
EOF
      msg_ok "Recorded release: $release_tag"
    else
      msg_warn "Could not determine release tag for LocalAGI"
    fi

    # Running service as root per project guidelines (AI.md)

    mkdir -p /etc/systemd/system/localagi.service.d
    override_file=/etc/systemd/system/localagi.service.d/override.conf
    if [[ ! -f "$override_file" ]]; then
      msg_info "Creating systemd drop-in override for LocalAGI"
      cat <<'EOF' >"$override_file"
[Service]
User=root
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
AmbientCapabilities=
StandardOutput=journal
StandardError=journal
EOF
      systemctl daemon-reload
      msg_ok "Installed systemd drop-in"
    else
      msg_info "Systemd drop-in exists; ensuring required directives"
      for d in "User=root" "NoNewPrivileges=true" "PrivateTmp=true" "ProtectSystem=full" "ProtectHome=true" "AmbientCapabilities=" "StandardOutput=journal" "StandardError=journal"; do
        if ! grep -q "^${d}" "$override_file" 2>/dev/null; then
          echo "$d" >>"$override_file"
        fi
      done
      systemctl daemon-reload
    fi

    if [[ "${env_backup_valid:-0}" == "1" && -n "${env_backup:-}" && -s "$env_backup" ]]; then
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
    if ! command -v bun >/dev/null 2>&1; then
      if curl -fsSL https://bun.sh/install | bash -s -- --no-chmod >/dev/null 2>&1; then
        msg_ok "Installed Bun (official installer)"
        if [[ -x /root/.bun/bin/bun ]]; then
          ln -sf /root/.bun/bin/bun /usr/local/bin/bun || msg_warn "Failed to symlink bun to /usr/local/bin"
        fi
      else
        msg_warn "Official Bun installer failed, falling back to npm"
        $STD npm install -g bun || { msg_error "Failed to install Bun"; exit 1; }
        msg_ok "Installed Bun (npm)"
      fi
    else
      msg_ok "Bun already installed"
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
    systemctl restart localagi || {
      msg_error "Failed to start LocalAGI service"
      exit 1
    }
    msg_ok "Started LocalAGI (external-llm)"

    # Run health check after start
    health_check || {
      msg_warn "Health check failed after update; check service logs"
    }

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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
