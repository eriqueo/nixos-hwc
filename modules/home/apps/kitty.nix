# nixos-hwc/modules/home/apps/kitty.nix
#
# KITTY TERMINAL - Terminal emulator configuration with theme integration
# Charter v6 compliant - Single-file app config with proper theming
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#   - modules/home/theme/palettes/deep-nord.nix (color theming)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports this module)
#   - modules/home/apps/hyprland/parts/behavior.nix (SUPER+Return keybinding)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../modules/home/apps/kitty.nix ]
#
# USAGE:
#   programs.kitty.enable = true;  # Enabled by default when imported

{ config, lib, pkgs, ... }:

let
  # Import theme colors for consistent theming
  palette = import ../theme/palettes/deep-nord.nix {};
in
{
  #============================================================================
  # IMPLEMENTATION - Kitty terminal configuration
  #============================================================================
  programs.kitty = {
    enable = true;
    package = pkgs.kitty;
    
    settings = {
      # Font configuration
      font_family = "CaskaydiaCove Nerd Font";
      font_size = 16;
      
      # Performance and behavior
      enable_audio_bell = false;
      window_padding_width = 4;
      background_opacity = "0.95";
      
      # Scrollback and history
      scrollback_lines = 10000;
      
      # Cursor configuration
      cursor_shape = "block";
      cursor_blink_interval = 0;  # No blinking
      
      # Window configuration
      remember_window_size = true;
      initial_window_width = 120;
      initial_window_height = 30;
      
      # Tab configuration
      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      
      # Mouse configuration
      mouse_hide_wait = 3.0;
      copy_on_select = true;
      
      # --- Theme Integration: Deep Nord Colors ---
 # Background/foreground
      foreground = palette.fg;
      background = palette.bg;
      selection_foreground = palette.selectionFg;     # better contrast on selection
      selection_background = palette.selectionBg;
      cursor = palette.cursor;
      cursor_text_color = palette.bg;
      url_color = palette.link;

      # Normal (0–7)
      color0  = palette.ansi.black;     # black
      color1  = palette.crit;       # red
      color2  = palette.good;       # green
      color3  = palette.warn;       # yellow
      color4  = palette.accent;     # blue-ish (your teal)
      color5  = palette.magenta or palette.accentAlt;  # choose one token from palette
      color6  = palette.accentAlt;  # cyan-ish
      color7  = palette.fg;         # white

      # Bright (8–15)
      color8  = palette.ansi.brightBlack;      # bright black
      color9  = palette.critBright or palette.crit;
      color10 = palette.goodBright or palette.good;
      color11 = palette.warnBright or palette.warn;
      color12 = palette.accentBright or palette.accent;
      color13 = palette.magentaBright or (palette.magenta or palette.accentAlt);
      color14 = palette.accentAltBright or palette.accentAlt;
      color15 = palette.fgBright or palette.fg;
    };
    
    # Key bindings
    keybindings = {
      # Basic clipboard operations
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      
      # Tab management
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      
      # Window management  
      "ctrl+shift+n" = "new_window";
      "ctrl+shift+q" = "close_window";
      
      # Font size adjustment
      "ctrl+plus" = "change_font_size all +2.0";
      "ctrl+minus" = "change_font_size all -2.0";
      "ctrl+0" = "change_font_size all 0";
      
      # Scrolling
      "ctrl+shift+up" = "scroll_line_up";
      "ctrl+shift+down" = "scroll_line_down";
      "ctrl+shift+page_up" = "scroll_page_up";
      "ctrl+shift+page_down" = "scroll_page_down";
      "ctrl+shift+home" = "scroll_home";
      "ctrl+shift+end" = "scroll_end";
    };
    
    # Shell integration
    shellIntegration.enableZshIntegration = true;
  };
  
  # Package provided by system base-packages.nix - configuration only here
}
