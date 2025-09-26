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

      hwc.home.apps.hyprland.enable = true;
      hwc.home.apps.waybar.enable = true;
      hwc.home.apps.kitty.enable = true;
      hwc.home.apps.thunar.enable = true;
      hwc.home.apps.betterbird.enable = true;
      hwc.home.apps.chromium.enable = true;
      hwc.home.apps.librewolf.enable = true;
      hwc.home.apps.obsidian.enable = true;
      hwc.home.apps.dunst.enable = true
      ;
      hwc.home.apps.protonAuthenticator.enable = true;
      hwc.home.apps.protonMail.enable = true;
      hwc.home.apps.aerc.enable = true;

      hwc.home.mail = {
        enable = true;

        accounts = {
          proton = {
            name = "proton";
            type = "proton-bridge";
            realName = "Eric";
            address = "eriqueo@proton.me";
            login = "";
            password = { mode = "pass"; pass = "email/proton/bridge"; };
            maildirName = "proton";
            sync.patterns = [ "INBOX" "Sent" "Drafts" "Trash" "Archive" ];
            send.msmtpAccount = "proton";
            primary = true;
          };

          gmail-personal = {
            name = "gmail-personal";
            type = "gmail";
            realName = "Eric O'Keefe";
            address = "eriqueokeefe@gmail.com";
            login = "eriqueokeefe@gmail.com";
            password = { mode = "agenix"; agenix = "/run/agenix/gmail-personal-password"; };
            maildirName = "gmail-personal";
            sync.patterns = [
              "INBOX"
              "[Gmail]/Sent Mail"
              "[Gmail]/Drafts"
              "[Gmail]/Trash"
              "[Gmail]/All Mail"
            ];
            send.msmtpAccount = "gmail-personal";
          };

          gmail-business = {
            name = "gmail-business";
            type = "gmail";
            realName = "Eric O'Keefe";
            address = "heartwoodcraftmt@gmail.com";
            login = "heartwoodcraftmt@gmail.com";
            password = { mode = "agenix"; agenix = "/run/agenix/gmail-business-password"; };
            maildirName = "gmail-business";
            sync.patterns = [
              "INBOX"
              "[Gmail]/Sent Mail"
              "[Gmail]/Drafts"
              "[Gmail]/Trash"
              "[Gmail]/All Mail"
            ];
            send.msmtpAccount = "gmail-business";
          };
        };

        notmuch = {
          enable = true;
          maildirRoot = "${config.home.homeDirectory}/Maildir";
          userName = "eric okeefe";
          primaryEmail = ""; 
          otherEmails = [ "eric@iheartwoodcraft.com" "eriqueokeefe@gmail.com" "heartwoodcraftmt@gmail.com" ];
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
      };

      hwc.home.apps.neomutt.enable = true;
      hwc.home.apps.neomutt.theme.palette = "gruv";
      hwc.home.apps.yazi.enable = true;
      hwc.home.apps.ipcalc.enable = true;
    };
  };
}
