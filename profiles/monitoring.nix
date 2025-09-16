{ ... }:
{
  imports = [
    ../modules/server/prometheus.nix
    ../modules/server/grafana.nix
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
