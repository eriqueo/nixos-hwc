# machines/laptop/home.nix
#
# MACHINE: HWC-LAPTOP — Home Manager overrides
# Machine-specific HM option overrides. Profiles/home-session.nix provides defaults;
# this file adjusts only what is unique to this machine.
# Shared between NixOS module (nixos-rebuild) and standalone (home-manager switch).

{ lib, ... }:

{
  # Apps enabled on this machine specifically
  hwc.home.apps = {
    calcurse.enable = true;
    calcure.enable = true;
    imv.enable = true;
    qbittorrent.enable = true;
    aider.enable = true;
    claude-code.enable = true;
    claude-desktop.enable = true;
    scraper.enable = true;
  };

  # Calendar: Apple iCloud sync via khal + vdirsyncer (CalDAV)
  hwc.mail.calendar = {
    enable = true;
    icsWatch.enable = false;
    accounts = {
      icloud = {
        email = "eric@iheartwoodcraft.com";
        color = "dark green";
      };
    };
  };
  hwc.mail.health = {
    enable = false;
  };

  # eXoDOS: auto-install retro_exo flatpaks on first use of this machine.
  # Runs during `nixos-rebuild switch` if ~/eXoDOS exists but flatpaks are absent.
  # Installs flathub runtimes + all local .flatpak bundles from ~/eXoDOS/eXo/Flatpaks/.
  # Safe to run repeatedly — the guard prevents re-installation.
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

  # Shell: MCP configured for laptop context
  hwc.home.shell = {
    enable = true;
    mcp = {
      enable = true;
      includeConfigDir = false;   # don't expose ~/.config to Claude
      includeServerTools = false; # no server MCP tools on laptop
      n8n = {
        enable = true;
        # accessToken is set via agenix secret injection or overridden locally.
        # To set temporarily: add  accessToken = "your-token-here";  below.
        # Long-term: wire this through an activation script reading the agenix secret file.
        accessToken = ""; # REPLACE with your token or wire via agenix
      };
    };
  };
}
