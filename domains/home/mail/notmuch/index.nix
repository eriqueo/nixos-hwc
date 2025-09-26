{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.mail.notmuch or {};

  # ----- parts (pure helpers) -----
  paths      = import ./parts/paths.nix { inherit lib config cfg; };
  coreConfig = import ./parts/core-config.nix {
    inherit lib pkgs;
    maildirRoot  = paths.maildirRoot;
    userName     = cfg.userName     or "eric okeefe";
    primaryEmail = cfg.primaryEmail or "eriqueo@proton.me";
    otherEmails  = cfg.otherEmails  or [ "eric@iheartwoodcraft.com" "eriqueokeefe@gmail.com" "heartwoodcraftmt@gmail.com" ];
    newTags      = cfg.newTags      or [ "unread" "inbox" ];
  };

  folders    = import ./parts/folders.nix { inherit lib; };
  rulesBlock = import ./parts/rules-render.nix { inherit lib; rules = cfg.rules or {}; };
  searches   = import ./parts/saved-searches.nix { inherit lib cfg; };
  scripts    = import ./parts/scripts.nix { inherit lib cfg; };

  postNewText = import ./parts/hook-post-new.nix {
    inherit lib;
    sentClauses    = folders.sent;
    draftsClauses  = folders.drafts;
    trashClauses   = folders.trash;
    spamClauses    = folders.spam;
    archiveClauses = folders.archive;
    rulesBlockText = rulesBlock;
  };
in
{
  config = lib.mkMerge [
    # programs.notmuch + base packages
    {
      home.packages = coreConfig.packages;
      programs.notmuch = coreConfig.programs.notmuch;
    }

    # post-new hook (declarative file)
    {
      home.file."${paths.maildirRoot}/.notmuch/hooks/post-new" = {
        text = postNewText;
        executable = true;
      };
    }

    # saved searches (declarative file)
    {
      xdg.configFile."notmuch/saved-searches".text = searches.text;
    }

    # optional scripts (dashboard, etc.)
    scripts.files
  ];
}
