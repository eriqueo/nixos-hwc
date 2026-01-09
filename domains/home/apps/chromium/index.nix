# HWC Charter Module/domains/home/apps/chromium/index.nix
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

{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.chromium;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;
in {
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.chromium ];
    # If you want chromium flags later:
    # xdg.desktopEntries.chromium.settings = { ... };

    # Future: Add universal domain parts
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
    # session = import ./parts/session.nix { inherit lib pkgs config; };
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      {
        assertion = !cfg.enable || !isNixOSHost || lib.attrByPath [ "hwc" "system" "apps" "chromium" "enable" ] false osConfig;
        message = ''
          hwc.home.apps.chromium is enabled but hwc.system.apps.chromium is not.
          System integration (dconf, dbus) is required for chromium.
          Enable hwc.system.apps.chromium in machine config.
        '';
      }
    ];
  };
}
