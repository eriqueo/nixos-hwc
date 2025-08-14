# Day 9: Security & Advanced Networking (5-6 hours)

## Morning Session (3 hours)
### 9:00 AM - Security Infrastructure ✅

```bash
cd /etc/nixos-next

# Step 1: Create comprehensive security module
cat > modules/infrastructure/security.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.security;
in {
  options.hwc.security = {
    enable = lib.mkEnableOption "Security hardening";
    
    firewall = {
      strictMode = lib.mkEnableOption "Strict firewall mode";
      
      allowedServices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "ssh" "http" "https" ];
        description = "Allowed services";
      };
      
      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "lo" ];
        description = "Trusted network interfaces";
      };
    };
    
    fail2ban = {
      enable = lib.mkEnableOption "Fail2ban intrusion prevention";
      
      maxRetries = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Max failed attempts";
      };
      
      banTime = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = "Ban duration";
      };
    };
    
    ssh = {
      passwordAuthentication = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow password auth";
      };
      
      permitRootLogin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow root SSH";
      };
      
      authorizedKeys = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {};
        description = "SSH authorized keys per user";
      };
    };
    
    audit = {
      enable = lib.mkEnableOption "Security auditing";
      
      rules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Audit rules";
      };
    };
  };
  
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Firewall configuration
    {
      networking.firewall = {
        enable = true;
        allowPing = !cfg.firewall.strictMode;
        trustedInterfaces = cfg.firewall.trustedInterfaces;
        
        # Service-based rules
        allowedTCPPorts = lib.flatten [
          (lib.optional (elem "ssh" cfg.firewall.allowedServices) 22)
          (lib.optional (elem "http" cfg.firewall.allowedServices) 80)
          (lib.optional (elem "https" cfg.firewall.allowedServices) 443)
        ];
        
        extraCommands = lib.optionalString cfg.firewall.strictMode ''
          # Drop all forwarding by default
          iptables -P FORWARD DROP
          
          # Rate limiting
          iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
          iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent \
            --update --seconds 60 --hitcount 4 -j DROP
        '';
      };
    }
    
    # SSH hardening
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = cfg.ssh.passwordAuthentication;
          PermitRootLogin = if cfg.ssh.permitRootLogin then "yes" else "no";
          KbdInteractiveAuthentication = false;
          X11Forwarding = false;
          StrictModes = true;
        };
        
        extraConfig = ''
          Protocol 2
          ClientAliveInterval 300
          ClientAliveCountMax 2
          MaxAuthTries 3
          MaxSessions 10
        '';
      };
      
      # Add authorized keys
      users.users = lib.mapAttrs (user: keys: {
        openssh.authorizedKeys.keys = keys;
      }) cfg.ssh.authorizedKeys;
    }
    
    # Fail2ban
    (lib.mkIf cfg.fail2ban.enable {
      services.fail2ban = {
        enable = true;
        maxretry = cfg.fail2ban.maxRetries;
        bantime = cfg.fail2ban.banTime;
        
        jails = {
          ssh = {
            enabled = true;
            filter = "sshd";
            maxretry = 3;
          };
          
          nginx = lib.mkIf config.services.nginx.enable {
            enabled = true;
            filter = "nginx-http-auth";
          };
        };
      };
    })
    
    # Audit system
    (lib.mkIf cfg.audit.enable {
      security.auditd.enable = true;
      security.audit.enable = true;
      security.audit.rules = cfg.audit.rules;
      
      # Default audit rules
      security.audit.rules = lib.mkDefault ''
        # Log all commands
        -a exit,always -F arch=b64 -S execve
        
        # Log file access
        -w /etc/passwd -p wa -k passwd_changes
        -w /etc/shadow -p wa -k shadow_changes
        
        # Log network connections
        -a exit,always -F arch=b64 -S connect -S accept
      '';
    })
    
    # General hardening
    {
      # Kernel hardening
      boot.kernel.sysctl = {
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;
        "kernel.ftrace_enabled" = false;
      };
      
      # Security packages
      environment.systemPackages = with pkgs; [
        aide      # Intrusion detection
        lynis     # Security auditing
        clamav    # Antivirus
        rkhunter  # Rootkit hunter
      ];
    }
  ]);
}
EOF

# Step 2: Create VPN/Tailscale module
cat > modules/services/vpn.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.vpn;
in {
  options.hwc.services.vpn = {
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN";
      
      authKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to auth key file";
      };
      
      exitNode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Act as exit node";
      };
      
      advertiseRoutes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Routes to advertise";
      };
    };
    
    wireguard = {
      enable = lib.mkEnableOption "WireGuard VPN";
      
      interfaces = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        description = "WireGuard interfaces";
      };
    };
  };
  
  config = lib.mkMerge [
    (lib.mkIf cfg.tailscale.enable {
      services.tailscale = {
        enable = true;
        authKeyFile = cfg.tailscale.authKeyFile;
        useRoutingFeatures = if cfg.tailscale.exitNode then "both" else "client";
        extraUpFlags = cfg.tailscale.advertiseRoutes;
      };
      
      networking.firewall = {
        checkReversePath = "loose";
        trustedInterfaces = [ "tailscale0" ];
      };
      
      # Enable IP forwarding if exit node
      boot.kernel.sysctl = lib.mkIf cfg.tailscale.exitNode {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
    })
    
    (lib.mkIf cfg.wireguard.enable {
      networking.wg-quick.interfaces = cfg.wireguard.interfaces;
      
      networking.firewall.allowedUDPPorts = [ 51820 ];
    })
  ];
}
EOF

# Step 3: Create advanced networking module
cat > modules/infrastructure/networking.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.networking;
in {
  options.hwc.networking = {
    vlans = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "VLAN configurations";
      example = {
        management = { id = 10; interface = "eth0"; };
        storage = { id = 20; interface = "eth0"; };
      };
    };
    
    bridges = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "Bridge configurations";
    };
    
    staticRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Static routes";
    };
    
    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "DNS servers";
    };
    
    search = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "local" ];
      description = "DNS search domains";
    };
    
    mtu = lib.mkOption {
      type = lib.types.int;
      default = 1500;
      description = "Default MTU";
    };
  };
  
  config = {
    # VLAN configuration
    networking.vlans = lib.mapAttrs (name: vlan: {
      id = vlan.id;
      interface = vlan.interface;
    }) cfg.vlans;
    
    # Bridge configuration
    networking.bridges = cfg.bridges;
    
    # Static routes
    networking.interfaces.eth0.ipv
EOF
```
