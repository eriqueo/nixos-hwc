# domains/home/apps/exodos/index.nix
#
# eXoDOS DOS game collection: retro_exo flatpak auto-install + exogui
# launcher entry. The collection itself is unmanaged data the user drops
# at `root` (default ~/eXoDOS); activation is a no-op until it exists.
{ config, lib, ... }:
let
  cfg = config.hwc.home.apps.exodos;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.exodos = {
    enable = lib.mkEnableOption "eXoDOS DOS game collection (flatpak runtimes + launcher)";

    root = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/eXoDOS";
      description = "Where the (unmanaged) eXoDOS collection lives";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Auto-install retro_exo flatpaks on switch. Runs only if the collection
    # is present and the flatpaks are not yet installed; safe to run
    # repeatedly — the guard prevents re-installation.
    home.activation.exodosFlatpaks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      flatpak=/run/current-system/sw/bin/flatpak
      flatpak_dir="${cfg.root}/eXo/Flatpaks"
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

    # Launcher desktop entry
    xdg.desktopEntries.exogui = {
      name = "eXoDOS";
      comment = "DOS Game Collection Browser";
      exec = "bash ${cfg.root}/exogui.command";
      icon = "${cfg.root}/eXo/util/exodos.png";
      categories = [ "Game" ];
    };
  };
}
