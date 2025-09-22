# nixos-h../domains/system/base-packages.nix
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
#   - profiles/base.nix: ../domains/system/base-packages.nix
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
      zsh git micro neovim                 # Default user shell (required for Home Manager integration) 
      tmux kitty xfce.thunar               # Terminal emulator (server: X11 forwarding, workstation: desktop)
      vim ncdu zoxide gh                   # GitHub CLI

      # Security and password management
      pass gnupg isync  # Password store, GPG encryption, Email sync (required by ProtonMail Bridge)
                        
      # Mail shit
      neomutt  msmtp  abook  w3m lynx gnupg  pass file 

      # System monitoring and utilities
      htop btop tree neofetch
      
      # Network tools
      wget curl
      
      # File management
      unzip zip p7zip rsync
      
      # Language servers for development
      lua-language-server nil pyright                     # Lua LSP, Nix LSP, Python LSP
      nodePackages.typescript-language-server  # TypeScript/JavaScript LSP
      gopls clang-tools                        # Go LSP, C/C++ LSP (includes clangd)
                 
      # Development build tools (needed for some LSP features)
      gcc gnumake cmake
      pkg-config nodejs                         # Needed for some LSPs
      python3 cargo go                   # Needed for Python development
       
      # Enhanced CLI tools (system-level)
      bat eza fzf ripgrep fd           
      
      # Development languages and tools
      python3Packages.pip
      python3Packages.pynvim         # the 'pynvim' host module
      nodePackages.neovim            # npm 'neovim' package (alternative host)
      tree-sitter                    # CLI for building parsers
      universal-ctags                # tag navigation
      
      # Security and secrets management
      sops age ssh-to-age
      
      # JSON/YAML processing
      jq yq
      
      # System information
      usbutils pciutils dmidecode
      
      # Disk and filesystem tools
      parted        # Disk partitioning tool
      gptfdisk      # GPT partition management (gdisk/sgdisk)
      dosfstools    # FAT32/VFAT filesystem tools
      e2fsprogs     # ext2/3/4 filesystem tools
      ntfs3g        # NTFS filesystem support

    ];
  };
}
