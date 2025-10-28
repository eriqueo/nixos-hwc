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

{ config, lib, pkgs, ... }:

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
      nixfmt-rfc-style
      statix
      deadnix
      alejandra
      
    ] ++ lib.optionals cfg.languages.python [
      # Python development
      python3
      python3Packages.pip
      python3Packages.virtualenv
      pyright
      
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

    # --- Neovim configuration ---
    programs.neovim = lib.mkIf cfg.editors.neovim {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;

      # New Home Manager neovim configuration format
      extraConfig = ''
        " Basic settings
        set number
        set relativenumber
        set tabstop=2
        set shiftwidth=2
        set expandtab
        set smartindent
        set wrap
        set noswapfile
        set nobackup
        set undodir=~/.vim/undodir
        set undofile
        set incsearch
        set termguicolors
        set scrolloff=8
        set colorcolumn=80

        " Key mappings
        let mapleader = " "
        nnoremap <leader>pv :Ex<CR>
        nnoremap <leader>w :w<CR>
        nnoremap <leader>q :q<CR>

        " Move lines
        vnoremap J :m '>+1<CR>gv=gv
        vnoremap K :m '<-2<CR>gv=gv
      '';

      plugins = with pkgs.vimPlugins; [
        vim-nix
        vim-commentary
        vim-surround
        fzf-vim
        telescope-nvim
        nvim-treesitter
        lualine-nvim
      ];
    };

    # --- Development environment variables ---
    home.sessionVariables = {
      # Default editors
      EDITOR = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      VISUAL = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      # Development directories
      PROJECTS = "$HOME/.nixos/workspace/projects";
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
