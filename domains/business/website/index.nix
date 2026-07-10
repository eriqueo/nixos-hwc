# domains/business/website/index.nix
#
# Heartwood CMS Dashboard — content management for iheartwoodcraft.com
# Node.js REST API + vanilla JS frontend, manages 11ty site content
#
# NAMESPACE: hwc.business.website.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - agenix secrets: cms-api-key, hostinger-sftp
#   - site_files repo at /home/eric/.nixos/domains/business/website/site_files/

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.website;
  paths = config.hwc.paths;
in
{
  imports = [
    ./webapps/index.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.business.website = {
    enable = lib.mkEnableOption "Heartwood CMS Dashboard (content management for iheartwoodcraft.com)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8095;
      description = "Port for Heartwood CMS API (binds to 127.0.0.1)";
    };

    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/heartwood-cms";
      description = "Path to the Heartwood CMS application directory";
    };

    siteDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/business/website-site";  # own repo (eriqueo/hwc-website) since 2026-07-06 — CMS-mutated working tree, evicted from nixos-hwc (audit 2.3)
      description = "Path to the 11ty site repo (content source)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };

    # Late-binding endpoints for the calculator/contact-form Vite build.
    # Inject as VITE_LEADS_WEBHOOK_URL / VITE_LEADS_WEBHOOK_APPT_URL so the
    # CalculatorRuntime prefers env over the JSON fallback. Single source
    # of truth for "where do leads go" — change here, rebuild + redeploy.
    leadsWebhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.iheartwoodcraft.com/webhook/calculator-lead";
      description = ''
        URL the calculator app POSTs lead submissions to. MUST be publicly
        reachable — site visitors' browsers call it directly. The previous
        hwc-server.ocelot-wahoo.ts.net default was tailnet-only and silently
        lost every public lead (2026-07-07 plumbing audit). Now the
        Cloudflare-tunnel n8n ingress: the thin-shell workflow
        (work_calculator_lead) HMAC-signs + forwards to hwc-leads on
        loopback :11650. A future direct-POST cutover would point this at
        a public hwc-leads route.
      '';
    };
    leadsAppointmentWebhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://crm.iheartwoodcraft.com/hooks/appointment";
      description = ''
        URL the calculator's "schedule a call" flow POSTs to (fire-and-forget,
        no-cors). Cutover 2026-07-10 from the broken work_calculator_appointment
        n8n path (wrote status='appointment_requested' to legacy
        hwc.calculator_leads, violating its CHECK) to hwc-crm's
        /hooks/appointment: appends to the funnel lead, forces schedule_estimate,
        writes a khal/Radicale event (day-before + hour-before VALARMs) and
        emails the customer an .ics invite. Path-locked Cloudflare ingress.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    #--------------------------------------------------------------------------
    # HEARTWOOD CMS SERVICE
    #--------------------------------------------------------------------------
    systemd.services.heartwood-cms = {
      description = "Heartwood CMS Dashboard";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Inject the leads endpoints so the `vite build` step (kicked off
      # by the CMS deploy action) bakes them into the calc bundle.
      environment = {
        VITE_LEADS_WEBHOOK_URL = cfg.leadsWebhookUrl;
        VITE_LEADS_WEBHOOK_APPT_URL = cfg.leadsAppointmentWebhookUrl;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/server.js";
        WorkingDirectory = cfg.srcDir;
        Restart = "on-failure";
        RestartSec = "5s";
        User = lib.mkForce cfg.user;
        Group = "users";
        SupplementaryGroups = [ "secrets" ]; # Read agenix secrets directly

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false; # Needs access to srcDir + siteDir
        ReadWritePaths = [
          cfg.srcDir       # .last-deploy.json
          cfg.siteDir      # Content files, build output
          "/tmp"           # Multer uploads
        ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "100%"; # Build needs CPU headroom
      };

      # Ensure ImageMagick and npx are available for build + image processing
      path = [ pkgs.imagemagick pkgs.nodejs_22 ];
    };

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    assertions = [
      {
        assertion = config.age.secrets ? cms-api-key;
        message = ''
          hwc.business.website requires the cms-api-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
      {
        assertion = config.age.secrets ? hostinger-sftp;
        message = ''
          hwc.business.website requires the hostinger-sftp agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
