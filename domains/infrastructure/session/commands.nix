# modules/infrastructure/session/commands.nix
#
# Shared CLI commands for cross-app integration
# Provides system-wide commands like gpu-launch that both HM and system can use
#
# DEPENDENCIES (Upstream):
#   - config.hwc.infrastructure.hardware.gpu.* (GPU acceleration info)
#
# USED BY (Downstream):
#   - modules/home/apps/hyprland (keybinds can use gpu-launch)
#   - modules/home/apps/waybar (can call gpu-launch in click actions)
#
# USAGE:
#   hwc.infrastructure.session.commands.enable = true;
#   hwc.infrastructure.session.commands.gpuLaunch = true;  # Enable gpu-launch command

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.session.commands;
in {
  #============================================================================
  # OPTIONS - Shared CLI Commands Configuration
  #============================================================================

  options.hwc.infrastructure.session.commands = {
    enable = lib.mkEnableOption "shared CLI commands for cross-app integration";

    gpuLaunch = lib.mkEnableOption "gpu-launch command for GPU-accelerated app launching";
  };

  #============================================================================
  # IMPLEMENTATION - Shared Command Helpers
  #============================================================================

  config = lib.mkIf cfg.enable {
    # GPU launch helper (placeholder for future implementation)
    environment.systemPackages = lib.optionals cfg.gpuLaunch [
      # Future: actual gpu-launch implementation
      # For now, this is a placeholder to maintain compatibility
    ];

    # Future: Other shared CLI commands can be added here
    # - network helpers
    # - storage helpers  
    # - service integration commands
  };
}