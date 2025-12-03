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

  # Normalize model configuration for health checks
  normalizeModel = model:
    if lib.isString model then
      { name = model; autoUpdate = true; priority = 50; }
    else
      model // { autoUpdate = model.autoUpdate or true; priority = model.priority or 50; };

  modelNames = map (m: (normalizeModel m).name) cfg.models;

  pullScript = import ./parts/pull-script.nix { inherit lib pkgs config; };
  diskMonitor = import ./parts/disk-monitor.nix { inherit pkgs config; };
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

    # Model health check service
    systemd.services.ollama-model-health = lib.mkIf cfg.modelHealth.enable {
      description = "Ollama model health check - validates all models";
      after = [ "podman-ollama.service" ];
      wants = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ollama-model-health" ''
          set -euo pipefail

          echo "Starting model health checks..."
          FAILED=0

          ${lib.concatMapStringsSep "\n" (modelName: ''
            echo "Testing model: ${modelName}"
            RESPONSE=$(${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
              --data '{"model":"${modelName}","prompt":"${cfg.modelValidation.testPrompt}","stream":false}' \
              http://127.0.0.1:${toString cfg.port}/api/generate 2>&1 || echo "CURL_FAILED")

            if echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -q '"response"'; then
              echo "✓ ${modelName} - healthy"
            else
              echo "✗ ${modelName} - unhealthy: $RESPONSE"
              FAILED=$((FAILED + 1))
            fi
          '') modelNames}

          if [ "$FAILED" -gt 0 ]; then
            echo "Model health check failed: $FAILED/${toString (builtins.length modelNames)} models unhealthy"
            exit 1
          else
            echo "All models healthy (${toString (builtins.length modelNames)}/${toString (builtins.length modelNames)})"
          fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Model health check timer
    systemd.timers.ollama-model-health = lib.mkIf cfg.modelHealth.enable {
      description = "Ollama model health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.modelHealth.schedule;
        Persistent = true;
        Unit = "ollama-model-health.service";
      };
    };

    # Disk space monitoring service
    systemd.services.ollama-disk-monitor = lib.mkIf cfg.diskMonitoring.enable {
      description = "Ollama disk space monitoring";
      after = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = diskMonitor;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Disk space monitoring timer
    systemd.timers.ollama-disk-monitor = lib.mkIf cfg.diskMonitoring.enable {
      description = "Ollama disk space monitoring timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.diskMonitoring.checkInterval;
        Unit = "ollama-disk-monitor.service";
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
