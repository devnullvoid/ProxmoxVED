#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAGI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
APP="LocalAGI"

# Load common UI/helpers and perform standard container bootstrap lifecycle.
# - `color`, `verb_ip6`, `catch_errors`: logging/error behavior
# - `setting_up_container`, `network_check`, `update_os`: baseline prep/update
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
header_content=""
if declare -f get_header >/dev/null 2>&1; then
  header_content=$(get_header 2>/dev/null || true)
fi
if [[ -n "$header_content" ]]; then
  echo "$header_content"
fi

# Build LocalAGI from source using upstream workflow:
# - Build frontend in `webui/react-ui` with Bun
# - Build backend binary with Go to `/usr/local/bin/localagi`
build_localagi_source() {
  msg_info "Building LocalAGI from source"
  cd /opt/localagi/webui/react-ui || return 1
  $STD bun install || return 1
  $STD bun run build || return 1
  cd /opt/localagi || return 1
  $STD go build -o /usr/local/bin/localagi || return 1
  msg_ok "Built LocalAGI from source"
}

# Generic command retry helper with linear backoff.
# Usage: retry_cmd <attempts> <base_delay_seconds> <command> [args...]
retry_cmd() {
  local max_attempts="$1"
  local base_delay="$2"
  shift 2
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    if [[ $attempt -lt $max_attempts ]]; then
      msg_warn "Command failed (attempt ${attempt}/${max_attempts}): $*"
      sleep $((base_delay * attempt))
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# Recovery path for transient apt repository/index failures.
# Especially useful for Hash Sum mismatch and stale list states.
apt_recover_indexes() {
  rm -rf /var/lib/apt/lists/partial/* /var/lib/apt/lists/* 2>/dev/null || true
  $STD apt clean
  $STD apt update
}

# Small wrappers so retry helper executes apt commands in current shell context.
# This avoids subshell issues with helper wrappers like `$STD` (e.g. `silent`).
apt_update_cmd() {
  $STD apt update
}

apt_install_cmd() {
  $STD apt install -y "$@"
}

apt_install_fix_missing_cmd() {
  $STD apt install -y --fix-missing "$@"
}

# Resilient package install flow:
# 1) Retry normal install
# 2) If still failing, clean apt state + refresh indexes
# 3) Retry with `--fix-missing`
install_apt_packages_resilient() {
  if retry_cmd 3 5 apt_install_cmd "$@"; then
    return 0
  fi

  msg_warn "APT install failed; attempting index recovery and retry"
  if ! retry_cmd 2 5 apt_recover_indexes; then
    return 1
  fi

  retry_cmd 2 5 apt_install_fix_missing_cmd "$@"
}

# Install base tooling needed to fetch/build/run LocalAGI.
msg_info "Installing Dependencies"
install_apt_packages_resilient \
  curl \
  ca-certificates \
  git \
  jq \
  build-essential
msg_ok "Installed Dependencies"

# Install language/runtime toolchains used by LocalAGI source build.
# - Node.js: frontend/Bun ecosystem compatibility
# - Go: backend binary build
NODE_VERSION="24" setup_nodejs
GO_VERSION="latest" setup_go

# Install Bun package manager (if not already present).
msg_info "Installing Bun"
if ! command -v bun >/dev/null 2>&1; then
  $STD npm install -g bun
fi
msg_ok "Installed Bun"

# Pull latest LocalAGI source snapshot from GitHub release tarball.
msg_info "Fetching LocalAGI Source"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "localagi" "mudler/LocalAGI" "tarball" "latest" "/opt/localagi"
msg_ok "Fetched LocalAGI Source"

# Configure external-LLM mode and prepare persistent state directory.
BACKEND="external-llm"
mkdir -p /opt/localagi/pool
msg_ok "Configured LocalAGI backend mode: ${BACKEND}"

# Generate runtime configuration file used by systemd service.
# Note: `LOCALAGI_LLM_API_URL` points to an OpenAI-compatible backend endpoint.
# Defaulting to Ollama's OpenAI-compatible API avoids a dead 127.0.0.1:8081 endpoint.
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

# Build source tree into executable binary.
if ! build_localagi_source; then
  msg_error "Failed to build LocalAGI from source"
  exit 1
fi

# Create and start systemd unit for LocalAGI.
# The service reads `/opt/localagi/.env` at runtime.
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/localagi.service
[Unit]
Description=LocalAGI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/localagi
EnvironmentFile=/opt/localagi/.env
ExecStart=/usr/local/bin/localagi
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now localagi
msg_ok "Created Service"

# Verify service health before exiting installer.
if ! systemctl is-active -q localagi; then
  msg_error "Failed to start LocalAGI service"
  exit 1
fi
msg_ok "Started LocalAGI (${BACKEND})"

# Standard post-install housekeeping from shared framework.
motd_ssh
customize
cleanup_lxc
