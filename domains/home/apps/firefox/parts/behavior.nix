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

  # Fingerprinting: deliberately NOT enabling privacy.resistFingerprinting
  # and NOT setting privacy.fingerprintingProtection overrides. The old
  # LibreWolf FPP +AllTargets stack caused site breakage (canvas noise
  # froze long-lived SPAs like claude.ai, timer fuzzing janked YouTube,
  # WebGLRenderCapability blocked WebGL context creation — Codeberg #2381).
  # Firefox's default ETP "strict" tracker/fingerprinter blocking below is
  # the chosen posture instead.

  # Force Dark Logic into the browser engine
  "ui.systemUsesDarkTheme" = 1;
  "layout.css.prefers-color-scheme.content-override" = 0; # 0 = Force Dark

  # Browser Behavior
  "browser.tabs.closeWindowWithLastTab" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.feeds.topsites" = false;
  "browser.sessionstore.interval" = 30000;
  "browser.urlbar.suggest.searches" = false;
  "browser.urlbar.suggest.history" = true;
  "ui.prefersReducedMotion" = 1;
  "toolkit.cosmeticAnimations.enabled" = false;
  "network.proxy.type" = proxyType;
  "browser.offline" = false;
  "network.manage-offline-status" = true;
  "network.connectivity-service.enabled" = true;

  #==========================================================================
  # Hardening — the curated slice of what LibreWolf shipped as baked-in
  # defaults, minus the perf-hostile fingerprinting knobs (see above).
  #==========================================================================

  # Telemetry: fully off.
  "toolkit.telemetry.enabled" = false;
  "toolkit.telemetry.unified" = false;
  "toolkit.telemetry.server" = "data:,";
  "toolkit.telemetry.archive.enabled" = false;
  "toolkit.telemetry.newProfilePing.enabled" = false;
  "toolkit.telemetry.shutdownPingSender.enabled" = false;
  "toolkit.telemetry.updatePing.enabled" = false;
  "toolkit.telemetry.bhrPing.enabled" = false;
  "toolkit.telemetry.firstShutdownPing.enabled" = false;
  "toolkit.telemetry.coverage.opt-out" = true;
  "toolkit.coverage.opt-out" = true;
  "datareporting.healthreport.uploadEnabled" = false;
  "datareporting.policy.dataSubmissionEnabled" = false;
  "app.shield.optoutstudies.enabled" = false;
  "app.normandy.enabled" = false;
  "app.normandy.api_url" = "";
  "browser.discovery.enabled" = false;

  # Crash reports: off.
  "breakpad.reportURL" = "";
  "browser.tabs.crashReporting.sendReport" = false;
  "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;

  # Pocket: off.
  "extensions.pocket.enabled" = false;

  # Sponsored content: off.
  "browser.newtabpage.activity-stream.showSponsored" = false;
  "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
  "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;

  # HTTPS-Only mode.
  "dom.security.https_only_mode" = true;

  # Tracking protection: strict ETP + privacy signals.
  "browser.contentblocking.category" = "strict";
  "privacy.donottrackheader.enabled" = true;
  "privacy.globalprivacycontrol.enabled" = true;

  #==========================================================================
  # Web platform features — Firefox defaults these on (unlike LibreWolf),
  # but they're pinned explicitly so the working state (Zoom, Meet,
  # claude.ai voice, Maps, Figma, streaming) can't drift via prefs.js or
  # future upstream changes.
  #==========================================================================

  # WebGL — Maps, Meet compositing, Figma, anything 3D/WebGPU.
  "webgl.disabled" = false;

  # WebRTC — Zoom, Meet, Discord web, any voice/video call.
  # ice.default_address_only=true keeps the leak surface to the default
  # route IP instead of every interface (VPNs, tunnel adapters, etc.).
  # ice.no_host=false keeps LAN-host ICE candidates enabled — turning it
  # off silently breaks LAN-local WebRTC (some screen-sharing tools,
  # local-network video chat) while Zoom/Meet over the public internet
  # still work via STUN/TURN.
  "media.peerconnection.enabled" = true;
  "media.peerconnection.ice.default_address_only" = true;
  "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
  "media.peerconnection.ice.no_host" = false;

  # EME / Widevine DRM — Netflix HD, Disney+, Spotify web. Without
  # gmp-widevinecdm.enabled the CDM never downloads on first use.
  "media.eme.enabled" = true;
  "media.gmp-widevinecdm.enabled" = true;
  "media.gmp-widevinecdm.visible" = true;

  # Clipboard events — Google Docs/Sheets, claude.ai paste handlers, most
  # rich-text web editors. Async clipboard reads are still site-prompted;
  # no silent background reads.
  "dom.event.clipboardevents.enabled" = true;
  "dom.events.asyncClipboard.read" = true;
  "dom.events.asyncClipboard.clipboardItem" = true;

  #==========================================================================
  # Session persistence — keep cookies/cache across restarts so logins
  # survive (claude.ai, JobTread, etc.). Firefox defaults mostly agree,
  # but pinned explicitly. Both v1 keys (legacy) and v2 keys (Firefox 122+
  # migration) are set for forward-compat.
  #==========================================================================
  "privacy.sanitize.sanitizeOnShutdown" = false;
  "privacy.clearOnShutdown.cookies" = false;
  "privacy.clearOnShutdown.cache" = false;
  "privacy.clearOnShutdown.sessions" = false;
  "privacy.clearOnShutdown.offlineApps" = false;
  "privacy.clearOnShutdown.history" = false;
  "privacy.clearOnShutdown.downloads" = false;
  "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
  "privacy.clearOnShutdown_v2.cache" = false;
  "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = false;
  "privacy.clearOnShutdown_v2.siteSettings" = false;

  # Cookie lifetime: 0 = honor the site's own Expires/Max-Age header
  # (Firefox default). Pinned so login cookies never die on browser close.
  "network.cookie.lifetimePolicy" = 0;

  # Restore previous session on startup. Side benefit for session-only
  # cookies that sites (JobTread, some auth flows) emit: restore treats
  # the restart as a continuation, so those cookies survive too.
  "browser.startup.page" = 3;
  "browser.sessionstore.resume_from_crash" = true;
  "browser.sessionstore.privacy_level" = 0;
}
