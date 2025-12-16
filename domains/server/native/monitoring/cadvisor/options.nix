# domains/server/monitoring/cadvisor/options.nix
#
# cAdvisor - Container Advisor for resource usage and performance metrics
#
# NAMESPACE: hwc.server.monitoring.cadvisor.*

{ lib, ... }:

{
  options.hwc.server.monitoring.cadvisor = {
    enable = lib.mkEnableOption "cAdvisor container metrics exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9120;
      description = "cAdvisor metrics port";
    };
  };
}
