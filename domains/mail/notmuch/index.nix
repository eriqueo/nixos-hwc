{ config, inputs, lib, pkgs, osConfig ? {}, ...}:
let
  on = (config.hwc.mail.enable or true);
  cfg = config.hwc.mail.notmuch or {};
  mailContract = config.hwc.mail.classifier.contract;
  defaultNewTags = [ "new" "unread" "inbox" ];
  paths = import ./parts/paths.nix { inherit lib config cfg; };
  ident = import ./parts/identity.nix { inherit lib cfg defaultNewTags; };
  afewCfg = config.hwc.mail.afew or {};
  afewPkg = import ../afew/package.nix { inherit lib pkgs; cfg = afewCfg; };
  cfgPart = import ./parts/config.nix {
    inherit lib pkgs;
    maildirRoot = paths.maildirRoot;
    inherit (ident) userName primaryEmail otherEmails newTags;
    excludeFolders = cfg.excludeFolders or [];

  };

  special = import ./parts/folders.nix { inherit lib config; };
  hookTxt = import ./parts/hooks.nix {
    inherit lib pkgs special afewPkg mailContract;
    afewEnabled = afewCfg.enable or false;
    extraHook = cfg.postNewHook or "";
  };

  searches = import ./parts/searches.nix { inherit lib cfg mailContract; };
  dashboardText = lib.replaceStrings
    [ "@DO_QUERY@" "@FINANCE_QUERY@" "@NEWSLETTER_QUERY@" "@SECURITY_QUERY@" ]
    (map (name: searches.searches.${name})
      [ "state:do" "fact:finance" "fact:newsletter" "fact:security" ])
    (builtins.readFile ./parts/dashboard.sh);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.mail.notmuch = {
    maildirRoot = lib.mkOption { type = lib.types.str; default = ""; };
    userName = lib.mkOption { type = lib.types.str; default = ""; };
    primaryEmail = lib.mkOption { type = lib.types.str; default = "eric@iheartwoodcraft.com"; };
    # One identity producer for notmuch and the classifier's self-learning guard.
    otherEmails = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "eriqueo@proton.me" "heartwoodcraftmt@gmail.com" "eriqueokeefe@gmail.com"
        "office@iheartwoodcraft.com" "admin@iheartwoodcraft.com"
        "eric@contractorcto.com" "g_hwcmt@proton.me" "g_erique@proton.me"
      ];
    };
    newTags = lib.mkOption { type = lib.types.listOf lib.types.str; default = defaultNewTags; };
    excludeFolders = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    postNewHook = lib.mkOption { type = lib.types.lines; default = ""; };
    savedSearches = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
    installDashboard = lib.mkOption { type = lib.types.bool; default = false; };
    # Defaults come from the canonical taxonomy (domains/mail/taxonomy/) —
    # edit data.nix there, NOT these options; a direct override here silently
    # re-forks the vocabulary (see docs/plans/unified-triage-architecture.md).
    rules = let tax = (import ../taxonomy/lib.nix { inherit lib; }).derived; in {
      trashSenders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = tax.trashSenders;
        description = "Legacy deny list consumed only by the separate Gmail janitor; never by local workflow classification.";
      };
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
