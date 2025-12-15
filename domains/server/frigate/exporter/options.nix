# domains/server/frigate/exporter/options.nix
#
# Frigate Prometheus Exporter - Converts Frigate stats API to Prometheus metrics
#
# NAMESPACE: hwc.server.frigate.exporter.*

{ lib, ... }:

{
  options.hwc.server.frigate.exporter = {
    enable = lib.mkEnableOption "Frigate Prometheus exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9192;
      description = "Frigate exporter metrics port";
    };

    frigateUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:5001";
      description = "Frigate API URL";
    };
  };
}
