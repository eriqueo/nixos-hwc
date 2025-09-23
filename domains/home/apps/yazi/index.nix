# domains/home/apps/yazi/index.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.yazi;
in
{
  imports = [
    ./options.nix
    ./parts/keymap.nix
    ./parts/plugins.nix
    ./parts/theme.nix
  ];

  config = lib.mkIf cfg.enable {
    # Install Yazi and all its dependencies/plugins
    home.packages = with pkgs; [
      yazi ffmpegthumbnailer unzip jq poppler_utils fontpreview
      fd ripgrep fzf zoxide file exiftool imagemagick
    ];

    # Define the main yazi.toml and import the other parts
    xdg.configFile = {
      "yazi/yazi.toml" = {
        text = ''
          [mgr]
          sort_by = "natural"
          sort_dir_first = true
          mouse_events = [ "click", "scroll" ]
          show_hidden = false
          show_symlink = true
          linemode = "size"
          scrolloff = 5
          
          [prv]
          max_width = 600
          max_height = 900
          cache_dir = ""
          ueberzug_scale = 1
          ueberzug_offset = [ 0, 0, 0, 0 ]
          
          [opener]
          edit = [
            { run = 'nvim "$@"', block = true, for = "text" },
            { run = 'nvim "$@"', block = true, for = "unix" },
          ]
          play = [
            { run = 'mpv "$@"', orphan = true, for = "video" },
            { run = 'mpv "$@"', orphan = true, for = "audio" },
          ]
          open = [
            { run = 'xdg-open "$@"', desc = "Open" },
          ]
          
          [open]
          rules = [
            { name = "*/", use = [ "edit", "open" ] },
            { mime = "text/*", use = [ "edit" ] },
            { mime = "video/*", use = [ "play" ] },
            { mime = "audio/*", use = [ "play" ] },
            { mime = "image/*", use = [ "open" ] },
            { mime = "application/pdf", use = [ "open" ] },
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
            { mime = "application/json", run = "json" },
          ]
          
          # Use the Kanagawa tmTheme for syntax highlighting
          tmtheme = "~/.config/yazi/Kanagawa.tmTheme"
        '';
      };
    };
  };
}
