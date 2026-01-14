# domains/ai/framework/index.nix
#
# AI Framework - Hardware-agnostic, thermal-aware AI system
# Provides unified interface for laptop/server AI workloads with Charter integration

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.framework;

  # Import hardware profiles
  hwProfiles = import ./parts/hardware-profiles.nix { inherit config lib; };

  # Create Charter search tool
  charterSearchTool = pkgs.writeScriptBin "charter-search" (builtins.readFile ./parts/charter-search.sh);

  # Create Ollama wrapper
  ollamaWrapperTool = pkgs.writeScriptBin "ollama-wrapper" (''
    #!${pkgs.bash}/bin/bash
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.gnugrep pkgs.gawk pkgs.libnotify pkgs.lm_sensors charterSearchTool ]}:$PATH"
    export CHARTER_PATH="${cfg.charter.charterPath}"
    export LOG_DIR="${cfg.logging.logDir}"
    export THERMAL_WARNING="${toString (hwProfiles.activeProfile.thermal.warningTemp or cfg.thermal.warningTemp)}"
    export THERMAL_CRITICAL="${toString (hwProfiles.activeProfile.thermal.criticalTemp or cfg.thermal.criticalTemp)}"
    export PROFILE="${hwProfiles.detectedProfile}"
    export VERBOSE="${if cfg.logging.enable then "true" else "false"}"

  '' + builtins.readFile ./parts/ollama-wrapper.sh);

  # Quick wrapper for common tasks
  aiDocTool = pkgs.writeScriptBin "ai-doc" ''
    #!${pkgs.bash}/bin/bash
    # Quick documentation generator using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper doc medium "$@"
  '';

  aiCommitTool = pkgs.writeScriptBin "ai-commit" ''
    #!${pkgs.bash}/bin/bash
    # Quick commit documentation using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper commit small "$@"
  '';

  aiLintTool = pkgs.writeScriptBin "ai-lint" ''
    #!${pkgs.bash}/bin/bash
    # Charter compliance checker using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper lint small "$@"
  '';

  # Grebuild integration script
  grebuildDocsTool = pkgs.writeScript "grebuild-docs" (''
    #!${pkgs.bash}/bin/bash
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.git pkgs.systemd pkgs.util-linux pkgs.libnotify pkgs.nettools ollamaWrapperTool ]}:$PATH"
    export NIXOS_DIR="/home/eric/.nixos"
    export OUTPUT_DIR="/home/eric/.nixos/docs/ai-generated"
    export OLLAMA_ENDPOINT="http://localhost:11434"
    export VERBOSE="false"
  '' + builtins.readFile ./parts/grebuild-docs.sh);

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

    # Install framework tools
    environment.systemPackages = [
      charterSearchTool
      ollamaWrapperTool
      aiDocTool
      aiCommitTool
      aiLintTool
    ] ++ lib.optionals cfg.logging.enable [
      # Add ai-status command when logging is enabled
      (pkgs.writeScriptBin "ai-status" ''
        #!${pkgs.bash}/bin/bash
        ${pkgs.systemd}/bin/systemctl start ai-framework-status.service
        ${pkgs.systemd}/bin/journalctl -u ai-framework-status.service -n 20 --no-pager
      '')
    ];

    # Create log directory
    systemd.tmpfiles.rules = lib.mkIf cfg.logging.enable [
      "d ${cfg.logging.logDir} 0755 eric users -"
    ];

    # Configure Ollama with profile-based limits
    hwc.ai.ollama = {
      # Enable Ollama if framework is enabled
      enable = lib.mkDefault true;

      # Use profile-detected models
      models = lib.mkDefault (
        [
          hwProfiles.activeProfile.models.small
          hwProfiles.activeProfile.models.medium
        ]
        ++ (lib.optional (hwProfiles.detectedProfile != "cpu-only") hwProfiles.activeProfile.models.large)
      );

      # Apply profile-based resource limits
      resourceLimits = {
        enable = true;
        maxCpuPercent = lib.mkDefault hwProfiles.activeProfile.ollama.maxCpuPercent;
        maxMemoryMB = lib.mkDefault hwProfiles.activeProfile.ollama.maxMemoryMB;
        maxRequestSeconds = lib.mkDefault hwProfiles.activeProfile.ollama.maxRequestSeconds;
      };

      # Apply profile-based thermal protection
      thermalProtection = lib.mkIf cfg.thermal.enable {
        enable = true;
        warningTemp = lib.mkDefault hwProfiles.activeProfile.thermal.warningTemp;
        criticalTemp = lib.mkDefault hwProfiles.activeProfile.thermal.criticalTemp;
        checkInterval = lib.mkDefault hwProfiles.activeProfile.thermal.checkInterval;
        cooldownMinutes = lib.mkDefault hwProfiles.activeProfile.thermal.cooldownMinutes;
      };

      # Apply profile-based idle shutdown
      idleShutdown = {
        enable = lib.mkDefault hwProfiles.activeProfile.idle.enable;
        idleMinutes = lib.mkDefault hwProfiles.activeProfile.idle.shutdownMinutes;
        checkInterval = lib.mkDefault hwProfiles.activeProfile.idle.checkInterval;
      };
    };

    # Thermal emergency stop service
    systemd.services.ai-thermal-emergency = lib.mkIf (cfg.thermal.enable && cfg.thermal.emergencyStop) {
      description = "AI Framework - Emergency thermal protection";
      after = [ "podman-ollama.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "ai-thermal-emergency" ''
          #!${pkgs.bash}/bin/bash
          TEMP=$(${pkgs.lm_sensors}/bin/sensors 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E 'Package id 0|CPU:' | ${pkgs.gnugrep}/bin/grep -oP '\+\K[0-9]+' | head -n1 || echo 0)

          if [[ $TEMP -gt ${toString cfg.thermal.criticalTemp} ]]; then
            echo "🚨 Emergency: CPU at ''${TEMP}°C, stopping Ollama"
            ${pkgs.systemd}/bin/systemctl stop podman-ollama.service
            ${pkgs.libnotify}/bin/notify-send "AI Emergency Stop" "CPU critical: ''${TEMP}°C" -u critical || true

            # Log emergency stop
            echo "$(${pkgs.coreutils}/bin/date): Emergency stop at ''${TEMP}°C" >> ${cfg.logging.logDir}/emergency.log
          fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Thermal emergency timer (runs every 10 seconds when Ollama is active)
    systemd.timers.ai-thermal-emergency = lib.mkIf (cfg.thermal.enable && cfg.thermal.emergencyStop) {
      description = "AI Framework - Thermal emergency check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "10s";
        Unit = "ai-thermal-emergency.service";
      };
    };

    # Framework status reporting service
    systemd.services.ai-framework-status = lib.mkIf cfg.logging.enable {
      description = "AI Framework - Status reporter";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "ai-framework-status" ''
          #!${pkgs.bash}/bin/bash
          echo "=== AI Framework Status ==="
          echo "Profile: ${hwProfiles.detectedProfile}"
          echo "Hardware:"
          echo "  - GPU: ${if hwProfiles.hardware.hasGPU then hwProfiles.hardware.gpuType else "none"}"
          echo "  - RAM: ${toString hwProfiles.hardware.totalRAM_GB}GB"
          echo ""
          echo "Active Configuration:"
          echo "  - Models: small=${hwProfiles.activeProfile.models.small}, medium=${hwProfiles.activeProfile.models.medium}, large=${hwProfiles.activeProfile.models.large or "none"}"
          echo "  - CPU Limit: ${toString hwProfiles.activeProfile.ollama.maxCpuPercent}%"
          echo "  - Memory Limit: ${toString hwProfiles.activeProfile.ollama.maxMemoryMB}MB"
          echo "  - Thermal Warning: ${toString hwProfiles.activeProfile.thermal.warningTemp}°C"
          echo "  - Thermal Critical: ${toString hwProfiles.activeProfile.thermal.criticalTemp}°C"
          echo ""

          # Show current temperature
          TEMP=$(${pkgs.lm_sensors}/bin/sensors 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E 'Package id 0|CPU:' | ${pkgs.gnugrep}/bin/grep -oP '\+\K[0-9]+' | head -n1 || echo "unknown")
          echo "Current CPU Temperature: ''${TEMP}°C"
          echo ""

          # Show Ollama status
          if ${pkgs.systemd}/bin/systemctl is-active --quiet podman-ollama.service; then
            echo "Ollama Status: ✅ Running"
          else
            echo "Ollama Status: ⚠️  Stopped"
          fi
        '';
        StandardOutput = "journal";
      };
    };

    # Post-rebuild AI documentation service (grebuild integration)
    systemd.services.post-rebuild-ai-docs = {
      description = "AI Framework - Post-rebuild documentation generator";
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash ${grebuildDocsTool}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.enable -> config.hwc.ai.ollama.enable or true;
        message = "AI framework requires Ollama to be available (hwc.ai.ollama module)";
      }
      {
        assertion = cfg.thermal.warningTemp < cfg.thermal.criticalTemp;
        message = "Thermal warning temperature must be less than critical temperature";
      }
      # Note: Charter path existence checked at runtime by scripts
    ];
  };
}
