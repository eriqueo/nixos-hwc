# NEW file: domains/system/services/hardware/options.nix
{ lib, config, ... }:

{
  options.hwc.system.services.hardware = {
    # The master switch for all hardware-related services.
    enable = lib.mkEnableOption "Enable hardware services (input, audio, monitoring)";

    # We can keep these as simple toggles. They are clear roles.
    keyboard.enable = lib.mkEnableOption "Enable universal keyboard mapping (keyd)";
    audio.enable = lib.mkEnableOption "Enable PipeWire audio system";

    # We can add a new option for hardware monitoring tools.
    monitoring.enable = lib.mkEnableOption "Enable hardware monitoring tools (sensors, etc.)";
  };
}
