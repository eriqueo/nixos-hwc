{ lib, cfg, osConfig ? {}}:
let
  defaults = {
    inbox = "tag:inbox AND tag:unread";
    action = "tag:action AND tag:unread";
    finance = "tag:finance AND tag:unread";
    newsletter = "tag:newsletter AND tag:unread";
    notifications = "tag:notification AND tag:unread";
    sent = "tag:sent";
    archive = "tag:archive";
  };

  # Built-in saved searches for unified inbox workflow
  builtinSearches = {
    # Unified view: All inbox mail from all accounts
    "unified" = "tag:inbox";

    # Per-account inbox views
    "inbox:hwc"             = "tag:inbox AND tag:hwc";
    "inbox:proton-hwc"      = "tag:inbox AND tag:proton-hwc";
    "inbox:proton-personal" = "tag:inbox AND tag:proton-personal";
    "inbox:gmail-personal"  = "tag:inbox AND tag:gmail-personal";
    "inbox:gmail-business"  = "tag:inbox AND tag:gmail-business";

    # Rollups by domain
    "all:work"     = "tag:inbox AND tag:hwc";
    "all:personal" = "tag:inbox AND (tag:proton-personal OR tag:gmail-personal)";
  };

  all = defaults // builtinSearches // (cfg.savedSearches or {});
  lines = lib.mapAttrsToList (n: q: "${n}=${q}") all;
  text = lib.concatStringsSep "\n" lines + "\n";
in { inherit text; }