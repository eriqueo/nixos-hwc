{ lib, pkgs, config, ... }:

{
  "gfx.webrender.all" = true;
  "layers.acceleration.force-enabled" = true;
  "media.ffmpeg.vaapi.enabled" = true;
  "media.hardware-video-decoding.force-enabled" = true;
  "media.av1.enabled" = true;
  "media.av1.use-dav1d" = true;
  "media.rdd-vpx.enabled" = true;
  "network.http.http3.enabled" = true;
  "network.trr.mode" = 0;
  "browser.cache.disk.enable" = false;
  "widget.dmabuf.force-enabled" = true;
  "media.ffmpeg.dmabuf-textures.enabled" = true;
  "media.ffmpeg.vaapi-drm-display.enabled" = true;
}
