#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="LocalAGI"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
setup_go

msg_info "Installing Bun"
$STD npm install -g bun
msg_ok "Installed Bun"

fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"

if [[ ! -d /opt/localagi/webui/react-ui ]]; then
  msg_error "Unexpected release layout: /opt/localagi/webui/react-ui not found"
  exit 1
fi

# Record installed release tag for update checks
msg_info "Recording installed LocalAGI release tag"
release_tag=$(curl -fsSL "https://api.github.com/repos/mudler/LocalAGI/releases/latest" | grep -E '"tag_name"' | head -n1 | sed -E 's/[^\"]*"([^"]+)".*/\1/' 2>/dev/null || true)
if [[ -n "$release_tag" ]]; then
  echo "$release_tag" >/opt/localagi/LOCALAGI_VERSION.txt 2>/dev/null || msg_warn "Failed to write version file"
  msg_ok "Recorded release: $release_tag"
else
  msg_warn "Could not determine release tag for LocalAGI"
fi

mkdir -p /opt/localagi/pool

msg_info "Configuring LocalAGI"
cat <<EOF >/opt/localagi/.env
LOCALAGI_MODEL=gemma-3-4b-it-qat
LOCALAGI_MULTIMODAL_MODEL=moondream2-20250414
LOCALAGI_IMAGE_MODEL=sd-1.5-ggml
LOCALAGI_LLM_API_URL=http://127.0.0.1:11434/v1
LOCALAGI_STATE_DIR=/opt/localagi/pool
LOCALAGI_TIMEOUT=5m
LOCALAGI_ENABLE_CONVERSATIONS_LOGGING=false
EOF
chmod 600 /opt/localagi/.env
msg_ok "Configured LocalAGI"

msg_info "Building LocalAGI from source"

# Create dedicated system user to run the service
if ! id -u localagi >/dev/null 2>&1; then
  msg_info "Creating system user 'localagi'"
  useradd --system --no-create-home --shell /usr/sbin/nologin --home /opt/localagi localagi || \
    msg_warn "Failed to create 'localagi' user; continuing if it already exists"
fi

# Ensure ownership and perms
chown -R localagi:localagi /opt/localagi || msg_warn "Failed to chown /opt/localagi"

cd /opt/localagi/webui/react-ui || { msg_error "Missing webui/react-ui directory"; exit 1; }

msg_info "Running bun install"
$STD bun install || { msg_error "bun install failed"; exit 1; }

msg_info "Building web UI"
$STD bun run build || { msg_error "bun build failed"; exit 1; }

cd /opt/localagi || { msg_error "Missing /opt/localagi"; exit 1; }

msg_info "Building Go binary"
$STD go build -o /usr/local/bin/localagi || { msg_error "go build failed"; exit 1; }
chmod 755 /usr/local/bin/localagi || msg_warn "Failed to chmod /usr/local/bin/localagi"
msg_ok "Built LocalAGI from source"

msg_info "Creating Service"
mkdir -p /etc/systemd/system/localagi.service.d
override_file=/etc/systemd/system/localagi.service.d/override.conf
if [[ ! -f "$override_file" ]]; then
  msg_info "Creating systemd drop-in override for LocalAGI"
  cat <<EOF >"$override_file"
[Service]
User=localagi
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
AmbientCapabilities=
StandardOutput=journal
StandardError=journal
EOF
  systemctl daemon-reload
else
  msg_info "Systemd drop-in exists; ensuring required directives"
  # Ensure required directives present; add if missing
  for d in "User=localagi" "NoNewPrivileges=true" "PrivateTmp=true" "ProtectSystem=full" "ProtectHome=true" "AmbientCapabilities=" "StandardOutput=journal" "StandardError=journal"; do
    if ! grep -q "^${d}" "$override_file" 2>/dev/null; then
      echo "$d" >>"$override_file"
    fi
  done
  systemctl daemon-reload
fi

LOCALAGI_SERVICE_NEEDS_RECOVERY=1
systemctl enable -q --now localagi
msg_ok "Created Service (drop-in override)"

if ! systemctl is-active -q localagi; then
  msg_error "Failed to start LocalAGI service"
  exit 1
fi

motd_ssh
customize
cleanup_lxc
