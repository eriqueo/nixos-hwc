# HWC Charter Module/domains/home/environment/development.nix
#
# DEVELOPMENT ENVIRONMENT - Complete development stack configuration
# Enhanced with rich git configuration, environment setup, and directory structure
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#   - profiles/workstation.nix (imports this module)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.home.development.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../domains/home/environment/development.nix ]
#
# USAGE:
#   hwc.home.development.enable = true;
#   hwc.home.development.languages.python = true;
#   hwc.home.development.editors.neovim = true;

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.development;
in
{
  #============================================================================
  # IMPLEMENTATION - Complete development environment
  #============================================================================
  config = lib.mkIf cfg.enable {

    # --- Development packages ---
    home.packages = with pkgs; [
      # Version control tools
      git-lfs
      gh                    # GitHub CLI
      
      # Network and VPN tools
      wireguard-tools
      
    ] ++ lib.optionals cfg.editors.micro [
      micro
      
    ] ++ lib.optionals cfg.languages.nix [
      # Nix development
      nil
      nixfmt
      statix
      deadnix
      alejandra
      
    ] ++ lib.optionals cfg.languages.python [
      # Python development
      pyright
    # Avoid adding a second Python interpreter when the analysis app already supplies one.
    ] ++ lib.optionals (cfg.languages.python && !config.hwc.home.apps.analysis.enable) [
      python3
      python3Packages.pip
      python3Packages.virtualenv
      
    ] ++ lib.optionals cfg.languages.javascript [
      # JavaScript development
      nodejs
      yarn
      typescript
      nodePackages.typescript-language-server
      
    ] ++ lib.optionals cfg.languages.rust [
      # Rust development
      rustc
      cargo
      rust-analyzer
      
    ] ++ lib.optionals cfg.containers [
      # Container tools
      docker-compose
      kubernetes-helm
      kubectl
    ];

    # --- Enhanced Git configuration ---
    # Git configuration moved to shell.nix for consistency

    # --- Neovim ---
    # Neovim is now managed by hwc.home.apps.nvim domain
    # This bridges the old editors.neovim option to the new domain
    hwc.home.apps.nvim.enable = lib.mkIf cfg.editors.neovim true;

    # --- Development environment variables ---
    home.sessionVariables = {
      # Default editors (nvim if enabled via the nvim domain)
      EDITOR = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      VISUAL = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      # Development directories
      PROJECTS = "$HOME/.nixos/workspace/hwc";
      SCRIPTS = "$HOME/.nixos/workspace";
      WORKSPACE = "$HOME/.nixos/workspace";

    } // lib.optionalAttrs cfg.languages.python {
      # Python development
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      PIP_USER = "1";
      
    } // lib.optionalAttrs cfg.languages.javascript {
      # Node.js development  
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    # --- Development directory structure ---
    #     # Development directory structure disabled - using NixOS workspace
    #     # home.file = lib.mkIf cfg.directoryStructure {
    #       "workspace/projects/.keep".text = "Development projects directory";
    #       "workspace/scripts/.keep".text = "Custom automation scripts directory";  
    #       "workspace/dotfiles/.keep".text = "Configuration backups and dotfiles directory";
    #       ".local/bin/.keep".text = "User-local executables directory";
    #     };

    # --- PATH extensions for development ---
    home.sessionPath = [
      "$HOME/.local/bin"
    ] ++ lib.optionals cfg.languages.javascript [
      "$HOME/.npm-global/bin"
    ];
  };
}
