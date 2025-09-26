{ config, pkgs, lib, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      hwc.home.theme.palette = "deep-nord";
      hwc.home.fonts.enable = true;
      hwc.home.shell = {
        enable = true;
        modernUnix = true;
        git.enable = true;
        zsh = {
          enable = true;
          starship = true;
          autosuggestions = true;
          syntaxHighlighting = true;
        };
      };

      # (unchanged unless you later add an Apps domain gate)
      hwc.home.apps.hyprland.enable = true;
      hwc.home.apps.waybar.enable = true;
      hwc.home.apps.kitty.enable = true;
      hwc.home.apps.thunar.enable = true;
      hwc.home.apps.betterbird.enable = true;
      hwc.home.apps.chromium.enable = true;
      hwc.home.apps.librewolf.enable = true;
      hwc.home.apps.obsidian.enable = true;
      hwc.home.apps.dunst.enable = true;
      hwc.home.apps.protonAuthenticator.enable = true;
      hwc.home.apps.protonMail.enable = true;
      hwc.home.apps.aerc.enable = true;

      # MAIL — accounts now come from domains/home/mail/accounts/index.nix
      hwc.home.mail = {
        enable = true;

        notmuch = {
          enable = true;
          userName = "eric okeefe";
          # primaryEmail = "";            # <- optional; will auto-derive
          # maildirRoot  = "...";         # <- optional; will auto-derive
          otherEmails = [
            "eric@iheartwoodcraft.com"
            "eriqueokeefe@gmail.com"
            "heartwoodcraftmt@gmail.com"
          ];
          newTags = [ "unread" "inbox" ];
          excludeFolders = [ "[Gmail]/Spam" "[Gmail]/Trash" ];
          postNewHook = ''
            notmuch tag +sent -inbox -unread -- "(from:eriqueo@proton.me OR from:eric@iheartwoodcraft.com OR from:eriqueokeefe@gmail.com OR from:heartwoodcraftmt@gmail.com)"
          '';
          savedSearches = {
            inbox = "tag:inbox AND tag:unread";
            action = "tag:action AND tag:unread";
            finance = "tag:finance AND tag:unread";
            newsletter = "tag:newsletter AND tag:unread";
            notifications = "tag:notification AND tag:unread";
          };
          installDashboard = true;
          installSampler = true;
        };

        # Optional overrides for Bridge (defaults are fine to omit)
        # bridge = {
        #   enable = true;        # defaults to true when a proton account exists
        #   logLevel = "warn";    # "error" | "warn" | "info" | "debug"
        #   extraArgs = [ ];
        #   environment = { };
        # };
      };

      hwc.home.apps.neomutt.enable = true;
      hwc.home.apps.neomutt.theme.palette = "gruv";
      hwc.home.apps.yazi.enable = true;
      hwc.home.apps.ipcalc.enable = true;
    };
  };
}
