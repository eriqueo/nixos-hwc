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
  # WebGLRenderCapability is excluded because +AllTargets includes a target
  # that blocks WebGL context creation at the content-process level even when
  # webgl.disabled=false (LibreWolf upstream issue, Codeberg #2381). Without
  # this exclusion every WebGL page hits "WebGL supported but disabled or
  # unavailable". Firefox is unaffected because it doesn't ship the FPP+
  # webgl-render override LibreWolf does.
  "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme,-WebGLRenderCapability";
  
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
  # ice.no_host=false re-enables LAN-host ICE candidates — was set true
  # in a previous browser session (about:config toggle, persisted to
  # prefs.js); leaving it true silently breaks any LAN-local WebRTC
  # (some screen-sharing tools, local-network video chat) while Zoom/
  # Meet over the public internet still work via STUN/TURN.
  "media.peerconnection.enabled" = true;
  "media.peerconnection.ice.default_address_only" = true;
  "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
  "media.peerconnection.ice.no_host" = false;

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

  #==========================================================================
  # Step 4/4 — session persistence. LibreWolf's librewolf.cfg defaults wipe
  # cookies+cache on shutdown AND treat all cookies as session-only, which
  # logs you out of every site (claude.ai, JobTread, etc.) on every browser
  # restart. These prefs flip that behavior off. Privacy posture preserved:
  # fingerprintingProtection on, GPC on, tracker blocking on — you're just
  # deciding to KEEP the cookies sites legitimately set so logins survive.
  #==========================================================================

  # Don't wipe anything on shutdown. LibreWolf defaults this whole branch
  # to true; the master sanitize toggle alone isn't enough because the
  # granular .cookies / .sessions / .cache toggles get evaluated too.
  # Both v1 keys (legacy) and v2 keys (Firefox 122+ migration) are set
  # for forward-compat — LibreWolf still reads both depending on version.
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
  # (Firefox default). LibreWolf overrides to 2 = session-only, which
  # makes EVERY login cookie die on browser close regardless of the
  # site's intent. This is the single biggest reason logins don't stick.
  "network.cookie.lifetimePolicy" = 0;

  # Restore previous session on startup. Side benefit relevant to
  # session-only cookies that sites (JobTread, some auth flows) emit:
  # when "restore previous session" is on, the browser treats the
  # restart as a continuation rather than a new session, so those
  # session-only cookies survive too.
  "browser.startup.page" = 3;
  "browser.sessionstore.resume_from_crash" = true;
  "browser.sessionstore.privacy_level" = 0;
}