{ lib, pkgs, config, ... }:

{
  "gfx.webrender.all" = true;
  "layers.acceleration.force-enabled" = true;

  "media.ffmpeg.vaapi.enabled" = true;
  "media.rdd-vpx.enabled" = true;

  "network.http.http3.enabled" = true;

  "accessibility.force_disabled" = 1;

  "browser.sessionstore.interval" = 30000;
  "privacy.globalprivacycontrol.enabled" = true;
  
  "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
  
  "network.trr.mode" = 5;
}
