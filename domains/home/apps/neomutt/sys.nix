# modules/home/apps/neomutt/sys.nix
#
# System lane wiring for neomutt.
# Charter v7: co-located sys.nix files for system dependencies

{ lib, config, pkgs, ... }:

let
  # Check if home options are available (they might not be during system-only imports)
  cfg = lib.attrByPath ["hwc" "home" "apps" "neomutt"] { enable = false; } config;
in {
  config = lib.mkIf cfg.enable {
    # Minimal system dependencies for neomutt
    # Most dependencies are handled in Home Manager

    # No specific system packages needed for neomutt
    # Mail transport handled by msmtp/isync in Home Manager
  };
}
