# NEW, REFACTORED file: domains/system/services/shell/index.nix
#
# SHELL - Core command-line environment and development tools.
# Installs essential CLI utilities, shells, editors, and developer toolchains.
#
# USAGE:
#   hwc.system.core.shell.enable = true;
#   hwc.system.core.shell.development.enable = true; # For a full dev setup

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.core.shell;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.core.shell = {
    # The master switch for the entire shell environment.
    enable = lib.mkEnableOption "Enable the core shell environment and CLI tools";

    # A sub-option for development tools. This gives you a choice
    # to have a minimal shell or a full development setup.
    development.enable = lib.mkEnableOption "Install development tools (compilers, language servers)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
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
        fastfetch
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
        # nodePackages.neovim removed in 24.11 - no longer needed
        tree-sitter
        universal-ctags
      ]);
    assertions = [];
  };

}
