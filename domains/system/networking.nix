# HWC System Networking (declarative + per-machine wait-online policy)
{ config, lib, pkgs, nixosApiVersion ? "unstable", ... }:

let
  cfg = config.hwc.system.networking;
  types = lib.types;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
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

    # ---- NFS ----
    nfs = {
      server = {
        enable = lib.mkEnableOption "Enable NFS v4 server for file sharing over Tailscale.";
        exports = lib.mkOption {
          type = types.lines;
          default = "";
          description = "NFS export lines (/etc/exports format).";
        };
      };
      client.enable = lib.mkEnableOption "Enable NFS client for mounting remote shares.";
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

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # =========================
    # NetworkManager
    # =========================
    networking.networkmanager.enable = lib.mkIf cfg.networkManager.enable true;

    # =========================
    # SSH
    # =========================
    services.openssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      ports  = [ cfg.ssh.port ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    # =========================
    # Tailscale
    # =========================
    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      authKeyFile = cfg.tailscale.authKeyFile;
      extraUpFlags = cfg.tailscale.extraUpFlags;
    };

    # Tailscale Funnel - expose MCP servers publicly via Caddy gateway
    # Caddy on :18080 routes: default → hwc-infra MCP, /n8n/* → n8n-mcp bridge
    # Funnel terminates TLS and proxies to this local HTTP origin
    systemd.services.tailscale-funnel = lib.mkIf (cfg.tailscale.enable && cfg.tailscale.funnel.enable) {
      description = "Tailscale Funnel - MCP gateway (port 443)";
      after = [ "tailscaled.service" "network-online.target" "caddy.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        # Run in foreground - tailscale funnel doesn't support --bg reliably in systemd
        ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --https=443 http://127.0.0.1:18080";
        ExecStopPost = "${pkgs.tailscale}/bin/tailscale funnel reset || true";
      };
    };

    # =========================
    # NFS Server
    # =========================
    services.nfs.server = lib.mkIf cfg.nfs.server.enable {
      enable = true;
      exports = cfg.nfs.server.exports;
    };

    # =========================
    # Samba
    # =========================
    # NixOS 24.11+ uses settings API
    services.samba = lib.mkIf cfg.samba.enable {
      enable = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          security = "user";
        };
      } // cfg.samba.shares;
    };

    # =========================
    # IP Forwarding (required for container networking / WireGuard in containers)
    # =========================
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.forwarding" = 1;
    };

    # =========================
    # Firewall
    # =========================
    networking.firewall = {
      enable    = cfg.firewall.level != "off";
      allowPing = cfg.firewall.level == "basic";
      # Required for WireGuard behind NAT (e.g., Podman containers)
      # Prevents kernel from dropping legitimate reply packets
      checkReversePath = "loose";
      allowedTCPPorts =
        cfg.firewall.extraTcpPorts
        ++ (lib.optionals (cfg.firewall.level == "server") [ 80 443 ])
        ++ (lib.optionals cfg.ssh.enable [ cfg.ssh.port ])
        ++ (lib.optionals cfg.nfs.server.enable [ 2049 ])
        ++ (lib.optionals cfg.samba.enable [ 139 445 ]);
      allowedUDPPorts =
        cfg.firewall.extraUdpPorts
        ++ (lib.optionals cfg.samba.enable [ 137 138 ]);
      trustedInterfaces = [ "eno1" "podman0" "podman1" ] ++ (lib.optionals cfg.tailscale.enable [ "tailscale0" ]);
    };

    # =========================
    # DNS (systemd-resolved)
    # =========================
    services.resolved = lib.mkMerge [
      { enable = true; }
      # nixos-25.11 stable uses flat options; unstable uses settings.Resolve.*
      (if nixosApiVersion == "stable" then {
        dnssec = "false";
        fallbackDns = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
        domains = [ "~." ];
      } else {
        settings.Resolve = {
          FallbackDNS = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
          DNSSEC = "false";
          Domains = [ "~." ];
        };
      })
    ];

    # =========================
    # Tooling
    # =========================
    environment.systemPackages = with pkgs; [
      wget curl dnsutils traceroute nettools iproute2 mtr nmap wireshark-cli
      networkmanagerapplet
    ]
    ++ (lib.optionals cfg.tailscale.enable [ tailscale ])
    ++ (lib.optionals (cfg.nfs.server.enable || cfg.nfs.client.enable) [ nfs-utils ])
    ++ (lib.optionals cfg.samba.enable     [ samba ]);

    # =========================
    # network-online policy (bombproof & declarative)
    # =========================

    # Only pull in network-online.target when we actually want to block on network.
    systemd.targets.network-online.wantedBy =
      lib.mkIf (cfg.waitOnline.mode != "off") [ "multi-user.target" ];

    # By default, disable NM wait-online unless asked otherwise.
    systemd.services.NetworkManager-wait-online.enable = (cfg.waitOnline.mode != "off");

    # Configure nm-online behavior per mode.
    #
    # NOTE: clearing ExecStart with [""] is required to override the upstream command.
    systemd.services.NetworkManager-wait-online.serviceConfig =
      let
        base = {
          TimeoutStartSec = "${toString cfg.waitOnline.timeoutSeconds}s";
        };
      in
      lib.mkIf (cfg.waitOnline.mode != "off")
        (base // {
          ExecStart =
            if cfg.waitOnline.mode == "all" then
              [
                "" # clear previous
                "${pkgs.networkmanager}/bin/nm-online -s -q"
              ]
            else
              # mode == "interfaces"
              let
                ifaceFlags =
                  lib.concatMapStringsSep " " (i: "--interface ${i}") cfg.waitOnline.interfaces;
              in
              [
                ""
                "${pkgs.bash}/bin/bash -uec '${pkgs.networkmanager}/bin/nm-online -s -q ${ifaceFlags}'"
              ];
        });

    # =========================
    # Safety assertions
    # =========================
    assertions = [
      {
        assertion = cfg.tailscale.enable -> (cfg.firewall.level != "off");
        message   = "The firewall must be enabled when using Tailscale.";
      }
      {
        assertion = (cfg.waitOnline.mode != "interfaces") || (cfg.waitOnline.interfaces != []);
        message   = "waitOnline.mode is \"interfaces\" but no interfaces were provided.";
      }
    ];
  };

}
