# domains/infrastructure/winapps/options.nix
{ lib, ... }:

let
  t = lib.types;
in
{
  options.hwc.infrastructure.winapps = {
    enable = lib.mkEnableOption "WinApps - Windows applications integration via RDP";

    rdpSettings = {
      vmName = lib.mkOption {
        type = t.str;
        default = "RDPWindows";
        description = "Name of the Windows VM (must match libvirt domain name)";
      };

      ip = lib.mkOption {
        type = t.str;
        default = "192.168.122.10";
        description = "IP address of the Windows VM";
      };

      user = lib.mkOption {
        type = t.str;
        default = "";
        description = "Windows username for RDP connection";
      };

      scale = lib.mkOption {
        type = t.int;
        default = 100;
        description = "Display scale percentage";
      };

      flags = lib.mkOption {
        type = t.str;
        default = "/cert-ignore /dynamic-resolution /audio-mode:1";
        description = "Additional FreeRDP flags";
      };
    };

    multiMonitor = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable multi-monitor support";
    };

    debug = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable debug mode for troubleshooting";
    };
  };
}