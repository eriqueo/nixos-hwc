# nixos-hwc/modules/home/apps/chromium/index.nix
#
# Home UI: Chromium Browser Configuration
# Charter v7 compliant - Web browser configuration with universal domains
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

{
  options.features.chromium.enable = 
    lib.mkEnableOption "Enable Chromium browser (HM)";

  config = lib.mkIf (config.features.chromium.enable or false) {
    home.packages = with pkgs; [
      chromium
    ];

    # Future: Add universal domain parts
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
    # session = import ./parts/session.nix { inherit lib pkgs config; };  
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  };
}