# domains/business/datax/default.nix
#
# DataX — legacy database wiring (postgres role + db) for lead_scout.
#
# The Facebook scrape/classify pipeline that used to live here was migrated
# to hwc.server.ai.leadScout in 2026-05. This module now only owns the
# `datax` PostgreSQL role and database that lead_scout connects to.
#
# NAMESPACE: hwc.business.datax.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (PostgreSQL engine)
#
# USED BY:
#   - domains/business/index.nix
#   - hwc.server.ai.leadScout (consumes DATABASE_URL=postgresql://datax@localhost/datax)

{ lib, ... }:

{
  imports = [ ./database.nix ];

  # ── OPTIONS ────────────────────────────────────────────────────────────────

  options.hwc.business.datax = {
    enable = lib.mkEnableOption "DataX legacy postgres role + database (used by lead_scout)";

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "datax";
      description = "PostgreSQL database name";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "datax";
      description = "PostgreSQL user";
    };
  };

  # ── IMPLEMENTATION ─────────────────────────────────────────────────────────
  # All implementation lives in ./database.nix (postgres role + db + schema).
}
