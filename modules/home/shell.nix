{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.shell;
     in {
       options.hwc.home.shell = {
         enable = lib.mkEnableOption "Shell configuration";

         zsh = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable ZSH configuration";
           };

           starship = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Starship prompt";
           };

           plugins = {
             autosuggestions = lib.mkOption {
               type = lib.types.bool;
               default = true;
               description = "Enable ZSH autosuggestions";
             };
             syntaxHighlighting = lib.mkOption {
               type = lib.types.bool;
               default = true;
               description = "Enable ZSH syntax highlighting";
             };
           };
         };

         tmux = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable tmux configuration";
           };
         };
       };

       config = lib.mkIf cfg.enable {
         # ZSH configuration
         programs.zsh = lib.mkIf cfg.zsh.enable {
           enable = true;
           autosuggestions.enable =
     cfg.zsh.plugins.autosuggestions;
           syntaxHighlighting.enable =
     cfg.zsh.plugins.syntaxHighlighting;

           shellAliases = {
             # System
             ll = "ls -la";
             la = "ls -la";
             ".." = "cd ..";
             "..." = "cd ../..";

             # Git shortcuts
             g = "git";
             gs = "git status";
             ga = "git add";
             gc = "git commit";
             gp = "git push";
             gl = "git log --oneline";

             # NixOS shortcuts
             nrs = "sudo nixos-rebuild switch";
             nrb = "sudo nixos-rebuild build";
             nrt = "sudo nixos-rebuild test";
             nfu = "nix flake update";

             # System monitoring
             df = "df -h";
             du = "du -h";
             free = "free -h";
           };

           ohMyZsh = {
             enable = true;
             plugins = [ "git" "sudo" "docker" "kubectl" ];
             theme = lib.mkIf (!cfg.zsh.starship) "robbyrussell";
           };
         };

         # Starship prompt
         programs.starship = lib.mkIf (cfg.zsh.enable &&
     cfg.zsh.starship) {
           enable = true;
           settings = {
             format = "$all$character";
             right_format = "$time";

             character = {
               success_symbol = "[➜](bold green)";
               error_symbol = "[➜](bold red)";
             };

             time = {
               disabled = false;
               format = "[$time]($style)";
               style = "bright-blue";
             };

             git_branch = {
               format = "[$symbol$branch]($style) ";
               symbol = " ";
             };

             git_status = {
               format = "([\\[$all_status$ahead_behind\\]]($style)
     )";
             };

             nix_shell = {
               format = "[$symbol$state( \\($name\\))]($style) ";
               symbol = " ";
             };

             directory = {
               truncation_length = 3;
               format =
     "[$path]($style)[$read_only]($read_only_style) ";
             };
           };
         };

         # Tmux configuration
         programs.tmux = lib.mkIf cfg.tmux.enable {
           enable = true;
           clock24 = true;
           terminal = "screen-256color";

           extraConfig = ''
             # Set prefix key
             set -g prefix C-a
             unbind C-b
             bind C-a send-prefix

             # Split windows
             bind | split-window -h
             bind - split-window -v

             # Switch panes
             bind h select-pane -L
             bind j select-pane -D
             bind k select-pane -U
             bind l select-pane -R

             # Resize panes
             bind -r H resize-pane -L 5
             bind -r J resize-pane -D 5
             bind -r K resize-pane -U 5
             bind -r L resize-pane -R 5

             # Mouse support
             set -g mouse on

             # Status bar
             set -g status-bg colour235
             set -g status-fg colour255
             set -g status-left '[#S] '
             set -g status-right '%Y-%m-%d %H:%M'

             # Window options
             setw -g mode-keys vi
             setw -g automatic-rename on
           '';
         };

         # Terminal emulator
         environment.systemPackages = with pkgs; [
           kitty
           alacritty
         ];
       };
     }
