# domains/server/monitoring/options.nix
# Feature toggle for monitoring stack (Prometheus, Grafana, etc.)

{ lib, ... }:
{
  options.hwc.server.monitoring = {
    enable = lib.mkEnableOption "monitoring stack (Prometheus, Grafana, exporters)" // {
      default = true;
    };
  };
}
