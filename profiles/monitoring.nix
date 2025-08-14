{ ... }:
{
  imports = [
    ../modules/services/prometheus.nix
    ../modules/services/grafana.nix
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
