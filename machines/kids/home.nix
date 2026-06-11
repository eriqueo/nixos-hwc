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
      # Browser: was firefox.enable = true (copy-paste from prior gaming
      # config). domains/home/apps/firefox/ never landed in this repo —
      # the codebase uses LibreWolf as the daily Firefox-engine browser.
      # Swapped 2026-05-31 to a module that actually exists.
      librewolf.enable = true;

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

  # eXoDOS: auto-install retro_exo flatpaks on first nixos-rebuild switch.
  # Runs only if ~/eXoDOS is present and flatpaks are not yet installed.
  home.activation.exodosFlatpaks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    flatpak=/run/current-system/sw/bin/flatpak
    flatpak_dir="$HOME/eXoDOS/eXo/Flatpaks"
    if [ -d "$flatpak_dir" ] && ! $flatpak list 2>/dev/null | grep -q "com.retro_exo.aria2c"; then
      echo "eXoDOS: installing retro_exo flatpaks..."
      $DRY_RUN_CMD $flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
      for runtime in \
        "org.freedesktop.Platform//24.08" \
        "org.freedesktop.Platform.Compat.i386//24.08" \
        "org.freedesktop.Platform//23.08" \
        "org.freedesktop.Platform.Compat.i386//23.08" \
        "org.gnome.Platform//46" \
        "org.kde.Platform//6.7" \
        "org.kde.Platform//5.15-23.08"; do
        $DRY_RUN_CMD $flatpak install --user -y flathub "$runtime" || true
      done
      for pkg in "$flatpak_dir"/*.flatpak; do
        [ -f "$pkg" ] && $DRY_RUN_CMD $flatpak install --user --reinstall -y "$pkg" || true
      done
      echo "eXoDOS: flatpak installation complete."
    fi
  '';

  # eXoDOS launcher desktop entry
  xdg.desktopEntries.exogui = {
    name = "eXoDOS";
    comment = "DOS Game Collection Browser";
    exec = "bash /home/eric/eXoDOS/exogui.command";
    icon = "/home/eric/eXoDOS/eXo/util/exodos.png";
    categories = [ "Game" ];
  };
}
