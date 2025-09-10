# KITTY TERMINAL - Terminal emulator configuration with theme integration
# Charter v6 compliant - Single-file app config with proper theming.
# This version is refactored to correctly handle the "pure data" palette.

{ config, lib, pkgs, ... }:

let
  # 1. Read the active color palette from the central config location.
  #    This is more robust than a direct file import.
  c = config.hwc.home.theme.colors;
  cfg = config.features.kitty;
  # 2. Define a "smart" helper function to format colors for Kitty.
  #    It ensures the color code is always prefixed with a '#'.
  toKitty = colorStr:
    if colorStr == null then "#888888" # Fallback for missing colors
    else "#" + (lib.removePrefix "#" colorStr);

in
{
 options.features.kitty.enable =
    lib.mkEnableOption "Enable the Kitty terminal emulator";

  #============================================================================
  # IMPLEMENTATION - Kitty terminal configuration
  #============================================================================
  config = lib.mkIf cfg.enable {
  programs.kitty = {
    enable = true;
    package = pkgs.kitty;

    settings = {
      # --- Font configuration ---
      font_family = "CaskaydiaCove Nerd Font";
      font_size = 16;

      # --- Performance and behavior ---
      enable_audio_bell = false;
      window_padding_width = 4;
      background_opacity = "0.95";

      # --- Scrollback and history ---
      scrollback_lines = 10000;

      # --- Cursor configuration ---
      cursor_shape = "block";
      cursor_blink_interval = 0;  # No blinking

      # --- Window configuration ---
      remember_window_size = true;
      initial_window_width = 120;
      initial_window_height = 30;

      # --- Tab configuration ---
      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";

      # --- Mouse configuration ---
      mouse_hide_wait = 3.0;
      copy_on_select = true;

      # --- Theme Integration: Deep Nord Colors (using the `toKitty` helper) ---
      # Background/foreground
      foreground = toKitty c.fg;
      background = toKitty c.bg;
      selection_foreground = toKitty c.selectionFg;
      selection_background = toKitty c.selectionBg;
      cursor = toKitty c.cursor;
      cursor_text_color = toKitty c.bg; # Often set to background color
      url_color = toKitty c.link;

      # Normal (0–7)
      color0  = toKitty c.ansi.black;
      color1  = toKitty c.crit;
      color2  = toKitty c.good;
      color3  = toKitty c.warn;
      color4  = toKitty c.accent;
      color5  = toKitty (c.ansi.magenta or c.accentAlt);
      color6  = toKitty c.accentAlt;
      color7  = toKitty c.fg;

      # Bright (8–15)
      color8  = toKitty c.ansi.brightBlack;
      color9  = toKitty (c.ansi.brightRed or c.crit);
      color10 = toKitty (c.ansi.brightGreen or c.good);
      color11 = toKitty (c.ansi.brightYellow or c.warn);
      color12 = toKitty (c.ansi.brightBlue or c.accent);
      color13 = toKitty (c.ansi.brightMagenta or (c.ansi.magenta or c.accentAlt));
      color14 = toKitty (c.ansi.brightCyan or c.accentAlt);
      color15 = toKitty (c.ansi.brightWhite or c.fg);
    };

    # --- Key bindings (unchanged) ---
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

    # --- Shell integration (unchanged) ---
    shellIntegration.enableZshIntegration = true;
  };
  };
}
