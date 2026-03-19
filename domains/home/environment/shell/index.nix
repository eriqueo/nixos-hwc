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

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.shell;

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
  options.hwc.home.shell = {
    enable = lib.mkEnableOption "Complete shell + CLI environment";

    modernUnix = lib.mkEnableOption "modern Unix replacements (eza, bat, etc.)";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        ripgrep fd fzf bat jq curl wget unzip tree micro btop fastfetch
        rsync rclone speedtest-cli nmap traceroute dig zip p7zip yq pandoc
        xclip diffutils less which lsof pstree git vim nano claude-code uv
      ];
      description = "Base CLI/tool packages.";
    };

    sessionVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
        EDITOR = "micro";
        VISUAL = "micro";
      };
      description = "Environment variables for the user session.";
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "ll" = "eza -l"; "la" = "eza -lh"; "lt" = "eza --tree --level=2";
        "cd" = "z"; "cdi" = "zi"; "cz" = "z"; "czz" = "zi";
        ".." = "cd .."; "..." = "cd ../.."; "...." = "cd ../../..";
        "df" = "df -h"; "du" = "du -h"; "free" = "free -h";
        "htop" = "btop"; "grep" = "rg"; "open" = "xdg-open";
        "gs" = "git status -sb"; "ga" = "git add ."; "gc" = "git commit -m"; "gp" = "git push"; "gpl" = "git pull";
        "nixflake" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/flake.nix\"";
        "nixlaphome" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/laptop/home.nix\"";
        "nixlapcon" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/laptop/config.nix\"";
        "nixserverhome" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/server/home.nix\"";
        "nixservercon" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/server/config.nix\"";
        "nixsearch" = "nix search nixpkgs"; "nixclean" = "nix-collect-garbage -d";
        "nixgen" = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
        "checkup" = "$HWC_NIXOS_DIR/scripts/system-checkup.sh"; "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me"; "reload" = "source ~/.zshrc";
        "server" = "ssh eric@100.114.232.124"; "xps" = "ssh eric@100.126.80.42";
        "vpnon" = "sudo wg-quick up protonvpn"; "vpnoff" = "sudo wg-quick down protonvpn";
        "vpnstatus" = "sudo wg show protonvpn 2>/dev/null || echo 'VPN disconnected'";
        "cdn" = "cd ~/.nixos";
        "downloads" = "cd ~/000_inbox/downloads"; "hwc" = "cd ~/100_hwc"; "inbox" = "cd ~/000_inbox";
        "media" = "cd /mnt/media"; "movies" = "cd /mnt/media/movies"; "music" = "cd /mnt/media/music";
        "nixos" = "cd ~/300_tech"; "screenshots" = "cd ~/500_media/510_pictures/screenshots";
        "tech" = "cd ~/300_tech"; "tv" = "cd /mnt/media/tv"; "vaults" = "cd ~/900_vaults";
        "business-db" = "psql postgresql://business_user:secure_password_change_me@localhost:5432/heartwood_business";
        "business-dev" = "cd /opt/business && source /etc/business/setup-dev-env.sh";
        "cameras" = "echo 'Frigate: http://100.115.126.41:5000'";
        "receipt-process" = "cd /opt/business/receipts && python3 ../api/services/ocr_processor.py";
        "work-stats" = "python3 /opt/adhd-tools/scripts/productivity-analysis.py";
        "ls" = "eza"; "vpn" = "vpnstatus"; "which-command" = "whence"; "run-help" = "man";
        "claude-usage" = "claude-monitor --plan pro"; "usage" = "claude-monitor --plan pro";
        "errors" = "journal-errors"; "errors-hour" = "journal-errors '1 hour ago'";
        "errors-today" = "journal-errors 'today'"; "errors-tdarr" = "journal-errors '10 minutes ago' podman-tdarr";
        "services" = "list-services"; "ss" = "list-services";
        "rebuild" = "grebuild"; "lint" = "charter-lint";
        "caddy" = "caddy-health"; "health" = "caddy-health";
        "photo-dedup" = "nix-shell -p rmlint czkawka jq bc --run '$HWC_NIXOS_DIR/workspace/utilities/photo-dedup/photo-dedup.sh'";
      };
      description = "Shell aliases for zsh";
    };

    git = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable Git configuration"; };
      userName = lib.mkOption { type = lib.types.str; default = "Eric"; description = "Git user name"; };
      userEmail = lib.mkOption { type = lib.types.str; default = "eric@hwc.moe"; description = "Git user email"; };
    };

    zsh = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable Zsh via Home-Manager"; };
      starship = lib.mkEnableOption "Starship prompt";
      autosuggestions = lib.mkEnableOption "zsh-autosuggestions";
      syntaxHighlighting = lib.mkEnableOption "zsh-syntax-highlighting";
    };

    tmux = {
      enable = lib.mkEnableOption "tmux via Home-Manager";
      extraConfig = lib.mkOption { type = lib.types.lines; default = ""; description = "Additional tmux configuration"; };
    };

    ssh = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable SSH client configuration"; };
      matchBlocks = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            hostname = lib.mkOption { type = lib.types.str; description = "Hostname or IP address"; };
            user = lib.mkOption { type = lib.types.str; default = "eric"; description = "Username for SSH connection"; };
            forwardAgent = lib.mkOption { type = lib.types.bool; default = true; description = "Enable SSH agent forwarding"; };
          };
        });
        default = {
          server = { hostname = "100.114.232.124"; user = "eric"; forwardAgent = true; };
        };
        description = "SSH host configurations";
      };
    };

    mcp = {
      enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable MCP configuration file generation for Claude Desktop"; };
      includeConfigDir = lib.mkOption { type = lib.types.bool; default = false; description = "Include user config directory in filesystem MCP server (laptop only)"; };
      includeServerTools = lib.mkOption { type = lib.types.bool; default = false; description = "Include server-specific MCP tools (postgres, prometheus, puppeteer)"; };
      n8n = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include n8n MCP server via supergateway bridge";
        };
        url = lib.mkOption {
          type = lib.types.str;
          default = "https://hwc.ocelot-wahoo.ts.net:2443/mcp-server/http";
          description = "n8n MCP server HTTP endpoint URL";
        };
        accessToken = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "n8n MCP Bearer access token (use agenix secret; do not hardcode in git)";
        };
      };
    };
  };

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
      settings = {
        user.name = cfg.git.userName;
        user.email = cfg.git.userEmail;
        init.defaultBranch = "main";
        core.editor = "micro";
      };
    };

    # SSH configuration
    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = lib.mkMerge [
        {
          "*" = {
            forwardAgent = false;
            addKeysToAgent = "no";
            compression = false;
            serverAliveInterval = 0;
            serverAliveCountMax = 3;
            hashKnownHosts = false;
            userKnownHostsFile = "~/.ssh/known_hosts";
            controlMaster = "no";
            controlPath = "~/.ssh/master-%r@%n:%p";
            controlPersist = "no";
          };
        }
        cfg.ssh.matchBlocks
      ];
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

        # NixOS rebuild shortcuts (dynamic hostname)
        snix() {
          sudo nixos-rebuild switch --flake "$HWC_NIXOS_DIR#$(hostname)" "$@"
        }
        tnix() {
          sudo nixos-rebuild test --flake "$HWC_NIXOS_DIR#$(hostname)" "$@"
        }
        bnix() {
          sudo nixos-rebuild build --flake "$HWC_NIXOS_DIR#$(hostname)" "$@"
        }

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

        # Interactive graph function for hwc-graph tool
        graph() {
          local graph_script="${config.home.homeDirectory}/.nixos/workspace/nixos/graph/hwc_graph.py"

          # If arguments provided, pass directly to script
          if [ $# -gt 0 ]; then
            python3 "$graph_script" "$@"
            return
          fi

          # Interactive mode
          echo "📊 HWC Dependency Graph Analyzer"
          echo "================================"
          echo ""

          PS3=$'\n'"Choose a command (1-6): "
          select cmd in "List all modules" "Show module details" "Impact analysis" "Requirements analysis" "Graph statistics" "Export to JSON" "Exit"; do
            case $REPLY in
              1)
                python3 "$graph_script" list
                break
                ;;
              2)
                echo ""
                echo -n "Enter module name (supports partial match): "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" show "$module_name"
                else
                  echo "❌ Module name required"
                fi
                break
                ;;
              3)
                echo ""
                echo -n "Enter module name to analyze impact: "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" impact "$module_name"
                else
                  echo "❌ Module name required"
                fi
                break
                ;;
              4)
                echo ""
                echo -n "Enter module name to analyze requirements: "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" requirements "$module_name"
                else
                  echo "❌ Module name required"
                fi
                break
                ;;
              5)
                python3 "$graph_script" stats
                break
                ;;
              6)
                echo ""
                echo -n "Output file (default: graph.json): "
                read output_file
                output_file=''${output_file:-graph.json}
                python3 "$graph_script" export --format=json > "$output_file"
                echo "✅ Exported to $output_file"
                break
                ;;
              7)
                echo "👋 Goodbye!"
                break
                ;;
              *)
                echo "❌ Invalid option. Please choose 1-7."
                ;;
            esac
          done
        }
      '';
    };

    # Global fd ignore - ONLY universal junk, not media files
    # Media ignores belong in Telescope config, not here
    xdg.configFile."fd/ignore".text = ''
      .git/
      node_modules/
      __pycache__/
      .cache/
      .vscode-server/
      .nix-profile/
      .nix-defexpr/
    '';

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
        } // lib.optionalAttrs (cfg.mcp.n8n.enable && cfg.mcp.n8n.accessToken != "") {
          n8n-mcp = {
            command = "npx";
            args = [
              "-y"
              "supergateway"
              "--streamableHttp"
              cfg.mcp.n8n.url
              "--header"
              "authorization:Bearer ${cfg.mcp.n8n.accessToken}"
            ];
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
