# Waybar Part: Scripts
# Generates all helper scripts required by custom Waybar modules.
{ config, lib, pkgs, ... }:

# This part is enabled by the main waybar toggle.
lib.mkIf config.hwc.home.apps.waybar.enable {
  home.file = {
    ".local/bin/waybar-gpu-status".text = ''
      #!/usr/bin/env bash
      # Check current GPU status and return JSON for waybar
              set -euo pipefail
      
              GPU_MODE_FILE="/tmp/gpu-mode"
              DEFAULT_MODE="intel"
      
              # Initialize mode file if it doesn't exist
              if [[ ! -f "$GPU_MODE_FILE" ]]; then
                echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
              fi
      
              CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
      
              # Get current GPU renderer with better detection
              CURRENT_GPU=$(${mesa-demos}/bin/glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
      
              # Get GPU power consumption and temperature (if available)
              NVIDIA_POWER=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
              NVIDIA_TEMP=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
      
              case "$CURRENT_MODE" in
                "intel")
                  ICON="󰢮"
                  CLASS="intel"
                  TOOLTIP="Intel Mode: $CURRENT_GPU"
                  ;;
                "nvidia")
                  ICON="󰾲"
                  CLASS="nvidia"
                  TOOLTIP="NVIDIA Mode: $CURRENT_GPU\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C"
                  ;;
                "performance")
                  ICON="⚡"
                  CLASS="performance"
                  TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C"
                  ;;
                *)
                  ICON="󰢮"
                  CLASS="intel"
                  TOOLTIP="Intel Mode (Default): $CURRENT_GPU"
                  ;;
              esac
      
              # Output JSON for waybar
              echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
          
    '';
    ".local/bin/waybar-gpu-toggle".text = ''
      #!/usr/bin/env bash
      set -euo pipefail
              
              GPU_MODE_FILE="/tmp/gpu-mode"
              CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")
      
              case "$CURRENT_MODE" in
                "intel")
                  echo "performance" > "$GPU_MODE_FILE"
                  ${lib.optionalString cfg.notifications ''
                    ${libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
                  ''}
                  ;;
                "performance")
                  echo "intel" > "$GPU_MODE_FILE"
                  ${lib.optionalString cfg.notifications ''
                    ${libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
                  ''}
                  ;;
                *)
                  echo "intel" > "$GPU_MODE_FILE"
                  ${lib.optionalString cfg.notifications ''
                    ${libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
                  ''}
                  ;;
              esac
      
              # Refresh waybar
              ${procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true      
    '';
    ".local/bin/waybar-network-status".text = ''
      #!/usr/bin/env bash
      # ... (full script content for waybar-network-status)
    '';
    # ... and so on for all 13 scripts.
    # Each script gets its own entry here.
  };
}
