{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.secrets.hardening;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [

    #---------------------------
    # FIREWALL (declarative)
    #---------------------------
    {
      networking.firewall = {
        enable = true;

        # Be explicit about kernel-side protection & behavior
        checkReversePath = "loose";   # anti-spoofing without breaking multi-homed
        logRefusedConnections = cfg.firewall.logRefused or true;

        allowPing = !(cfg.firewall.strictMode or false);
        trustedInterfaces = cfg.firewall.trustedInterfaces or [];

        allowedTCPPorts = lib.flatten [
          (lib.optional (lib.elem "ssh"   (cfg.firewall.allowedServices or [])) 22)
          (lib.optional (lib.elem "http"  (cfg.firewall.allowedServices or [])) 80)
          (lib.optional (lib.elem "https" (cfg.firewall.allowedServices or [])) 443)
        ];

        # No raw iptables/nftables shell here; keep it fully declarative.
        # If you need nft rules later, prefer networking.nftables.tables/extra*Rules.
      };

      # SSH service hardening complements Fail2ban without raw firewall hacks
      services.openssh = lib.mkIf (lib.elem "ssh" (cfg.firewall.allowedServices or [])) {
        enable = true;
        settings = {
          PasswordAuthentication = false;   # prefer keys
          KbdInteractiveAuthentication = false;
          X11Forwarding = false;
          AllowTcpForwarding = "no";
          MaxAuthTries = 3;
          LoginGraceTime = "20s";
          # MaxStartups "10:30:60" throttles parallel unauth’d connections
          MaxStartups = "10:30:60";
        };
      };
    }

    #---------------------------
    # FAIL2BAN
    #---------------------------
    (lib.mkIf (cfg.fail2ban.enable or false) {
      services.fail2ban = {
        enable = true;
        maxretry = cfg.fail2ban.maxRetries or 5;
        bantime  = cfg.fail2ban.banTime    or "1h";
        # You can add jails overrides here if needed:
        # jails.sshd.settings.ignoreip = "127.0.0.1/8 10.0.0.0/8";
      };
    })

    #---------------------------
    # AUDIT (be mindful of verbosity)
    #---------------------------
    (lib.mkIf (cfg.audit.enable or false) {
      security.auditd.enable = true;
      security.audit.enable  = true;

      # Configure auditd with proper log rotation
      environment.etc."audit/auditd.conf".text = '';
        # Log rotation settings to prevent disk space issues
        max_log_file = 100
        max_log_file_action = rotate
        num_logs = 5
        space_left = 75
        space_left_action = email
        admin_space_left = 50
        admin_space_left_action = suspend
        disk_full_action = suspend
        disk_error_action = suspend
        use_libwrap = yes
        tcp_listen_queue = 5
        tcp_max_per_addr = 1
        tcp_client_max_idle = 0
        enable_krb5 = no
        krb5_principal = auditd
        name_format = HOSTNAME
        plugin_dir = /etc/audit/plugins.d
      '';

      security.audit.rules =
        let
          defaults = [
            "-a exit,always -F arch=b64 -S execve"
            "-w /etc/passwd -p wa -k passwd_changes"
            "-w /etc/shadow -p wa -k shadow_changes"
            "-a exit,always -F arch=b64 -S connect -S accept"
          ];
          extra =
            if (cfg.audit.rules or "") == "" then
              []
            else
              lib.filter (s: s != "") (lib.splitString "\n" cfg.audit.rules);
        in defaults ++ extra;
    })

    #---------------------------
    # SYSCTL HARDENING (singleton lives here)
    #---------------------------
    {
      boot.kernel.sysctl = {
        # Existing
        "kernel.unprivileged_bpf_disabled" = 1;
        "net.core.bpf_jit_harden" = 2;
        "kernel.ftrace_enabled" = false;
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks"  = 1;

        # Sensible additions (low breakage risk)
        "kernel.kptr_restrict" = 2;
        "kernel.yama.ptrace_scope" = 1;
        "kernel.kexec_load_disabled" = 1;
        "kernel.dmesg_restrict" = 1;

        # IPv{4,6} redirect hardening
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;

        # Reverse path filtering (complements firewall.checkReversePath)
        "net.ipv4.conf.all.rp_filter" = 2;
        "net.ipv4.conf.default.rp_filter" = 2;

        # Leave unprivileged user namespaces ON (0 disables) to avoid breaking containers/flatpaks.
        # "kernel.unprivileged_userns_clone" = 0;  # intentionally NOT set
      };
    }

    #---------------------------
    # SECURITY TOOLS (opt-in)
    #---------------------------
    (lib.mkIf (cfg.packages.enable or false) {
      environment.systemPackages = with pkgs; [
        aide
        lynis
        clamav
      ];
    })
  ]);
}
