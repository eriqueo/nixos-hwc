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

{ config, lib, pkgs, osConfig ? { }, tetherPackage ? null, ... }:

let
  cfg = config.hwc.home.apps.tether;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;
  # The package is produced once, by the system half; HM only runs it. The
  # flake hands it to both lanes as `tetherPackage` (standalone `hms` has no
  # osConfig). On a host without the system half there is nothing to run.
  package = tetherPackage;

  # tetherd owns $XDG_CONFIG_HOME/tether/bluetooth.json (it writes the paired
  # phone and its own toggles there) and has no socket command for some keys,
  # group_messages_enabled among them. So Nix does not own the file: before
  # each start it merges the declared keys over whatever tetherd last wrote,
  # atomically and at mode 0600. tetherd reads the file only at startup.
  settingsJson = pkgs.writeText "tether-settings.json" (builtins.toJSON cfg.settings);
  applySettings = pkgs.writeShellScript "tether-apply-settings" ''
    set -eu
    dir="''${XDG_CONFIG_HOME:-$HOME/.config}/tether"
    file="$dir/bluetooth.json"
    mkdir -p "$dir"
    [ -s "$file" ] || echo '{}' > "$file"
    tmp=$(mktemp "$dir/.bluetooth.json.XXXXXX")
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$file" ${settingsJson} > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$file"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.tether = {
    enable = lib.mkEnableOption "Tether daemon and clients (iPhone messages over Bluetooth)";

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [ lib.types.bool lib.types.int lib.types.str ]);
      default = { };
      example = { group_messages_enabled = true; };
      description = ''
        Keys merged into tetherd's bluetooth.json before every start. Keys not
        set here stay as tetherd or its clients left them.
      '';
    };
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
        ExecStartPre = lib.mkIf (cfg.settings != { }) "${applySettings}";
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
