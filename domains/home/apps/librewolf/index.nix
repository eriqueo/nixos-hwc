# HWC Charter Module/domains/home/apps/librewolf/index.nix
#
# Home UI: LibreWolf Browser Configuration  
# Charter v7 compliant - Privacy-focused Firefox fork configuration with universal domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#   Universal domains: behavior.nix (keybindings/shortcuts), session.nix (services), appearance.nix (styling)

{ lib, pkgs, config, ... }:

let cfg = config.hwc.home.apps.librewolf or { enable = false; };
in {
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.librewolf ];
  };
}
    # Future: Add universal domain parts
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
    # session = import ./parts/session.nix { inherit lib pkgs config; };  
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };

  #==========================================================================
  # VALIDATION
  #==========================================================================