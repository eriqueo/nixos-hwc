# HWC Charter Module/domains/home/environment/shell/index.nix
#
# SHELL IMPLEMENTATION - Complete shell and CLI configuration
# Aggregator module implementing shell functionality using parts
#
# DEPENDENCIES (Upstream):
#   - domains/home/environment/shell/options.nix (API definition)
#   - domains/home/environment/shell/parts/* (pure helper functions)
#
# USED BY (Downstream):
#   - profiles/home.nix (imports this module)
#
# IMPORTS REQUIRED IN:
#   - profiles/home.nix: ../domains/home/environment/shell
#
# USAGE:
#   hwc.home.shell.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.shell;
  
  # Import parts (pure functions)
  grebuildScript = import ./parts/grebuild.nix { inherit pkgs; };
  
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [
    ./options.nix
  ];

  #============================================================================
  # IMPLEMENTATION - Complete shell and CLI environment
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Base packages plus optional modern Unix tools
    home.packages = cfg.packages 
      ++ lib.optionals cfg.modernUnix (with pkgs; [
        eza bat procs dust zoxide
      ])
      ++ lib.optionals cfg.scripts.grebuild [
        grebuildScript
      ];

    # Environment variables
    home.sessionVariables = cfg.sessionVariables;

    # Modern Unix replacements configuration
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
        "--height 40%" "--reverse" "--border"
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

    programs.micro = {
      enable = true;
      settings = {
        colorscheme = "gruvbox-tc";
        autoindent = true;
        tabstospaces = true;
        tabsize = 2;
      };
    };

    # Git configuration
    programs.git = lib.mkIf cfg.git.enable {
      enable = true;
      userName = cfg.git.userName;
      userEmail = cfg.git.userEmail;
      extraConfig = {
        init.defaultBranch = "main";
        core.editor = "micro";
      };
    };

    # Zsh configuration
    programs.zsh = lib.mkIf cfg.zsh.enable {
      enable = true;
      autosuggestion.enable = cfg.zsh.autosuggestions;
      syntaxHighlighting.enable = cfg.zsh.syntaxHighlighting;
      history = {
        size = 5000;
        save = 5000;
      };
      shellAliases = cfg.aliases;
      initContent = ''
        # Helper functions for enhanced shell experience
        
        # Fuzzy finding function
        ff() {
          fd -t f . ~ | fzf --query="$*" --preview 'head -20 {}'
        }

        # Quick system status check
        status() {
          echo "🖥️  System Status Overview"
          echo "=========================="
          echo "💾 Memory: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
          echo "💽 Disk: $(df -h / | awk 'NR==2{print $5}')"
          echo "🔥 Load: $(uptime | awk -F'load average:' '{print $2}')"
        }

        # add-app shell function
        add-app() {
          /home/eric/.nixos/scripts/filesystem/add-home-app.sh "$@"
        }
      '';
    };

    # Starship prompt
    programs.starship.enable = cfg.zsh.starship;

    # Direnv for development environments
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Tmux configuration
    programs.tmux = lib.mkIf cfg.tmux.enable {
      enable = true;
      clock24 = true;
      keyMode = "vi";
      mouse = true;
      extraConfig = cfg.tmux.extraConfig;
    };
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  # Add assertions and validation logic here
}
