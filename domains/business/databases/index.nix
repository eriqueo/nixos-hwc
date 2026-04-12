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

    # Register for per-database backups
    hwc.data.databases.postgresql.backup.perDatabase.databases = [ cfg.databaseName ];

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
