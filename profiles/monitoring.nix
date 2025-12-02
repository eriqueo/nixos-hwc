{ lib, config, ... }:
let
  cfg = config.hwc.features.monitoring;
in
{
  options.hwc.features.monitoring = {
    enable = lib.mkEnableOption "monitoring services (Prometheus, Grafana)";
  };

  config = lib.mkIf cfg.enable {
    #==========================================================================
    # MONITORING SERVICES
    #==========================================================================
    imports = [
      ../domains/server/monitoring/index.nix
    ];

    hwc.services.prometheus = {
      enable = true;
      retention = "90d";
    };

    hwc.services.grafana = {
      enable = true;
      domain = "grafana.hwc.local";
    };
  };
}
