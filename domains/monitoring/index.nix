# domains/monitoring/index.nix
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
  options.hwc.monitoring = {
    enable = lib.mkEnableOption "monitoring stack (Prometheus, Grafana, exporters)" // {
      default = true;
    };
  };

  imports = [
    ./prometheus/index.nix
    ./grafana/index.nix
    ./alertmanager/index.nix
    ./cadvisor/index.nix
    ./exportarr/index.nix
    ./homepage/index.nix
    ./uptime-kuma/index.nix
    ./alerts/index.nix            # Alert sources, thresholds, severity mapping
  ];
  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = {
    assertions = [];
  };
}
