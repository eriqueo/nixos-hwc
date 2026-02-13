#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo) so ownership and permissions are preserved."
  exit 1
fi

log() {
  echo "[media-migrate] $*"
}

has_data() {
  local dir="$1"
  [ -d "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

copy_dir() {
  local src="$1"
  local dst="$2"
  if [ ! -d "$src" ]; then
    log "skip (missing): $src"
    return 0
  fi
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src"/ "$dst"/
  else
    cp -a "$src"/. "$dst"/
  fi
  chown -R 1000:100 "$dst"
  log "copied: $src -> $dst"
}

copy_file() {
  local src="$1"
  local dst="$2"
  if [ ! -f "$src" ]; then
    log "skip (missing): $src"
    return 0
  fi
  install -D -m 0644 "$src" "$dst"
  chown 1000:100 "$dst"
  log "copied: $src -> $dst"
}

log "starting migration from /mnt/hot/downloads to /opt"

# Standard configs: /mnt/hot/downloads/<name> -> /opt/<name>/config
for name in \
  sonarr radarr lidarr prowlarr \
  qbittorrent sabnzbd jellyfin navidrome \
  books caddy organizr \
  beets recyclarr \
; do
  src="/mnt/hot/downloads/$name"
  dst="/opt/$name/config"
  if has_data "$dst"; then
    log "skip (target not empty): $dst"
    continue
  fi
  copy_dir "$src" "$dst"
done

# Jellyseerr: old path used /mnt/hot/downloads/jellyseerr/config
if ! has_data "/opt/jellyseerr/config"; then
  copy_dir "/mnt/hot/downloads/jellyseerr/config" "/opt/jellyseerr/config"
fi

# Gluetun: state dir + env file
if ! has_data "/opt/gluetun"; then
  copy_dir "/mnt/hot/downloads/gluetun" "/opt/gluetun"
fi
if [ ! -f "/opt/gluetun/.env" ] && [ -f "/mnt/hot/downloads/.env" ]; then
  copy_file "/mnt/hot/downloads/.env" "/opt/gluetun/.env"
fi

# Soularr: config.ini + data
if ! has_data "/opt/soularr/config"; then
  if [ -f "/mnt/hot/downloads/soularr/config.ini" ]; then
    copy_file "/mnt/hot/downloads/soularr/config.ini" "/opt/soularr/config/config.ini"
  else
    copy_dir "/mnt/hot/downloads/soularr" "/opt/soularr/config"
  fi
fi
if ! has_data "/opt/soularr/data" && [ -d "/mnt/hot/downloads/soularr/data" ]; then
  copy_dir "/mnt/hot/downloads/soularr/data" "/opt/soularr/data"
fi

# Tdarr: split layout
if ! has_data "/opt/tdarr/server"; then
  copy_dir "/mnt/hot/downloads/tdarr/server" "/opt/tdarr/server"
fi
if ! has_data "/opt/tdarr/configs"; then
  copy_dir "/mnt/hot/downloads/tdarr/configs" "/opt/tdarr/configs"
fi
if ! has_data "/opt/tdarr/logs"; then
  copy_dir "/mnt/hot/downloads/tdarr/logs" "/opt/tdarr/logs"
fi

log "migration complete"
