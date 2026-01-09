{ lib, pkgs, config, ... }:

let
  sessionVars = lib.attrByPath [ "home" "sessionVariables" ] {} config;
  proxyEnvNames = [
    "http_proxy" "https_proxy" "HTTP_PROXY" "HTTPS_PROXY"
    "all_proxy" "ALL_PROXY"
  ];
  proxyEnvPresent = builtins.any (name: builtins.hasAttr name sessionVars) proxyEnvNames;
  # Respect proxies when explicitly set; otherwise stay direct.
  proxyType = if proxyEnvPresent then 5 else 0;
in
{
   # ensure userChrome/userContent are loaded
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

  "browser.tabs.closeWindowWithLastTab" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.feeds.topsites" = false;
  "browser.sessionstore.interval" = 30000;
  "privacy.globalprivacycontrol.enabled" = true;
  "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
  "browser.urlbar.suggest.searches" = false;    # disable remote suggestions
  "browser.urlbar.suggest.history" = true;      # keep fast local history
  "ui.prefersReducedMotion" = 1;
  "toolkit.cosmeticAnimations.enabled" = false;
  "network.proxy.type" = proxyType;
  "browser.offline" = false;
  "network.manage-offline-status" = true;
  "network.connectivity-service.enabled" = true;
}
