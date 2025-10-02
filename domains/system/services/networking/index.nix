# domains/system/services/networking/index.nix
#
# HWC System Networking Configuration (Charter v5 Refactor)
# Centralized networking setup for SSH, Tailscale, Samba, and firewall.
#
# USAGE:
#   hwc.networking.enable = true;
#   hwc.networking.ssh.enable = true;
#   hwc.networking.tailscale.enable = true;
#   hwc.networking.firewall.level = "strict"; # Can be: off, basic, strict, server
#   hwc.networking.samba.enable = true;
#   hwc.networking.samba.shares = { ... };

{ config, lib, pkgs, ... }:

let
  # This now points to our new, clean options API in networking/options.nix
  cfg = config.hwc.networking;
in
{
  # NO MORE IMPORTS NEEDED HERE. All logic is self-contained.

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SSH SERVER CONFIGURATION
    #=========================================================================
    services.openssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      ports = [ cfg.ssh.port ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    #=========================================================================
    # TAILSCALE VPN CONFIGURATION
    #=========================================================================
    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      authKeyFile = cfg.tailscale.authKeyFile;
      extraUpFlags = cfg.tailscale.extraUpFlags;
    };

    #=========================================================================
    # SAMBA FILE SHARING CONFIGURATION
    #=========================================================================
    services.samba = lib.mkIf cfg.samba.enable {
      enable = true;
      # Hardcoded sensible defaults
      workgroup = "WORKGROUP";
      security = "user";
      # Use the 'shares' option which we kept
      shares = cfg.samba.shares;
      # Add any other static samba settings here
    };

    #=========================================================================
    # NETWORKMANAGER CONFIGURATION
    #=========================================================================
    networking.networkmanager.enable = lib.mkIf cfg.networkManager.enable true;

    #=========================================================================
    # FIREWALL CONFIGURATION (using the new 'level' option)
    #=========================================================================
    networking.firewall = {
      enable = cfg.firewall.level != "off";
      allowPing = cfg.firewall.level == "basic";
      allowedTCPPorts = (cfg.firewall.extraTcpPorts)
        ++ (lib.optionals (cfg.firewall.level == "server") [ 80 443 ])
        ++ (lib.optionals cfg.ssh.enable [ cfg.ssh.port ])
        # Open standard Samba ports if enabled
        ++ (lib.optionals cfg.samba.enable [ 139 445 ]);
      allowedUDPPorts = (cfg.firewall.extraUdpPorts)
        # Open standard Samba ports if enabled
        ++ (lib.optionals cfg.samba.enable [ 137 138 ]);
      trustedInterfaces = lib.optionals cfg.tailscale.enable [ "tailscale0" ];
    };

    #=========================================================================
    # DNS CONFIGURATION (with sensible defaults)
    #=========================================================================
    services.resolved = {
      enable = true;
      fallbackDns = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
      dnssec = "false";
      domains = [ "~." ];
    };

    #=========================================================================
    # CO-LOCATED NETWORK PACKAGES
    #=========================================================================
    environment.systemPackages = with pkgs; [
      # Core tools
      wget curl dnsutils traceroute nettools iproute2 mtr nmap wireshark-cli
      # GUI tools
      networkmanagerapplet
    ]
    ++ (lib.optionals cfg.tailscale.enable [ tailscale ])
    # Add the samba package if the samba service is enabled
    ++ (lib.optionals cfg.samba.enable [ samba ]);

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
        assertion = cfg.tailscale.enable -> (cfg.firewall.level != "off");
        message = "The firewall must be enabled when using Tailscale.";
      }
    ];
  };
}
