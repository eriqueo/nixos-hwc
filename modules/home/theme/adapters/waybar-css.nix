{ config, lib, ... }:
let c = config.hwc.home.theme.colors;
in {
  options.hwc.home.theme.adapters.waybar.css = lib.mkOption {
    type = lib.types.str;
    default = ''
      :root {
        --bg: ${c.bg};
        --fg: ${c.fg};
        --accent: ${c.accent};
        --warn: ${c.warn};
        --crit: ${c.crit};
      }
    '';
    description = "Waybar CSS variables from the active palette.";
  };
}
