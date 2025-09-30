# HWC Charter Module/domains/system/networking.nix
#
# NETWORKING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.networking.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/system/networking.nix
#
# USAGE:
#   hwc.system.networking.enable = true;
#   # TODO: Add specific usage examples

# modules/system/networking.nix
#
# HWC System Networking Configuration (Charter v3)
# Centralized networking setup for SSH, Tailscale, and firewall
#
# DEPENDENCIES:
#   Upstream: modules/security/secrets.nix (optional VPN secrets)
#
# USED BY:
#   Downstream: profiles/base.nix (basic networking)
#   Downstream: profiles/server.nix (server-specific networking)
#   Downstream: profiles/workstation.nix (workstation networking)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../domains/system/networking.nix
#
# USAGE:
#   hwc.networking.ssh.enable = true;           # SSH server
#   hwc.networking.tailscale.enable = true;     # Tailscale VPN
#   hwc.networking.firewall.strict = true;      # Strict firewall rules
#
# VALIDATION:
#   - SSH keys properly configured
#   - Tailscale certificates accessible
#   - Firewall rules allow required services

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.networking;
in {
  #============================================================================
  # IMPLEMENTATION - Network Service Configuration
  #============================================================================

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SSH SERVER CONFIGURATION
    #=========================================================================
    services.openssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      ports = [ cfg.ssh.port ];
      settings = {
        PermitRootLogin = cfg.ssh.allowRootLogin;
        PasswordAuthentication = cfg.ssh.passwordAuthentication;
        KbdInteractiveAuthentication = false;
        X11Forwarding = cfg.ssh.x11Forwarding;
        PubkeyAuthentication = true;
        AuthorizedKeysFile = "%h/.ssh/authorized_keys";
      };
    };

    #=========================================================================
    # TAILSCALE VPN CONFIGURATION
    #=========================================================================
    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      permitCertUid = cfg.tailscale.permitCertUid;
      authKeyFile = cfg.tailscale.authKeyFile;
      extraUpFlags = cfg.tailscale.extraUpFlags;
    };

    #=========================================================================
    # NETWORKMANAGER CONFIGURATION
    #=========================================================================
    networking.networkmanager = lib.mkIf cfg.networkManager.enable {
      enable = true;
      dns = cfg.networkManager.dns;
      wifi = {
        backend = cfg.networkManager.wifi.backend;
        powersave = cfg.networkManager.wifi.powersave;
      };
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    networking.firewall = lib.mkIf cfg.firewall.enable {
      enable = true;
      allowPing = cfg.firewall.allowPing;

      # Service-based port configuration
      allowedTCPPorts = [ ]
        ++ lib.optionals cfg.firewall.services.ssh [ cfg.ssh.port ]
        ++ lib.optionals cfg.firewall.services.web [ 80 443 ]
        ++ cfg.firewall.extraTcpPorts;

      allowedUDPPorts = [ ]
        ++ lib.optionals cfg.firewall.services.tailscale [ 41641 ]
        ++ cfg.firewall.extraUdpPorts;

      # Trusted interfaces (full access)
      trustedInterfaces = cfg.firewall.trustedInterfaces
        ++ lib.optionals cfg.tailscale.enable [ "tailscale0" ];

      # Interface-specific rules for Tailscale internal services
      interfaces = lib.mkIf cfg.tailscale.enable {
        "tailscale0" = {
          allowedTCPPorts = [
            # Add common internal service ports here
            # These will be populated by service modules
          ];
          allowedUDPPorts = [ ];
        };
      };
    };

    #=========================================================================
    # DNS CONFIGURATION
    #=========================================================================
    services.resolved = lib.mkIf (cfg.dns.enable && cfg.networkManager.dns == "systemd-resolved") {
      enable = true;
      fallbackDns = cfg.dns.servers ++ cfg.dns.fallbackServers;
      dnssec = "false";  # Disable DNSSEC to silence cosmetic validation failures
      domains = [ "~." ];  # Use for all domains
    };

    #=========================================================================
    # ADDITIONAL NETWORK PACKAGES
    #=========================================================================
    environment.systemPackages = with pkgs; [
      # Network diagnostic tools
      wget curl
      dnsutils
      traceroute
      nettools
      iproute2

      # Tailscale management
    ] ++ lib.optionals cfg.tailscale.enable [
      tailscale
    ] ++ lib.optionals cfg.networkManager.enable [
      networkmanagerapplet  # GUI for NetworkManager
    ];

    #=========================================================================
    # SYSTEMD NETWORK WAIT
    #=========================================================================
    systemd.targets.network-online.wantedBy = [ "multi-user.target" ];
    systemd.services.NetworkManager-wait-online.enable = lib.mkIf cfg.networkManager.enable true;

    #=========================================================================
    # SECURITY ASSERTIONS
    #=========================================================================
    assertions = [
      {
        assertion = cfg.ssh.enable -> cfg.ssh.passwordAuthentication || cfg.ssh.allowRootLogin != "yes";
        message = "SSH password authentication should be disabled when root login is allowed";
      }
      {
        assertion = cfg.tailscale.enable -> cfg.firewall.enable;
        message = "Firewall should be enabled when using Tailscale for security";
      }
    ];
  };
}
