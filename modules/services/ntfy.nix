{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ntfy;
  paths = config.hwc.paths;
in {
  options.hwc.services.ntfy = {
    enable = lib.mkEnableOption "ntfy notification service";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "ntfy web port";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ntfy";
      description = "Data directory";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://localhost:${toString cfg.port}";
        listen-http = ":${toString cfg.port}";
        cache-file = "${cfg.dataDir}/cache.db";
      };
    };
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0755 root root -" ];
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
