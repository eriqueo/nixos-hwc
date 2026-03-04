# HWC Container Services Aggregator
# Most containers moved to their respective domains during DDD migration.
# Remaining: business containers (paperless, firefly), caddy container, shared infra.

{ lib, config, ... }:

{
  imports = [
    # Legacy namespace compatibility
    (lib.mkRenamedOptionModule [ "hwc" "services" "containers" ] [ "hwc" "server" "containers" ])

    # Shared infrastructure (directories.nix still needed for tmpfiles)
    ./_shared/directories.nix

    # Business containers (TODO Phase 8: move to domains/business/)
    ./paperless/index.nix
    ./firefly/index.nix

    # Caddy container (unused/stub — kept for option compatibility)
    ./caddy/index.nix
  ];

  config = { };
}
