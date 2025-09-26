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
  all = defaults // (cfg.savedSearches or {});
  lines = lib.mapAttrsToList (n: q: "${n}=${q}") all;
  text = lib.concatStringsSep "\n" lines + "\n";
in { inherit text; }
