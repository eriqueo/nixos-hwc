# domains/monitoring/index.nix
#
#

{ lib, ... }:
{
  # OPTIONS
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
    ./podman-exporter/index.nix
    ./exportarr/index.nix
    ./fleet-map/index.nix
    ./homepage/index.nix
    ./alerts/index.nix
    ./heartbeat/index.nix
  ];
}
