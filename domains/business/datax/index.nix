# domains/business/datax/default.nix
#
# lead_scout database wiring (postgres role + db).
#
# The Facebook scrape/classify pipeline that used to live here was migrated
# to hwc.server.ai.leadScout in 2026-05. This module now only owns the
# `lead_scout` PostgreSQL role and database that lead_scout connects to.
#
# THE NAME. Nothing here relates to the DataX product. The Facebook scraper was
# built on 2026-05-11 under a project called `datax` (499286ec, "feat(datax):
# FB group scraper"), which is when Postgres created a database of that name.
# Six days later the scraper became its own repo, lead_scout. The code moved;
# the database name did not, because renaming a live database means a dump and
# a restore. It carried its birth name for three months.
#
# Renamed 2026-08-26: `ALTER DATABASE datax RENAME TO lead_scout` plus the same
# for the role. The database holds fb_posts, fb_comments, post_classifications
# and scrape_sources — lead-scout tables, all of them, and no DataX table.
# Do not confuse it with `datax_monitor` (orgs, agents, executions, tool_calls),
# which IS DataX monitoring and is a different database.
#
# The MODULE still lives under domains/business/datax/ and keeps the
# hwc.business.datax namespace. That is now the only misleading name left, and
# it violates Law 2 (name mirrors structure) because the module no longer owns
# anything called datax. The fix is to move this role+db into
# domains/server/native/ai/lead-scout/ and delete this module; it was left for
# a separate reviewable change rather than folded into a live rename.
#
# NAMESPACE: hwc.business.datax.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (PostgreSQL engine)
#
# USED BY:
#   - domains/business/index.nix
#   - hwc.server.ai.leadScout (consumes DATABASE_URL=postgresql://lead_scout@localhost/lead_scout)
#   - hwc.business.crm.leadscoutIngest (reads it, read-only by contract)

{ lib, ... }:

{
  imports = [ ./database.nix ];

  # ── OPTIONS ────────────────────────────────────────────────────────────────

  options.hwc.business.datax = {
    enable = lib.mkEnableOption "lead_scout postgres role + database";

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "lead_scout";
      description = "PostgreSQL database name (renamed from `datax` on 2026-08-26)";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "lead_scout";
      description = "PostgreSQL role (renamed from `datax` on 2026-08-26)";
    };
  };

  # ── IMPLEMENTATION ─────────────────────────────────────────────────────────
  # All implementation lives in ./database.nix (postgres role + db + schema).
}
