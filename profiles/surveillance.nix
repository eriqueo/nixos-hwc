# profiles/surveillance.nix - Surveillance Profile
#
# Charter v3 Surveillance Configuration Profile
# Provides home security and monitoring via Frigate NVR
#
# DEPENDENCIES:
#   Upstream: profiles/base.nix (core system configuration)
#   Upstream: profiles/infrastructure.nix (GPU support)
#
# USED BY:
#   Downstream: machines/hwc-server.nix (production server)
#
# IMPORTS REQUIRED IN:
#   - machines/hwc-server.nix: ../../profiles/surveillance.nix
#
# USAGE:
#   Provides complete surveillance environment with:
#   - Frigate NVR with GPU acceleration
#   - MQTT broker (Mosquitto) for camera communication
#   - Storage management for recordings
#
# VALIDATION:
#   - Requires GPU hardware acceleration (NVIDIA)
#   - Requires network access to IP cameras

{ lib, pkgs, config, ... }: {

  #============================================================================
  # SURVEILLANCE DOMAIN IMPORTS
  #============================================================================
  
  # Note: Surveillance domain needs to be created in domains/server/surveillance/
  # For now, we'll configure services directly in this profile
  # TODO: Migrate to domains/server/surveillance/ following charter structure

  #============================================================================
  # MQTT BROKER (Mosquitto)
  #============================================================================
  
  services.mosquitto = {
    enable = true;
    listeners = [{
      address = "127.0.0.1";
      port = 1883;
      acl = [ "pattern readwrite #" ];
      omitPasswordAuth = true;
      settings.allow_anonymous = true;
    }];
  };

  #============================================================================
  # FRIGATE NVR CONTAINER
  #============================================================================
  
  # Frigate requires a container setup with GPU access
  # This will be migrated to domains/server/surveillance/frigate.nix
  
  virtualisation.oci-containers.containers.frigate = {
    image = "ghcr.io/blakeblackshear/frigate:stable";
    
    volumes = [
      "/opt/surveillance/frigate/config:/config"
      "/opt/surveillance/frigate/media:/media/frigate"
      "/etc/localtime:/etc/localtime:ro"
    ];
    
    environment = {
      NVIDIA_VISIBLE_DEVICES = "all";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      FRIGATE_MQTT_HOST = "127.0.0.1";
      FRIGATE_MQTT_PORT = "1883";
    };
    
    extraOptions = [
      "--network=host"
      "--privileged"
      "--shm-size=256m"
      "--device=/dev/dri/card0:/dev/dri/card0"
      "--device=/dev/dri/renderD128:/dev/dri/renderD128"
      "--device=/dev/nvidia0:/dev/nvidia0"
      "--device=/dev/nvidiactl:/dev/nvidiactl"
      "--device=/dev/nvidia-modeset:/dev/nvidia-modeset"
      "--device=/dev/nvidia-uvm:/dev/nvidia-uvm"
      "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools"
    ];
  };

  #============================================================================
  # FRIGATE CONFIGURATION GENERATOR
  #============================================================================
  
  systemd.services.frigate-config = {
    description = "Generate Frigate configuration";
    wantedBy = [ "podman-frigate.service" ];
    before = [ "podman-frigate.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /opt/surveillance/frigate/config
      mkdir -p /opt/surveillance/frigate/media
      
      # Create base Frigate configuration
      # Note: This should be customized per deployment
      cat > /opt/surveillance/frigate/config/config.yaml << 'EOF'
mqtt:
  enabled: true
  host: 127.0.0.1
  port: 1883

detectors:
  tensorrt:
    type: tensorrt
    device: 0

ffmpeg:
  hwaccel_args:
    - -hwaccel
    - nvdec
    - -hwaccel_device
    - "0"
    - -hwaccel_output_format
    - nv12

# Camera configuration should be added here
# See old config for camera examples
cameras: {}
EOF
    '';
  };

  #============================================================================
  # SYSTEM PACKAGES
  #============================================================================
  
  environment.systemPackages = with pkgs; [
    ffmpeg
    mosquitto
  ];

  #============================================================================
  # FIREWALL CONFIGURATION
  #============================================================================
  
  networking.firewall.allowedTCPPorts = [
    5000  # Frigate web interface
    1883  # MQTT (local only, but opened for flexibility)
  ];
  
  networking.firewall.allowedUDPPorts = [
    8555  # Frigate WebRTC
  ];

  #============================================================================
  # STORAGE DIRECTORIES
  #============================================================================
  
  systemd.tmpfiles.rules = [
    "d /opt/surveillance 0755 root root -"
    "d /opt/surveillance/frigate 0755 root root -"
    "d /opt/surveillance/frigate/config 0755 root root -"
    "d /opt/surveillance/frigate/media 0755 root root -"
  ];

  #============================================================================
  # ASSERTIONS AND VALIDATION
  #============================================================================
  
  assertions = [
    {
      assertion = config.hwc.infrastructure.hardware.gpu.enable or false;
      message = "Surveillance profile requires GPU acceleration for Frigate. Enable hwc.infrastructure.hardware.gpu.enable";
    }
  ];
}

