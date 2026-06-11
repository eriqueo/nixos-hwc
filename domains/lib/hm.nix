# domains/lib/hm.nix
#
# Cross-lane helpers for Home Manager modules (Law 1: HM modules must
# evaluate with osConfig = {}; feature-detect NixOS hosts, never assume).
#
# Usage:
#   hmLib = import ../../../lib/hm.nix { inherit lib; };
#   isNixOSHost = hmLib.isNixOSHost osConfig;
#   osCfg       = hmLib.osCfgOr osConfig;
#   assertions  = [ (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "waybar"; }) ];

{ lib }:

rec {
  # True when evaluated inside nixos-rebuild (HM-as-module) on an HWC host.
  isNixOSHost = osConfig: osConfig ? hwc;

  # The system config when on a NixOS host, {} otherwise.
  osCfgOr = osConfig: if isNixOSHost osConfig then osConfig else {};

  # Cross-lane consistency: on NixOS hosts, the matching system-lane app
  # toggle must be on when the HM app is enabled. On non-NixOS hosts the
  # user owns system-lane dependencies, so the check passes.
  sysLaneAssert = { osConfig, enabled, app }: {
    assertion = !enabled
      || !(isNixOSHost osConfig)
      || lib.attrByPath [ "hwc" "system" "apps" app "enable" ] false osConfig;
    message = ''
      hwc.home.apps.${app} is enabled but hwc.system.apps.${app} is not.
      Enable hwc.system.apps.${app} in the machine/role config (system lane).
    '';
  };
}
