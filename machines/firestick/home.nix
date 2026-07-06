# machines/firestick/home.nix
#
# MACHINE: HWC-FIRESTICK — Home Manager config (HM lane)
# Travel TV stick: Jellyfin player + minimal shell. The base role's home
# half provides CLI-shared defaults via the flake glue; everything this
# lean machine does not want is explicitly disabled below (preserves the
# pre-roles behavior — relax deliberately, not by accident).

{ config, pkgs, lib, ... }:

{
  imports = [
    ../../domains/mail/index.nix
  ];

  hwc.mail.enable = false;

  hwc.home = {
    core.shell.enable = true;
    # base/home.nix turns these on by default — the stick stays lean
    core.shell.modernUnix = false;
    core.shell.zsh.starship = false;
    core.shell.zsh.autosuggestions = false;
    core.shell.zsh.syntaxHighlighting = false;
    core.development.enable = false;

    apps = {
      hyprland.enable = true;
      kitty.enable = true;
      yazi.enable = true;

      jellyfin-media-player = {
        enable = true;
        autoStart = true;
      };
    };
  };

  # Trim everything non-essential for travel use.
  hwc.home.apps = {
    chromium.enable = false;
    firefox.enable = false;
    qutebrowser.enable = false;
    obsidian.enable = false;
    onlyoffice-desktopeditors.enable = false;
    slack.enable = false;
    slack-cli.enable = false;
    google-cloud-sdk.enable = false;
    n8n.enable = false;
    neomutt.enable = false;
    proton-mail.enable = false;
    proton-authenticator.enable = false;
    proton-pass.enable = false;
    thunar.enable = false;
    localsend.enable = false;
    bottles-unwrapped.enable = false;
    opencode.enable = false;

    # base/home.nix CLI extras not wanted on the stick
    gpg.enable = false;
    herdr.enable = false;
    codex.enable = false;
    aider.enable = false;
    gemini-cli.enable = false;
  };
}
