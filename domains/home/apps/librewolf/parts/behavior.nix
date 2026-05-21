{ lib, pkgs, config, osConfig ? {}, ...}:

let
  sessionVars = lib.attrByPath [ "home" "sessionVariables" ] {} config;
  proxyEnvNames = [
    "http_proxy" "https_proxy" "HTTP_PROXY" "HTTPS_PROXY"
    "all_proxy" "ALL_PROXY"
  ];
  proxyEnvPresent = builtins.any (name: builtins.hasAttr name sessionVars) proxyEnvNames;
  proxyType = if proxyEnvPresent then 5 else 0;
in
{
  # Ensure userStyles are loaded
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

  # Privacy: Switch from RFP to FPP to allow site-level Dark Mode
  "privacy.resistFingerprinting" = false; 
  "privacy.fingerprintingProtection" = true;
  "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme";
  
  # Force Dark Logic into the browser engine
  "ui.systemUsesDarkTheme" = 1; 
  "layout.css.prefers-color-scheme.content-override" = 0; # 0 = Force Dark

  # Browser Behavior
  "browser.tabs.closeWindowWithLastTab" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.feeds.topsites" = false;
  "browser.sessionstore.interval" = 30000;
  "privacy.globalprivacycontrol.enabled" = true;
  "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
  "browser.urlbar.suggest.searches" = false;
  "browser.urlbar.suggest.history" = true;
  "ui.prefersReducedMotion" = 1;
  "toolkit.cosmeticAnimations.enabled" = false;
  "network.proxy.type" = proxyType;
  "browser.offline" = false;
  "network.manage-offline-status" = true;
  "network.connectivity-service.enabled" = true;

  #==========================================================================
  # Step 2/4 — re-enable modern web platform features that LibreWolf's
  # librewolf.cfg disables by default. Sites that need these silently fail
  # (Zoom, Meet, claude.ai voice, Maps, Figma, streaming services).
  # Privacy posture stays strong: fingerprintingProtection (FPP) above is
  # still on, GPC is still on, tracker blocking unchanged.
  #==========================================================================

  # WebGL — needed for Maps, Meet compositing, Figma, anything 3D/WebGPU.
  # Overrides LibreWolf's webgl.disabled = true.
  "webgl.disabled" = false;

  # WebRTC — needed for Zoom, Meet, Discord web, any voice/video call.
  # Overrides LibreWolf's media.peerconnection.enabled = false.
  # ice.default_address_only=true keeps the leak surface to the default
  # route IP instead of every interface (VPNs, tunnel adapters, etc.).
  "media.peerconnection.enabled" = true;
  "media.peerconnection.ice.default_address_only" = true;
  "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;

  # EME / Widevine DRM — needed for Netflix HD, Disney+, Spotify web.
  # Overrides LibreWolf's media.eme.enabled = false. Without
  # gmp-widevinecdm.enabled the CDM never downloads on first use.
  "media.eme.enabled" = true;
  "media.gmp-widevinecdm.enabled" = true;
  "media.gmp-widevinecdm.visible" = true;

  # Clipboard events — needed for Google Docs/Sheets, claude.ai paste
  # handlers, most rich-text web editors. Overrides LibreWolf's
  # dom.event.clipboardevents.enabled = false. Async clipboard reads are
  # still site-prompted; no silent background reads.
  "dom.event.clipboardevents.enabled" = true;
  "dom.events.asyncClipboard.read" = true;
  "dom.events.asyncClipboard.clipboardItem" = true;
}