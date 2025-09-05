# nixos-hwc/modules/home/hyprland/parts/session.nix
#
# Hyprland Session: Autostart Configuration & Session Management
# Charter v5 compliant - Universal session domain for lifecycle management
#
# DEPENDENCIES (Upstream):
#   - config.hwc.infrastructure.gpu.enable (for gpu-launch integration)
#   - systemPackages for basic tools (pkgs.jq, pkgs.procps, etc.)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let session = import ./parts/session.nix { inherit lib pkgs; };
#   in { exec-once = session.execOnce; }
#

{ lib, pkgs, ... }:
let
  # Dependencies for scripts
  inherit (pkgs) hyprland procps libnotify jq coreutils gawk lm_sensors systemd;
in
{
  #============================================================================
  # AUTOSTART APPLICATIONS - Session initialization
  #============================================================================
  execOnce = [
    # "hyprland-startup"  # Disabled - was launching apps to specific workspaces
    "hyprpaper"           # Wallpaper manager
    "wl-paste --type text --watch cliphist store"    # Text clipboard history
    "wl-paste --type image --watch cliphist store"   # Image clipboard history
  ];

  # Tools moved to parts/system.nix for system-wide access
}