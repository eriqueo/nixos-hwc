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
          (lib.optional (lib.elem "ssh" cfg.firewall.allowedServices) 22)
          (lib.optional (lib.elem "http" cfg.firewall.allowedServices) 80)
          (lib.optional (lib.elem "https" cfg.firewall.allowedServices) 443)
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
       };
     })
         
        
    # audit
(lib.mkIf cfg.audit.enable {
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules =
    let
      defaults = [
        "-a exit,always -F arch=b64 -S execve"
        "-w /etc/passwd -p wa -k passwd_changes"
        "-w /etc/shadow -p wa -k shadow_changes"
        "-a exit,always -F arch=b64 -S connect -S accept"
      ];
      extra =
        if cfg.audit.rules == "" then
          []
        else
          lib.filter (s: s != "") (lib.splitString "\n" cfg.audit.rules);
    in defaults ++ extra;
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
          # Rootkit hunter
      ];
    }
  ]);
}
