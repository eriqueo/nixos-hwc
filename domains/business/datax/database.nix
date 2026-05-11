# domains/business/datax/database.nix
#
# DataX PostgreSQL database and user setup
#
# NAMESPACE: hwc.business.datax.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (engine must be enabled)

{ config, lib, ... }:

let
  cfg = config.hwc.business.datax;
in
{
  config = lib.mkIf cfg.enable {
    # Create the datax database
    services.postgresql.ensureDatabases = [ cfg.databaseName ];

    # Create datax user and grant full access
    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -c "DO \$\$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${cfg.databaseUser}') THEN
          CREATE ROLE ${cfg.databaseUser} LOGIN;
        END IF;
      END \$\$;" || true
      $PSQL -d ${cfg.databaseName} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.databaseName} TO ${cfg.databaseUser};" || true
      $PSQL -d ${cfg.databaseName} -c "GRANT USAGE, CREATE ON SCHEMA public TO ${cfg.databaseUser};" || true
      $PSQL -d ${cfg.databaseName} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${cfg.databaseUser};" || true
      $PSQL -d ${cfg.databaseName} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${cfg.databaseUser};" || true
      $PSQL -d ${cfg.databaseName} -f ${./fb-monitor-bak/schema.sql} || true
    '';

    # Register datax for per-database backups
    hwc.data.databases.postgresql.backup.perDatabase.databases = [ cfg.databaseName ];

    assertions = [
      {
        assertion = config.hwc.data.databases.postgresql.enable;
        message = ''
          hwc.business.datax requires hwc.data.databases.postgresql to be enabled.
          Enable it in domains/data/databases/ first.
        '';
      }
    ];
  };
}
