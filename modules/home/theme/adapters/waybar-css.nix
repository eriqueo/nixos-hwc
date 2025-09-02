# nixos-hwc/modules/home/theme/adapters/waybar-css.nix
#
# Theme Adapter: Palette → Waybar CSS Variables
# Charter v4 compliant - Pure data transformation for Waybar theming
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#
# USED BY (Downstream):
#   - modules/home/waybar/theme-deep-nord.nix (in PR 2)
#
# USAGE:
#   let palette = import ../palettes/deep-nord.nix {};
#   in import ./waybar-css.nix { inherit palette; }
#

{ palette }:
''
  :root {
    --bg: ${palette.bg};
    --bg-alt: ${palette.bgAlt};
    --bg-dark: ${palette.bgDark};
    --fg: ${palette.fg};
    --muted: ${palette.muted};
    --accent: ${palette.accent};
    --accent-alt: ${palette.accentAlt};
    --good: ${palette.good};
    --warn: ${palette.warn};
    --crit: ${palette.crit};
  }
  
  * {
    font-family: Inter, JetBrains Mono, monospace;
    font-size: 12pt;
  }
  
  window#waybar {
    background: rgba(46,52,64,0.7);
    color: var(--fg);
  }
  
  #battery.warning { color: var(--warn); }
  #battery.critical { color: var(--crit); }
''