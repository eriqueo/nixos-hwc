# domains/server/monitoring/default.nix
#
# Server monitoring subdomain aggregator
# Imports options and monitoring implementation files

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/prometheus.nix
    ./parts/grafana.nix
  ];
}