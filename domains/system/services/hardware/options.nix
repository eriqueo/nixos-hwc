{ lib, ... }:

{
  options.hwc.system.services.hardware = {
    # Master toggle
    enable = lib.mkEnableOption "Enable all hardware-related services (audio, input, monitoring)";

    # Sub-modules
    keyboard.enable = lib.mkEnableOption "Enable universal keyboard mapping (keyd)";
    audio.enable    = lib.mkEnableOption "Enable PipeWire audio system and portals";
    monitoring.enable = lib.mkEnableOption "Enable hardware monitoring tools (sensors, smartctl, etc.)";
  };
}
