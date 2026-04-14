# domains/home/core/development.nix
#
# Development environment — languages, editors, container tools
#
# NAMESPACE: hwc.home.development.*
# USED BY: profiles/session.nix, machines/server/config.nix
# USAGE: hwc.home.development.enable = true;

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.development;
  t = lib.types;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.development = {
    enable = lib.mkEnableOption "Development tools and environment";

    editors = {
      neovim = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Neovim with configuration";
      };
      micro = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Micro editor";
      };
    };

    languages = {
      nix = lib.mkOption { type = t.bool; default = true; description = "Enable Nix development tools"; };
      python = lib.mkOption { type = t.bool; default = true; description = "Enable Python development tools"; };
      javascript = lib.mkOption { type = t.bool; default = false; description = "Enable JavaScript/Node.js development tools"; };
      rust = lib.mkOption { type = t.bool; default = false; description = "Enable Rust development tools"; };
    };

    containers = lib.mkOption { type = t.bool; default = true; description = "Enable container development tools"; };
    directoryStructure = lib.mkOption { type = t.bool; default = true; description = "Create development directory structure"; };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    home.packages = with pkgs; [
      git-lfs
      gh
      wireguard-tools

    ] ++ lib.optionals cfg.editors.micro [
      micro

    ] ++ lib.optionals cfg.languages.nix [
      nil
      nixfmt
      statix
      deadnix
      alejandra

    ] ++ lib.optionals cfg.languages.python [
      pyright
    ] ++ lib.optionals (cfg.languages.python && !config.hwc.home.apps.analysis.enable) [
      python3
      python3Packages.pip
      python3Packages.virtualenv

    ] ++ lib.optionals cfg.languages.javascript [
      nodejs
      yarn
      typescript
      typescript-language-server

    ] ++ lib.optionals cfg.languages.rust [
      rustc
      cargo
      rust-analyzer

    ] ++ lib.optionals cfg.containers [
      docker-compose
      kubernetes-helm
      kubectl
    ];

    # Bridge editors.neovim to the nvim app domain
    hwc.home.apps.nvim.enable = lib.mkIf cfg.editors.neovim true;

    home.sessionVariables = {
      EDITOR = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      VISUAL = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      PROJECTS = "$HOME/.nixos/workspace";
      SCRIPTS = "$HOME/.nixos/workspace";
      WORKSPACE = "$HOME/.nixos/workspace";

    } // lib.optionalAttrs cfg.languages.python {
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      PIP_USER = "1";

    } // lib.optionalAttrs cfg.languages.javascript {
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    home.sessionPath = [
      "$HOME/.local/bin"
    ] ++ lib.optionals cfg.languages.javascript [
      "$HOME/.npm-global/bin"
    ];
  };
}
