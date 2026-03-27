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
    # Unified view
    "unified" = "tag:inbox";

    # Proton identity views
    "inbox:hwc"             = "tag:inbox AND tag:hwc";
    "inbox:proton-hwc"      = "tag:inbox AND tag:proton-hwc";
    "inbox:proton-personal" = "tag:inbox AND tag:proton-personal";

    # Disabled - Gmail sync removed (both accounts now forward to Proton)
    # "inbox:gmail-personal"  = "tag:inbox AND tag:gmail-personal";
    # "inbox:gmail-business"  = "tag:inbox AND tag:gmail-business";

    # Domain rollups (Proton-only now)
    "all:work"     = "tag:inbox AND tag:hwc";
    "all:personal" = "tag:inbox AND tag:proton-personal";

    # --- Proton label views ---
    "label:work"      = "tag:work AND NOT tag:trash";
    "label:finance"   = "tag:finance AND NOT tag:trash";
    "label:coaching"  = "tag:coaching AND NOT tag:trash";
    "label:tech"      = "tag:tech AND NOT tag:trash";
    "label:bank"      = "tag:bank AND NOT tag:trash";
    "label:insurance" = "tag:insurance AND NOT tag:trash";
    "label:personal"  = "tag:gmail-personal AND NOT tag:trash";
    "label:hwcmt"     = "tag:hwcmt AND NOT tag:trash";
    "label:hide"      = "tag:hide";
  };

  all = defaults // builtinSearches // (cfg.savedSearches or {});
  lines = lib.mapAttrsToList (n: q: "${n}=${q}") all;
  text = lib.concatStringsSep "\n" lines + "\n";
in { inherit text; }