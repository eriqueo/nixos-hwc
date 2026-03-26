# domains/home/apps/kitty/parts/appearance.nix
# Pure function: palette colors → kitty settings attrset.
# No options, no side-effects.
{ lib, colors }:

let
  C = colors;

  toKitty = colorStr:
    let s = if colorStr == null then "888888" else lib.removePrefix "#" colorStr;
    in "#${s}";

  caretColor =
    if C ? cursorColor then C.cursorColor
    else if C ? caret then C.caret
    else if C ? cursor && builtins.typeOf C.cursor == "string" then C.cursor
    else if C ? accent then C.accent
    else "d5c4a1";

  selectionFg = C.selectionFg or C.bg or "23282d";
  selectionBg = C.selectionBg or C.accent or "cf995f";
  urlColor    = C.link or C.accent2 or C.accent or "0085ba";
in
{
  # Chrome
  foreground = toKitty (C.fg or "d5c4a1");
  background = toKitty (C.bg or "23282d");
  selection_foreground = toKitty selectionFg;
  selection_background = toKitty selectionBg;
  cursor = toKitty caretColor;
  cursor_text_color = toKitty (C.bg or "23282d");
  url_color = toKitty urlColor;

  # ANSI 0–7 (from palette ansi block)
  color0  = toKitty (C.ansi.black   or "282828");
  color1  = toKitty (C.ansi.red     or "cc241d");
  color2  = toKitty (C.ansi.green   or "98971a");
  color3  = toKitty (C.ansi.yellow  or "d79921");
  color4  = toKitty (C.ansi.blue    or "458588");
  color5  = toKitty (C.ansi.magenta or "b16286");
  color6  = toKitty (C.ansi.cyan    or "689d6a");
  color7  = toKitty (C.ansi.white   or "a89984");

  # ANSI 8–15 (from palette ansi block)
  color8  = toKitty (C.ansi.brightBlack   or "928374");
  color9  = toKitty (C.ansi.brightRed     or "fb4934");
  color10 = toKitty (C.ansi.brightGreen   or "b8bb26");
  color11 = toKitty (C.ansi.brightYellow  or "fabd2f");
  color12 = toKitty (C.ansi.brightBlue    or "83a598");
  color13 = toKitty (C.ansi.brightMagenta or "d3869b");
  color14 = toKitty (C.ansi.brightCyan    or "8ec07c");
  color15 = toKitty (C.ansi.brightWhite   or "ebdbb2");
}
