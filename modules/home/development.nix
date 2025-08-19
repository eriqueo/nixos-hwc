     { config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.development;
     in {
       options.hwc.home.development = {
         enable = lib.mkEnableOption "Development tools and
     editors";

         editors = {
           neovim = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Neovim with configuration";
           };
           micro = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Micro editor";
           };
         };

         languages = {
           nix = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Nix development tools";
           };
           python = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Python development tools";
           };
           rust = lib.mkOption {
             type = lib.types.bool;
             default = false;
             description = "Enable Rust development tools";
           };
           javascript = lib.mkOption {
             type = lib.types.bool;
             default = false;
             description = "Enable JavaScript/Node.js development
     tools";
           };
         };

         containers = lib.mkOption {
           type = lib.types.bool;
           default = true;
           description = "Enable container development tools";
         };
       };

       config = lib.mkIf cfg.enable {
         # Neovim configuration
         programs.neovim = lib.mkIf cfg.editors.neovim {
           enable = true;
           defaultEditor = true;
           viAlias = true;
           vimAlias = true;

           configure = {
             customRC = ''
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

             packages.myVimPackage = with pkgs.vimPlugins; {
               start = [
                 vim-nix
                 vim-commentary
                 vim-surround
                 fzf-vim
                 telescope-nvim
                 nvim-treesitter
                 lualine-nvim
               ];
             };
           };
         };

         environment.systemPackages = with pkgs; [
           # Editors
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
         ] ++ lib.optionals cfg.languages.rust [
           # Rust development
           rustc
           cargo
           rust-analyzer
         ] ++ lib.optionals cfg.languages.javascript [
           # JavaScript development
           nodejs
           yarn
           typescript
           nodePackages.typescript-language-server
         ] ++ lib.optionals cfg.containers [
           # Container tools
           docker-compose
           kubernetes-helm
           kubectl
         ];

         # LSP servers for development
         environment.variables = {
           EDITOR = lib.mkIf cfg.editors.neovim "nvim";
         };
       };
     }
