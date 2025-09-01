# nixos-hwc/modules/infrastructure/waybar-gpu-tools.nix
#
# WAYBAR GPU TOOLS - GPU monitoring tools for Waybar integration
# Provides hardware monitoring scripts that waybar tools can consume
#
# DEPENDENCIES (Upstream):
#   - config.hwc.gpu.type (modules/infrastructure/gpu.nix)
#   - config.boot.kernelPackages.nvidiaPackages (when GPU type = nvidia)
#
# USED BY (Downstream):
#   - modules/home/waybar/tools/ (consume waybar-gpu-status, waybar-gpu-toggle binaries)
#   - profiles/workstation.nix (enables infrastructure capability)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/infrastructure/waybar-gpu-tools.nix
#
# USAGE:
#   hwc.infrastructure.waybarGpuTools.enable = true;
#   # Provides: waybar-gpu-status, waybar-gpu-toggle binaries

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.waybarGpuTools;
  gpuCfg = config.hwc.gpu;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.infrastructure.waybarGpuTools = {
    enable = lib.mkEnableOption "GPU monitoring tools for Waybar";
    
    toggleNotifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show desktop notifications when GPU mode changes";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    #==========================================================================
    # VALIDATION - Assertions and checks
    #==========================================================================
    assertions = [
      {
        assertion = gpuCfg.type != "none";
        message = "waybar-gpu-tools requires hwc.gpu.type to be set (nvidia/intel/amd)";
      }
    ];

    # Export hardware monitoring tools to system packages
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "waybar-gpu-status" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        GPU_MODE_FILE="/tmp/gpu-mode"
        DEFAULT_MODE="intel"

        if [[ ! -f "$GPU_MODE_FILE" ]]; then
          echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
        fi

        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
        
        ${lib.optionalString (gpuCfg.type == "nvidia") ''
          # NVIDIA-specific monitoring
          if command -v nvidia-smi >/dev/null 2>&1; then
            POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            NVIDIA_INFO="$POWER W | $TEMP°C"
          else
            NVIDIA_INFO="No nvidia-smi"
          fi
        ''}

        case "$CURRENT_MODE" in
          "intel")
            ICON="󰢮"
            CLASS="intel"
            TOOLTIP="Intel Mode: Integrated GPU"
            ;;
          "nvidia")
            ICON="󰾲"
            CLASS="nvidia"
            ${lib.optionalString (gpuCfg.type == "nvidia") ''
              TOOLTIP="NVIDIA Mode: $NVIDIA_INFO"
            ''}
            ;;
          "performance")
            ICON="⚡"
            CLASS="performance"
            ${lib.optionalString (gpuCfg.type == "nvidia") ''
              TOOLTIP="Performance Mode: Auto-GPU Selection | NVIDIA: $NVIDIA_INFO"
            ''}
            ;;
          *)
            ICON="󰢮"
            CLASS="intel"
            TOOLTIP="Intel Mode (Default)"
            ;;
        esac

        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')

      (pkgs.writeShellScriptBin "waybar-gpu-toggle" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        GPU_MODE_FILE="/tmp/gpu-mode"
        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

        case "$CURRENT_MODE" in
          "intel")
            echo "performance" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.toggleNotifications ''
              ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
            ''}
            ;;
          "performance")
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.toggleNotifications ''
              ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
            ''}
            ;;
          *)
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.toggleNotifications ''
              ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
            ''}
            ;;
        esac

        # Refresh waybar
        ${pkgs.procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true
      '')
    ];
  };
}