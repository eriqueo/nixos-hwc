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
#     → http://localhost:<port> (machines/server/config.nix) — the tracking
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
      default = "ghcr.io/umami-software/umami:postgresql-latest";
      description = "Umami container image (postgresql variant)";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "umami";
      description = "PostgreSQL database for Umami";
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

      # DATABASE_URL + APP_SECRET live in the agenix env file; the DB
      # connection uses the podman gateway (10.89.0.1) trust rule, so the
      # URL carries no password — APP_SECRET is the only real secret.
      environmentFiles = [ config.age.secrets."umami-env".path ];

      environment = {
        DATABASE_TYPE = "postgresql";
      };
    })

    {
      # Database registration (engine creates it; role added below)
      hwc.data.databases.postgresql.databases = [ cfg.databaseName ];

      # Umami connects as role "umami" from the podman subnet (trust auth).
      # ensureDatabases owns the db as postgres, so create the role and hand
      # over the schema.
      # NOTE: deliberately self-contained — current nixpkgs runs the ensure*
      # logic in postgresql-setup.service, so postgresql.service's postStart
      # has NO $PSQL preamble anymore. (The older hwc modules' $PSQL lines in
      # this hook are all dead code saved only by their `|| true`.) Absolute
      # binary paths + a private variable keep this block working regardless.
      systemd.services.postgresql.postStart = lib.mkAfter ''
        UMAMI_PSQL="${config.services.postgresql.package}/bin/psql"
        $UMAMI_PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname='umami'" | ${pkgs.gnugrep}/bin/grep -q 1 || \
          $UMAMI_PSQL -c "CREATE ROLE umami LOGIN" || true
        $UMAMI_PSQL -c "ALTER DATABASE ${cfg.databaseName} OWNER TO umami" || true
        $UMAMI_PSQL -d ${cfg.databaseName} -c "ALTER SCHEMA public OWNER TO umami" || true
      '';

      # Start after postgres is up (container network + db)
      systemd.services.podman-umami = {
        after = [ "postgresql.service" "init-media-network.service" ];
        wants = [ "postgresql.service" ];
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
