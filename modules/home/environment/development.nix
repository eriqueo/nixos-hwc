# nixos-hwc/modules/home/environment/development.nix
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
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../modules/home/environment/development.nix ]
#
# USAGE:
#   hwc.home.development.enable = true;
#   hwc.home.development.languages.python = true;
#   hwc.home.development.editors.neovim = true;

{ config, lib, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.home.development;
in
{
  #============================================================================
  # OPTIONS - Complete development environment configuration
  #============================================================================
  options.hwc.home.development = {
    enable = lib.mkEnableOption "Development tools and environment";

    git = {
      enable = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Git with enhanced configuration";
      };
      userName = lib.mkOption {
        type = t.str;
        default = "eric";
        description = "Git user name";
      };
      userEmail = lib.mkOption {
        type = t.str;
        default = "eriqueo@proton.me";
        description = "Git user email";
      };
    };

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
      nix = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Nix development tools";
      };
      python = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Python development tools";
      };
      javascript = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable JavaScript/Node.js development tools";
      };
      rust = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable Rust development tools";
      };
    };

    containers = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable container development tools";
    };

    directoryStructure = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Create development directory structure";
    };
  };

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
    programs.git = lib.mkIf cfg.git.enable {
      enable = true;
      userName = cfg.git.userName;
      userEmail = cfg.git.userEmail;

      extraConfig = {
        init.defaultBranch = "main";
        core.editor = "micro";
        pull.rebase = false;
        push.default = "simple";
        
        # Better diffs and merging
        diff.tool = "meld";
        merge.tool = "meld";
        
        # Performance improvements
        core.preloadindex = true;
        core.fscache = true;
        gc.auto = 256;
        
        # Security
        transfer.fsckobjects = true;
        fetch.fsckobjects = true;
        receive.fsckObjects = true;
      };

      # Enhanced aliases for better workflow
      aliases = {
        # Basic shortcuts
        st = "status -sb";
        co = "checkout";
        br = "branch";
        ci = "commit";
        
        # Enhanced log views
        lg = "log --oneline --graph --decorate --all";
        ll = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        
        # Workflow shortcuts  
        aa = "add .";
        cm = "commit -m";
        pu = "push";
        pl = "pull";
        
        # Advanced operations
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
        
        # Cleanup operations
        cleanup = "!git branch --merged | grep -v '\\*\\|master\\|main' | xargs -n 1 git branch -d";
        prune-branches = "remote prune origin";
      };
      
      # Comprehensive gitignore patterns
      ignores = [
        # OS generated files
        ".DS_Store"
        ".DS_Store?"
        "._*"
        ".Spotlight-V100"
        ".Trashes"
        "ehthumbs.db"
        "Thumbs.db"
        
        # Editor files
        "*~"
        "*.swp"
        "*.swo"
        ".vscode/"
        ".idea/"
        
        # Build artifacts
        "node_modules/"
        "dist/"
        "build/"
        "*.log"
        ".env"
        ".env.local"
        
        # Python
        "__pycache__/"
        "*.pyc"
        "*.pyo"
        "*.pyd"
        ".Python"
        "env/"
        "venv/"
        ".venv/"
        
        # NixOS
        "result"
        "result-*"
      ];
    };

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
      EDITOR = if cfg.editors.neovim then "nvim" else "micro";
      VISUAL = if cfg.editors.neovim then "nvim" else "micro";
      
      # Development directories
      PROJECTS = "$HOME/workspace/projects";
      SCRIPTS = "$HOME/workspace/scripts";
      DOTFILES = "$HOME/workspace/dotfiles";
      
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
    home.file = lib.mkIf cfg.directoryStructure {
      "workspace/projects/.keep".text = "Development projects directory";
      "workspace/scripts/.keep".text = "Custom automation scripts directory";  
      "workspace/dotfiles/.keep".text = "Configuration backups and dotfiles directory";
      ".local/bin/.keep".text = "User-local executables directory";
    };

    # --- PATH extensions for development ---
    home.sessionPath = [
      "$HOME/.local/bin"
    ] ++ lib.optionals cfg.languages.javascript [
      "$HOME/.npm-global/bin"
    ];
  };
}