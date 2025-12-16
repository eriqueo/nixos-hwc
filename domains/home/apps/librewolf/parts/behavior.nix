{ lib, pkgs, config, ... }:

{
   # ensure userChrome/userContent are loaded
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
  # Proton can override toolbar styles — disable while testing
  "browser.proton.enabled" = false;

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
  "network.proxy.type" = 0; # ensure direct connection
  "browser.offline" = false;
  "network.manage-offline-status" = true;
  "network.connectivity-service.enabled" = true;
}
