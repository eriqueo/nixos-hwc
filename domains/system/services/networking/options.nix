# domains/system/services/networking/options.nix
{ lib, config, ... }:
{
  options.hwc.networking = {
    enable = lib.mkEnableOption "HWC networking configuration";

    ssh = {
      enable = lib.mkEnableOption "SSH server configuration";
      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "SSH server port";
      };
    };

    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN mesh networking";

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to Tailscale auth key file";
      };

      extraUpFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra flags for tailscale up command";
      };
    };

    networkManager = {
      enable = lib.mkEnableOption "NetworkManager for network management";
    };

    firewall = {
      level = lib.mkOption {
        type = lib.types.enum [ "off" "basic" "strict" "server" ];
        default = "strict";
        description = "High-level firewall profile";
      };

      extraTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "Additional TCP ports to open";
      };

      extraUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "Additional UDP ports to open";
      };
    };

    samba = {
      enable = lib.mkEnableOption "Samba file sharing service";

      shares = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Samba share definitions";
      };
    };
  };
}
