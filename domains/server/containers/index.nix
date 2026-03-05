# HWC Container Services Aggregator
# Most containers moved to their respective domains during DDD migration.
# Remaining: caddy container (stub), shared tmpfiles infrastructure.

{ lib, config, ... }:

{
  imports = [
    # Shared infrastructure (directories.nix still needed for tmpfiles)
    ./_shared/directories.nix

    # Caddy container (unused/stub — kept for option compatibility)
    ./caddy/index.nix
  ];

  config = { };
}
