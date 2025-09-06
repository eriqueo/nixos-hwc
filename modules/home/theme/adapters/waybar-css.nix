# Waybar CSS Theme Adapter (v6 - Synchronized & Syntactically Correct)
# - Reads the specific palette from config.hwc.home.theme.colors
# - Maps the palette's semantic names to Waybar's CSS variables.

{ config, lib, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # Helper function to generate a @define-color line.
  # It now uses the correct Nix syntax for default values.
  defineColor = name: value:
    # The `or` keyword can only be used when accessing an attribute.
    # Since `value` is passed as an argument, we check if it's null instead.
    let
      finalValue = if value == null then "888888" else value;
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
  #    We use the `or null` pattern here to safely pass values to the helper.
  #    If a color doesn't exist, `null` is passed, and the helper provides the fallback.
  config.hwc.home.theme.adapters.waybar.css = ''
    /* Generated from the ${c.name or "unnamed"} palette */
    ${defineColor "background" (c.bg or null)}
    ${defineColor "foreground" (c.fg or null)}
    ${defineColor "accent" (c.accent or null)}
    ${defineColor "accentAlt" (c.accentAlt or null)}
    ${defineColor "crit" (c.crit or null)}
    ${defineColor "error" (c.crit or null)}  # Mapping 'error' to your 'crit' color
    ${defineColor "warning" (c.warn or null)}
    ${defineColor "info" (c.info or null)}
    ${defineColor "success" (c.good or null)}
    ${defineColor "muted" (c.muted or null)}

    /*
     * Mapping the generic colorN variables to your ANSI color set.
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
