{ config, lib, ... }:

let
  c = config.hwc.home.theme.colors;

  # This helper now returns a list containing a single line of CSS, or an empty list.
  defineColor = name: value:
    if value != null then
      [ "@define-color ${name} #${value};" ]
    else
      [ "/* @define-color ${name} is undefined in palette */" ];
in
{
  options.hwc.home.theme.adapters.waybar.css = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    description = "A string of CSS @define-color variables generated from the active palette.";
  };

  # Instead of one giant string, we now build a list of strings.
  config.hwc.home.theme.adapters.waybar.css =
    let
      # A list of all the CSS lines
      lines =
        [ "/* Generated from the ${c.name or "unnamed"} palette */" ]
        ++ (defineColor "background" (c.bg or null))
        ++ (defineColor "foreground" (c.fg or null))
        ++ (defineColor "accent" (c.accent or null))
        ++ (defineColor "accentAlt" (c.accentAlt or null))
        ++ (defineColor "crit" (c.crit or null))
        ++ (defineColor "error" (c.crit or null))
        ++ (defineColor "warning" (c.warn or null))
        ++ (defineColor "info" (c.info or null))
        ++ (defineColor "success" (c.good or null))
        ++ (defineColor "muted" (c.muted or null))
        ++ (defineColor "color1" (c.ansi.red or null))
        ++ (defineColor "color2" (c.ansi.green or null))
        ++ (defineColor "color3" (c.ansi.yellow or null))
        ++ (defineColor "color4" (c.ansi.blue or null))
        ++ (defineColor "color5" (c.ansi.magenta or null))
        ++ (defineColor "color6" (c.ansi.cyan or null))
        ++ (defineColor "color7" (c.ansi.white or null))
        ++ (defineColor "color8" (c.ansi.brightBlack or null))
        ++ (defineColor "color9" (c.ansi.brightRed or null))
        ++ (defineColor "color10" (c.ansi.brightGreen or null))
        ++ (defineColor "color11" (c.ansi.brightYellow or null))
        ++ (defineColor "color12" (c.ansi.brightBlue or null))
        ++ (defineColor "color13" (c.ansi.brightMagenta or null))
        ++ (defineColor "color14" (c.ansi.brightCyan or null));
    in
    # Use the built-in function `lib.concatStringsSep` to join the list
    # of lines into a single string, separated by newlines.
    lib.concatStringsSep "\n" lines;
}
