#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thiago Canozzo Lahr (tclahr)
# License: MIT | https://github.com/tclahr/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/immichFrame/ImmichFrame

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
msg_info "Installing Dependencies"
$STD apt install -y \
  libicu-dev \
  libssl-dev \
  nodejs \
  npm \
  gettext-base
msg_ok "Installed Dependencies"
msg_ok "Installed Dependencies"

msg_info "Installing .NET 8 SDK via dotnet-install.sh"
mkdir -p /opt/dotnet
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh

$STD /tmp/dotnet-install.sh \
  --channel 8.0 \
  --install-dir /opt/dotnet \
  --no-path

ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet

# Make dotnet available system-wide
ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet

rm /tmp/dotnet-install.sh
msg_ok ".NET 8 SDK Installed"

msg_info "Fetching Latest ImmichFrame Release"
RELEASE=$(curl -s https://api.github.com/repos/immichFrame/ImmichFrame/releases/latest \
  | grep "tag_name" | awk -F'"' '{print $4}')
msg_ok "Latest release: ${RELEASE}"

msg_info "Downloading ImmichFrame Source (${RELEASE})"
curl -fsSL "https://github.com/immichFrame/ImmichFrame/archive/refs/tags/${RELEASE}.tar.gz" \
  -o /tmp/immichframe.tar.gz
$STD tar -xzf /tmp/immichframe.tar.gz -C /tmp/
SRCDIR=$(ls -d /tmp/ImmichFrame-*)
msg_ok "Source Downloaded"

msg_info "Building ImmichFrame Backend (ASP.NET Core)"
mkdir -p /app
cd "${SRCDIR}"
$STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
  --configuration Release \
  --runtime linux-x64 \
  --self-contained false \
  --output /app
msg_ok "Backend Built"

