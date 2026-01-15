# domains/ai/framework/index.nix
#
# AI Framework - Hardware-agnostic, thermal-aware AI system
# Provides unified interface for laptop/server AI workloads with Charter integration

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.framework;

  npuEnabled = cfg.npu.enable;

  pythonNpuEnv = pkgs.python312.withPackages (ps: [
    ps.openvino
    ps.huggingface-hub
  ]);

  aiNpuTool = pkgs.writeShellScriptBin "ai-npu" ''
    #!/usr/bin/env bash
    set -euo pipefail

    VERBOSE="''${VERBOSE:-false}"
    MODEL_DIR="''${HWC_NPU_MODEL_DIR:-${cfg.npu.modelDir}}"

    log_debug() {
      [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $*" >&2 || true
    }

    if [[ ! -d "$MODEL_DIR" ]]; then
      echo "NPU model directory missing: $MODEL_DIR" >&2
      exit 1
    fi

    # Read full prompt from stdin
    prompt=$(cat)
    if [[ -z "$prompt" ]]; then
      echo "No prompt provided on stdin" >&2
      exit 1
    fi

    # Run inference with OpenVINO GenAI
    MODEL_DIR="$MODEL_DIR" ${pythonNpuEnv}/bin/python - "$@" <<'PY'
import os
import sys

try:
    from openvino_genai import LLMPipeline, GenerationConfig
except Exception as exc:  # pragma: no cover - runtime safety
    print(f"Failed to import OpenVINO GenAI: {exc}", file=sys.stderr)
    sys.exit(1)

MODEL_DIR = os.environ.get("MODEL_DIR")
PROMPT = sys.stdin.read()

if not MODEL_DIR:
    print("MODEL_DIR not set", file=sys.stderr)
    sys.exit(1)

try:
    pipeline = LLMPipeline(MODEL_DIR, device="NPU")
except Exception as exc:  # pragma: no cover
    print(f"Failed to load model at {MODEL_DIR}: {exc}", file=sys.stderr)
    sys.exit(1)

config = GenerationConfig(
    max_new_tokens=1024,
    temperature=0.7,
    top_p=0.9,
    do_sample=True,
)

try:
    for token in pipeline.generate(PROMPT, generation_config=config, stream=True):
        sys.stdout.write(token)
        sys.stdout.flush()
except Exception as exc:  # pragma: no cover
    print(f"NPU inference failed: {exc}", file=sys.stderr)
    sys.exit(1)

sys.stdout.write("\n")
sys.stdout.flush()
PY
  '';

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
    export NPU_ENABLED="${if cfg.npu.enable then "true" else "false"}"
    export AI_NPU_BIN="${aiNpuTool}/bin/ai-npu"
    export HWC_NPU_MODEL_DIR="${cfg.npu.modelDir}"

  '' + builtins.readFile ./parts/ollama-wrapper.sh);

  # Quick wrapper for common tasks
  aiDocTool = pkgs.writeScriptBin "ai-doc" ''
    #!${pkgs.bash}/bin/bash
    # Quick documentation generator using ollama-wrapper
    if [[ "''${1:-}" == "--npu" ]]; then
      export AI_FORCE_NPU=true
      shift
    fi
    ${ollamaWrapperTool}/bin/ollama-wrapper doc medium "$@"
  '';

  aiCommitTool = pkgs.writeScriptBin "ai-commit" ''
    #!${pkgs.bash}/bin/bash
    # Quick commit documentation using ollama-wrapper
    if [[ "''${1:-}" == "--npu" ]]; then
      export AI_FORCE_NPU=true
      shift
    fi
    ${ollamaWrapperTool}/bin/ollama-wrapper commit small "$@"
  '';

  aiLintTool = pkgs.writeScriptBin "ai-lint" ''
    #!${pkgs.bash}/bin/bash
    # Charter compliance checker using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper lint small "$@"
  '';

  npuModelDownload = pkgs.writeShellScript "ai-npu-download" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODEL_ID="${cfg.npu.modelId}"
    MODEL_DIR="${cfg.npu.modelDir}"
    CLI=${pkgs.python312Packages.huggingface-hub}/bin/huggingface-cli

    mkdir -p "$MODEL_DIR"

    if [[ -f "$MODEL_DIR/config.json" || -f "$MODEL_DIR/model_index.json" ]]; then
      echo "NPU model already present in $MODEL_DIR"
      exit 0
    fi

    echo "Downloading NPU model ${cfg.npu.modelId} -> $MODEL_DIR"
    export HF_HUB_ENABLE_HF_TRANSFER=0
    export HF_HUB_DISABLE_HF_TRANSFER=1
    export HF_HUB_DISABLE_TELEMETRY=1
    "$CLI" download \
      "$MODEL_ID" \
      --local-dir "$MODEL_DIR" \
      --local-dir-use-symlinks False \
      --resume-download
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

    boot.kernelModules = lib.mkIf cfg.npu.enable (lib.mkAfter [ "intel_vpu" ]);
    boot.initrd.kernelModules = lib.mkIf cfg.npu.enable (lib.mkAfter [ "intel_vpu" ]);
    hardware.firmware = lib.mkIf cfg.npu.enable (lib.mkAfter [
      pkgs.linux-firmware
    ]);

    # Install framework tools
    environment.systemPackages = [
      charterSearchTool
      ollamaWrapperTool
      aiDocTool
      aiCommitTool
      aiLintTool
    ] ++ lib.optionals cfg.npu.enable [
      pkgs.openvino
      pythonNpuEnv
      pkgs.python312Packages.huggingface-hub
      aiNpuTool
    ] ++ lib.optionals cfg.logging.enable [
      # Add ai-status command when logging is enabled
      (pkgs.writeScriptBin "ai-status" ''
        #!${pkgs.bash}/bin/bash
        ${pkgs.systemd}/bin/systemctl start ai-framework-status.service
        ${pkgs.systemd}/bin/journalctl -u ai-framework-status.service -n 20 --no-pager
      '')
    ];

    # Create log and model directories
    systemd.tmpfiles.rules =
      lib.optionals cfg.logging.enable [
        "d ${cfg.logging.logDir} 0755 eric users -"
      ]
      ++ lib.optionals cfg.npu.enable [
        "d ${cfg.npu.modelDir} 0755 eric users -"
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
          if ${if cfg.npu.enable then "true" else "false"}; then
            if ls /dev/accel* >/dev/null 2>&1; then
              echo "  - NPU: detected ($(ls /dev/accel* 2>/dev/null | tr '\n' ' '))"
            else
              echo "  - NPU: enabled but not detected (/dev/accel* missing)"
            fi
            echo ""
            echo "Tier-0 NPU:"
            if dmesg | ${pkgs.gnugrep}/bin/grep -q "intel_vpu.*Firmware:.*vpu_37xx_v0.0.bin"; then
              echo "  - Firmware: Loaded (37xx blob)"
            elif dmesg | ${pkgs.gnugrep}/bin/grep -q "Failed to request firmware: -2"; then
              echo "  - Firmware: MISSING/MISMATCHED (probe failed -2)"
              echo "    -> Run: lspci -nn | grep -i npu (identify generation)"
              echo "    -> If Lunar Lake, switch firmware to vpu_40xx_v0.0.bin"
            else
              echo "  - Firmware: Status unknown (check: dmesg | grep -i vpu)"
            fi
            if [ -d "${cfg.npu.modelDir}" ]; then
              echo "  - Model cache: ${cfg.npu.modelDir}"
            else
              echo "  - Model cache: missing (${cfg.npu.modelDir})"
            fi
          else
            echo "  - NPU: disabled"
          fi
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

    # NPU model cache (downloaded once)
    systemd.services.ai-npu-model = lib.mkIf cfg.npu.enable {
      description = "AI Framework - NPU model cache";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [
          "HWC_NPU_MODEL_DIR=${cfg.npu.modelDir}"
          "HF_HUB_ENABLE_HF_TRANSFER=0"
          "HF_HUB_DISABLE_HF_TRANSFER=1"
          "HF_HUB_DISABLE_TELEMETRY=1"
        ];
        ExecStart = npuModelDownload;
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
