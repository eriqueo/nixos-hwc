# domains/home/apps/nvim/options.nix
{ lib, ... }:
{
  options.hwc.home.apps.nvim = {
    enable = lib.mkEnableOption "Neovim editor with full lua configuration";
  };
}
