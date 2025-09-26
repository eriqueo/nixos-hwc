{ lib, ... }:
with lib;
{
  options.hwc.home.apps.notmuch = {
    enable = mkEnableOption "Enable Notmuch module";
    maildirRoot = mkOption { type = types.str; default = "~/.local/share/mail"; };
    userName = mkOption { type = types.str; default = "user"; };
    primaryEmail = mkOption { type = types.str; default = ""; };
    otherEmails = mkOption { type = types.listOf types.str; default = []; };
    newTags = mkOption { type = types.listOf types.str; default = [ "unread" "inbox" ]; };
    excludeFolders = mkOption { type = types.listOf types.str; default = []; };
    postNewHook = mkOption { type = types.lines; default = ""; };
    savedSearches = mkOption {
      type = types.attrsOf types.str;
      default = {
        inbox = "tag:inbox AND tag:unread";
        action = "tag:action AND tag:unread";
        finance = "tag:finance AND tag:unread";
        newsletter = "tag:newsletter AND tag:unread";
        notifications = "tag:notification AND tag:unread";
      };
    };
    installDashboard = mkOption { type = types.bool; default = true; };
    installSampler = mkOption { type = types.bool; default = true; };
  };
}
