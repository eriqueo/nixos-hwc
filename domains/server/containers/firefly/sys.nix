# domains/server/containers/firefly/sys.nix
#
# Firefly III System Lane Configuration
# PostgreSQL database grants and setup
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.firefly;
in
{
  config = lib.mkIf cfg.enable {
    #=========================================================================
    # POSTGRESQL DATABASE SETUP
    #=========================================================================
    # Grant eric user access to firefly databases for container connections
    systemd.services.postgresql.postStart = lib.mkAfter (''
      # Firefly III main database
      $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "GRANT USAGE, CREATE ON SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO eric;" || true
      $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO eric;" || true
    '' + lib.optionalString cfg.pico.enable ''
      # Firefly-Pico database
      $PSQL -d ${cfg.database.picoName} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.picoName} TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "GRANT USAGE, CREATE ON SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO eric;" || true
      $PSQL -d ${cfg.database.picoName} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO eric;" || true
    '');
  };
}
