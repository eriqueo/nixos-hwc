# domains/home/apps/nvim/index.nix
#
# NEOVIM - Full IDE-like editor with lazy.nvim plugin management
#
# DEPENDENCIES (Upstream):
#   - Home Manager programs.neovim
#
# USED BY (Downstream):
#   - User configuration via hwc.home.apps.nvim.enable
#
{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.nvim;
  colors = (config.hwc.home.theme or {}).colors or {};
  appearance = import ./parts/appearance.nix { inherit lib colors; };

  # Lua configuration directory structure
  luaDir = ./parts/lua;

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

    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withRuby = false;
      withPython3 = false;
      extraPackages = with pkgs; [
        wl-clipboard
        stylua
        luajitPackages.jsregexp
      ];
      # Load the lua configuration
      initLua = ''
        require("core")
      '';

    };

    # Deploy lua configuration declaratively via xdg.configFile
    # This mirrors the yazi pattern for managing config files
    xdg.configFile = {
      # Core modules
      "nvim/lua/core/init.lua".source = "${luaDir}/core/init.lua";
      "nvim/lua/core/keymaps.lua".source = "${luaDir}/core/keymaps.lua";
      "nvim/lua/core/options.lua".source = "${luaDir}/core/options.lua";
      "nvim/lua/core/plugins.lua".source = "${luaDir}/core/plugins.lua";
      "nvim/lua/core/colorscheme.lua".text = appearance.colorscheme;

      # Plugin configurations
      "nvim/lua/plugins/telescope.lua".source = "${luaDir}/plugins/telescope.lua";
      "nvim/lua/plugins/treesitter.lua".source = "${luaDir}/plugins/treesitter.lua";
      "nvim/lua/plugins/lsp.lua".source = "${luaDir}/plugins/lsp.lua";
      "nvim/lua/plugins/cmp.lua".source = "${luaDir}/plugins/cmp.lua";

      # Lua language server config to recognize vim global
      "nvim/.luarc.json".source = ./parts/.luarc.json;
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.enable -> config.programs.neovim.enable;
        message = "hwc.home.apps.nvim requires programs.neovim to be enabled";
      }
    ];
  };
}
