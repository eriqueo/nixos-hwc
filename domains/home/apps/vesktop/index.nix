# domains/home/apps/vesktop/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.vesktop;
  package = config.programs.vesktop.package;

  # Electron's GPU process held /dev/nvidiactl and the NVIDIA render node open
  # for a whole session, keeping the dGPU at ~15 W while idle. Own the plain
  # command so every caller (launcher, xdg-open, autostart) runs with NVIDIA
  # devices hidden by the system's gpu-integrated boundary.
  launcher = pkgs.writeShellScriptBin "vesktop" ''
    if command -v gpu-integrated >/dev/null 2>&1; then
      exec gpu-integrated ${package}/bin/vesktop "$@"
    fi
    exec ${package}/bin/vesktop "$@"
  '';
in
{
  # OPTIONS
  options.hwc.home.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop Discord client";
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    programs.vesktop.enable = true;

    # Resolve the colliding bin/vesktop to the launcher; the package keeps
    # its icons and data.
    home.packages = [ (lib.hiPrio launcher) ];

    xdg.desktopEntries.vesktop = {
      name = "Vesktop";
      genericName = "Internet Messenger";
      exec = "${lib.getExe launcher} %U";
      icon = "vesktop";
      terminal = false;
      categories = [ "Network" "InstantMessaging" "Chat" ];
      startupNotify = true;
    };

    # Vesktop's "Start on login" setting writes this file with a raw electron
    # store path, which bypasses the launcher and goes stale on upgrade.
    # Own it so login starts cross the same boundary.
    xdg.configFile."autostart/vesktop.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Vesktop
        Exec=${lib.getExe launcher}
        Icon=vesktop
        StartupNotify=false
        Terminal=false
      '';
    };

    # VALIDATION
    assertions = [
      {
        assertion = config.programs.vesktop.enable;
        message = "programs.vesktop must remain enabled when hwc.home.apps.vesktop is enabled";
      }
    ];
  };
}
