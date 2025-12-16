# domains/server/monitoring/index.nix
#
# Monitoring Domain Aggregator
# Charter v7.0 compliant
#
# Imports all monitoring modules

{ ... }:

{
  imports = [
    ./prometheus/index.nix
    ./grafana/index.nix
    ./alertmanager/index.nix
    ./cadvisor/index.nix
    ./exportarr/index.nix
  ];
}