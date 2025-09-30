{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      #==========================================================================
      # OPTIONAL FEATURES - Sensible defaults, override per machine
      #==========================================================================
      hwc.home.theme.palette = "gruv";
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
      hwc.home.apps.geminiCli.enable = true;
      hwc.home.apps.onlyofficeDesktopeditors.enable = true;
    };
  };
}
