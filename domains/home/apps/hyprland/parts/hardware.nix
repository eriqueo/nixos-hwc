# HWC Charter Module/domains/home/hyprland/parts/hardware.nix
#
# Hyprland Hardware: Monitor Configuration, Input Settings & Display Management
# Charter v5 compliant - Universal hardware domain for physical device interaction
#
# DEPENDENCIES (Upstream):
#   - None (hardware configuration and control)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let hardware = import ./parts/hardware.nix { inherit lib pkgs; };
#   in { 
#     monitor = hardware.monitor;
#     workspace = hardware.workspace;
#     input = hardware.input;
#   }
#

{ lib, pkgs, osConfig ? {}, ... }:
let
  # Dependencies for scripts
  inherit (pkgs) hyprland jq libnotify;
  # Matched by description: its connector name changes with the port
  # (DP-1 vs DP-2), which silently dropped the 11-18 workspace binding.
  external = "desc:Ancor Communications Inc VG248 E6LMQS027213";
in
{
  #============================================================================
  # MONITOR CONFIGURATION - Exact monolith preservation
  #============================================================================
  monitor = [
    "eDP-1,2560x1600@165,0x0,1"      # Laptop at 0,0 (left)
    "${external},1920x1080@60,2560x0,1"  # External at 2560,0 (right), on any port
    ",preferred,auto,1"              # Any other output goes right of the rest
  ];

  #============================================================================
  # WORKSPACE ASSIGNMENTS - Monitor-specific workspace mapping
  #============================================================================
  workspace = [
    # Monitor ID 0 (eDP-1) gets workspaces 1-8
    "1,monitor:eDP-1"
    "2,monitor:eDP-1"
    "3,monitor:eDP-1"
    "4,monitor:eDP-1"
    "5,monitor:eDP-1"
    "6,monitor:eDP-1"
    "7,monitor:eDP-1"
    "8,monitor:eDP-1"
    
    # The external monitor gets workspaces 11-18
    "11,monitor:${external}"
    "12,monitor:${external}"
    "13,monitor:${external}"
    "14,monitor:${external}"
    "15,monitor:${external}"
    "16,monitor:${external}"
    "17,monitor:${external}"
    "18,monitor:${external}"
  ];

  #============================================================================
  # INPUT CONFIGURATION - Keyboard and touchpad settings
  #============================================================================
  # Per-device overrides: disable on_button_down scroll for the Rival 3 Wireless.
  # libinput marks BTN_MIDDLE as the scroll button and (in wlroots) defaults to
  # on_button_down scroll mode. Any mouse movement during the press suppresses
  # the click — light presses fail because hand tremor triggers scroll mode.
  device = [
    {
      name = "steelseries-steelseries-rival-3-wireless";
      scroll_method = "no_scroll";
      sensitivity = 0.75;
      accel_profile = "flat";
    }
  ];

  input = {
    kb_layout = "us";
    kb_options = "caps:escape_shifted_capslock";  # CapsLock=Esc, Shift+CapsLock=CapsLock
    follow_mouse = 1;
    touchpad = {
      natural_scroll = true;
      scroll_factor = 1.0;
      tap-to-click = true;
      drag_lock = false;
      disable_while_typing = true;
    };
    sensitivity = -0.2;  # -1.0 to 1.0, 0 = no modification. Lowered for better control.
    accel_profile = "flat"; # Disables acceleration for more predictable movement.
  };

  # Tools moved to parts/system.nix for system-wide access
}
