# domains/system/packages/iso-tools.nix
# ISO and CD image manipulation tools

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.packages.isoTools;
in
{
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        xorriso      # ISO 9660 + Rock Ridge + Joliet + El Torito manipulation
        cdrtools     # Provides genisoimage, cdrecord, and other CD/DVD tools
      ];
    })

    # Debug warning
    (lib.mkIf cfg.enable {
      warnings = [ "ISO tools module is active (xorriso, cdrtools)" ];
    })
  ];

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # No additional validation needed
}
