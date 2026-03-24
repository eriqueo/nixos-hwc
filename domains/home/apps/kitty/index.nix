# domains/home/apps/kitty/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.kitty;
  colors = (config.hwc.home.theme or {}).colors or {};
  appearance = import ./parts/appearance.nix { inherit lib colors; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.kitty = {
    enable = lib.mkEnableOption "Kitty terminal emulator";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    programs.kitty = {
      enable = true;
      package = pkgs.kitty;

      settings = {
        font_family = "CaskaydiaCove Nerd Font";
        font_size = 16;
        enable_audio_bell = false;
        window_padding_width = 4;
        allow_remote_control = true;
        background_opacity = "0.75";
        scrollback_lines = 10000;

        cursor_shape = "block";
        cursor_blink_interval = 0;

        remember_window_size = true;
        initial_window_width = 120;
        initial_window_height = 30;

        tab_bar_edge = "bottom";
        tab_bar_style = "powerline";
        tab_powerline_style = "slanted";

        mouse_hide_wait = 3.0;
        copy_on_select = true;

        # Link ergonomics
        detect_urls = "yes";
        open_url_with = "default";
        clipboard_control = "write-primary write-clipboard no-append";
      } // appearance;

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

      # Mouse mappings not representable via the 'settings' attrset
      # Use extraConfig for raw kitty directives.
      extraConfig = ''
        # Ungrabbed mode: select text or open URLs
        mouse_map left release ungrabbed mouse_click_url_or_select

        # Grabbed mode: pass clicks through to application (aerc, vim, etc.)
        # This allows clicking in aerc's UI to select messages, folders, tabs
        mouse_map left press grabbed mouse_send
        mouse_map left click grabbed mouse_send
        mouse_map left release grabbed mouse_send

        # Double-click inside grabbed apps (aerc) -> send Enter to open items
        mouse_map left doublepress grabbed send_text all "\r"

        # Allow Ctrl+click for URLs even when grabbed
        mouse_map ctrl+left release grabbed,ungrabbed mouse_click_url

      '';

      shellIntegration.enableZshIntegration = true;
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Add dependency assertions here if needed
    ];
  };
}
