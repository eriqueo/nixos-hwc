# modules/home/apps/kitty/index.nix
# Adapter: palette -> Kitty config (HM module, no systemd)
{ config, lib, pkgs, ... }:

let
  # Palette resolver: support both {colors = {...}} and flat tokens.
  T = config.hwc.home.theme or {};
  C = T.colors or T;

  # Ensure # prefix for Kitty colors
  toKitty = colorStr:
    let s = if colorStr == null then "888888" else lib.removePrefix "#" colorStr;
    in "#${s}";

# Safe caret color resolution (no 'or' misuse)
caretColor =
  if T ? cursorColor then T.cursorColor
  else if C ? cursorColor then C.cursorColor
  else if C ? caret then C.caret
  else if C ? cursor && builtins.typeOf C.cursor == "string" then C.cursor
  else if C ? accent then C.accent
  else "7daea3";
  
selectionFg = if C ? selectionFg then C.selectionFg else (if C ? bg then C.bg else "2e3440");
selectionBg = if C ? selectionBg then C.selectionBg else (if C ? accent then C.accent else "7daea3");
urlColor    = if C ? link then C.link else (if C ? accent2 then C.accent2 else (if C ? accent then C.accent else "7daea3"));

in
{
  imports = [ ./options.nix ];
  config = lib.mkIf (config.hwc.home.apps.kitty.enable or false) {
    programs.kitty = {
      enable = true;
      package = pkgs.kitty;

      settings = {
        # Fonts / behavior
        font_family = "CaskaydiaCove Nerd Font";
        font_size = 16;
        enable_audio_bell = false;
        window_padding_width = 4;
        background_opacity = "0.95";
        scrollback_lines = 10000;

        # Cursor (caret)
        cursor_shape = "block";
        cursor_blink_interval = 0;

        # Window
        remember_window_size = true;
        initial_window_width = 120;
        initial_window_height = 30;

        # Tabs
        tab_bar_edge = "bottom";
        tab_bar_style = "powerline";
        tab_powerline_style = "slanted";

        # Mouse
        mouse_hide_wait = 3.0;
        copy_on_select = true;

        # Theme from palette
        foreground = toKitty (C.fg or "ECEFF4");
        background = toKitty (C.bg or "2e3440");
        selection_foreground = toKitty selectionFg;
        selection_background = toKitty selectionBg;
        cursor = toKitty caretColor;
        cursor_text_color = toKitty (C.bg or "2e3440");
        url_color = toKitty urlColor;

        # ANSI 0–7
        color0  = toKitty (C.ansi.black   or "45403d");
        color1  = toKitty (C.crit         or C.ansi.red     or "BF616A");
        color2  = toKitty (C.good         or C.ansi.green   or "A3BE8C");
        color3  = toKitty (C.warn         or C.ansi.yellow  or "EBCB8B");
        color4  = toKitty (C.accent       or C.ansi.blue    or "7daea3");
        color5  = toKitty (C.ansi.magenta or C.accentAlt    or "d3869b");
        color6  = toKitty (C.accentAlt    or C.ansi.cyan    or "89b482");
        color7  = toKitty (C.fg           or C.ansi.white   or "ECEFF4");

        # ANSI 8–15
        color8  = toKitty (C.ansi.brightBlack   or C.muted or "4C566A");
        color9  = toKitty (C.ansi.brightRed     or C.crit  or "ea6962");
        color10 = toKitty (C.ansi.brightGreen   or C.good  or "a9b665");
        color11 = toKitty (C.ansi.brightYellow  or C.warn  or "d8a657");
        color12 = toKitty (C.ansi.brightBlue    or C.accent or "7daea3");
        color13 = toKitty (C.ansi.brightMagenta or C.ansi.magenta or C.accentAlt or "d3869b");
        color14 = toKitty (C.ansi.brightCyan    or C.accentAlt    or "89b482");
        color15 = toKitty (C.ansi.brightWhite   or C.fg           or "d4be98");
      };

      keybindings = {
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
        "ctrl+shift+t" = "new_tab";
        "ctrl+shift+w" = "close_tab";
        "ctrl+shift+right" = "next_tab";
        "ctrl+shift+left" = "previous_tab";
        "ctrl+shift+n" = "new_window";
        "ctrl+shift+q" = "close_window";
        "ctrl+plus" = "change_font_size all +2.0";
        "ctrl+minus" = "change_font_size all -2.0";
        "ctrl+0" = "change_font_size all 0";
        "ctrl+shift+up" = "scroll_line_up";
        "ctrl+shift+down" = "scroll_line_down";
        "ctrl+shift+page_up" = "scroll_page_up";
        "ctrl+shift+page_down" = "scroll_page_down";
        "ctrl+shift+home" = "scroll_home";
        "ctrl+shift+end" = "scroll_end";
      };

      shellIntegration.enableZshIntegration = true;
    };
  };
}
