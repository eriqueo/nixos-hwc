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
}
