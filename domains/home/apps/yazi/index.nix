# domains/home/apps/yazi/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.yazi;

  tomlConfig   = import ./parts/toml.nix;
  # Law 3 + Law 1: media root derives from system paths when hosted on
  # NixOS, with a literal fallback so the module evaluates with osConfig = {}.
  # attrByPath returns the stored value even when it is null, so handle
  # null explicitly (machines without media storage declare root = null).
  mediaRoot =
    let v = lib.attrByPath [ "hwc" "paths" "media" "root" ] null osConfig;
    in if v == null then "/mnt/media" else v;
  keymapConfig = import ./parts/keymap.nix { inherit mediaRoot; };
  colors       = (config.hwc.home.theme or {}).colors or {};
  appearance   = import ./parts/appearance.nix { inherit lib colors; };
  home = config.home.homeDirectory;
  # One seed list; store.py owns the writable list after the first edit.
  favorites = [
    { name = "Inbox"; path = "${home}/000_inbox"; }
    { name = "Apps"; path = "${home}/600_apps"; }
    { name = "NixOS"; path = "${home}/.nixos"; }
    { name = "Brain"; path = "${home}/900_vaults/brain"; }
    { name = "Downloads"; path = "${home}/000_inbox/downloads"; }
    { name = "Home"; path = home; }
    { name = "Config"; path = config.xdg.configHome; }
    { name = "Work"; path = "${home}/100_hwc"; }
    { name = "Personal"; path = "${home}/200_personal"; }
    { name = "Tech"; path = "${home}/300_tech"; }
    { name = "Media"; path = "${home}/500_media"; }
    { name = "Vaults"; path = "${home}/900_vaults"; }
  ];
  luaString = builtins.toJSON;

  # Inline the former plugins.nix content here
  pluginsSources = {
    full-border   = ./parts/plugins/full-border.yazi;
    glow          = ./parts/plugins/glow.yazi;
    "smart-filter" = ./parts/plugins/smart-filter.yazi;
    chmod         = ./parts/plugins/chmod.yazi;
    bookmarks = pkgs.runCommand "yazi-bookmarks" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -B ${./parts/plugins/bookmarks.yazi}/test.py -v
      mkdir -p "$out"
      cp ${./parts/plugins/bookmarks.yazi}/{main.lua,store.py} "$out/"
    '';
  };

in
{
  # OPTIONS
  options.hwc.home.apps.yazi = {
    enable = lib.mkEnableOption "Blazing fast terminal file manager written in Rust, based on async I/O";
  };

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
        require("bookmarks"):setup {
          store = {
            python = ${luaString "${pkgs.python3}/bin/python3"},
            helper = ${luaString "${config.xdg.configHome}/yazi/plugins/bookmarks.yazi/store.py"},
            path = ${luaString "${config.xdg.dataHome}/yazi/favorites.json"},
            defaults = ${luaString "${config.xdg.configHome}/yazi/favorites-defaults.json"},
          },
          favorites = {
            ${lib.concatMapStringsSep "\n" (entry:
              "{ name = ${luaString entry.name}, path = ${luaString entry.path} },"
            ) favorites}
          },
        }
        require("zoxide"):setup { update_db = true }
        require("glow")
        require("smart-filter")
        require("chmod")
      '';
    };

    xdg.configFile = {
      "yazi/favorites-defaults.json".text = builtins.toJSON { version = 1; inherit favorites; };
      "yazi/yazi.toml".text       = tomlConfig."yazi/yazi.toml".text;
      "yazi/keymap.toml".text     = keymapConfig."yazi/keymap.toml".text;
      "yazi/theme.toml".text       = appearance.theme;
      "yazi/Kanagawa.tmTheme".text  = appearance.syntaxTheme;
    };
  };
}
