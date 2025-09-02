# nixos-hwc/modules/system/base-packages.nix
#
# BASE PACKAGES - Essential system tools and utilities
# Core command-line tools needed on all machines
#
# DEPENDENCIES (Upstream):
#   - None (base system packages)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.system.basePackages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/base-packages.nix
#
# USAGE:
#   hwc.system.basePackages.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.basePackages;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.system.basePackages = {
    enable = lib.mkEnableOption "Essential system packages";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Base tooling - Editor, shell tools, etc. (ergonomics)
    environment.systemPackages = with pkgs; [
      vim
      git
      wget
      curl
      htop
      tmux
      ncdu
      tree
      ripgrep
      fd
      bat
      eza
      zoxide
      fzf
    ];
  };
}