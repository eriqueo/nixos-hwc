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

let cfg = config.features.chromium or { enable = false; };
in {
  options.features.chromium.enable =
    lib.mkEnableOption "Enable Chromium (user-scoped)";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.chromium ];
    # If you want chromium flags later:
    # xdg.desktopEntries.chromium.settings = { ... };
  };
}
    # Future: Add universal domain parts
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
    # session = import ./parts/session.nix { inherit lib pkgs config; };  
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
