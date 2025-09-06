# Waybar CSS Theme Adapter (v6)
# - Reads active palette from config.hwc.home.theme.colors
# - Exports a string of CSS variables for Waybar theming.
#
# Usage in HM:
#   imports = [ ../modules/home/theme/adapters/waybar-css.nix ];
#   ...
#   let cssVars = config.hwc.home.theme.adapters.waybar.css;
#   in { xdg.configFile."waybar/style.css".text = cssVars + '' ... ''; }

{ config, lib, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # Helper function to generate a @define-color line.
  # It gracefully handles missing colors from the palette.
  defineColor = name: value:
    if value != null then
      "@define-color ${name} #${value};"
    else
      "/* @define-color ${name} is undefined in palette */";
in
{
  # 2. Define a formal option to provide the generated CSS to the system.
  options.hwc.home.theme.adapters.waybar.css = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    description = "A string of CSS @define-color variables generated from the active palette.";
  };

  # 3. Set the value of the option by transforming the palette into CSS.
  config.hwc.home.theme.adapters.waybar.css = ''
    /* Generated from the ${c.name or "unnamed"} palette */
    ${defineColor "background" c.bg}
    ${defineColor "foreground" c.fg}
    ${defineColor "accent" c.accent}
    ${defineColor "accentAlt" c.accentAlt}
    ${defineColor "crit" c.crit}
    ${defineColor "error" c.warn}
    ${defineColor "warning" c.warning}
    ${defineColor "info" c.info}
    ${defineColor "success" c.success}
    ${defineColor "muted" c.muted}
    ${defineColor "color1" c.color1}
    ${defineColor "color2" c.color2}
    ${defineColor "color3" c.color3}
    ${defineColor "color4" c.color4}
    ${defineColor "color5" c.color5}
    ${defineColor "color6" c.color6}
    ${defineColor "color7" c.color7}
    ${defineColor "color8" c.color8}
    ${defineColor "color9" c.color9}
    ${defineColor "color10" c.color10}
    ${defineColor "color11" c.color11}
    ${defineColor "color12" c.color12}
    ${defineColor "color13" c.color13}
    ${defineColor "color14" c.color14}
  '';
}
