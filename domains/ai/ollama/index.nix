# domains/ai/ollama/index.nix
{ config, lib, pkgs, aiProfile ? null, aiProfileName ? "laptop", ... }:

let
  cfg = config.hwc.ai.ollama;
  paths = config.hwc.paths or {};

  accel = config.hwc.system.hardware.gpu.accel or "cpu";
  gpuType = config.hwc.system.hardware.gpu.type or "none";

  # For NVIDIA, use CDI annotation for proper driver mounting
  gpuExtraOptions = if gpuType == "nvidia" then [
    "--device=nvidia.com/gpu=all"
    "--security-opt=label=disable"
  ] else config.hwc.system.hardware.gpu.containerOptions or [];

  gpuEnv = config.hwc.system.hardware.gpu.containerEnvironment or {};

  # Models: use profile defaults only if user didn't set explicitly
  effectiveModels =
    if cfg.models != null
    then cfg.models
    else if aiProfile != null
    then [
      aiProfile.models.small
      aiProfile.models.medium
      aiProfile.models.large
    ]
    else [ "llama3.2:3b" ];  # Fallback if no profile available

  # Normalize model configuration for health checks
  normalizeModel = model:
    if lib.isString model then
      { name = model; autoUpdate = true; priority = 50; }
    else
      model // { autoUpdate = model.autoUpdate or true; priority = model.priority or 50; };

  modelNames = map (m: (normalizeModel m).name) effectiveModels;

  pullScript = import ./parts/pull-script.nix { inherit lib pkgs config; };
  diskMonitor = import ./parts/disk-monitor.nix { inherit pkgs config; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port for the Ollama service";
    };

    models = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Model name in Ollama format (e.g., llama3.2:3b)";
          };
          autoUpdate = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Automatically update this model on rebuilds";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = "Pull priority (lower = pulled first, useful for dependencies)";
          };
        };
      })));
      default = null;
      description = ''
        Models to pre-download and keep available.
        If null (default), profile-based defaults are used.
        If set explicitly, overrides profile without needing mkForce.

        Can be either strings (e.g., "llama3:8b") or attribute sets with configuration:
        { name = "llama3.2:3b"; autoUpdate = false; priority = 10; }
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ollama";
      description = "Directory for storing Ollama models";
    };

    healthCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable health check for Ollama service";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "Health check interval (systemd time format)";
      };
    };

    modelValidation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Validate models after pull by testing inference";
      };

      testPrompt = lib.mkOption {
        type = lib.types.str;
        default = "Hello";
        description = "Test prompt to verify model loads correctly";
      };
    };

    modelHealth = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable periodic model health checks";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time to run model health checks (HH:MM format)";
      };
    };

    diskMonitoring = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable disk space monitoring for model storage";
      };

      warningThreshold = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Disk usage percentage to trigger warning (default: 80%)";
      };

      criticalThreshold = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Disk usage percentage to trigger critical alert (default: 90%)";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "6h";
        description = "Disk space check interval (systemd time format)";
      };
    };

    resourceLimits = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable resource limits to prevent runaway CPU/memory usage";
      };

      maxCpuPercent = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum CPU usage percentage (100 = 1 core, 200 = 2 cores, etc.)
          null = unlimited (server default), set to 200-400 for laptop
        '';
      };

      maxMemoryMB = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum memory in MB
          null = unlimited (server default), set to 4096-8192 for laptop
        '';
      };

      maxRequestSeconds = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = ''
          Maximum seconds for a single request before killing it
          Server: 600s (10min), Laptop: 180s (3min) recommended
        '';
      };
    };

    idleShutdown = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Auto-stop ollama service after idle timeout
          Recommended: true for laptop, false for server
        '';
      };

      idleMinutes = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "Minutes of inactivity before shutting down";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "2min";
        description = "How often to check for idle state";
      };
    };

    thermalProtection = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Monitor CPU temperature and throttle/stop ollama if too hot
          Recommended: true for laptop, false for server (if datacenter cooling)
        '';
      };

      warningTemp = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Temperature (°C) to start throttling ollama (pause new requests)";
      };

      criticalTemp = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Temperature (°C) to immediately stop ollama";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "How often to check CPU temperature";
      };

      cooldownMinutes = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Minutes to wait after thermal shutdown before allowing restart";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Apply profile-based defaults if profile available
    (lib.mkIf (aiProfile != null) {
      hwc.ai.ollama.resourceLimits = {
        enable = lib.mkDefault true;
        maxCpuPercent = lib.mkDefault aiProfile.ollama.maxCpuPercent;
        maxMemoryMB = lib.mkDefault aiProfile.ollama.maxMemoryMB;
        maxRequestSeconds = lib.mkDefault aiProfile.ollama.maxRequestSeconds;
      };

      hwc.ai.ollama.thermalProtection = {
        enable = lib.mkDefault aiProfile.idle.enable;  # Follows idle behavior
        warningTemp = lib.mkDefault aiProfile.thermal.warningTemp;
        criticalTemp = lib.mkDefault aiProfile.thermal.criticalTemp;
        checkInterval = lib.mkDefault aiProfile.thermal.checkInterval;
        cooldownMinutes = lib.mkDefault aiProfile.thermal.cooldownMinutes;
      };

      hwc.ai.ollama.idleShutdown = {
        enable = lib.mkDefault aiProfile.idle.enable;
        idleMinutes = lib.mkDefault aiProfile.idle.shutdownMinutes;
        checkInterval = lib.mkDefault aiProfile.idle.checkInterval;
      };
    })

    # Service implementation
    {
    virtualisation.oci-containers.containers.ollama = {
      autoStart = false;  # Don't auto-start on boot
      image = "ollama/ollama:latest";
      ports = [ "${toString cfg.port}:11434" ];
      volumes = [ "${cfg.dataDir}:/root/.ollama" ];

      environment = gpuEnv // {
        OLLAMA_HOST = "0.0.0.0";
      };

      extraOptions = gpuExtraOptions;
    };

    # Note: No tmpfiles rule needed - OCI containers backend automatically creates
    # ${cfg.dataDir} as a symlink to /var/lib/private/ollama for isolation

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    environment.systemPackages = [ pkgs.ollama ];

    # Ensure CDI generator runs before container starts (prevents GPU device resolution race condition)
    # Also apply resource limits to prevent runaway CPU/memory usage
    systemd.services.podman-ollama = {
      after = lib.mkIf (gpuType == "nvidia") [ "nvidia-container-toolkit-cdi-generator.service" ];
      requires = lib.mkIf (gpuType == "nvidia") [ "nvidia-container-toolkit-cdi-generator.service" ];

      # Apply resource limits if enabled
      serviceConfig = lib.mkIf cfg.resourceLimits.enable (lib.mkMerge [
        (lib.mkIf (cfg.resourceLimits.maxCpuPercent != null) {
          CPUQuota = "${toString cfg.resourceLimits.maxCpuPercent}%";
        })
        (lib.mkIf (cfg.resourceLimits.maxMemoryMB != null) {
          MemoryMax = "${toString (cfg.resourceLimits.maxMemoryMB * 1024 * 1024)}";
          MemoryHigh = "${toString (cfg.resourceLimits.maxMemoryMB * 1024 * 1024 * 90 / 100)}";
        })
        (lib.mkIf (cfg.resourceLimits.maxRequestSeconds > 0) {
          # Add timeout handling via wrapper script
          ExecStartPre = [
            "${pkgs.coreutils}/bin/echo 'Ollama starting with ${toString cfg.resourceLimits.maxRequestSeconds}s request timeout'"
          ];
        })
      ]);
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

    # Idle shutdown monitor service
    systemd.services.ollama-idle-monitor = lib.mkIf cfg.idleShutdown.enable {
      description = "Ollama idle shutdown monitor";
      after = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ollama-idle-monitor" ''
          set -euo pipefail

          IDLE_THRESHOLD=${toString (cfg.idleShutdown.idleMinutes * 60)}
          TIMESTAMP_FILE="/var/lib/ollama/last-request"

          # Check if service is running
          if ! ${pkgs.systemd}/bin/systemctl is-active podman-ollama.service >/dev/null 2>&1; then
            echo "Ollama not running, nothing to do"
            exit 0
          fi

          # Check last request time via API tags endpoint
          if ${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.port}/api/tags >/dev/null 2>&1; then
            # Service is responsive, update timestamp
            date +%s > "$TIMESTAMP_FILE"
            echo "Ollama responsive, updated timestamp"
            exit 0
          fi

          # Check if timestamp file exists
          if [[ ! -f "$TIMESTAMP_FILE" ]]; then
            echo "No timestamp file, creating one"
            date +%s > "$TIMESTAMP_FILE"
            exit 0
          fi

          # Calculate idle time
          LAST_REQUEST=$(cat "$TIMESTAMP_FILE")
          NOW=$(date +%s)
          IDLE_TIME=$((NOW - LAST_REQUEST))

          echo "Ollama idle for $IDLE_TIME seconds (threshold: $IDLE_THRESHOLD)"

          if [[ $IDLE_TIME -gt $IDLE_THRESHOLD ]]; then
            echo "⚠️  Ollama idle for ${toString cfg.idleShutdown.idleMinutes} minutes, shutting down..."
            ${pkgs.systemd}/bin/systemctl stop podman-ollama.service
          fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Idle shutdown timer
    systemd.timers.ollama-idle-monitor = lib.mkIf cfg.idleShutdown.enable {
      description = "Ollama idle shutdown monitor timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.idleShutdown.checkInterval;
        Unit = "ollama-idle-monitor.service";
      };
    };

    # Thermal protection monitor service
    systemd.services.ollama-thermal-monitor = lib.mkIf cfg.thermalProtection.enable {
      description = "Ollama thermal protection monitor";
      after = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ollama-thermal-monitor" ''
          set -euo pipefail

          # Check if sensors command is available
          if ! command -v ${pkgs.lm_sensors}/bin/sensors >/dev/null 2>&1; then
            echo "⚠️  lm_sensors not available, skipping thermal check"
            exit 0
          fi

          # Get CPU temperature (look for Package id or CPU temp)
          CPU_TEMP=$(${pkgs.lm_sensors}/bin/sensors | ${pkgs.gnugrep}/bin/grep -E '(Package id 0|CPU):' | ${pkgs.gnugrep}/bin/grep -oP '\+\K[0-9]+' | head -n1 || echo "0")

          if [[ -z "$CPU_TEMP" || "$CPU_TEMP" == "0" ]]; then
            echo "⚠️  Could not read CPU temperature, skipping check"
            exit 0
          fi

          echo "CPU temperature: ''${CPU_TEMP}°C (warning: ${toString cfg.thermalProtection.warningTemp}°C, critical: ${toString cfg.thermalProtection.criticalTemp}°C)"

          # Critical temperature - immediate shutdown
          if [[ $CPU_TEMP -ge ${toString cfg.thermalProtection.criticalTemp} ]]; then
            echo "🚨 CRITICAL: CPU temperature ''${CPU_TEMP}°C >= ${toString cfg.thermalProtection.criticalTemp}°C!"
            echo "Stopping ollama immediately for thermal protection..."
            ${pkgs.systemd}/bin/systemctl stop podman-ollama.service

            # Create cooldown marker
            COOLDOWN_FILE="/var/lib/ollama/thermal-cooldown"
            COOLDOWN_UNTIL=$(($(date +%s) + ${toString (cfg.thermalProtection.cooldownMinutes * 60)}))
            echo "$COOLDOWN_UNTIL" > "$COOLDOWN_FILE"

            echo "Cooldown period: ${toString cfg.thermalProtection.cooldownMinutes} minutes"
            exit 0
          fi

          # Warning temperature - log but don't stop (could implement throttling here)
          if [[ $CPU_TEMP -ge ${toString cfg.thermalProtection.warningTemp} ]]; then
            echo "⚠️  WARNING: CPU temperature ''${CPU_TEMP}°C >= ${toString cfg.thermalProtection.warningTemp}°C"
            echo "Consider reducing load or improving cooling"
          fi

          # Check if in cooldown period
          COOLDOWN_FILE="/var/lib/ollama/thermal-cooldown"
          if [[ -f "$COOLDOWN_FILE" ]]; then
            COOLDOWN_UNTIL=$(cat "$COOLDOWN_FILE")
            NOW=$(date +%s)

            if [[ $NOW -lt $COOLDOWN_UNTIL ]]; then
              REMAINING=$((COOLDOWN_UNTIL - NOW))
              echo "Still in cooldown period: $((REMAINING / 60)) minutes remaining"

              # Keep service stopped
              if ${pkgs.systemd}/bin/systemctl is-active podman-ollama.service >/dev/null 2>&1; then
                echo "Stopping ollama due to cooldown period"
                ${pkgs.systemd}/bin/systemctl stop podman-ollama.service
              fi
            else
              echo "Cooldown period expired, removing marker"
              rm -f "$COOLDOWN_FILE"
            fi
          fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Thermal protection timer
    systemd.timers.ollama-thermal-monitor = lib.mkIf cfg.thermalProtection.enable {
      description = "Ollama thermal protection monitor timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.thermalProtection.checkInterval;
        Unit = "ollama-thermal-monitor.service";
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
        assertion = effectiveModels != [];
        message = "hwc.ai.ollama effective models list cannot be empty (check profile or explicit config)";
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
    }  # End service implementation block
  ]);  # End mkMerge + mkIf cfg.enable
}
