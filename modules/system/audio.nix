# nixos-hwc/modules/system/audio.nix
#
# AUDIO SYSTEM - PipeWire audio server configuration  
# Modern audio server with ALSA/PulseAudio compatibility for workstations
#
# DEPENDENCIES (Upstream):
#   - None (base system services)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.system.audio.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/system/audio.nix
#
# USAGE:
#   hwc.system.audio.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.audio;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.system.audio = {
    enable = lib.mkEnableOption "PipeWire audio system";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Real-time kit for audio processing
    security.rtkit.enable = true;
    
    # PipeWire audio server
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    
    # XDG portal configuration (for desktop integration)
    xdg.portal.config.common.default = "*";  # Keep < 1.17 behavior for compatibility
  };
}