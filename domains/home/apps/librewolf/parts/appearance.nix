{ lib, pkgs, config, ... }:

{
  "browser.tabs.closeWindowWithLastTab" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.feeds.topsites" = false;
  "gfx.webrender.all" = true;
  "media.ffmpeg.vaapi.enabled" = true;
  "network.http.http3.enabled" = true;
  "accessibility.force_disabled" = 1;
  "browser.sessionstore.interval" = 30000;
}
