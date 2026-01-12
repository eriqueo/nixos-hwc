# domains/server/monitoring/index.nix
#
# Monitoring Domain Aggregator
# Charter v7.0 compliant
#
# Imports all monitoring modules

{ lib, ... }:
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
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
