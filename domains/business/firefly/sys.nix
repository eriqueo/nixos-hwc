# domains/business/firefly/sys.nix
#
# Firefly III System Lane Configuration
# PostgreSQL login role for the firefly databases.
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.business.firefly;
in
{
  config = lib.mkIf cfg.enable {
    #=========================================================================
    # POSTGRESQL LOGIN ROLE
    #=========================================================================
    # This file used to hold sixteen `$PSQL` GRANT / ALTER DEFAULT PRIVILEGES
    # lines — the same eight-line block once per database — and not one of them
    # ever ran. `$PSQL` is undefined in the generated postgresql post-start
    # script, and every line ended in `|| true`, which swallowed the resulting
    # command-not-found. Full audit (54 statements across ten modules) in
    # domains/data/databases/README.md, 2026-08-28.
    #
    # They are not restored, because they were never load-bearing. Firefly and
    # firefly-pico connect as `${cfg.database.user}`, which is `eric` — a
    # Postgres superuser who also owns all 81 firefly and 15 firefly_pico
    # tables. A grant to the object owner grants nothing.
    #
    # The role itself is NOT declared here. `${cfg.database.user}` is the primary
    # user, and domains/data/databases/index.nix declares that role once for the
    # whole cluster — one producer per fact. Three app modules briefly declared
    # it in parallel; that was the same duplication in a new place.
    #
    # `ensureDBOwnership` is deliberately not set anywhere for these two
    # databases. Both are owned by `postgres` on the live cluster while their
    # objects are owned by `eric`; setting it would rewrite live ownership to
    # chase a tidier declaration, which is a state change disguised as a cleanup.
    #
    # This file therefore declares nothing. It is kept rather than deleted so the
    # firefly module still has a system lane to grow into, and so this reasoning
    # has a home next to the code it explains.
  };
}
