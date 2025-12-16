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
        # Quieter curve with a wide idle band; last entry is a safety handoff to firmware
        default = [
          [ 0             0   60 ]
          [ 1            58   70 ]
          [ 2            62   76 ]
          [ 3            68   82 ]
          [ 5            74   88 ]
          [ "level auto" 86 32767 ]
        ];
        description = "Thinkfan level table (value, lower temp C, upper temp C).";
      };
    };
  };
}
