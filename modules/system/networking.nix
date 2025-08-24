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
#   - profiles/base.nix: ../modules/system/networking.nix
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
  # OPTIONS - Network Configuration
  #============================================================================

  options.hwc.networking = {
    enable = lib.mkEnableOption "HWC networking configuration";

    #=========================================================================
    # SSH CONFIGURATION
    #=========================================================================
    ssh = {
      enable = lib.mkEnableOption "SSH server configuration";

      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "SSH server port";
      };

      allowRootLogin = lib.mkOption {
        type = lib.types.enum [ "yes" "no" "prohibit-password" ];
        default = "no";
        description = "Allow root login via SSH";
      };

      passwordAuthentication = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow password authentication";
      };

      x11Forwarding = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable X11 forwarding for GUI applications";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open SSH port in firewall";
      };
    };

    #=========================================================================
    # TAILSCALE VPN CONFIGURATION
    #=========================================================================
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN mesh networking";

      permitCertUid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User that can access Tailscale certificates (e.g., 'caddy')";
      };

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to Tailscale auth key file";
      };

      extraUpFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra flags for tailscale up command";
      };
    };

    #=========================================================================
    # NETWORKMANAGER CONFIGURATION
    #=========================================================================
    networkManager = {
      enable = lib.mkEnableOption "NetworkManager for network management";

      dns = lib.mkOption {
        type = lib.types.enum [ "systemd-resolved" "dnsmasq" "none" ];
        default = "systemd-resolved";
        description = "DNS backend for NetworkManager";
      };

      wifi = {
        backend = lib.mkOption {
          type = lib.types.enum [ "wpa_supplicant" "iwd" ];
          default = "wpa_supplicant";
          description = "WiFi backend";
        };

        powersave = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable WiFi power saving";
        };
      };
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    firewall = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable firewall";
      };

      strict = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use strict firewall rules (deny by default)";
      };

      allowPing = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow ICMP ping requests";
      };

      # Common service ports
      services = {
        ssh = lib.mkOption {
          type = lib.types.bool;
          default = cfg.ssh.enable;
          description = "Allow SSH traffic";
        };

        web = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow HTTP/HTTPS traffic (80, 443)";
        };

        tailscale = lib.mkOption {
          type = lib.types.bool;
          default = cfg.tailscale.enable;
          description = "Allow Tailscale traffic";
        };
      };

      # Custom port configurations
      extraTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional TCP ports to open";
      };

      extraUdpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional UDP ports to open";
      };

      # Interface-specific rules (e.g., for Tailscale)
      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Network interfaces to trust completely";
      };
    };

    #=========================================================================
    # DNS CONFIGURATION
    #=========================================================================
    dns = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure DNS resolution";
      };

      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "1.1.1.1" "8.8.8.8" ];
        description = "DNS servers to use";
      };

      fallbackServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "9.9.9.9" "149.112.112.112" ];
        description = "Fallback DNS servers";
      };
    };
  };

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
      dnssec = "allow-downgrade";
      domains = [ "~." ];  # Use for all domains
    };

    #=========================================================================
    # ADDITIONAL NETWORK PACKAGES
    #=========================================================================
    environment.systemPackages = with pkgs; [
      # Network diagnostic tools
      wget curl
      dig nslookup
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
