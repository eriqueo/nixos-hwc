# domains/home/apps/tether/index.nix
# Tether: iMessage and SMS from the iPhone over Bluetooth, no Mac. This half
# runs the daemon (tetherd) as a user service and puts the CLI, TUI and GTK
# client in the session. The daemon's local UNIX socket (newline JSON) is what
# our own clients speak: the Waybar module and the HWC Textual client.
#
# The system half (sys.nix) owns BlueZ's experimental bearer API and the
# adapter class; without it iOS never offers "Show Message Notifications".
# One-time pairing is a hands-on step at the laptop with the phone: see the
# project wizard (agent/imessage-linux/pair-tether.sh).

{ config, lib, pkgs, osConfig ? { }, ... }:

let
  cfg = config.hwc.home.apps.tether;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;
  # The package is produced once, by the system half; HM only runs it. On a
  # host without the system half (standalone HM) there is nothing to run.
  sysCfg = lib.attrByPath [ "hwc" "system" "apps" "tether" ] { } osConfig;
  package = sysCfg.package or null;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.tether = {
    enable = lib.mkEnableOption "Tether daemon and clients (iPhone messages over Bluetooth)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (package != null) package;

    # The daemon: Bluetooth MAP/PBAP/ANCS sessions with the paired phone, the
    # local socket for clients, Wayland clipboard sync when the session is up.
    # Our own unit, not the package's, so its placement is one fact here.
    systemd.user.services.tetherd = lib.mkIf (package != null) {
      Unit = {
        Description = "Tether daemon (iPhone messages, notifications, clipboard)";
        After = [ "graphical-session.target" "bluetooth.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${package}/bin/tetherd";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "tether"; })
      {
        assertion = !isNixOSHost || package != null;
        message = "hwc.home.apps.tether: the system half must expose its package (hwc.system.apps.tether.enable = true).";
      }
    ];
  };
}
