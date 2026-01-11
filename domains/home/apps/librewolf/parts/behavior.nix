{ lib, pkgs, config, ... }:

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
}
