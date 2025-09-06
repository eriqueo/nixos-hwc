# Waybar CSS Theme Adapter (v6 - Synchronized)
# - Reads the specific palette from config.hwc.home.theme.colors
# - Maps the palette's semantic names (bg, fg, ansi.red) to Waybar's
#   generic CSS variables (@background, @color1, etc.).

{ config, lib, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # Helper function to generate a @define-color line.
  # It now uses `or` to provide a default fallback and prevent errors.
  defineColor = name: value:
    let
      # Use the provided value or fallback to a safe default grey.
      finalValue = value or "888888";
    in
      "@define-color ${name} #${finalValue};";
in
{
  # 2. Define the formal option (this part is correct).
  options.hwc.home.theme.adapters.waybar.css = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    description = "A string of CSS @define-color variables generated from the active palette.";
  };

  # 3. Set the value of the option by correctly mapping the palette to CSS.
  config.hwc.home.theme.adapters.waybar.css = ''
    /* Generated from the ${c.name or "unnamed"} palette */
    ${defineColor "background" c.bg}
    ${defineColor "foreground" c.fg}
    ${defineColor "accent" c.accent}
    ${defineColor "accentAlt" c.accentAlt}
    ${defineColor "crit" c.crit}
    ${defineColor "error" c.crit}  # Mapping 'error' to your 'crit' color
    ${defineColor "warning" c.warn}
    ${defineColor "info" c.info}
    ${defineColor "success" c.good}
    ${defineColor "muted" c.muted}

    /*
     * Mapping the generic colorN variables to your ANSI color set.
     * This provides a consistent terminal-like color scheme for Waybar modules.
     */
    ${defineColor "color1" (c.ansi.red or null)}
    ${defineColor "color2" (c.ansi.green or null)}
    ${defineColor "color3" (c.ansi.yellow or null)}
    ${defineColor "color4" (c.ansi.blue or null)}
    ${defineColor "color5" (c.ansi.magenta or null)}
    ${defineColor "color6" (c.ansi.cyan or null)}
    ${defineColor "color7" (c.ansi.white or null)}
    ${defineColor "color8" (c.ansi.brightBlack or null)}
    ${defineColor "color9" (c.ansi.brightRed or null)}
    ${defineColor "color10" (c.ansi.brightGreen or null)}
    ${defineColor "color11" (c.ansi.brightYellow or null)}
    ${defineColor "color12" (c.ansi.brightBlue or null)}
    ${defineColor "color13" (c.ansi.brightMagenta or null)}
    ${defineColor "color14" (c.ansi.brightCyan or null)}
  '';
}
