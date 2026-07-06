# machines/kids/home.nix
#
# MACHINE: HWC-KIDS — Home Manager config (HM lane)
# Kids retro gaming station: browser, RetroArch, eXoDOS. No dev/work/mail.
# The base role's home half provides CLI-shared defaults via the flake glue;
# everything this lean machine does not want is explicitly disabled below
# (preserves the pre-roles behavior — relax deliberately, not by accident).

{ config, lib, pkgs, ... }:

{
  hwc.home = {
    core.shell.enable = true;
    # base/home.nix turns these on by default — kids stays lean
    core.shell.modernUnix = false;
    core.shell.zsh.starship = false;
    core.shell.zsh.autosuggestions = false;
    core.shell.zsh.syntaxHighlighting = false;
    core.development.enable = false;

    apps = {
      kitty.enable = true;
      yazi.enable = true;
      hyprland.enable = true;
      # Browser: firefox module (2026-07-06 migration off LibreWolf, which
      # went unmaintained/insecure-flagged in nixpkgs).
      firefox.enable = true;

      # base/home.nix CLI extras not wanted on the kids machine
      gpg.enable = false;
      herdr.enable = false;
      codex.enable = false;
      aider.enable = false;
      gemini-cli.enable = false;
    };
  };

  # Kids machine's role set doesn't include mail, so hwc.mail.* options are
  # not declared in scope — do not set them here.

  # RetroArch with a curated core set for common retro systems
  home.packages = [
    (pkgs.retroarch.withCores (cores: with cores; [
      snes9x          # Super Nintendo
      genesis-plus-gx # Sega Genesis / Game Gear / Master System
      mgba            # Game Boy Advance / Game Boy Color
      gambatte        # Game Boy / Game Boy Color (accurate)
      nestopia         # NES / Famicom
      mupen64plus      # Nintendo 64
      beetle-psx-hw    # PlayStation 1 (hardware renderer)
      mame             # Arcade
      dosbox-pure      # DOS (fallback outside eXoDOS)
    ]))
  ];

  # eXoDOS (flatpak auto-install + launcher) — domains/home/apps/exodos
  hwc.home.apps.exodos.enable = true;
}
