# nixos-hwc/modules/users/eric.nix
#
# This module defines the primary user 'eric', including system-level
# properties, shell configuration, and Home Manager integration.
# It consolidates settings from the old user, system zsh, and home-manager zsh configs.

{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.users.eric;
in
{
  options.hwc.users.eric = {
    enable = lib.mkEnableOption "the 'eric' user account";
  };

  config = lib.mkIf cfg.enable {
    # 1. System-level user definition
    users.users.eric = {
      isNormalUser = true;
      description = "Eric";
      extraGroups = [ "wheel" "networkmanager" "docker" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHerGf1yJDIc2cT2i7sJjHSH39u5sA+Z5p2hN4Fqes+B eric@nixos"
      ];
    };

    # 2. System-wide ZSH configuration
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        g = "git";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gs = "git status";
        gl = "git log --oneline --graph --decorate --all";
        # This alias will be updated to point to the new repo path later
        grebuild = "sudo nixos-rebuild switch --flake /etc/nixos/nixos-hwc";
        grebirth = "sudo nixos-rebuild boot --flake /etc/nixos/nixos-hwc";
      };
    };
    users.defaultUserShell = lib.mkDefault pkgs.zsh;

    # 3. Home Manager integration for the 'eric' user
    home-manager.users.eric = {
      programs.zsh = {
        enable = true;
        dotDir = ".config/zsh";
        history = {
          size = 10000;
          path = "$HOME/.config/zsh/history";
        };
        initExtra = ''
          # Custom ZSH initializations can go here
        '';
      };
    };
  };
}