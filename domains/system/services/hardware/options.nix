{ lib, ... }:

let
  t = lib.types;
in {
  options.hwc.system.services.hardware = {
    # Master toggle
    enable = lib.mkEnableOption "Enable all hardware-related services (audio, input, monitoring)";

    # Sub-modules
    keyboard.enable = lib.mkEnableOption "Enable universal keyboard mapping (keyd)";
    audio.enable    = lib.mkEnableOption "Enable PipeWire audio system and portals";
    bluetooth.enable = lib.mkEnableOption "Enable Bluetooth support";
    monitoring.enable = lib.mkEnableOption "Enable hardware monitoring tools (sensors, smartctl, etc.)";

    fanControl = {
      enable = lib.mkEnableOption "Enable ThinkPad fan control via thinkfan";

      levels = lib.mkOption {
        type = t.listOf (t.listOf (t.either t.int t.str));
        # Smooth fan curve with gradual ramp-up to reduce thermal cycling
        default = [
          [ 0             0   55 ]   # Silent zone
          [ 1            53   62 ]   # Gentle ramp
          [ 2            60   68 ]   # Gradual increase
          [ 3            66   74 ]   # Medium cooling
          [ 4            72   80 ]   # Higher cooling (eliminates jump to level 5)
          [ 5            78   88 ]   # Maximum manual control
          [ "level auto" 86 32767 ]  # Emergency firmware handoff
        ];
        description = "Thinkfan level table (value, lower temp C, upper temp C).";
      };
    };
  };
}
