# domains/home/apps/yazi/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.yazi;

  tomlConfig   = import ./parts/toml.nix;
  keymapConfig = import ./parts/keymap.nix;
  themeConfig  = import ./parts/theme.nix { inherit config; };

  # Inline the former plugins.nix content here
  pluginsSources = {
    full-border   = ./parts/plugins/full-border.yazi;
    glow          = ./parts/plugins/glow.yazi;
    "smart-filter" = ./parts/plugins/smart-filter.yazi;
    chmod         = ./parts/plugins/chmod.yazi;
    bookmarks     = ./parts/plugins/bookmarks.yazi;
  };

in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      yazi micro ffmpegthumbnailer unzip jq poppler-utils fontpreview
      fd ripgrep fzf zoxide file exiftool imagemagick p7zip glow
    ];

    programs.yazi = {
      enable = true;
      shellWrapperName = "y";  # New default in 26.05

      plugins = pluginsSources;

      initLua = ''
        require("full-border"):setup()
        require("bookmarks"):setup()
        require("glow")
        require("smart-filter")
        require("chmod")
      '';
    };

    xdg.configFile = {
      "yazi/yazi.toml".text       = tomlConfig."yazi/yazi.toml".text;
      "yazi/keymap.toml".text     = keymapConfig."yazi/keymap.toml".text;
      "yazi/theme.toml".text      = themeConfig."yazi/theme.toml".text;
      "yazi/Kanagawa.tmTheme".text = themeConfig."yazi/Kanagawa.tmTheme".text;
    };
  };
}
