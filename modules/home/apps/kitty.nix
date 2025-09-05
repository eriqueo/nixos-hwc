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
      # Background and foreground
      foreground = palette.fg;
      background = palette.bg;
      selection_foreground = palette.fg;
      selection_background = palette.accent;
      cursor = palette.accent;
      cursor_text_color = palette.bg;
      url_color = palette.accent;
      
      # Normal colors (0-7)
      color0 = "#45403d";   # black (gruvbox material dark0)
      color1 = palette.crit; # red
      color2 = palette.good; # green
      color3 = palette.warn; # yellow
      color4 = palette.accent; # blue (teal)
      color5 = "#d3869b"; # magenta (gruvbox material)
      color6 = palette.accentAlt; # cyan (green)
      color7 = palette.fg;   # white
      
      # Bright colors (8-15)
      color8 = palette.muted; # bright black
      color9 = "#ea6962";   # bright red (gruvbox material)
      color10 = "#a9b665";  # bright green (gruvbox material)  
      color11 = "#d8a657";  # bright yellow (gruvbox material)
      color12 = "#7daea3";  # bright blue (matches accent)
      color13 = "#d3869b";  # bright magenta
      color14 = "#89b482";  # bright cyan (matches accentAlt)
      color15 = "#d4be98";  # bright white (gruvbox material fg)
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