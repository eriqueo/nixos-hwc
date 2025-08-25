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
#   - machines/*/config.nix (e.g., hwc.home.shell.enable = true)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (or any profile that wants user shell config)
#
# USAGE:
#   hwc.home.shell.enable = true;
#   hwc.home.shell.packages = with pkgs; [ ripgrep fd zoxide eza ];
#   hwc.home.shell.sessionVariables = { EDITOR = "nvim"; };
#   hwc.home.shell.aliases = { ll = "eza -lah"; };

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

    zshExtra = lib.mkOption {
      type = t.lines;
      default = "";
      description = "Additional Zsh init lines (programs.zsh.initExtra).";
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

      # --- HM: shell & helpers ------------------------------------------------
      programs.zsh = {
        enable = true;
        autosuggestion.enable     = true;
        syntaxHighlighting.enable = true;
        history = {
          size = 5000;
          save = 5000;
        };
        shellAliases = cfg.aliases;
        initExtra    = cfg.zshExtra;
      };

      programs.starship.enable = true;
      programs.fzf.enable      = true;
      programs.zoxide.enable   = true;

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # HM housekeeping (set elsewhere globally if you prefer)
      home.stateVersion = lib.mkDefault "24.05";
    };
  };
}
