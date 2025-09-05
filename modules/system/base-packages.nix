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
    
    development = lib.mkEnableOption "Development tools and language servers";
    
    multimedia = lib.mkEnableOption "Multimedia and graphics tools";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # System-level packages - Development tools, language servers, build tools
    environment.systemPackages = with pkgs; [
      # Core system shells
      zsh                    # Default user shell (required for Home Manager integration)
      
      # Core development tools
      git
      micro
      neovim
      
      # System monitoring and utilities
      htop
      btop
      tree
      neofetch
      
      # Network tools
      wget
      curl
      
      # File management
      unzip
      zip
      p7zip
      rsync
      
      # Language servers for development
      lua-language-server              # Lua LSP
      nil                             # Nix LSP  
      pyright                         # Python LSP
      nodePackages.typescript-language-server  # TypeScript/JavaScript LSP
      gopls                          # Go LSP
      clang-tools                    # C/C++ LSP (includes clangd)
      
      # Development build tools (needed for some LSP features)
      gcc
      gnumake
      cmake
      pkg-config
      nodejs                         # Needed for some LSPs
      python3                        # Needed for Python development
      cargo                          # Rust package manager
      go                            # Go compiler
      
      # Enhanced CLI tools (system-level)
      bat          # better cat
      eza          # better ls
      fzf          # fuzzy finder
      ripgrep      # better grep
      fd           # better find
      
      # Development languages and tools
      python3Packages.pip
      python3Packages.pynvim         # the 'pynvim' host module
      nodePackages.neovim            # npm 'neovim' package (alternative host)
      tree-sitter                    # CLI for building parsers
      universal-ctags                # tag navigation
      
      # Security and secrets management
      sops
      age
      ssh-to-age
      
      # Terminal multiplexer
      tmux
      
      # Universal GUI tools (needed by both server and workstation)
      kitty                  # Terminal emulator (server: X11 forwarding, workstation: desktop)
      xfce.thunar           # File manager (server: X11 forwarding, workstation: desktop)
      
      # JSON/YAML processing
      jq
      yq
      
      # System information
      usbutils
      pciutils
      dmidecode
      
      # Disk and filesystem tools
      parted        # Disk partitioning tool
      gptfdisk      # GPT partition management (gdisk/sgdisk)
      dosfstools    # FAT32/VFAT filesystem tools
      e2fsprogs     # ext2/3/4 filesystem tools
      ntfs3g        # NTFS filesystem support
      
      # Version control and GitHub
      gh           # GitHub CLI
      
      # Core system utilities
      vim
      ncdu
      zoxide
    ];
  };
}