{ lib, config, ... }:
let
  cfg = config.hwc.features.monitoring;
   imports = [
      ../domains/server/monitoring/index.nix
    ];
in
{
  options.hwc.features.monitoring = {
    enable = lib.mkEnableOption "monitoring services (Prometheus, Grafana)";
  };

  config = lib.mkIf cfg.enable {
    #==========================================================================
    # MONITORING SERVICES
    #==========================================================================
   

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
