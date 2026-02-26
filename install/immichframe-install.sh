#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thiago Canozzo Lahr (tclahr)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/immichFrame/ImmichFrame

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libicu-dev \
  libssl-dev \
  nodejs \
  npm \
  gettext-base
msg_ok "Installed Dependencies"

msg_info "Installing .NET 8 SDK"
mkdir -p /opt/dotnet
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
$STD /tmp/dotnet-install.sh \
  --channel 8.0 \
  --install-dir /opt/dotnet \
  --no-path
ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet
msg_ok "Installed .NET 8 SDK"

fetch_and_deploy_gh_release "immichframe" "immichFrame/ImmichFrame" "tarball" "latest" "/tmp/immichframe"

msg_info "Building Application"
mkdir -p /app
cd /tmp/immichframe
$STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
  --configuration Release \
  --runtime linux-x64 \
  --self-contained false \
  --output /app
cd /tmp/immichframe/immichFrame.Web
$STD npm ci
$STD npm run build
cp -r build/* /app/wwwroot
rm -rf /tmp/immichframe
msg_ok "Application Built"

msg_info "Configuring ImmichFrame"
mkdir -p /app/Config

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
msg_ok "Configured ImmichFrame"

msg_info "Creating immichframe User"
useradd -r -s /sbin/nologin -d /app -M immichframe 2>/dev/null
chown -R immichframe:immichframe /app
msg_ok "User immichframe Created"

msg_info "Creating Service"
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
systemctl enable -q --now immichframe
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
