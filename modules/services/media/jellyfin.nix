# nixos-hwc/modules/services/media/jellyfin.nix
#
# JELLYFIN - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.jellyfin.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/jellyfin.nix
#
# USAGE:
#   hwc.services.jellyfin.enable = true;
#   # TODO: Add specific usage examples

# nixos-hwc/modules/services/media/jellyfin.nix
#
# Jellyfin Media Server
# Provides streaming media server with optional GPU transcoding
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.hot (modules/system/paths.nix)
#   Upstream: config.hwc.paths.media (modules/system/paths.nix)
#   Upstream: config.hwc.infrastructure.hardware.gpu.type (modules/infrastructure/hardware/gpu.nix) [optional]
#   Upstream: config.hwc.infrastructure.hardware.gpu.containerOptions (modules/infrastructure/hardware/gpu.nix)
#   Upstream: config.hwc.infrastructure.hardware.gpu.containerEnvironment (modules/infrastructure/hardware/gpu.nix)
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/jellyfin.nix
#   - Any machine using Jellyfin
#
# USAGE:
#   hwc.services.jellyfin.enable = true;
#   hwc.services.jellyfin.enableGpu = true;  # For hardware transcoding
#   hwc.services.jellyfin.port = 8096;
#
# VALIDATION:
#   - Requires hwc.paths.hot to be configured
#   - GPU acceleration requires hwc.infrastructure.hardware.gpu.type != "none"
#   - Port must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.jellyfin;
  paths = config.hwc.paths;
  gpu = config.hwc.infrastructure.hardware.gpu;
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
      default = "${paths.hot}/jellyfin";
      description = "Data directory for Jellyfin";
    };
    
    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = paths.media;
      description = "Media library directory";
    };
    
    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.cache}/jellyfin";
      description = "Cache directory for transcoding";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin/jellyfin:latest";
      description = "Container image to use";
    };
    
    memory = lib.mkOption {
      type = lib.types.str;
      default = "4g";
      description = "Memory limit for container";
    };
    
    cpus = lib.mkOption {
      type = lib.types.str;
      default = "2.0";
      description = "CPU limit for container";
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check required dependencies
    assertions = [
      {
        assertion = paths.hot != null;
        message = "Jellyfin requires hwc.paths.hot to be configured";
      }
      {
        assertion = paths.media != null;
        message = "Jellyfin requires hwc.paths.media to be configured";
      }
      {
        assertion = cfg.enableGpu -> (gpu.type != "none");
        message = "Jellyfin GPU acceleration requires hwc.infrastructure.hardware.gpu.type to be configured";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.jellyfin = {
      image = cfg.image;
      autoStart = true;
      
      ports = [ "127.0.0.1:${toString cfg.port}:8096" ];
      
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.cacheDir}:/cache"
        "${cfg.mediaDir}:/media:ro"
      ];
      
      environment = {
        TZ = config.time.timeZone;
        JELLYFIN_PublishedServerUrl = "http://localhost:${toString cfg.port}";
        PUID = "1000";
        PGID = "1000";
      } // (lib.optionalAttrs cfg.enableGpu gpu.containerEnvironment);
      
      extraOptions = [
        "--memory=${cfg.memory}"
        "--cpus=${cfg.cpus}"
        "--memory-swap=${cfg.memory}"
      ] ++ (lib.optionals cfg.enableGpu gpu.containerOptions);
    };
    
    # Directory creation
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 jellyfin jellyfin -"
      "d ${cfg.dataDir}/config 0755 jellyfin jellyfin -"
      "d ${cfg.cacheDir} 0755 jellyfin jellyfin -"
    ];
    
    # Create jellyfin user and group
    users.users.jellyfin = {
      isSystemUser = true;
      group = "jellyfin";
      uid = 1000;
      extraGroups = lib.optionals cfg.enableGpu [ "video" ];
    };
    
    users.groups.jellyfin = {
      gid = 1000;
    };
    
    # GPU-specific configuration
    systemd.services.jellyfin-gpu-config = lib.mkIf cfg.enableGpu {
      description = "Configure Jellyfin hardware acceleration";
      before = [ "podman-jellyfin.service" ];
      wantedBy = [ "podman-jellyfin.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure Jellyfin config directory exists
        mkdir -p ${cfg.dataDir}/config
        
        # Create optimized encoding.xml for GPU acceleration
        cat > ${cfg.dataDir}/config/encoding.xml << 'ENCODING_EOF'
<?xml version="1.0" encoding="utf-8"?>
<EncodingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <EncodingThreadCount>-1</EncodingThreadCount>
  <EnableFallbackFont>false</EnableFallbackFont>
  <EnableAudioVbr>false</EnableAudioVbr>
  <DownMixAudioBoost>2</DownMixAudioBoost>
  <DownMixStereoAlgorithm>None</DownMixStereoAlgorithm>
  <MaxMuxingQueueSize>2048</MaxMuxingQueueSize>
  <EnableThrottling>false</EnableThrottling>
  <ThrottleDelaySeconds>180</ThrottleDelaySeconds>
  <EnableSegmentDeletion>false</EnableSegmentDeletion>
  <SegmentKeepSeconds>720</SegmentKeepSeconds>
  
  <!-- Enable hardware acceleration based on GPU type -->
  <HardwareAccelerationType>${if gpu.type == "nvidia" then "nvenc" else if gpu.type == "intel" then "vaapi" else "none"}</HardwareAccelerationType>
  
  <EncoderAppPathDisplay>/usr/lib/jellyfin-ffmpeg/ffmpeg</EncoderAppPathDisplay>
  <VaapiDevice>/dev/dri/renderD128</VaapiDevice>
  <QsvDevice />
  <EnableTonemapping>false</EnableTonemapping>
  <EnableVppTonemapping>false</EnableVppTonemapping>
  <EnableVideoToolboxTonemapping>false</EnableVideoToolboxTonemapping>
  <TonemappingAlgorithm>bt2390</TonemappingAlgorithm>
  <TonemappingMode>auto</TonemappingMode>
  <TonemappingRange>auto</TonemappingRange>
  <TonemappingDesat>0</TonemappingDesat>
  <TonemappingPeak>100</TonemappingPeak>
  <TonemappingParam>0</TonemappingParam>
  <VppTonemappingBrightness>16</VppTonemappingBrightness>
  <VppTonemappingContrast>1</VppTonemappingContrast>
  <H264Crf>23</H264Crf>
  <H265Crf>28</H265Crf>
  <EncoderPreset xsi:nil="true" />
  <DeinterlaceDoubleRate>false</DeinterlaceDoubleRate>
  <DeinterlaceMethod>yadif</DeinterlaceMethod>
  <EnableDecodingColorDepth10Hevc>true</EnableDecodingColorDepth10Hevc>
  <EnableDecodingColorDepth10Vp9>true</EnableDecodingColorDepth10Vp9>
  <EnableDecodingColorDepth10HevcRext>false</EnableDecodingColorDepth10HevcRext>
  <EnableDecodingColorDepth12HevcRext>false</EnableDecodingColorDepth12HevcRext>
  
  <!-- GPU-specific settings -->
  <EnableEnhancedNvdecDecoder>${if gpu.type == "nvidia" then "true" else "false"}</EnableEnhancedNvdecDecoder>
  <PreferSystemNativeHwDecoder>true</PreferSystemNativeHwDecoder>
  
  <!-- Intel acceleration settings -->
  <EnableIntelLowPowerH264HwEncoder>${if gpu.type == "intel" then "true" else "false"}</EnableIntelLowPowerH264HwEncoder>
  <EnableIntelLowPowerHevcHwEncoder>${if gpu.type == "intel" then "true" else "false"}</EnableIntelLowPowerHevcHwEncoder>
  
  <!-- Enable hardware encoding -->
  <EnableHardwareEncoding>true</EnableHardwareEncoding>
  
  <!-- Codec support based on GPU type -->
  <AllowHevcEncoding>${if gpu.type == "nvidia" then "true" else "false"}</AllowHevcEncoding>
  <AllowAv1Encoding>false</AllowAv1Encoding>
  
  <EnableSubtitleExtraction>true</EnableSubtitleExtraction>
  
  <!-- Hardware decoding codecs -->
  <HardwareDecodingCodecs>
    <string>h264</string>
    <string>vc1</string>
    <string>hevc</string>
    <string>vp8</string>
    <string>vp9</string>
    <string>mpeg2</string>
    <string>mpeg4</string>
  </HardwareDecodingCodecs>
  
  <AllowOnDemandMetadataBasedKeyframeExtractionForExtensions>
    <string>mkv</string>
  </AllowOnDemandMetadataBasedKeyframeExtractionForExtensions>
</EncodingOptions>
ENCODING_EOF

        # Set proper ownership and permissions
        chown jellyfin:jellyfin ${cfg.dataDir}/config/encoding.xml
        chmod 644 ${cfg.dataDir}/config/encoding.xml
        
        echo "Jellyfin GPU configuration applied successfully"
      '';
    };
    
    # Firewall configuration
    networking.firewall.allowedTCPPorts = [ cfg.port ];
    
    # Health check service
    systemd.services.jellyfin-health = {
      description = "Jellyfin health check";
      after = [ "podman-jellyfin.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}/health";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

