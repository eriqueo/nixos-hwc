# nixos-hwc/modules/home/shell.nix
#
# Home UI: Shell + CLI stack (HM consumer via NixOS orchestrator)
# NixOS options gate inclusion; Home-Manager config lives under home-manager.users.<user>.
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports HM and sets home.stateVersion)
#   - home-manager.nixosModules.home-manager (enabled at flake/machine)
#
# USED BY (Downstream):
#   - machines/*/config.nix (e.g., hwc.home.shell.* toggles)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (or any profile that wants user shell config)
#
# USAGE:
#   hwc.home.shell.enable = true;
#   hwc.home.shell.packages = with pkgs; [ ripgrep fd zoxide eza ];
#   hwc.home.shell.sessionVariables = { EDITOR = "nvim"; };
#   hwc.home.shell.aliases = { ll = "eza -lah"; };
#   hwc.home.shell.zsh = {
#     enable = true;
#     starship = true;
#     plugins.autosuggestions = true;
#     plugins.syntaxHighlighting = true;
#   };
#   hwc.home.shell.tmux = {
#     enable = true;
#     extraConfig = ''
#       set -g mouse on
#     '';
#   };

{ config, lib, pkgs, ... }:

let
  t   = lib.types;
  cfg = config.hwc.home.shell;
in
{
  #============================================================================
  # OPTIONS (NixOS layer)
  #============================================================================
  options.hwc.home.shell = {
    enable = lib.mkEnableOption "User shell + CLI configuration via Home-Manager";

    packages = lib.mkOption {
      type = t.listOf t.package;
      default = with pkgs; [ ripgrep fd zoxide eza fzf bat jq curl wget unzip ];
      description = "User-scoped CLI/tool packages (Home-Manager: home.packages).";
    };

    sessionVariables = lib.mkOption {
      type = t.attrsOf t.str;
      default = {};
      description = "Environment variables for the user session (HM: home.sessionVariables).";
    };

    aliases = lib.mkOption {
      type = t.attrsOf t.str;
      default = {};
      description = "Shell aliases (mapped to programs.zsh.shellAliases).";
    };

    zsh = {
      enable = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Zsh via Home-Manager.";
      };

      starship = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Starship prompt.";
      };

      plugins = {
        autosuggestions = lib.mkOption {
          type = t.bool;
          default = true;
          description = "Enable zsh-autosuggestions.";
        };
        syntaxHighlighting = lib.mkOption {
          type = t.bool;
          default = true;
          description = "Enable zsh-syntax-highlighting.";
        };
      };

      initExtra = lib.mkOption {
        type = t.lines;
        default = "";
        description = "Additional Zsh init lines (programs.zsh.initExtra).";
      };
    };

    tmux = {
      enable = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable tmux via Home-Manager.";
      };

      extraConfig = lib.mkOption {
        type = t.lines;
        default = "";
        description = "Extra tmux.conf content (programs.tmux.extraConfig).";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION (NixOS -> HM bridge)
  #============================================================================
  config = lib.mkIf cfg.enable {

    home-manager.useGlobalPkgs = lib.mkDefault true;

    home-manager.users.eric = { ... }: {

      # --- HM: packages & env -------------------------------------------------
      home.packages         = cfg.packages;
      home.sessionVariables = cfg.sessionVariables;

      # --- HM: Zsh & prompt ---------------------------------------------------
      programs.zsh = {
        enable = cfg.zsh.enable;
        autosuggestion.enable     = cfg.zsh.plugins.autosuggestions;
        syntaxHighlighting.enable = cfg.zsh.plugins.syntaxHighlighting;
        history = {
          size = 5000;
          save = 5000;
        };
        shellAliases = cfg.aliases;
        initExtra    = cfg.zsh.initExtra;
      };

      programs.starship.enable = cfg.zsh.starship;
      programs.fzf.enable      = true;
      programs.zoxide.enable   = true;

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # --- HM: tmux -----------------------------------------------------------
      programs.tmux = {
        enable      = cfg.tmux.enable;
        sensible    = true;
        clock24     = true;
        mouse       = true;
        extraConfig = cfg.tmux.extraConfig;
      };

      # HM housekeeping (set globally elsewhere if desired)
      home.stateVersion = lib.mkDefault "24.05";
    };
  };
}
