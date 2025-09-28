# domains/home/apps/yazi/index.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.yazi;

  # Import the parts as local variables
  keymapConfig = import ./parts/keymap.nix;
  pluginsConfig = import ./parts/plugins.nix;
  themeConfig = import ./parts/theme.nix;

in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      yazi micro ffmpegthumbnailer unzip jq poppler_utils fontpreview
      fd ripgrep fzf zoxide file exiftool imagemagick p7zip
    ];

    xdg.configFile =
      {
        "yazi/yazi.toml" = {
          text = ''
            [manager]
            sort_by = "natural"
            sort_dir_first = true
            mouse_events = [ "click", "scroll" ]
            show_hidden = false
            show_symlink = true
            linemode = "size"
            scrolloff = 5

            [preview]
            max_width = 600
            max_height = 900
            cache_dir = ""
            ueberzug_scale = 1
            ueberzug_offset = [ 0, 0, 0, 0 ]

            [opener]
            edit = [
              { run = 'micro "$@"', block = true, for = "text" },
              { run = 'micro "$@"', block = true, for = "unix" }
            ]
            open = [ { run = 'xdg-open "$@"', desc = "Open" } ]
            extract = [ { run = '7z x -y "$@"', desc = "Extract here (7z)", for = "unix" } ]

            [open]
            prepend_rules = [
              { mime = "application/{zip,gzip,x-7z-compressed,x-xz,x-bzip*,x-rar,x-tar}", use = ["extract"] }
            ]
            rules = [
              { name = "*/", use = [ "open" ] },
              { mime = "text/*", use = [ "edit" ] },
              { mime = "video/*", use = [ "open" ] },
              { mime = "audio/*", use = [ "open" ] },
              { mime = "image/*", use = [ "open" ] },
              { mime = "application/pdf", use = [ "open" ] }
            ]

            [plugin]
            previewers = [
              { name = "*/", run = "folder", sync = true },
              { mime = "text/*", run = "code" },
              { mime = "*/xml", run = "code" },
              { mime = "*/javascript", run = "code" },
              { mime = "*/x-wine-extension-ini", run = "code" },
              { mime = "image/*", run = "image" },
              { mime = "video/*", run = "video" },
              { mime = "application/pdf", run = "pdf" },
              { mime = "application/json", run = "json" }
            ]

            tmtheme = "~/.config/yazi/Kanagawa.tmTheme"
          '';
        };
      }
      // keymapConfig
      // pluginsConfig
      // themeConfig;
  };
}

  #==========================================================================
  # VALIDATION
  #==========================================================================