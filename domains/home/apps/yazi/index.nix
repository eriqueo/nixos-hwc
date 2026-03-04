# domains/home/apps/yazi/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.yazi;

  # Import the parts as local variables
  tomlConfig = import ./parts/toml.nix;
  keymapConfig = import ./parts/keymap.nix;
  pluginsConfig = import ./parts/plugins.nix;
  themeConfig = import ./parts/theme.nix { inherit config; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.yazi = {
    enable = lib.mkEnableOption "Yazi terminal file manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      yazi micro ffmpegthumbnailer unzip jq poppler-utils fontpreview
      fd ripgrep fzf zoxide file exiftool imagemagick p7zip glow
    ];
  xdg.configFile = {
      "yazi/yazi.toml".text = tomlConfig."yazi/yazi.toml".text;  
      "yazi/keymap.toml".text = keymapConfig."yazi/keymap.toml".text;
      "yazi/theme.toml".text = themeConfig."yazi/theme.toml".text;
    };
   home.file = let
     plugins = import ./parts/plugins.nix;
   in {
          "yazi/init.lua".text = plugins."yazi/init.lua".text;
          "yazi/plugins/full-border.yazi/main.lua".text = plugins."yazi/plugins/full-border.yazi/main.lua".text;
          "yazi/plugins/glow.yazi/main.lua".text = plugins."yazi/plugins/glow.yazi/main.lua".text;
          "yazi/plugins/smart-filter.yazi/main.lua".text = plugins."yazi/plugins/smart-filter.yazi/main.lua".text;
          "yazi/plugins/chmod.yazi/main.lua".text = plugins."yazi/plugins/chmod.yazi/main.lua".text;
          "yazi/plugins/bookmarks.yazi/main.lua".text = plugins."yazi/plugins/bookmarks.yazi/main.lua".text;
          "yazi/Kanagawa.tmTheme".text = themeConfig."yazi/Kanagawa.tmTheme".text;
        };
}
