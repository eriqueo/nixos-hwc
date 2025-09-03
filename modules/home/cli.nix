# nixos-hwc/modules/home/cli.nix
#
# CLI TOOLS - Modern command-line interface tools and configurations
# Home Manager module providing modern Unix replacements with proper integration
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#   - profiles/workstation.nix (imports this module)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.home.cli.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../modules/home/cli.nix ]
#
# USAGE:
#   hwc.home.cli.enable = true;
#   hwc.home.cli.modernUnix = true;
#   hwc.home.cli.git.enable = true;

 { config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.cli;
     in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
       options.hwc.home.cli = {
         enable = lib.mkEnableOption "CLI tools and utilities";

         modernUnix = lib.mkOption {
           type = lib.types.bool;
           default = true;
           description = "Enable modern Unix replacements (eza,
     bat, fd, etc.)";
         };

         git = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Git configuration";
           };
           userName = lib.mkOption {
             type = lib.types.str;
             default = "Eric";
             description = "Git user name";
           };
           userEmail = lib.mkOption {
             type = lib.types.str;
             default = "eric@hwc.moe";
             description = "Git user email";
           };
         };
       };


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
       config = lib.mkIf cfg.enable {
         # CLI Tools via Home Manager (provides better integration)
         home.packages = with pkgs; [
           # Modern CLI replacements
           ripgrep       # rg
           btop
           fd            # pairs better with fzf than find
           fastfetch     # neofetch is unmaintained; fastfetch is modern replacement

           # Essential CLI utilities  
           tree          # keep for classic tree output
           micro

           # Network and transfer tools
           curl
           wget
           rsync
           rclone
           speedtest-cli
           nmap

           # Archive and compression
           zip
           unzip
           p7zip

           # Text and data processing
           jq
           yq
           pandoc

           # System utilities
           xclip
           diffutils
           less
           which
           
           # Network tools
           traceroute
           dig
           
           # System tools
           lsof
           pstree
           
           # Core development
           git
           vim
           nano
           
           # AI/Development tools
           claude-code
         ] ++ lib.optionals cfg.modernUnix [
           # Additional modern Unix tools
           eza          # ls replacement (configured below)
           bat          # cat replacement (configured below) 
           procs        # ps replacement
           dust         # du replacement
           zoxide       # cd replacement (configured below)
         ];
         
         # Modern CLI tool configurations with proper integration
         programs.eza = lib.mkIf cfg.modernUnix {
           enable = true;
           git = true;
           icons = "auto";
           extraOptions = [ "--group-directories-first" ];
         };
         
         programs.bat = lib.mkIf cfg.modernUnix {
           enable = true;
           config = {
             theme = "TwoDark";
             italic-text = "always";
             pager = "less -FR";
           };
         };
         
         programs.fzf = {
           enable = true;
           enableZshIntegration = true;
           defaultCommand = "fd --type f --hidden --follow --exclude .git";
           fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
           historyWidgetOptions = [ "--exact" ];
           defaultOptions = [
             "--height 40%"
             "--reverse"
             "--border"
             # Gruvbox Material color scheme
             "--color=bg+:#32302f,bg:#282828,spinner:#89b482,hl:#7daea3"
             "--color=fg:#d4be98,header:#7daea3,info:#d8a657,pointer:#89b482"
             "--color=marker:#89b482,fg+:#d4be98,prompt:#d8a657,hl+:#89b482"
           ];
         };
         
         programs.zoxide = lib.mkIf cfg.modernUnix {
           enable = true;
           enableZshIntegration = true;
           options = [ "--cmd=z" ];
         };
         
         programs.tmux = {
           enable = true;
           clock24 = true;
           keyMode = "vi";
           extraConfig = ''
             # Gruvbox Material theme
             set -g status-bg "#282828"
             set -g status-fg "#d4be98"
             set -g status-left-style "bg=#7daea3,fg=#282828"
             set -g status-right-style "bg=#45403d,fg=#d4be98"
             set -g window-status-current-style "bg=#7daea3,fg=#282828"
             
             # Better key bindings
             bind-key v split-window -h
             bind-key s split-window -v
             bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!"
           '';
         };
         
         programs.micro = {
           enable = true;
           settings = {
             colorscheme = "gruvbox-tc";
             autoclose = true;
             autoindent = true;
             autosave = 10;
             cursorline = true;
             diffgutter = true;
             ftoptions = true;
             ignorecase = false;
             indentchar = " ";
             infobar = true;
             keymenu = true;
             mouse = true;
             rmtrailingws = true;
             ruler = true;
             savecursor = true;
             saveundo = true;
             scrollbar = true;
             smartpaste = true;
             softwrap = false;
             splitbottom = true;
             splitright = true;
             statusformatl = "$(filename) $(modified)($(line),$(col)) $(status.paste)| ft:$(opt:filetype) | $(opt:fileformat) | $(opt:encoding)";
             statusformatr = "$(bind:ToggleKeyMenu): bindings, $(bind:ToggleHelp): help";
             tabsize = 2;
             tabstospaces = true;
           };
         };
         
         # Git configuration with full user setup
         programs.git = lib.mkIf cfg.git.enable {
           enable = true;
           userName = cfg.git.userName;
           userEmail = cfg.git.userEmail;
           extraConfig = {
             init.defaultBranch = "main";
             pull.rebase = false;
             core.editor = "micro";
             alias = {
               st = "status";
               co = "checkout";
               br = "branch";
               ci = "commit";
               ca = "commit -a";
               cm = "commit -m";
               cam = "commit -am";
               unstage = "reset HEAD --";
               last = "log -1 HEAD";
               visual = "!gitk";
               tree = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
             };
           };
         };
         
         # No shell aliases here - they are managed in modules/home/shell.nix
         # This keeps single source of truth for shell configuration
       };
     }
