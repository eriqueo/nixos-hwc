# NEW, REFACTORED file: domains/system/services/shell/index.nix
#
# SHELL - Core command-line environment and development tools.
# Installs essential CLI utilities, shells, editors, and developer toolchains.
#
# USAGE:
#   hwc.system.services.shell.enable = true;
#   hwc.system.services.shell.development.enable = true; # For a full dev setup

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.shell;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # CO-LOCATED SHELL & UTILITY PACKAGES
    #=========================================================================
    environment.systemPackages = with pkgs;
      # --- Core Shell Experience ---
      # These packages are fundamental to the interactive shell.
      [
        zsh
        git
        tmux
        kitty
        neovim
        micro

        # Modern CLI replacements & utilities
        eza      # 'ls' replacement
        bat      # 'cat' replacement
        fzf      # Fuzzy finder
        ripgrep  # 'grep' replacement
        fd       # 'find' replacement

        # System info and navigation
        htop
        btop
        tree
        neofetch
        ncdu
        zoxide
        gh       # GitHub CLI

        # Archive tools
        unzip
        zip
        p7zip

        # Data parsing
        jq
        yq
      ]

      # --- Development Toolchain ---
      # This block is installed only if 'development.enable' is true.
      ++ (lib.optionals cfg.development.enable [
        # Compilers and build systems
        gcc
        gnumake
        cmake
        pkg-config
        go
        cargo
        nodejs
        python3

        # Language Servers
        lua-language-server
        nil # Nix Language Server
        pyright
        nodePackages.typescript-language-server
        gopls
        clang-tools

        # Neovim/Editor support tools
        python3Packages.pip
        python3Packages.pynvim
        nodePackages.neovim
        tree-sitter
        universal-ctags
      ]);
  };
}
