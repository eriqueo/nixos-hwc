# nixos-hwc/modules/services/media/jellyfin.nix
#
# Jellyfin Media Server
# Provides streaming media server with optional GPU transcoding
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.infrastructure.hardware.gpu.type (modules/infrastructure/hardware/gpu.nix) [optional]
#   Upstream: virtualisation.docker.enable (profiles/base.nix)
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/jellyfin.nix
#   - Any machine using this service
#
# USAGE:
#   hwc.services.jellyfin.enable = true;
#   hwc.services.jellyfin.enableGpu = true;  # For hardware transcoding
#   hwc.services.jellyfin.dataDir = "/custom/path";  # Override default
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot to be configured
#   - GPU acceleration requires hwc.infrastructure.hardware.gpu.type != "none"
#   - Port 8096 must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.jellyfin;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
    
    # Core settings
    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Web interface port";
    };
    
    # Advanced settings
    enableGpu = lib.mkEnableOption "GPU hardware transcoding";
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/jellyfin";
      description = "Data directory for Jellyfin";
    };
    
    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = paths.storage.media or "/var/lib/jellyfin/media";
      description = "Media library directory";
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check required dependencies
    assertions = [
      {
        assertion = paths.storage.hot != null;
        message = "Jellyfin requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = cfg.enableGpu -> (config.hwc.infrastructure.hardware.gpu.type or "none") != "none";
        message = "Jellyfin GPU acceleration requires hwc.infrastructure.hardware.gpu.type to be configured";
      }
    ];
    
    # Service implementation
    virtualisation.oci-containers.containers.jellyfin = {
      image = "jellyfin/jellyfin:latest";
      
      ports = [ "${toString cfg.port}:8096" ];
      
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/cache:/cache"
        "${cfg.mediaDir}:/media:ro"
      ];
      
      environment = {
        TZ = config.time.timeZone;
        JELLYFIN_PublishedServerUrl = "http://localhost:${toString cfg.port}";
      };
      
      extraOptions = lib.optionals cfg.enableGpu (
        if config.hwc.infrastructure.hardware.gpu.type == "nvidia" then [
          "--runtime=nvidia"
          "--gpus=all"
        ] else if config.hwc.infrastructure.hardware.gpu.type == "intel" then [
          "--device=/dev/dri"
        ] else []
      );
    };
    
    # Directory creation
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/cache 0755 root root -"
    ];
    
    # Firewall
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}

