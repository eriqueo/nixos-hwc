# domains/business/website/index.nix
#
# Heartwood CMS Dashboard — content management for iheartwoodcraft.com
# Node.js REST API + vanilla JS frontend, manages 11ty site content
#
# NAMESPACE: hwc.business.website.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - agenix secret: cms-api-key
#   - website source at hwc.paths.business.websiteSite on the business host

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
      readOnly = true;
      default = paths.business.websiteSite;  # own repo (eriqueo/hwc-website) since 2026-07-06 — CMS-mutated working tree, evicted from nixos-hwc (audit 2.3)
      description = "Path to the 11ty site repo (content source)";
    };

    publishDir = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = paths.business.websitePublished;
      description = "Local published website releases";
    };
    originPort = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Loopback-only public static origin behind Cloudflare Tunnel";
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
      default = "https://crm.iheartwoodcraft.com/hooks/calculator";
      description = ''
        URL the calculator app POSTs lead submissions to. MUST be publicly
        reachable — site visitors' browsers call it directly. The previous
        hwc-server.ocelot-wahoo.ts.net default was tailnet-only and silently
        lost every public lead (2026-07-07 plumbing audit). Cutover
        2026-09-18 (hwc-crm D42) from the n8n thin shell → hwc-leads path to
        hwc-crm's path-locked /hooks/calculator, which saves the lead and its
        report, builds the JobTread graph, pings Discord and sends the
        acknowledgement. It answers the CORS preflight and returns
        {reportId, reportUrl}. The n8n route stays up until Cloudflare's
        7-day cache of the old bundle has expired.
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
        HWC_WEBSITE_SITE_DIR = toString cfg.siteDir;
        HWC_WEBSITE_PUBLISH_DIR = toString cfg.publishDir;
        HWC_WEBSITE_CALCULATOR_DIR = "${paths.nixos}/domains/business/website/calculator/app";
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
          cfg.siteDir      # CRITICAL source: covered by the host's /opt/business backup
          cfg.publishDir   # REPLACEABLE: publisher retains current + previous release
          "${paths.nixos}/domains/business/website/calculator/app"
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
      path = [ pkgs.imagemagick pkgs.nodejs_22 pkgs.util-linux ];
    };


    # The public listener serves only atomic published output, never source/CMS.
    systemd.tmpfiles.rules = [
      "d ${cfg.publishDir} 0755 eric users -"
    ];
    # AUTO-MANAGED generated releases: publisher keeps current + previous;
    # this fail-safe removes abandoned staging even when nobody publishes.
    systemd.services.website-release-prune = {
      description = "Prune unused website releases";
      path = [ pkgs.util-linux ];
      # Each service owns its generated PATH; share only application settings.
      environment = builtins.removeAttrs config.systemd.services.heartwood-cms.environment [ "PATH" ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/lib/deployer.js --prune";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.publishDir ];
      };
    };
    systemd.timers.website-release-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "30m"; };
    };
    services.caddy.virtualHosts."http://:${toString cfg.originPort}".extraConfig = ''
      # Tunnel preserves the public Host header; accept both names on loopback.
      bind 127.0.0.1
      root * ${cfg.publishDir}/current
      encode zstd gzip
      header X-HWC-Website-Origin ${config.networking.hostName}
      header Cache-Control "public, max-age=0, must-revalidate"
      route {
        @private path_regexp private (^|/)\.
        respond @private 404
        redir /bathroom /bathroom/remodeling/ 301
        redir /bathroom/ /bathroom/remodeling/ 301
        redir /bathroom/renovation /bathroom/remodeling/ 301
        redir /bathroom/renovation/ /bathroom/remodeling/ 301
        redir /basement /basement/remodeling/ 301
        redir /basement/ /basement/remodeling/ 301
        redir /basement/renovation /basement/remodeling/ 301
        redir /basement/renovation/ /basement/remodeling/ 301
        redir /3d-design-previews-see-your-remodel-before-we-build-it /blog/3d-design-previews-see-your-remodel-before-we-build-it/ 301
        redir /3d-design-previews-see-your-remodel-before-we-build-it/ /blog/3d-design-previews-see-your-remodel-before-we-build-it/ 301
        redir /are-bathroom-renovations-tax-deductible /blog/are-bathroom-renovations-tax-deductible/ 301
        redir /are-bathroom-renovations-tax-deductible/ /blog/are-bathroom-renovations-tax-deductible/ 301
        redir /can-i-get-a-free-deck-design-from-lowes /blog/can-i-get-a-free-deck-design-from-lowes/ 301
        redir /can-i-get-a-free-deck-design-from-lowes/ /blog/can-i-get-a-free-deck-design-from-lowes/ 301
        redir /common-bathroom-remodel-mistakes-in-bozeman-mt /blog/common-bathroom-remodel-mistakes-in-bozeman-mt/ 301
        redir /common-bathroom-remodel-mistakes-in-bozeman-mt/ /blog/common-bathroom-remodel-mistakes-in-bozeman-mt/ 301
        redir /common-bathroom-renovation-mistakes-in-bozeman-mt /blog/common-bathroom-renovation-mistakes-in-bozeman-mt/ 301
        redir /common-bathroom-renovation-mistakes-in-bozeman-mt/ /blog/common-bathroom-renovation-mistakes-in-bozeman-mt/ 301
        redir /do-i-need-permits-to-finish-a-basement-in-bozeman-mt /blog/do-i-need-permits-to-finish-a-basement-in-bozeman-mt/ 301
        redir /do-i-need-permits-to-finish-a-basement-in-bozeman-mt/ /blog/do-i-need-permits-to-finish-a-basement-in-bozeman-mt/ 301
        redir /does-a-finished-basement-increase-home-insurance /blog/does-a-finished-basement-increase-home-insurance/ 301
        redir /does-a-finished-basement-increase-home-insurance/ /blog/does-a-finished-basement-increase-home-insurance/ 301
        redir /does-home-depot-do-bathroom-remodels /blog/does-home-depot-do-bathroom-remodels/ 301
        redir /does-home-depot-do-bathroom-remodels/ /blog/does-home-depot-do-bathroom-remodels/ 301
        redir /does-home-depot-renovate-basements /blog/does-home-depot-renovate-basements/ 301
        redir /does-home-depot-renovate-basements/ /blog/does-home-depot-renovate-basements/ 301
        redir /how-expensive-is-it-to-redo-a-basement /blog/how-expensive-is-it-to-redo-a-basement/ 301
        redir /how-expensive-is-it-to-redo-a-basement/ /blog/how-expensive-is-it-to-redo-a-basement/ 301
        redir /how-long-does-a-full-home-remodel-take /blog/how-long-does-a-full-home-remodel-take/ 301
        redir /how-long-does-a-full-home-remodel-take/ /blog/how-long-does-a-full-home-remodel-take/ 301
        redir /how-much-does-a-10x20-deck-cost-in-bozeman-mt /blog/how-much-does-a-10x20-deck-cost-in-bozeman-mt/ 301
        redir /how-much-does-a-10x20-deck-cost-in-bozeman-mt/ /blog/how-much-does-a-10x20-deck-cost-in-bozeman-mt/ 301
        redir /how-much-does-a-contractor-charge-to-finish-a-basement-in-bozeman-mt /blog/how-much-does-a-contractor-charge-to-finish-a-basement-in-bozeman-mt/ 301
        redir /how-much-does-a-contractor-charge-to-finish-a-basement-in-bozeman-mt/ /blog/how-much-does-a-contractor-charge-to-finish-a-basement-in-bozeman-mt/ 301
        redir /how-to-choose-a-remodeling-contractor-in-bozeman /blog/how-to-choose-a-remodeling-contractor-in-bozeman/ 301
        redir /how-to-choose-a-remodeling-contractor-in-bozeman/ /blog/how-to-choose-a-remodeling-contractor-in-bozeman/ 301
        redir /is-a-12x20-deck-big-enough-for-a-bozeman-home /blog/is-a-12x20-deck-big-enough-for-a-bozeman-home/ 301
        redir /is-a-12x20-deck-big-enough-for-a-bozeman-home/ /blog/is-a-12x20-deck-big-enough-for-a-bozeman-home/ 301
        redir /is-a-deck-collapse-covered-by-homeowners-insurance /blog/is-a-deck-collapse-covered-by-homeowners-insurance/ 301
        redir /is-a-deck-collapse-covered-by-homeowners-insurance/ /blog/is-a-deck-collapse-covered-by-homeowners-insurance/ 301
        redir /is-it-cheaper-to-build-or-buy-a-deck-in-bozeman-mt /blog/is-it-cheaper-to-build-or-buy-a-deck-in-bozeman-mt/ 301
        redir /is-it-cheaper-to-build-or-buy-a-deck-in-bozeman-mt/ /blog/is-it-cheaper-to-build-or-buy-a-deck-in-bozeman-mt/ 301
        redir /is-it-worth-finishing-a-basement-in-bozeman-mt /blog/is-it-worth-finishing-a-basement-in-bozeman-mt/ 301
        redir /is-it-worth-finishing-a-basement-in-bozeman-mt/ /blog/is-it-worth-finishing-a-basement-in-bozeman-mt/ 301
        redir /is-it-worth-renovating-a-basement /blog/is-it-worth-renovating-a-basement/ 301
        redir /is-it-worth-renovating-a-basement/ /blog/is-it-worth-renovating-a-basement/ 301
        redir /is-remodeling-cheaper-than-building-a-new-home-in-bozeman-mt /blog/is-remodeling-cheaper-than-building-a-new-home-in-bozeman-mt/ 301
        redir /is-remodeling-cheaper-than-building-a-new-home-in-bozeman-mt/ /blog/is-remodeling-cheaper-than-building-a-new-home-in-bozeman-mt/ 301
        redir /should-i-hire-a-contractor-to-finish-my-basement-in-bozeman-mt /blog/should-i-hire-a-contractor-to-finish-my-basement-in-bozeman-mt/ 301
        redir /should-i-hire-a-contractor-to-finish-my-basement-in-bozeman-mt/ /blog/should-i-hire-a-contractor-to-finish-my-basement-in-bozeman-mt/ 301
        redir /what-accounts-for-90-of-deck-collapses /blog/what-accounts-for-90-of-deck-collapses/ 301
        redir /what-accounts-for-90-of-deck-collapses/ /blog/what-accounts-for-90-of-deck-collapses/ 301
        redir /what-adds-the-most-value-to-a-bathroom /blog/what-adds-the-most-value-to-a-bathroom/ 301
        redir /what-adds-the-most-value-to-a-bathroom/ /blog/what-adds-the-most-value-to-a-bathroom/ 301
        redir /what-are-common-basement-finishing-problems /blog/what-are-common-basement-finishing-problems/ 301
        redir /what-are-common-basement-finishing-problems/ /blog/what-are-common-basement-finishing-problems/ 301
        redir /what-are-hidden-renovation-costs /blog/what-are-hidden-renovation-costs/ 301
        redir /what-are-hidden-renovation-costs/ /blog/what-are-hidden-renovation-costs/ 301
        redir /what-are-the-4-types-of-decks-for-bozeman-homes /blog/what-are-the-4-types-of-decks-for-bozeman-homes/ 301
        redir /what-are-the-4-types-of-decks-for-bozeman-homes/ /blog/what-are-the-4-types-of-decks-for-bozeman-homes/ 301
        redir /what-are-the-latest-remodeling-trends /blog/what-are-the-latest-remodeling-trends/ 301
        redir /what-are-the-latest-remodeling-trends/ /blog/what-are-the-latest-remodeling-trends/ 301
        redir /what-are-the-trends-for-home-remodel-in-2025 /blog/what-are-the-trends-for-home-remodel-in-2025/ 301
        redir /what-are-the-trends-for-home-remodel-in-2025/ /blog/what-are-the-trends-for-home-remodel-in-2025/ 301
        redir /what-color-flooring-makes-a-bathroom-look-bigger /blog/what-color-flooring-makes-a-bathroom-look-bigger/ 301
        redir /what-color-flooring-makes-a-bathroom-look-bigger/ /blog/what-color-flooring-makes-a-bathroom-look-bigger/ 301
        redir /what-comes-first-when-remodeling-a-house /blog/what-comes-first-when-remodeling-a-house/ 301
        redir /what-comes-first-when-remodeling-a-house/ /blog/what-comes-first-when-remodeling-a-house/ 301
        redir /what-do-i-wish-i-knew-before-finishing-the-basement /blog/what-do-i-wish-i-knew-before-finishing-the-basement/ 301
        redir /what-do-i-wish-i-knew-before-finishing-the-basement/ /blog/what-do-i-wish-i-knew-before-finishing-the-basement/ 301
        redir /what-does-a-bathroom-remodel-cost-in-bozeman /blog/what-does-a-bathroom-remodel-cost-in-bozeman/ 301
        redir /what-does-a-bathroom-remodel-cost-in-bozeman/ /blog/what-does-a-bathroom-remodel-cost-in-bozeman/ 301
        redir /what-does-a-full-remodel-include /blog/what-does-a-full-remodel-include/ 301
        redir /what-does-a-full-remodel-include/ /blog/what-does-a-full-remodel-include/ 301
        redir /what-does-it-cost-to-finish-a-basement-in-bozeman /blog/what-does-it-cost-to-finish-a-basement-in-bozeman/ 301
        redir /what-does-it-cost-to-finish-a-basement-in-bozeman/ /blog/what-does-it-cost-to-finish-a-basement-in-bozeman/ 301
        redir /what-flooring-is-best-for-a-bathroom-in-bozeman-mt /blog/what-flooring-is-best-for-a-bathroom-in-bozeman-mt/ 301
        redir /what-flooring-is-best-for-a-bathroom-in-bozeman-mt/ /blog/what-flooring-is-best-for-a-bathroom-in-bozeman-mt/ 301
        redir /what-flooring-is-urine-proof-best-options-for-bozeman-homes /blog/what-flooring-is-urine-proof-best-options-for-bozeman-homes/ 301
        redir /what-flooring-is-urine-proof-best-options-for-bozeman-homes/ /blog/what-flooring-is-urine-proof-best-options-for-bozeman-homes/ 301
        redir /what-happens-during-remodeling-in-bozeman-mt /blog/what-happens-during-remodeling-in-bozeman-mt/ 301
        redir /what-happens-during-remodeling-in-bozeman-mt/ /blog/what-happens-during-remodeling-in-bozeman-mt/ 301
        redir /what-is-a-reasonable-budget-for-a-bathroom-remodel-in-bozeman-mt /blog/what-is-a-reasonable-budget-for-a-bathroom-remodel-in-bozeman-mt/ 301
        redir /what-is-a-reasonable-budget-for-a-bathroom-remodel-in-bozeman-mt/ /blog/what-is-a-reasonable-budget-for-a-bathroom-remodel-in-bozeman-mt/ 301
        redir /what-is-the-best-foundation-for-a-deck-in-bozeman-mt /blog/what-is-the-best-foundation-for-a-deck-in-bozeman-mt/ 301
        redir /what-is-the-best-foundation-for-a-deck-in-bozeman-mt/ /blog/what-is-the-best-foundation-for-a-deck-in-bozeman-mt/ 301
        redir /what-is-the-best-time-to-renovate-a-bathroom-in-bozeman-mt /blog/what-is-the-best-time-to-renovate-a-bathroom-in-bozeman-mt/ 301
        redir /what-is-the-best-time-to-renovate-a-bathroom-in-bozeman-mt/ /blog/what-is-the-best-time-to-renovate-a-bathroom-in-bozeman-mt/ 301
        redir /what-is-the-best-time-to-renovate-in-bozeman-mt /blog/what-is-the-best-time-to-renovate-in-bozeman-mt/ 301
        redir /what-is-the-best-time-to-renovate-in-bozeman-mt/ /blog/what-is-the-best-time-to-renovate-in-bozeman-mt/ 301
        redir /what-is-the-biggest-deck-you-can-build-without-a-permit-in-bozeman-mt /blog/what-is-the-biggest-deck-you-can-build-without-a-permit-in-bozeman-mt/ 301
        redir /what-is-the-biggest-deck-you-can-build-without-a-permit-in-bozeman-mt/ /blog/what-is-the-biggest-deck-you-can-build-without-a-permit-in-bozeman-mt/ 301
        redir /what-is-the-difference-between-renovation-and-remodeling /blog/what-is-the-difference-between-renovation-and-remodeling/ 301
        redir /what-is-the-difference-between-renovation-and-remodeling/ /blog/what-is-the-difference-between-renovation-and-remodeling/ 301
        redir /what-is-universal-design-the-7-principles-explained-for-homeowners /blog/what-is-universal-design-the-7-principles-explained-for-homeowners/ 301
        redir /what-is-universal-design-the-7-principles-explained-for-homeowners/ /blog/what-is-universal-design-the-7-principles-explained-for-homeowners/ 301
        redir /what-to-ask-a-contractor-before-a-remodel-in-bozeman-mt /blog/what-to-ask-a-contractor-before-a-remodel-in-bozeman-mt/ 301
        redir /what-to-ask-a-contractor-before-a-remodel-in-bozeman-mt/ /blog/what-to-ask-a-contractor-before-a-remodel-in-bozeman-mt/ 301
        redir /what-to-expect-during-a-bathroom-remodel-in-bozeman /blog/what-to-expect-during-a-bathroom-remodel-in-bozeman/ 301
        redir /what-to-expect-during-a-bathroom-remodel-in-bozeman/ /blog/what-to-expect-during-a-bathroom-remodel-in-bozeman/ 301
        redir /when-not-to-renovate-a-house-in-bozeman-mt /blog/when-not-to-renovate-a-house-in-bozeman-mt/ 301
        redir /when-not-to-renovate-a-house-in-bozeman-mt/ /blog/when-not-to-renovate-a-house-in-bozeman-mt/ 301
        redir /when-should-you-not-finish-a-basement-in-bozeman-mt /blog/when-should-you-not-finish-a-basement-in-bozeman-mt/ 301
        redir /when-should-you-not-finish-a-basement-in-bozeman-mt/ /blog/when-should-you-not-finish-a-basement-in-bozeman-mt/ 301
        redir /what-salary-typically-affords-a-300000-house / 301
        redir /what-salary-typically-affords-a-300000-house/ / 301
        redir /at-what-point-is-a-house-not-worth-fixing / 301
        redir /at-what-point-is-a-house-not-worth-fixing/ / 301
        redir /what-is-the-30-rule-in-remodeling / 301
        redir /what-is-the-30-rule-in-remodeling/ / 301
        redir /what-is-the-smartest-way-to-pay-for-home-improvements-in-bozeman-mt / 301
        redir /what-is-the-smartest-way-to-pay-for-home-improvements-in-bozeman-mt/ / 301
        redir /what-should-you-not-skimp-on-when-building-a-house / 301
        redir /what-should-you-not-skimp-on-when-building-a-house/ / 301
        redir /how-do-people-afford-to-finish-a-basement-in-bozeman-mt / 301
        redir /how-do-people-afford-to-finish-a-basement-in-bozeman-mt/ / 301
        redir /what-is-the-most-expensive-part-of-a-home-renovation-in-bozeman-mt / 301
        redir /what-is-the-most-expensive-part-of-a-home-renovation-in-bozeman-mt/ / 301
        redir /what-is-the-most-popular-home-renovation / 301
        redir /what-is-the-most-popular-home-renovation/ / 301
        redir /top-remodeling-tips-for-bozeman-homeowners-from-bathrooms-to-basements / 301
        redir /top-remodeling-tips-for-bozeman-homeowners-from-bathrooms-to-basements/ / 301
        # Permanent public aliases: old cached pages use brand/ for these icons.
        rewrite /img/brand/Construction-Contractor-Logo.jpg /img/icons/Construction-Contractor-Logo.jpg
        rewrite /img/brand/iccu-small.jpg /img/icons/iccu-small.jpg
        rewrite /img/brand/jobtread-badge.webp /img/icons/jobtread-badge.webp
        @report path_regexp report ^/report/([A-Za-z0-9-]{4,64})/?$
        rewrite @report /report/?id={re.report.1}
        file_server
      }
    '';
    hwc.networking.cloudflared.extraIngress = {
      "iheartwoodcraft.com" = "http://127.0.0.1:${toString cfg.originPort}";
      "www.iheartwoodcraft.com" = "http://127.0.0.1:${toString cfg.originPort}";
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
    ];
  };
}
