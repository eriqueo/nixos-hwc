{ config, lib, pkgs, osConfig ? {}, ...}:
let
  on = (config.hwc.home.mail.enable or true);
  cfg = config.hwc.home.mail.notmuch or {};
  paths = import ./parts/paths.nix { inherit lib config cfg; };
  ident = import ./parts/identity.nix { inherit lib cfg; };
  afewCfg = config.hwc.home.mail.afew or {};
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
  options.hwc.home.mail.notmuch = {
    maildirRoot = lib.mkOption { type = lib.types.str; default = ""; };
    userName = lib.mkOption { type = lib.types.str; default = ""; };
    primaryEmail = lib.mkOption { type = lib.types.str; default = ""; };
    otherEmails = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    newTags = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "unread" "inbox" ]; };
    excludeFolders = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    postNewHook = lib.mkOption { type = lib.types.lines; default = ""; };
    savedSearches = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
    installDashboard = lib.mkOption { type = lib.types.bool; default = false; };
    rules = {
      newsletterSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "newsletter@" "news@" "updates@" "digest@" "list@" "mailer@" ]; };
      notificationSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "no-reply@" "noreply@" "notifications@" "notices@" "github.com" ]; };
      financeSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "amazon.com" "paypal.com" "stripe.com" "squareup.com" "intuit.com" "quickbooks" "chase.com" "bankofamerica.com" ]; };
      actionSubjects = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "invoice" "quote" "proposal" "estimate" "RFP" "action required" "approve" "signature" "past due" ]; };
      trashSenders = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Senders whose mail is auto-trashed on arrival."; };
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
