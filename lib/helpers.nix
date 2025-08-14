{ lib }:
rec {
  # Helper to create a service module
  mkServiceModule = { name, port, description }: { config, lib, pkgs, ... }:
    let
      cfg = config.hwc.services.${name};
      paths = config.hwc.paths;
    in {
      options.hwc.services.${name} = {
        enable = lib.mkEnableOption description;
        
        port = lib.mkOption {
          type = lib.types.port;
          default = port;
          description = "Service port";
        };
        
        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "${paths.state}/${name}";
          description = "Data directory";
        };
      };
      
      config = lib.mkIf cfg.enable {
        # Implementation here
      };
    };
  
  # Helper to create container service
  mkContainerService = { name, image, port }: { config, lib, pkgs, ... }:
    let
      cfg = config.hwc.services.${name};
    in {
      options.hwc.services.${name} = {
        enable = lib.mkEnableOption name;
        
        image = lib.mkOption {
          type = lib.types.str;
          default = image;
        };
        
        port = lib.mkOption {
          type = lib.types.port;
          default = port;
        };
      };
      
      config = lib.mkIf cfg.enable {
        virtualisation.oci-containers.containers.${name} = {
          inherit image;
          ports = [ "${toString cfg.port}:${toString port}" ];
        };
      };
    };
  
  # Helper for GPU services
  mkGpuService = options: options // {
    enableGpu = lib.mkEnableOption "GPU acceleration";
    
    gpuMemory = lib.mkOption {
      type = lib.types.str;
      default = "2GB";
      description = "GPU memory allocation";
    };
  };
  
  # Path helpers
  mkDataDir = service: paths: "${paths.state}/${service}";
  mkCacheDir = service: paths: "${paths.cache}/${service}";
  mkLogDir = service: paths: "${paths.logs}/${service}";
}
