# domains/server/monitoring/index.nix
#
# Monitoring Domain Aggregator
# Charter v7.0 compliant
#
# Imports all monitoring modules

{ lib, config, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./prometheus/index.nix
    ./grafana/index.nix
    ./alertmanager/index.nix
    ./cadvisor/index.nix
    ./exportarr/index.nix
  ];
  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = {
    assertions = [];
  };
}
