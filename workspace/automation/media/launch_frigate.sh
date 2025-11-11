#!/bin/bash

# Paths
DOTFILES_CONFIG=~/workspace/dotfiles/frigate
LOCAL_CONFIG=~/frigate/config
LOCAL_MEDIA=~/frigate/media

# Symlink config if not already linked
mkdir -p ~/frigate
if [ ! -L "$LOCAL_CONFIG" ]; then
    ln -s "$DOTFILES_CONFIG" "$LOCAL_CONFIG"
    echo "Linked $LOCAL_CONFIG -> $DOTFILES_CONFIG"
fi

# Create media directory
mkdir -p "$LOCAL_MEDIA"

# Run Frigate container
docker run -d \
  --name frigate \
  --restart=unless-stopped \
  --privileged \
  --mount type=tmpfs,target=/tmp/cache,tmpfs-size=100000000 \
  -v "$LOCAL_CONFIG":/config \
  -v "$LOCAL_MEDIA":/media \
  -v /etc/localtime:/etc/localtime:ro \
  -p 5000:5000 \
  -e FRIGATE_RTSP_PASSWORD="iL0wwlm?" \
  ghcr.io/blakeblackshear/frigate:stable


