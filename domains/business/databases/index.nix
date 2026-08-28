# domains/business/databases/index.nix
#
# Business data layer — hwc PostgreSQL database
#
# NAMESPACE: hwc.business.databases.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (engine must be enabled)
#
# USED BY:
#   - n8n workflows (calculator_leads, daily_logs)
#   - Estimate Assembler (cost catalog, project state)

{ lib, config, ... }:
let
  cfg = config.hwc.business.databases;
in
{
  # OPTIONS
  options.hwc.business.databases = {
    enable = lib.mkEnableOption "Heartwood Craft business database layer";

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "hwc";
      description = "PostgreSQL database name for business data";
    };

    schemaFile = lib.mkOption {
      type = lib.types.path;
      default = ./schema.sql;
      description = "Path to the business schema SQL file (applied manually)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "PostgreSQL user for business database access";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Ensure the business database exists
    services.postgresql.ensureDatabases = [ cfg.databaseName ];

    # The login role for `${cfg.user}` is NOT declared here. It is the primary
    # user, declared once for the whole cluster in
    # domains/data/databases/index.nix — one producer per fact.
    #
    # `business_user` IS declared here, because this module owns it: schema.sql
    # (lines 772-774) and migrations/001-catalog-schema-split.sql grant to that
    # role by name, and nothing else in the repo mentions it. The role existed on
    # the live cluster by hand until 2026-08-28; a rebuilt cluster would have run
    # those grants against a role that does not exist. No ensureDBOwnership —
    # `eric` owns this database and its objects, and business_user is a grantee.
    services.postgresql.ensureUsers = [{ name = "business_user"; }];
    #
    # No postStart grant block and no per-database backup registration.
    #
    # Four `$PSQL` GRANT lines used to sit here and none ever ran: `$PSQL` is
    # undefined in the generated postgresql post-start script and `|| true`
    # swallowed the command-not-found (audit 2026-08-28, see
    # domains/data/databases/README.md). They were not load-bearing either —
    # `${cfg.user}` is a superuser AND the owner of this database.
    #
    # postgresql-db-backup was retired 2026-08-26 (Law 15), so registering into
    # it would be dead config reading as a backup. `hwc` rides the borg
    # pre-hook's nightly pg_dumpall into /var/lib/backups.

    # VALIDATION
    assertions = [
      {
        assertion = config.hwc.data.databases.postgresql.enable;
        message = ''
          hwc.business.databases requires hwc.data.databases.postgresql to be enabled.
          The business database layer depends on the PostgreSQL engine managed by
          domains/data/databases/.
        '';
      }
    ];
  };
}
