{ lib, config, ... }:

let
  types = lib.types;
in
{
  options.hwc.system.networking = {
    enable = lib.mkEnableOption "Enable HWC networking (SSH, Tailscale, Samba, firewall, NM).";

    # ---- NetworkManager ----
    networkManager.enable = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Enable NetworkManager.";
    };

    # ---- SSH ----
    ssh = {
      enable = lib.mkEnableOption "Enable OpenSSH server.";
      port = lib.mkOption {
        type = types.port;
        default = 22;
        description = "OpenSSH TCP port.";
      };
    };

    # ---- Tailscale ----
    tailscale = {
      enable = lib.mkEnableOption "Enable Tailscale.";
      authKeyFile = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to a file containing TS_AUTHKEY (optional).";
      };
      extraUpFlags = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "--operator=eric" "--advertise-exit-node" ];
        description = "Extra flags for `tailscale up`.";
      };
      funnel = {
        enable = lib.mkEnableOption "Enable Tailscale Funnel for public access.";
        ports = lib.mkOption {
          type = types.listOf types.port;
          default = [];
          example = [ 443 2443 ];
          description = "Ports to expose publicly via Tailscale Funnel.";
        };
      };
    };

    # ---- Samba ----
    samba = {
      enable = lib.mkEnableOption "Enable Samba file sharing.";
      shares = lib.mkOption {
        type = types.attrsOf types.attrs;
        default = { };
        example = {
          public = { path = "/data/public"; browseable = true; readOnly = true; guestAccess = true; };
        };
        description = "Samba shares attrset, passed to services.samba.shares.";
      };
    };

    # ---- Firewall ----
    firewall = {
      level = lib.mkOption {
        type = types.enum [ "off" "basic" "strict" "server" ];
        default = "strict";
        description = "Firewall profile.";
      };
      extraTcpPorts = lib.mkOption {
        type = types.listOf types.port;
        default = [];
        description = "Extra TCP ports to open.";
      };
      extraUdpPorts = lib.mkOption {
        type = types.listOf types.port;
        default = [];
        description = "Extra UDP ports to open.";
      };
    };

    # ---- Wait-online policy (per-machine) ----
    waitOnline = {
      mode = lib.mkOption {
        type = types.enum [ "off" "all" "interfaces" ];
        default = "off";
        description = ''
          Network boot policy:
            - "off": do not block boot on network (best for laptops/Hyprland)
            - "all": wait for any NM-managed connection to be online
            - "interfaces": wait only for the given interface names
        '';
      };
      interfaces = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "eth0" "enp5s0" "wlp0s20f3" ];
        description = "Interfaces to wait for when mode = \"interfaces\".";
      };
      timeoutSeconds = lib.mkOption {
        type = types.ints.positive;
        default = 90;
        description = "Maximum time nm-online should wait before timing out.";
      };
    };
  };
}
