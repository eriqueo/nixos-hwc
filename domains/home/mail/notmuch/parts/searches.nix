{ lib, cfg }:
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
   savedSearches = {
    "inbox:hwc"    = "tag:inbox AND tag:hwc";
    "inbox:proton" = "tag:inbox AND tag:proton";
    "inbox:gmail-personal" = "tag:inbox AND tag:gmail-personal";
    "inbox:gmail-business" = "tag:inbox AND tag:gmail-business";
    
    # Rollups now super clean:
    "all:work"  = "tag:inbox AND tag:hwc";
    "all:personal" = "tag:inbox AND (tag:proton OR tag:gmail-personal)";
  };
  all = defaults // (cfg.savedSearches or {});
  lines = lib.mapAttrsToList (n: q: "${n}=${q}") all;
  text = lib.concatStringsSep "\n" lines + "\n";
in { inherit text; }