msg_info "Building ImmichFrame Frontend (SvelteKit)"
cd "${SRCDIR}/immichFrame.Web" || exit
$STD npm ci
$STD npm run build
cp -r build/* /app/wwwroot
msg_ok "Frontend Built"

msg_info "Creating Configuration Directory"
mkdir -p /app/Config

# Cria Settings.yml com comentários explicativos
cat <<'EOF' > /app/Config/Settings.yml
# =====================================================================
# ImmichFrame Configuration
# Docs: https://immichframe.dev/docs/getting-started/configuration
# =====================================================================
# settings applicable to the web client - when viewing with a browser or webview
General:
  # When set, every client needs to authenticate via Bearer Token and this value.
  AuthenticationSecret: null  # string, no default
  # whether to download images to the server
  DownloadImages: false  # boolean
  # if images are downloaded, re-download if age (in days) is more than this
  RenewImagesDuration: 30  # int
  # A list of webcalendar URIs in the .ics format. Supports basic auth via standard URL format.
  # e.g. https://calendar.google.com/calendar/ical/XXXXXX/public/basic.ics
  # e.g. https://user:pass@calendar.immichframe.dev/dav/calendars/basic.ics
  Webcalendars:  # string[]
    - UUID
  # Interval in hours. Determines how often images are pulled from a person in immich.
  RefreshAlbumPeopleInterval: 12  # int
  # Date format. See https://date-fns.org/v4.1.0/docs/format for more information.
  PhotoDateFormat: 'yyyy-MM-dd'  # string
  ImageLocationFormat: 'City,State,Country'
  # Get an API key from OpenWeatherMap: https://openweathermap.org/appid
  WeatherApiKey: ''  # string
  # Imperial or metric system (Fahrenheit or Celsius)
  UnitSystem: 'metric'  # 'imperial' | 'metric'
  # Set the weather location with lat/lon.
  WeatherLatLong: '40.730610,-73.935242'  # string
  # 2 digit ISO code, sets the language of the weather description.
  Language: 'en'  # string
  # Webhook URL to be notified e.g. http://example.com/notify
  Webhook: null  # string
  # Image interval in seconds. How long an image is displayed in the frame.
  Interval: 45
  # Duration in seconds.
  TransitionDuration: 2  # float
  # Displays the current time.
  ShowClock: true  # boolean
  # Time format
  ClockFormat: 'hh:mm'  # string
  # Date format for the clock
  ClockDateFormat: 'eee, MMM d' # string
  # Displays the progress bar.
  ShowProgressBar: true  # boolean
  # Displays the date of the current image.
  ShowPhotoDate: true  # boolean
  # Displays the description of the current image.
  ShowImageDesc: true  # boolean
  # Displays a comma separated list of names of all the people that are assigned in immich.
  ShowPeopleDesc: true  # boolean
  # Displays a comma separated list of names of all the tags that are assigned in immich.
  ShowTagsDesc: true  # boolean
  # Displays a comma separated list of names of all the albums for an image.
  ShowAlbumName: true  # boolean
  # Displays the location of the current image.
  ShowImageLocation: true  # boolean
  # Lets you choose a primary color for your UI. Use hex with alpha value to edit opacity.
  PrimaryColor: '#f5deb3'  # string
  # Lets you choose a secondary color for your UI. (Only used with `style=solid or transition`) Use hex with alpha value to edit opacity.
  SecondaryColor: '#000000'  # string
  # Background-style of the clock and metadata.
  Style: 'none'  # none | solid | transition | blur
  # Sets the base font size, uses standard CSS formats (https://developer.mozilla.org/en-US/docs/Web/CSS/font-size)
  BaseFontSize: '17px'  # string
  # Displays the description of the current weather.
  ShowWeatherDescription: true  # boolean
  # URL for the icon to load for the current weather condition
  WeatherIconUrl: 'https://openweathermap.org/img/wn/{IconId}.png'
  # Zooms into or out of an image and gives it a touch of life.
  ImageZoom: true  # boolean
  # Pans an image in a random direction and gives it a touch of life.
  ImagePan: false  # boolean
  # Whether image should fill available space. Aspect ratio maintained but may be cropped.
  ImageFill: false  # boolean
  # Whether to play audio for videos that have audio tracks.
  PlayAudio: false  # boolean
  # Allow two portrait images to be displayed next to each other
  Layout: 'splitview'  # single | splitview

# multiple accounts permitted
Accounts:
  - # The URL of your Immich server e.g. `http://photos.yourdomain.com` / `http://192.168.0.100:2283`.
    ImmichServerUrl: 'REQUIRED'  # string, required, no default
    # Read more about how to obtain an Immich API key: https://immich.app/docs/features/command-line-interface#obtain-the-api-key
    # Exactly one of ApiKey or ApiKeyFile must be set.
    ApiKey: "super-secret-api-key"
    # ApiKeyFile: "/path/to/api.key"
    # Show images after date. Overwrites the `ImagesFromDays`-Setting
    ImagesFromDate: null  # Date
    # If this is set, memories are displayed.
    ShowMemories: false  # boolean
    # If this is set, favorites are displayed.
    ShowFavorites: false  # boolean
    # If this is set, assets marked archived are displayed.
    ShowArchived: false  # boolean
    # If this is set, video assets are included in the slideshow.
    ShowVideos: false  # boolean
    # Show images from the last X days, e.g., 365 -> show images from the last year
    ImagesFromDays: null  # int
    # Show images before date.
    ImagesUntilDate: '2020-01-02'  # Date
    # Rating of an image in stars, allowed values from -1 to 5. This will only show images with the exact rating you are filtering for.
    Rating: null  # int
    # UUID of album(s) - e.g. ['00000000-0000-0000-0000-000000000001']
    Albums:  # string[]
      - UUID
    # UUID of excluded album(s)
    #ExcludedAlbums:  # string[]
    #  - UUID
    # UUID of People
    #People:  # string[]
    #  - UUID
    # Tag values (full hierarchical paths, case-sensitive)
    #Tags:  # string[]
    #  - "Vacation"
    #  - "Travel/Europe"

EOF
msg_ok "Configuration File Created"

msg_info "Creating Dedicated User"
useradd -r -s /sbin/nologin -d /app -M immichframe 2>/dev/null || true
chown -R immichframe:immichframe /app
msg_ok "User 'immichframe' Created"

msg_info "Creating ImmichFrame systemd Service"
cat <<'EOF' > /etc/systemd/system/immichframe.service
[Unit]
Description=ImmichFrame Digital Photo Frame
After=network.target

[Service]
Type=simple
User=immichframe
Group=immichframe

WorkingDirectory=/app
ExecStart=/opt/dotnet/dotnet /app/ImmichFrame.WebApi.dll

# ASP.NET Core environment
Environment=ASPNETCORE_URLS=http://0.0.0.0:8080
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_CONTENTROOT=/app
Environment=DOTNET_ROOT=/opt/dotnet

Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal
SyslogIdentifier=immichframe

[Install]
WantedBy=multi-user.target
EOF
msg_ok "systemd Service Created"

msg_info "Enabling and Starting ImmichFrame Service"
$STD systemctl daemon-reload
$STD systemctl enable immichframe
$STD systemctl start immichframe
msg_ok "ImmichFrame Service Started"

msg_info "Saving Version Info"
echo "${RELEASE}" > /app/version.txt
msg_ok "Version ${RELEASE} Saved"

msg_info "Cleaning Up Build Artifacts"
#rm -rf /tmp/immichframe.tar.gz "${SRCDIR}"

#$STD apt-get autoremove -y
$STD apt-get clean
msg_ok "Cleanup Complete"

motd_ssh
customize
cleanup_lxc
