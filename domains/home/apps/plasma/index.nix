{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.plasma;
  isNixOS = osConfig ? hwc;
  defaults = {
    "kdeglobals" = ''
      [KDE]
      SingleClick=false
      LookAndFeelPackage=org.kde.breeze.desktop
      [General]
      BrowserApplication=firefox.desktop
    '';
    "kscreenlockerrc" = ''
      [Daemon]
      Autolock=false
      LockOnResume=false
    '';
    "ksmserverrc" = ''
      [General]
      loginMode=emptySession
    '';
    "powerdevilrc" = ''
      [AC][SuspendAndShutdown]
      AutoSuspendAction=0
      LidAction=0
    '';
  };
in {
  options.hwc.home.apps.plasma.enable = lib.mkEnableOption "a familiar stock Plasma desktop";
  config = lib.mkIf cfg.enable {
    assertions = lib.mkIf isNixOS [{
      assertion = lib.attrByPath [ "services" "desktopManager" "plasma6" "enable" ] false osConfig;
      message = "Plasma home defaults need the native Plasma desktop.";
    }];
    home.packages = [ pkgs.firefox pkgs.kdePackages.spectacle pkgs.vulkan-tools pkgs.mesa-demos ];
    xdg.enable = true;
    xdg.userDirs = { enable = true; createDirectories = true; };
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "inode/directory" = [ "org.kde.dolphin.desktop" ];
      };
    };
    # CRITICAL user settings: seed absent files only. Later user edits survive
    # rebuilds. Removing a generated default does not delete personal state.
    home.activation.plasmaDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -d -m 0700 "$HOME/.config"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: content: ''
        if [ ! -e "$HOME/.config/${name}" ]; then
          install -m 0600 ${pkgs.writeText "plasma-default-${name}" content} "$HOME/.config/${name}"
        fi
      '') defaults)}
    '';
    home.file."Desktop/Start Here.txt".text = ''
      Welcome

      Open the application menu at the bottom left.
      Firefox opens the web. Dolphin opens your files. Steam opens your games.
      Windows have minimize, maximize and close buttons at the top right.
      Double-click a file or folder to open it.

      Leave this computer plugged in. It also runs a home server.
      Log Out ends your desktop session. Shutting down stops the server.
      Eric can help remotely through his separate administrator account.

      Store personal files in Documents, Desktop or Pictures.
      Downloaded games and Downloads are not included in the state backup.
      Tell Eric if a game fails to start or files need to be restored.
    '';
  };
}
