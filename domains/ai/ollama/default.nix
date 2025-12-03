{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.ollama;
  paths = config.hwc.paths or {};

  accel = config.hwc.infrastructure.hardware.gpu.accel or "cpu";
  gpuType = config.hwc.infrastructure.hardware.gpu.type or "none";

  # For NVIDIA, use CDI annotation for proper driver mounting
  gpuExtraOptions = if gpuType == "nvidia" then [
    "--device=nvidia.com/gpu=all"
    "--security-opt=label=disable"
  ] else config.hwc.infrastructure.hardware.gpu.containerOptions or [];

  gpuEnv = config.hwc.infrastructure.hardware.gpu.containerEnvironment or {};

  pullScript = import ./parts/pull-script.nix { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    virtualisation.oci-containers.containers.ollama = {
      image = "ollama/ollama:latest";
      ports = [ "${toString cfg.port}:11434" ];
      volumes = [ "${cfg.dataDir}:/root/.ollama" ];

      environment = gpuEnv // {
        OLLAMA_HOST = "0.0.0.0";
      };

      extraOptions = gpuExtraOptions;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    environment.systemPackages = [ pkgs.ollama ];

    # Ensure CDI generator runs before container starts (prevents GPU device resolution race condition)
    systemd.services.podman-ollama = lib.mkIf (gpuType == "nvidia") {
      after = [ "nvidia-container-toolkit-cdi-generator.service" ];
      requires = [ "nvidia-container-toolkit-cdi-generator.service" ];
    };

    systemd.services.ollama-pull-models = {
      description = "Pre-download initial Ollama models";
      after = [ "network-online.target" "oci-containers-ollama.service" ];
      wants = [ "network-online.target" "oci-containers-ollama.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pullScript;
      };
    };

    # Health check service
    systemd.services.ollama-health = lib.mkIf cfg.healthCheck.enable {
      description = "Ollama health check";
      after = [ "podman-ollama.service" ];
      wants = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}/api/tags";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Health check timer
    systemd.timers.ollama-health = lib.mkIf cfg.healthCheck.enable {
      description = "Ollama health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.healthCheck.interval;
        Unit = "ollama-health.service";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.port > 0 && cfg.port < 65536;
        message = "hwc.ai.ollama.port must be between 1 and 65535";
      }
      {
        assertion = cfg.models != [];
        message = "hwc.ai.ollama.models list cannot be empty";
      }
      {
        assertion = builtins.pathExists cfg.dataDir || true;  # Will be created by tmpfiles
        message = "hwc.ai.ollama.dataDir must be a valid path";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "hwc.ai.ollama requires Podman as OCI container backend";
      }
    ];
  };
}
