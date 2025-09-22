# nixos-h../domains/infrastructure/hardening.nix
#
# HARDENING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.hardening.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/hardening.nix
#
# USAGE:
#   hwc.infrastructure.hardening.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.security.hardening;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.security.hardening = {
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


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
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
    # Set secure defaults for the HWC networking options
    {
      hwc.networking.ssh.passwordAuthentication = lib.mkDefault false;
      hwc.networking.ssh.allowRootLogin = lib.mkDefault "no";
      hwc.networking.ssh.x11Forwarding = lib.mkDefault false;
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
        "fs.protected_hardlinks" = 1;  # Prevent hardlink-based privilege escalation
        "fs.protected_symlinks" = 1;   # Prevent symlink-based privilege escalation
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
