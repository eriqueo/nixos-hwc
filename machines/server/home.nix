# machines/server/home.nix
#
# MACHINE: HWC-SERVER — Home Manager configuration
# Shared between NixOS module (nixos-rebuild) and standalone (home-manager switch).
# Headless server: CLI only, no GUI.

{ lib, ... }:

{
  imports = [
    ../../domains/home/index.nix
    ../../domains/mail/index.nix
  ];

  home.stateVersion = "24.05";

  # Mail — infrastructure + aerc + calendar
  hwc.mail = {
    enable = true;
    bridge.enable = true;
    aerc.enable = true;

    calendar = {
      enable = true;
      accounts.icloud = {
        email = "eric@iheartwoodcraft.com";
        color = "dark green";
      };
    };

    health = {
      enable = true;
      webhook.url = "https://hwc.ocelot-wahoo.ts.net:10000/webhook/mail-health";
    };

    notmuch = {
      maildirRoot = "/home/eric/400_mail/Maildir";
      userName = "Eric O'Keefe";
      primaryEmail = "eric@iheartwoodcraft.com";
      otherEmails = [ "eriqueo@proton.me" "heartwoodcraftmt@gmail.com" "eriqueokeefe@gmail.com" ];
      newTags = [ "unread" "inbox" ];
      excludeFolders = [ "trash" "spam" "[Gmail]/All Mail" ];
      savedSearches = {
        inbox = "tag:inbox and not tag:archived";
        unread = "tag:unread";
        work = "from:*@iheartwoodcraft.com or from:*heartwoodcraftmt@gmail.com";
        personal = "from:*@proton.me or from:*eriqueokeefe@gmail.com";
        urgent = "tag:urgent or tag:important";
      };
    };
  };

  hwc.home = {
    # CLI tools only
    shell = {
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

    development.enable = true;

    # No GUI, no theme
    theme.fonts.enable = false;

    # CLI-only apps
    apps = {
      gpg.enable = true;
      codex.enable = true;
      aider.enable = true;
      gemini-cli.enable = true;
    };
  };

  # Enable home-manager CLI for standalone `hms` rebuilds
  programs.home-manager.enable = true;

  # Disable desktop services
  targets.genericLinux.enable = false;
  dconf.enable = lib.mkForce false;
  services.mako.enable = lib.mkForce false;
}
