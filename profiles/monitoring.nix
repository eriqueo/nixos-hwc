{ ... }:
{
  imports = [
    ../domains/server/prometheus.nix
    ../domains/server/grafana.nix
  ];
  
  hwc.services.prometheus = {
    enable = true;
    retention = "90d";
  };
  
  hwc.services.grafana = {
    enable = true;
    domain = "grafana.hwc.local";
  };
}
