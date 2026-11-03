# domains/business/umami/index.nix
#
# Umami — self-hosted, cookieless web analytics for iheartwoodcraft.com
#
# NAMESPACE: hwc.business.umami.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (engine + 10.89.0.1 container binding)
#   - agenix secret: umami-env (APP_SECRET + DATABASE_URL)
#   - public ingress: cloudflared extraIngress "stats.iheartwoodcraft.com"
#     → http://localhost:<port> (machines/home/config.nix) — the tracking
#     script and /api/send collect endpoint must be reachable by site
#     visitors' browsers, so this rides the Cloudflare tunnel like the
#     calculator webhooks.
#
# PORTS:
#   - Host: 3009 (loopback) → container 3000

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.umami;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;
in
{
  imports = [ ./parts/weekly-report.nix ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.business.umami = {
    enable = lib.mkEnableOption "Umami web analytics";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3009;
      description = "Host loopback port for the Umami web UI / collect API";
    };

    image = lib.mkOption {
      type = lib.types.str;
      # 3.4.1 security hotfix; qualified against the unchanged 3.4.0 schema.
      default = "ghcr.io/umami-software/umami@sha256:f2c645cc5cdff76e7fbfe4c7eeabc7e363840bd34364f4f719b69d11f9ef1c19";
      description = "Umami container image";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "umami";
      description = "PostgreSQL database for Umami";
    };

    websiteId = lib.mkOption {
      type = lib.types.str;
      default = "02d2b023-55a7-4a24-8064-0d97e4801284";
      description = "Umami website UUID for iheartwoodcraft.com (created 2026-07-07 via API; used by the tracking snippet, morning briefing, and weekly report)";
    };

    #========================================================================
    # WEEKLY REPORT (implementation: ./parts/weekly-report.nix)
    # Declared here, not in parts/: Law 10 — "mkOption anywhere else,
    # including parts/*.nix" is the violation. Moved 2026-08-06.
    #========================================================================
    weeklyReport = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Weekly website-metrics email (Umami + calculator leads)";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "Mon 07:00";
        description = "systemd OnCalendar spec (local server time)";
      };
      recipient = lib.mkOption {
        type = lib.types.str;
        default = "eric@iheartwoodcraft.com";
        description = "Report recipient";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [

    (mkContainer {
      name = "umami";
      image = cfg.image;
      networkMode = "media";
      gpuEnable = false;
      timeZone = "America/Denver";
      memory = "512m";
      cpus = "0.5";
      memorySwap = "1g";

      ports = [ "127.0.0.1:${toString cfg.port}:3000" ];

      # The unchanged APP_SECRET and password-bearing DATABASE_URL share the
      # existing protected OCI environment file; never put either in Nix.
      environmentFiles = [ config.age.secrets."umami-env".path ];

      environment = {
        DATABASE_TYPE = "postgresql";
      };
    })

    {
      hwc.data.databases.postgresql.applicationRoles.${cfg.databaseName} = {
        credential.environment = {
          secret = "umami-env"; field = "DATABASE_URL"; encoding = "postgresql-url";
        };
        authority.owned = {};
      };

      # Start after postgres is up (container network + db)
      systemd.services.podman-umami = {
        after = [ "postgresql.service" "postgresql-application-roles.service" "init-media-network.service" ];
        requires = [ "postgresql-application-roles.service" ];
        restartTriggers = [ config.age.secrets.umami-env.file config.system.build.postgresqlApplicationRoleTool ];
        serviceConfig = {
          # Next drains requests, then deliberately exits 143 for SIGTERM.
          # Keep unsolicited termination recoverable as well as planned stops clean.
          SuccessExitStatus = [ 143 ];
          Restart = lib.mkForce "always";
        };
      };

      # VALIDATION
      assertions = [
        {
          assertion = config.hwc.data.databases.postgresql.enable;
          message = "hwc.business.umami requires PostgreSQL (hwc.data.databases.postgresql.enable = true)";
        }
        {
          assertion = config.hwc.data.databases.postgresql.containerNetwork.enable or true;
          message = "hwc.business.umami connects over the podman gateway; postgresql containerNetwork binding must be enabled";
        }
      ];
    }
  ]);
}
