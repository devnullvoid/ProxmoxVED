#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://netboot.xyz

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  tftpd-hpa
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "netboot-xyz" "netbootxyz/netboot.xyz" "prebuild" "latest" "/var/www/html" "menus.tar.gz"

USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "netboot-xyz-efi" "netbootxyz/netboot.xyz" "singlefile" "latest" "/var/www/html" "netboot.xyz.efi"
USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "netboot-xyz-snp" "netbootxyz/netboot.xyz" "singlefile" "latest" "/var/www/html" "netboot.xyz-snp.efi"
USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "netboot-xyz-kpxe" "netbootxyz/netboot.xyz" "singlefile" "latest" "/var/www/html" "netboot.xyz.kpxe"
USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "netboot-xyz-undionly" "netbootxyz/netboot.xyz" "singlefile" "latest" "/var/www/html" "netboot.xyz-undionly.kpxe"

msg_info "Configuring Webserver"
rm -f /etc/nginx/sites-enabled/default
cat <<'EOF' >/etc/nginx/sites-available/netboot-xyz
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    server_name _;

    location / {
        autoindex on;
        add_header Access-Control-Allow-Origin "*";
        add_header Access-Control-Allow-Headers "Content-Type";
    }
}
EOF
ln -sf /etc/nginx/sites-available/netboot-xyz /etc/nginx/sites-enabled/netboot-xyz
$STD systemctl reload nginx
msg_ok "Configured Webserver"

msg_info "Configuring TFTP Server"
cat <<EOF >/etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/www/html"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
EOF
systemctl enable -q --now tftpd-hpa
msg_ok "Configured TFTP Server"

motd_ssh
customize
cleanup_lxc
