{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.SERVICE_NAME;
  paths = config.hwc.paths;
in {
  options.hwc.services.SERVICE_NAME = {
    enable = lib.mkEnableOption "SERVICE_DESCRIPTION";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = PORT_NUMBER;
      description = "Port for SERVICE_NAME";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/SERVICE_NAME";
      description = "Data directory";
    };
    
    # Add service-specific options here
  };
  
  config = lib.mkIf cfg.enable {
    # Service implementation
  };
}
