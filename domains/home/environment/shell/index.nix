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
  cfg = config.hwc.home.environment.shell;

  # Import script derivations from parts/
  grebuild = import ./parts/grebuild.nix { inherit pkgs config; };
  journal-errors = import ./parts/journal-errors.nix { inherit pkgs config; };
  list-services = import ./parts/list-services.nix { inherit pkgs config; };
  charter-lint = import ./parts/charter-lint.nix { inherit pkgs config; };
  caddy-health = import ./parts/caddy-health.nix { inherit pkgs config; };
  secret = import ./parts/secret.nix { inherit pkgs config; };
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
      ++ [
        # Daily driver script commands from workspace
        grebuild
        journal-errors
        list-services
        charter-lint
        caddy-health
        secret
      ];

    # Environment variables
    home.sessionVariables = cfg.sessionVariables // {
      # Override HWC_NIXOS_DIR to use dynamic home directory
      HWC_NIXOS_DIR = "${config.home.homeDirectory}/.nixos";

      # Workspace root path for runtime override capability
      HWC_WORKSPACE_ROOT = "${config.home.homeDirectory}/.nixos/workspace";
    };

    # Modern Unix replacements configuration
    programs.eza = lib.mkIf cfg.modernUnix {
      enable = true;
      git = true;
      icons = true;  # HM 24.05 only accepts boolean, not "auto"
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
      shellAliases = cfg.aliases // {
        # Override SSH aliases to use dynamic username
        "homeserver" = "ssh ${config.home.username}@100.115.126.41";
        "server" = "ssh ${config.home.username}@100.115.126.41";
      };
      initExtra = ''
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
          ${config.home.homeDirectory}/.nixos/workspace/nixos/add-home-app.sh "$@"
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

    # MCP (Model Context Protocol) configuration for Claude Desktop
    # Generate .mcp.json with dynamic paths
    home.file.".mcp.json" = lib.mkIf cfg.mcp.enable {
      text = builtins.toJSON {
        mcpServers = {
          filesystem = {
            command = "npx";
            args = [
              "-y"
              "@modelcontextprotocol/server-filesystem"
              "${config.home.homeDirectory}/.nixos"
              "/etc/nixos"
            ] ++ lib.optionals cfg.mcp.includeConfigDir [
              "${config.xdg.configHome}"
            ];
          };
          git = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-git" ];
            cwd = "${config.home.homeDirectory}/.nixos";
          };
          brave-search = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
            env = {};
          };
          github = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-github" ];
            env = {};
          };
          sequential-thinking = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-sequential-thinking" ];
          };
          time = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-time" ];
          };
          fetch = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-fetch" ];
          };
          memory = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-memory" ];
          };
        } // lib.optionalAttrs cfg.mcp.includeServerTools {
          postgres = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-postgres" ];
            env = {
              POSTGRES_CONNECTION_STRING = "postgresql://localhost:5432/postgres";
            };
          };
          prometheus = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-prometheus" ];
            env = {
              PROMETHEUS_URL = "http://localhost:9090";
            };
          };
          puppeteer = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-puppeteer" ];
          };
        };
      };
    };
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  # Add assertions and validation logic here
}
