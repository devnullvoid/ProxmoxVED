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

# Decide which runtime backend label to use for LocalAGI during updates.
# Priority:
# 1) Explicit user choice (`var_localagi_backend` or `var_torch_backend`)
# 2) Auto-detection when GPU passthrough is enabled:
#    - NVIDIA device nodes => `cu128`
#    - AMD KFD node => `rocm7.2`
# 3) Fallback => `cpu`
resolve_backend() {
  local requested="${var_localagi_backend:-${var_torch_backend:-auto}}"
  local backend="cpu"
  local gpu_type="${GPU_TYPE:-unknown}"
  local has_nvidia="no"
  local has_kfd="no"
  local has_amd_pci="no"
  local has_amd_vendor="no"

  [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]] && has_nvidia="yes"
  [[ -e /dev/kfd ]] && has_kfd="yes"
  lspci 2>/dev/null | grep -qiE 'AMD|Radeon' && has_amd_pci="yes"
  grep -qEi '0x1002|0x1022' /sys/class/drm/renderD*/device/vendor /sys/class/drm/card*/device/vendor 2>/dev/null && has_amd_vendor="yes"

  case "$requested" in
  cpu | cu128 | rocm7.2)
    backend="$requested"
    ;;
  *)
    if [[ "${var_gpu:-no}" == "yes" ]]; then
      if [[ "${gpu_type}" == "NVIDIA" || "${has_nvidia}" == "yes" ]]; then
        backend="cu128"
      elif [[ "${gpu_type}" == "AMD" || "${has_kfd}" == "yes" ]]; then
        backend="rocm7.2"
      elif [[ "${has_amd_pci}" == "yes" ]]; then
        backend="rocm7.2"
      elif [[ "${has_amd_vendor}" == "yes" ]]; then
        backend="rocm7.2"
      fi
    fi
    ;;
  esac

  RESOLVED_BACKEND="$backend"
  BACKEND_DETECTION_SUMMARY="requested=${requested}, var_gpu=${var_gpu:-no}, GPU_TYPE=${gpu_type}, nvidia=${has_nvidia}, kfd=${has_kfd}, amd_pci=${has_amd_pci}, amd_vendor=${has_amd_vendor}, selected=${backend}"
}

# Update or append a key=value pair inside LocalAGI environment file.
# Used to keep backend and runtime flags in sync across updates.
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

# Install ROCm runtime via AMD Debian package-manager method.
# Steps:
# - Determine supported suite mapping for current Debian version
# - Install AMD signing key
# - Add ROCm and graphics repositories for 7.2
# - Pin AMD repo origin
# - Install `rocm` meta-package
install_rocm_runtime_debian() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
  fi

  local rocm_suite=""
  case "${VERSION_ID:-}" in
  13*) rocm_suite="noble" ;;
  12*) rocm_suite="jammy" ;;
  *)
    msg_warn "Unsupported Debian version for automatic ROCm repo setup"
    return 1
    ;;
  esac

  msg_info "Configuring ROCm apt repositories (${rocm_suite})"
  mkdir -p /etc/apt/keyrings
  if ! curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg; then
    msg_warn "Failed to add ROCm apt signing key"
    return 1
  fi

  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 ${rocm_suite} main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu ${rocm_suite} main
EOF

  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  msg_info "Installing ROCm runtime packages (this may take several minutes)"
  apt update || return 1
  apt install -y rocm || return 1
  ldconfig || true
  msg_ok "Installed ROCm runtime packages"
}

ensure_localagi_kfd_passthrough() {
  if [[ "${var_gpu:-no}" != "yes" ]]; then
    return 0
  fi

  if [[ ! -e /dev/kfd ]]; then
    return 0
  fi

  local lxc_config="/etc/pve/lxc/${CTID}.conf"
  if [[ ! -f "${lxc_config}" ]]; then
    return 0
  fi

  if grep -qE '^dev[0-9]+: /dev/kfd(,|$)' "${lxc_config}"; then
    return 0
  fi

  local dev_index=0
  while grep -q "^dev${dev_index}:" "${lxc_config}"; do
    dev_index=$((dev_index + 1))
  done

  echo "dev${dev_index}: /dev/kfd,gid=44" >>"${lxc_config}"
  msg_ok "Added LocalAGI /dev/kfd passthrough"

  if pct status "${CTID}" 2>/dev/null | grep -q running; then
    msg_info "Restarting container to apply /dev/kfd passthrough"
    pct reboot "${CTID}" >/dev/null 2>&1 || true
    msg_ok "Container restart requested"
  fi
}

function update_script() {
  # Standard update prechecks and environment summary.
  header_info
  check_container_storage
  check_container_resources

  # Ensure LocalAGI source install and service exist before update flow.
  if [[ ! -d /opt/localagi || ! -f /etc/systemd/system/localagi.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Pull latest release and refresh source tree if a new version is available.
  local update_performed="no"
  if check_for_gh_release "localagi" "mudler/LocalAGI"; then
    update_performed="yes"

    # Stop service and preserve runtime env before replacing source tree.
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

  # Re-evaluate backend each update in case hardware/override changed.
  msg_info "Resolving LocalAGI backend"
  resolve_backend
  BACKEND="${RESOLVED_BACKEND:-cpu}"
  msg_info "Backend detection: ${BACKEND_DETECTION_SUMMARY:-unavailable}"
  msg_ok "Resolved LocalAGI backend: ${BACKEND}"
  if [[ ! -f /opt/localagi/.env ]]; then
    msg_warn "Missing /opt/localagi/.env. Recreate by running install script again."
    exit
  fi

  # Provision ROCm runtime only when AMD backend is selected.
  if [[ "${BACKEND}" == "rocm7.2" ]]; then
    install_rocm_runtime_debian || msg_warn "ROCm runtime package installation failed"
  fi

  # Ensure source-build toolchain exists for update rebuild step.
  NODE_VERSION="24" setup_nodejs
  GO_VERSION="latest" setup_go
  if ! command -v bun >/dev/null 2>&1; then
    msg_info "Installing Bun"
    $STD npm install -g bun
    msg_ok "Installed Bun"
  fi

  # Persist backend marker and rebuild the project from source.
  set_env_var /opt/localagi/.env "LOCALAGI_GPU_BACKEND" "$BACKEND"
  if ! build_localagi_source; then
    msg_error "Failed to build LocalAGI from source"
    exit
  fi

  # Restart service with rebuilt binary and current env settings.
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
ensure_localagi_kfd_passthrough
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
