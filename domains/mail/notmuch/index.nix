{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on = (config.hwc.mail.enable or true);
  cfg = config.hwc.mail.notmuch or {};
  paths = import ./parts/paths.nix { inherit lib config cfg; };
  ident = import ./parts/identity.nix { inherit lib cfg; };
  afewCfg = config.hwc.mail.afew or {};
  afewPkg = import ../afew/package.nix { inherit lib pkgs; cfg = afewCfg; };

  cfgPart = import ./parts/config.nix {
    inherit lib pkgs;
    maildirRoot = paths.maildirRoot;
    inherit (ident) userName primaryEmail otherEmails newTags;
    excludeFolders = cfg.excludeFolders or [];

  };

  special = import ./parts/folders.nix { inherit lib config; };
  rules   = import ./parts/rules.nix { inherit lib cfg; };

  hookTxt = import ./parts/hooks.nix {
    inherit lib pkgs special afewPkg;
    afewEnabled = afewCfg.enable or false;
    rulesText = rules.text;
    extraHook = cfg.postNewHook or "";
  };

  searches = import ./parts/searches.nix { inherit lib cfg; };
  dashboardText = builtins.readFile ./parts/dashboard.sh;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.mail.notmuch = {
    maildirRoot = lib.mkOption { type = lib.types.str; default = ""; };
    userName = lib.mkOption { type = lib.types.str; default = ""; };
    primaryEmail = lib.mkOption { type = lib.types.str; default = ""; };
    otherEmails = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    newTags = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "unread" "inbox" ]; };
    excludeFolders = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    postNewHook = lib.mkOption { type = lib.types.lines; default = ""; };
    savedSearches = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
    installDashboard = lib.mkOption { type = lib.types.bool; default = false; };
    # Defaults come from the canonical taxonomy (domains/mail/taxonomy/) —
    # edit data.nix there, NOT these options; a direct override here silently
    # re-forks the vocabulary (see docs/plans/unified-triage-architecture.md).
    rules = let tax = (import ../taxonomy/lib.nix { inherit lib; }).derived; in {
      newsletterSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.newsletterSenders; };
      notificationSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.notificationSenders; };
      financeSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.financeSenders; };
      actionSubjects = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.actionSubjects; };
      trashSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.trashSenders; description = "Senders whose mail is auto-trashed on arrival (+trash -inbox -unread, scoped to tag:new). Default: taxonomy senders.trash."; };
      archiveSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = tax.archiveSenders; description = "Senders whose mail is auto-archived on arrival (+archive -inbox, kept but out of inbox; scoped to tag:new). Default: taxonomy senders.archive."; };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on (lib.mkMerge [
    { home.packages = cfgPart.packages; }
    { programs.notmuch = cfgPart.programs.notmuch; }

    { home.file."${paths.maildirRoot}/.notmuch/hooks/post-new" = {
        text = hookTxt.text;
        executable = true;
      };
    }

    { xdg.configFile."notmuch/searches".text = searches.text; }

    (lib.mkIf (cfg.installDashboard or false) {
      home.file.".local/bin/mail-dashboard" = {
        text = dashboardText;
        executable = true;
      };
    })
  ]);
}
