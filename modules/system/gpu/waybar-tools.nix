# nixos-hwc/modules/system/gpu/waybar-tools.nix
#
# WAYBAR TOOLS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.waybar-tools.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/system/gpu/waybar-tools.nix
#
# USAGE:
#   hwc.system.waybar-tools.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  drv = lib.getAttrFromPath [ "boot" "kernelPackages" "nvidiaPackages" "stable" ] config or null;
  nvsmi = if drv != null then "${drv}/bin/nvidia-smi" else "nvidia-smi";
  waybarGpuStatus = pkgs.writeShellScriptBin "waybar-gpu-status" ''
    set -euo pipefail
    icon="󰾲"; cls="nvidia"; tooltip="GPU"; power="0"; temp="0"
    if command -v ${nvsmi} >/dev/null 2>&1; then
      power="$(${nvsmi} --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
      temp="$(${nvsmi} --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
      tooltip="NVIDIA • ${power}W • ${temp}°C"
    else
      icon="󰢮"; cls="no-gpu"; tooltip="No NVIDIA tools"
    fi
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$icon" "$cls" "$tooltip"
  '';
  waybarGpuToggle = pkgs.writeShellScriptBin "waybar-gpu-toggle" ''
    set -euo pipefail
    f="/tmp/gpu-mode"
    cur="$(cat "$f" 2>/dev/null || echo performance)"
    next=$([[ "$cur" = performance ]] && echo powersave || echo performance)
    echo "$next" > "$f"
    pkill -SIGUSR1 waybar 2>/dev/null || true
  '';
in {
  environment.systemPackages = [ waybarGpuStatus waybarGpuToggle ];
}
