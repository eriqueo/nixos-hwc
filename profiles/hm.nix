# profiles/hm.nix
{ config, pkgs, lib, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # Ensure HM will back up any pre-existing files instead of failing.
    backupFileExtension = "hm-bak";

    users.eric = {
      imports = [ ../modules/home/index.nix ];

      home.stateVersion = "24.05";

      # Your feature toggles (keep as-is if the modules exist)
      features = {
        hyprland.enable     = true;
        waybar.enable       = true;
        kitty.enable        = true;
        thunar.enable       = true;
        betterbird.enable   = true;
        chromium.enable     = true;
        librewolf.enable    = true;
        protonBridge.enable = true;
        obsidian.enable     = true;
        protonMail.enable   = true;
        protonPass.enable   = true;
        dunst.enable        = true;
        #-----------------------
        #   ---Mail---
        #-----------------------
                                
        mail ={
          enable         = true;
          accounts ={
             proton = {
              name       = "proton";
              type       = "proton-bridge";
              realName   = "Eric";
              address    = "eriqueo@proton.me";
              # Leave login empty -> generator will fall back to bridgeUsername/address
              login      = "";
              password = {
                mode   = "pass";
                pass   = "email/proton/bridge";  # pass insert email/proton/bridge
              };
              maildirName = "proton";
              sync.patterns = [ "INBOX" "Sent" "Drafts" "Trash" "Archive" ];
              send.msmtpAccount = "proton";
              primary = true;
            };

            gmail-personal = {
              name       = "gmail-personal";
              type       = "gmail";
              realName   = "Eric O'Keefe";
              address    = "eriqueokeefe@gmail.com";
              login      = "eriqueokeefe@gmail.com";
              password = {
                mode   = "agenix";
                agenix = "/run/agenix/gmail-personal-password";
              };
              maildirName = "gmail-personal";
              # Gmail folder names with spaces — generator quotes them
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
              name       = "gmail-business";
              type       = "gmail";
              realName   = "Eric O'Keefe";
              address    = "heartwoodcraftmt@gmail.com";
              login      = "heartwoodcraftmt@gmail.com";
              password = {
                mode   = "agenix";
                agenix = "/run/agenix/gmail-business-password";
              };
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
          };

        #-----------------------
        #   --- NeoMutt---
        #-----------------------
        neomutt = {
          enable = true;
          theme.palette = "gruv"; };
      };

      # Theme and shell (unchanged)
      hwc.home.theme.palette = "deep-nord";

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
    };
  };
}
