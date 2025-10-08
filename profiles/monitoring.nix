{ ... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/server/prometheus.nix
    ../domains/server/grafana.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.services.prometheus = {
    enable = true;
    retention = "90d";
  };
  
  hwc.services.grafana = {
    enable = true;
    domain = "grafana.hwc.local";
  };
}
