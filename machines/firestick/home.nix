{ config, pkgs, lib, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = {
      imports = [
        ../../domains/home/index.nix
      ];

      home.stateVersion = "24.05";

      hwc.home = {
        shell.enable = true;
        development.enable = false;
        mail.enable = false;

        apps = {
          hyprland.enable = true;
          kitty.enable = true;
          yazi.enable = true;

          jellyfinMediaPlayer = {
            enable = true;
            autoStart = true;
          };
        };
      };

      # Trim everything non-essential for travel use.
      hwc.home.apps = {
        chromium.enable = false;
        librewolf.enable = false;
        qutebrowser.enable = false;
        obsidian.enable = false;
        onlyoffice-desktopeditors.enable = false;
        slack.enable = false;
        slack-cli.enable = false;
        google-cloud-sdk.enable = false;
        n8n.enable = false;
        aerc.enable = false;
        betterbird.enable = false;
        neomutt.enable = false;
        protonMail.enable = false;
        proton-authenticator.enable = false;
        protonPass.enable = false;
        thunar.enable = false;
        localsend.enable = false;
        bottles-unwrapped.enable = false;
        opencode.enable = false;
      };
    };
  };
}
