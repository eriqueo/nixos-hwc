# profiles/home.nix
#
# HOME DOMAIN - Feature menu for Home Manager capabilities
# Provides user environment configuration and application management
{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # HOME MANAGER ACTIVATION - Machine-level HM configuration
  #==========================================================================
  
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      #========================================================================
      # BASE HOME - Essential user environment
      #========================================================================
      
      # Core theme and shell functionality
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

      #========================================================================
      # OPTIONAL HOME FEATURES - Application toggles per machine
      #========================================================================
      
      # Desktop environment
      hwc.home.apps.hyprland.enable = true;
      hwc.home.apps.waybar.enable = true;
      hwc.home.apps.kitty.enable = true;
      hwc.home.apps.thunar.enable = true;
      hwc.home.apps.betterbird.enable = true;
      hwc.home.apps.chromium.enable = true;
      hwc.home.apps.librewolf.enable = true;
      hwc.home.apps.obsidian.enable = true;
      hwc.home.apps.dunst.enable = true;
      
      # Mail configuration
      hwc.home.core.mail = {
          enable = true;
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

      
      # NeoMutt configuration  
      hwc.home.apps.neomutt.enable = true;
      hwc.home.apps.neomutt.theme.palette = "gruv";
    };
  };
}
