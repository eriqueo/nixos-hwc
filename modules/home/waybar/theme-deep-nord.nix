# nixos-hwc/modules/home/waybar/theme-deep-nord.nix
#
# THEME DEEP NORD - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.home.theme-deep-nord.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/home/waybar/theme-deep-nord.nix
#
# USAGE:
#   hwc.home.theme-deep-nord.enable = true;
#   # TODO: Add specific usage examples

''
* {
  font-family: Inter, JetBrains Mono, monospace;
  font-size: 12pt;
}
window#waybar {
  background: rgba(46,52,64,0.7);
  color: #ECEFF4;
}
#battery.warning { color: #EBCB8B; }
#battery.critical { color: #BF616A; }
''
