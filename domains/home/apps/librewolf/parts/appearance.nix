{ lib, pkgs, config, ... }:

{
  "gfx.webrender.all" = true;
  "layers.acceleration.force-enabled" = true;
  "media.ffmpeg.vaapi.enabled" = true;
  "media.hardware-video-decoding.force-enabled" = true;
  "media.av1.enabled" = true;
  "media.av1.use-dav1d" = true;
  "media.rdd-vpx.enabled" = true;
  "browser.sessionstore.interval" = 30000;
  "network.http.http3.enabled" = true;
  # Keep DoH off unless you set a resolver; TRR mode 0 uses system DNS.
  "network.trr.mode" = 0;
  "accessibility.force_disabled" = 1;
  "browser.cache.disk.capacity" = 256000; # ~256MB cap
  "browser.cache.disk.enable" = false;    # prefer memory cache
}
