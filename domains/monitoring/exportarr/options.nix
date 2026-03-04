# domains/server/monitoring/exportarr/options.nix
#
# Exportarr - Prometheus exporter for *arr applications (Sonarr/Radarr/Lidarr/Prowlarr)
#
# NAMESPACE: hwc.monitoring.exportarr.*

{ lib, ... }:

{
  options.hwc.monitoring.exportarr = {
    enable = lib.mkEnableOption "Exportarr metrics exporter for *arr applications";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9707;
      description = "Exportarr metrics port";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["sonarr" "radarr" "lidarr" "prowlarr"]);
      default = ["sonarr" "radarr" "lidarr" "prowlarr"];
      description = "Arr applications to monitor";
    };
  };
}
