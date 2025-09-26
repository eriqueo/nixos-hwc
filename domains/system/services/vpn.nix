# nixos-hwc/modules/services/network/vpn.nix
#
# PROTONVPN SERVICE - Simple On-Demand VPN Toggle  
# Provides ProtonVPN connectivity via simple WireGuard configuration
# that can be toggled on/off without breaking base networking
#
# DEPENDENCIES (Upstream):
#   - None (private key hardcoded, no SOPS)
#
# USED BY (Downstream):
#   - hosts/laptop/config.nix (enables via hwc.services.network.vpn.enable)
#
# DESIGN PATTERN:
#   Simple toggle: vpnon/vpnoff commands for coffee shop use
#
# USAGE:
#   hwc.services.network.vpn.enable = true;
#   vpnon   # Connect to VPN  
#   vpnoff  # Disconnect from VPN

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.network.vpn;
  
  # Simple VPN management scripts
  vpnStartScript = pkgs.writeScriptBin "vpnon" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🔐 Starting ProtonVPN..."
    
    # Check if already running
    if sudo wg show protonvpn &>/dev/null; then
      echo "✅ Already connected to ProtonVPN"
      sudo wg show protonvpn
      exit 0
    fi
    
    # Start WireGuard interface
    echo "🌍 Connecting via WireGuard..."
    sudo wg-quick up protonvpn
    
    # Wait for connection
    sleep 2
    
    if sudo wg show protonvpn &>/dev/null; then
      echo "✅ ProtonVPN connected successfully!"
      
      # Test connectivity
      echo "🌐 Testing connection..."
      timeout 5 curl -s ifconfig.me || echo "IP check timed out"
    else
      echo "❌ Failed to connect to ProtonVPN"
      exit 1
    fi
  '';
  
  vpnStopScript = pkgs.writeScriptBin "vpnoff" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "🛑 Stopping ProtonVPN..."
    
    if ! sudo wg show protonvpn &>/dev/null; then
      echo "ℹ️ ProtonVPN not running"
      exit 0
    fi
    
    # Stop WireGuard interface
    sudo wg-quick down protonvpn
    
    if sudo wg show protonvpn &>/dev/null; then
      echo "❌ Failed to disconnect ProtonVPN"  
      exit 1
    else
      echo "✅ ProtonVPN disconnected successfully!"
    fi
  '';
  
  vpnStatusScript = pkgs.writeScriptBin "vpnstatus" ''
    #!/usr/bin/env bash
    
    echo "=== ProtonVPN Status ==="
    echo ""
    
    if sudo wg show protonvpn &>/dev/null; then
      echo "🟢 Status: Connected"
      echo ""
      
      # Show interface info
      echo "📊 WireGuard Interface:"
      sudo wg show protonvpn
      echo ""
      
      # Check external IP
      echo "🌐 External IP:"
      timeout 5 curl -s ifconfig.me || echo "IP check failed"
      echo ""
    else
      echo "🔴 Status: Disconnected"  
      echo ""
      echo "💡 Use 'vpnon' to connect"
    fi
  '';

in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.network.vpn = {
    enable = lib.mkEnableOption "Simple ProtonVPN toggle service";
  };

  #============================================================================
  # CONFIG - What gets applied when enabled
  #============================================================================ 
  config = lib.mkIf cfg.enable {
    # Basic WireGuard support
    networking.wireguard.enable = true;
    
    # Create WireGuard config file (wg-quick style)
    environment.etc."wireguard/protonvpn.conf" = {
      text = ''
        [Interface]
        PrivateKey = MIRyjxQtMGac3PoK3cVyw2FhyZqtRqXxfnGbnJYTGmY=
        Address = 10.2.0.2/32
        DNS = 10.2.0.1
        
        [Peer] 
        PublicKey = 9f0svvw50qgvHun/0tZnApsgyF1OQSgc2Xd/4K5Hbzs=
        Endpoint = 68.169.42.239:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
      '';
      mode = "0600";
    };
    
    # Install management scripts
    environment.systemPackages = with pkgs; [
      wireguard-tools   # wg, wg-quick commands
      vpnStartScript    # vpnon command
      vpnStopScript     # vpnoff command  
      vpnStatusScript   # vpnstatus command
    ];
    
    # Allow passwordless sudo for VPN commands
    security.sudo.extraRules = [{
      users = [ "eric" ];
      commands = [{
        command = "/run/current-system/sw/bin/vpnon";
        options = [ "NOPASSWD" ];
      } {
        command = "/run/current-system/sw/bin/vpnoff";
        options = [ "NOPASSWD" ];
      } {
        command = "/run/current-system/sw/bin/wg-quick";
        options = [ "NOPASSWD" ];
      }];
    }];
    
    # Allow WireGuard through firewall
    networking.firewall.allowedUDPPorts = [ 51820 ];
  };
}