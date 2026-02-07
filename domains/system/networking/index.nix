# HWC System Networking (declarative + per-machine wait-online policy)
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.networking;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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

    # Tailscale Funnel - expose ports publicly via local HTTP listener
    # Caddy on :18080 handles /webhook/* only (plain HTTP)
    # Funnel terminates TLS and proxies to this local HTTP origin
    systemd.services.tailscale-funnel = lib.mkIf (cfg.tailscale.enable && cfg.tailscale.funnel.enable) {
      description = "Tailscale Funnel - expose webhooks publicly";
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
    # Samba
    # =========================
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
    # Firewall
    # =========================
    networking.firewall = {
      enable    = cfg.firewall.level != "off";
      allowPing = cfg.firewall.level == "basic";
      allowedTCPPorts =
        cfg.firewall.extraTcpPorts
        ++ (lib.optionals (cfg.firewall.level == "server") [ 80 443 ])
        ++ (lib.optionals cfg.ssh.enable [ cfg.ssh.port ])
        ++ (lib.optionals cfg.samba.enable [ 139 445 ]);
      allowedUDPPorts =
        cfg.firewall.extraUdpPorts
        ++ (lib.optionals cfg.samba.enable [ 137 138 ]);
      trustedInterfaces = [ "eno1" ] ++ (lib.optionals cfg.tailscale.enable [ "tailscale0" ]);
    };

    # =========================
    # DNS (systemd-resolved)
    # =========================
    services.resolved = {
      enable = true;
      fallbackDns = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
      dnssec = "false";
      domains = [ "~." ];
    };

    # =========================
    # Tooling
    # =========================
    environment.systemPackages = with pkgs; [
      wget curl dnsutils traceroute nettools iproute2 mtr nmap wireshark-cli
      networkmanagerapplet
    ]
    ++ (lib.optionals cfg.tailscale.enable [ tailscale ])
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
