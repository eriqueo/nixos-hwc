# domains/lib/hm.nix
#
# Cross-lane helpers for Home Manager modules (Law 1: HM modules must
# evaluate with osConfig = {}; feature-detect NixOS hosts, never assume).
#
# Usage:
#   hmLib = import ../../../lib/hm.nix { inherit lib; };
#   isNixOSHost = hmLib.isNixOSHost osConfig;
#   osCfg       = hmLib.osCfgOr osConfig;
#   fleet       = hmLib.fleet osConfig;      # fleet.ips.main, fleet.fqdn.main
#   assertions  = [ (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "waybar"; }) ];

{ lib }:

rec {
  # True when evaluated inside nixos-rebuild (HM-as-module) on an HWC host.
  isNixOSHost = osConfig: osConfig ? hwc;

  # The system config when on a NixOS host, {} otherwise.
  osCfgOr = osConfig: if isNixOSHost osConfig then osConfig else {};

  # Fleet addressing for HM modules, read from hwc.networking.hosts when hosted
  # on NixOS. Law 1 forces a literal fallback for standalone HM (osConfig = {}),
  # so THIS FILE is deliberately the single HM-lane copy of these values — the
  # system lane's copy is the registry's own option defaults. Two producers, one
  # per lane, both greppable; not one per consumer, which is what turned a
  # routine re-registration into a four-file breakage on 2026-08-12.
  #
  # If you are adding a third copy somewhere else, that is the bug.
  fleet = osConfig: {
    ips = lib.attrByPath [ "hwc" "networking" "hosts" "ips" ] {
      main = "100.77.195.118";
      xps  = "100.126.80.42";
    } osConfig;

    fqdn = lib.attrByPath [ "hwc" "networking" "hosts" "fqdn" ] {
      main = "hwc-server.ocelot-wahoo.ts.net";
      xps  = "hwc-xps.ocelot-wahoo.ts.net";
    } osConfig;
  };

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
