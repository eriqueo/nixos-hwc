# profiles/base/home.nix — base role, Home Manager lane
#
# CLI-shared HM defaults for every machine (headless-safe, OS-agnostic).
# All set with mkDefault — machines can override any option.
#
# REPLACES: the CLI-shared portion of profiles/home-session.nix
# USED BY: every machine (see the machines table in flake.nix)

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../domains/home/index.nix
  ];

  home.stateVersion = "24.05";

  # Restart changed user units on switch (sd-switch diffs the unit set).
  # DELIBERATE: this reaches every machine — user units, including the
  # server's mail timers, restart when their definitions change.
  systemd.user.startServices = "sd-switch";

  hwc.home = {
    # Theme — palette applies headless too (shell/CLI colors)
    theme.palette = lib.mkDefault "hwc";

    # Shell Environment
    core.shell = {
      enable = lib.mkDefault true;
      modernUnix = lib.mkDefault true;
      git.enable = lib.mkDefault true;
      zsh = {
        enable = lib.mkDefault true;
        starship = lib.mkDefault true;
        autosuggestions = lib.mkDefault true;
        syntaxHighlighting = lib.mkDefault true;
      };
    };

    # Development Environment
    core.development.enable = lib.mkDefault true;

    # CLI apps
    apps = {
      gpg.enable = lib.mkDefault true;
      yazi.enable = lib.mkDefault true;
      herdr.enable = lib.mkDefault true;
      codex.enable = lib.mkDefault true;
      pi.enable = lib.mkDefault true;
      aider.enable = lib.mkDefault true;
      gemini-cli.enable = lib.mkDefault true;
    };
  };
}
