# /modules/home/apps/waybar/parts/theme.nix

# This is a "part" that adapts the active theme palette into CSS for Waybar.
# It is a simple function that returns a single string of CSS.
# It is imported by the main waybar/index.nix module.

{ config, lib, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # 2. Helper to define a CSS variable.
  defineColor = name: value:
    if value != null then
      [ "--${name}: #${value};" ]
    else
      [ "/* --${name} is undefined in palette */" ];

  # 3. Build a list of all the CSS lines.
  lines =
    [ "/* Generated from the ${c.name or "unnamed"} palette */"
       ]
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
    ++ (defineColor "color14" (c.ansi.brightCyan or null))
    ;

in
# 4. Directly return the final value.
#    Join the list of lines into a single string, separated by newlines.
lib.concatStringsSep "\n" lines

