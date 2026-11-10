{ lib, pkgs, osConfig ? {}, workspacePlan ? rec {
  slots = lib.range 1 8;
  externalOffset = 10;
  externalSlots = map (slot: slot + externalOffset) slots;
}, ... }:
let
  # Matched by description: its connector name changes with the port
  # (DP-1 vs DP-2), which silently dropped the 11-18 workspace binding.
  external = "desc:Ancor Communications Inc VG248 E6LMQS027213";
in
{
  inherit workspacePlan;

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
  workspace = map (slot: "${toString slot},monitor:eDP-1") workspacePlan.slots
    ++ map (slot: "${toString slot},monitor:${external}") workspacePlan.externalSlots;

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
