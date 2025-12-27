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
        onlyofficeDesktopeditors.enable = false;
        slack.enable = false;
        slackCli.enable = false;
        googleCloudSdk.enable = false;
        n8n.enable = false;
        aerc.enable = false;
        betterbird.enable = false;
        neomutt.enable = false;
        protonMail.enable = false;
        protonAuthenticator.enable = false;
        protonPass.enable = false;
        thunar.enable = false;
        localsend.enable = false;
        bottlesUnwrapped.enable = false;
        opencode.enable = false;
      };
    };
  };
}
