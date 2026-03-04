# domains/server/monitoring/options.nix
# Feature toggle for monitoring stack (Prometheus, Grafana, etc.)

{ lib, ... }:
{
  options.hwc.monitoring = {
    enable = lib.mkEnableOption "monitoring stack (Prometheus, Grafana, exporters)" // {
      default = true;
    };
  };
}
