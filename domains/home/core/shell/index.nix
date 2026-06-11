# domains/home/core/shell/index.nix
#
# Complete shell and CLI configuration
#
# NAMESPACE: hwc.home.shell.*
# USED BY: profiles/session.nix
# USAGE: hwc.home.shell.enable = true;

{ config, lib, pkgs, osConfig ? {}, nixosApiVersion ? "unstable", ... }:

let
  cfg = config.hwc.home.shell;
  ws = "$HWC_WORKSPACE_ROOT";
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
        yt-dlp
      ];
      description = "Base CLI/tool packages.";
    };

    sessionVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
        EDITOR = "micro";
        VISUAL = "micro";
        _ZO_DOCTOR = "0";
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
        "aliases" = "cd ~/.nixos && nvim domains/home/core/shell/index.nix";
        "web-build" = "cd /home/eric/.nixos/domains/business/website/site_files && npx @11ty/eleventy";
        "htop" = "btop"; "open" = "xdg-open";
        "web-deploy" = "curl -s -X POST -H 'x-api-key: '$(cat /run/agenix/cms-api-key) http://localhost:8095/api/deploy | jq .";
        "web-speed" = "${ws}/tools/web-speed.sh";
        "gs" = "git status -sb"; "ga" = "git add ."; "gc" = "git commit -m"; "gp" = "git push"; "gpl" = "git pull";
        "nixsearch" = "nix search nixpkgs"; "nixclean" = "nix-collect-garbage -d";
        "checkup" = "$HWC_NIXOS_DIR/scripts/system-checkup.sh"; "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me"; "reload" = "source ~/.zshrc";
        "server" = "ssh eric@100.114.232.124"; "xps" = "ssh eric@100.126.80.42";
        "vpnon" = "sudo systemctl start wg-quick-protonvpn"; "vpnoff" = "sudo systemctl stop wg-quick-protonvpn";
        "vpnstatus" = "sudo wg show protonvpn 2>/dev/null || echo 'VPN disconnected'";
        "website" = "ssh -i ~/.ssh/hostinger_deploy -p 65002 u930853409@194.195.84.13";
        "cdn" = "cd ~/.nixos";
        "cdd" = "cd ~/700_datax/datax"; "cdj" = "cd ~/700_datax/jt-mcp";
        "downloads" = "cd ~/000_inbox/downloads"; "hwc" = "cd ~/100_hwc"; "inbox" = "cd ~/000_inbox";
        "screenshots" = "cd ~/500_media/510_pictures/screenshots";
        "cameras" = "echo 'Frigate: http://100.115.126.41:5000'";
        "ls" = "eza"; "vpn" = "vpnstatus"; "which-command" = "whence"; "run-help" = "man";
        # Workspace script aliases
        "errors" = "${ws}/monitoring/journal-errors.sh";
        "errors-hour" = "${ws}/monitoring/journal-errors.sh '1 hour ago'";
        "errors-today" = "${ws}/monitoring/journal-errors.sh 'today'";
        "errors-tdarr" = "${ws}/monitoring/journal-errors.sh '10 minutes ago' podman-tdarr";
        "services" = "${ws}/nixos-dev/list-services.sh";
        "rebuild" = "${ws}/nixos-dev/grebuild.sh"; "lint" = "${ws}/nixos-dev/charter-lint.sh";
        "caddy" = "${ws}/monitoring/caddy-health-check.sh"; "health" = "${ws}/monitoring/caddy-health-check.sh";
        "secret" = "${ws}/system/secret-manager.sh";
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
          default = "https://hwc-server.ocelot-wahoo.ts.net:2443/mcp-server/http";
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
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Base packages plus optional modern Unix tools
    home.packages = cfg.packages
      ++ lib.optionals cfg.modernUnix (with pkgs; [
        eza bat procs dust zoxide
      ]);

    home.sessionPath = [
      "${config.home.homeDirectory}/bin"
      "${config.home.homeDirectory}/.npm-global/bin"
    ];

    # Environment variables
    home.sessionVariables = cfg.sessionVariables // {
      COLORTERM = "truecolor";
      HWC_NIXOS_DIR = "${config.home.homeDirectory}/.nixos";
      HWC_WORKSPACE_ROOT = "${config.home.homeDirectory}/.nixos/workspace";
    };

    # Modern Unix replacements configuration
    programs.eza = lib.mkIf cfg.modernUnix {
      enable = true;
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
      signing.format = null;
      settings = {
        user.name = cfg.git.userName;
        user.email = cfg.git.userEmail;
        init.defaultBranch = "main";
        core.editor = "micro";
      };
    };

    # SSH configuration — API differs between HM 25.11 (stable) and 26.05+ (unstable).
    # Stable uses `matchBlocks` with HM camelCase attrs (hostname/user/forwardAgent...);
    # unstable uses `settings` with literal "Host *" keys and OpenSSH directive names.
    # User-facing DSL `cfg.ssh.matchBlocks` is unchanged; we translate it per API.
    programs.ssh = lib.mkIf cfg.ssh.enable (
      if nixosApiVersion == "stable" then {
        enable = true;
        matchBlocks = {
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
        } // (lib.mapAttrs (name: host: {
          hostname     = host.hostname;
          user         = host.user;
          forwardAgent = host.forwardAgent;
        }) cfg.ssh.matchBlocks);
      } else {
        enable = true;
        enableDefaultConfig = false;
        settings = lib.mkMerge [
          {
            "Host *" = {
              ForwardAgent = false;
              AddKeysToAgent = "no";
              Compression = false;
              ServerAliveInterval = 0;
              ServerAliveCountMax = 3;
              HashKnownHosts = false;
              UserKnownHostsFile = "~/.ssh/known_hosts";
              ControlMaster = "no";
              ControlPath = "~/.ssh/master-%r@%n:%p";
              ControlPersist = "no";
            };
          }
          (lib.mapAttrs' (name: host: lib.nameValuePair "Host ${name}" {
            HostName     = host.hostname;
            User         = host.user;
            ForwardAgent = host.forwardAgent;
          }) cfg.ssh.matchBlocks)
        ];
      }
    );

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
        # Refresh zsh's command hash table before every prompt. Required because
        # this host runs BOTH HM-as-module (via nixos-rebuild, useUserPackages=true)
        # and HM-as-flake (via `hms`). HM-as-module wipes the legacy nix-env user
        # profile under ~/.nix-profile during activation, which invalidates any
        # absolute paths zsh already cached from there (e.g. starship). hash -r
        # is in-process and effectively free.
        # NB: add-zsh-hook requires a function NAME, not a command — wrap hash -r.
        autoload -Uz add-zsh-hook
        _hwc_hash_refresh() { hash -r; }
        add-zsh-hook precmd _hwc_hash_refresh

        # NixOS rebuild shortcuts (dynamic hostname)
        # `env HOME=~root` stops Nix warning that /home/eric isn't owned by root.
        # (sudo -H / -i don't work here: this system's sudo preserves the caller's
        # environment and HOME survives both flags — verified 2026-06-10.)
        # snix/tnix auto-reload Hyprland when run inside a Hyprland session because they
        # activate the HM-as-module config (via home-manager-eric.service, oneshot, so
        # ~/.config/hypr/hyprland.conf is on disk by the time the command returns).
        # bnix is pure build, no activation, so no reload.
        # _hwc_rebuild tees output to a temp log and re-prints warning lines at the
        # end so deprecation warnings can't scroll away unnoticed (zero-warning baseline).
        _hwc_rebuild() {
          local log rc warns
          log=$(mktemp -t nixos-rebuild-log.XXXXXX)
          sudo env HOME=~root nixos-rebuild "$@" --flake "$HWC_NIXOS_DIR#$(hostname)" 2>&1 | tee "$log"
          rc=''${pipestatus[1]}
          warns=$(grep -E '^(evaluation warning|warning|trace):' "$log" | sort -u)
          rm -f "$log"
          if [ -n "$warns" ]; then
            print -P "\n%F{yellow}── warnings (deduped) ──%f"
            print -r -- "$warns"
          fi
          return $rc
        }
        snix() {
          if [ -n "$(git -C "$HWC_NIXOS_DIR" status --porcelain 2>/dev/null)" ]; then
            print -P "%F{yellow}dirty git tree%f — doctrine: commit before rebuild"
            git -C "$HWC_NIXOS_DIR" status --short
            read -q "?continue anyway? [y/N] " || { print; return 1; }
            print
          fi
          _hwc_rebuild switch "$@" || return $?
          hash -r
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }
        tnix() {
          _hwc_rebuild test "$@" || return $?
          hash -r
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }
        bnix() {
          _hwc_rebuild build "$@"
        }

        # Home Manager standalone activation (HM-as-flake path).
        # Auto-reloads Hyprland after activation when running inside a
        # Hyprland session, because HM activation writes ~/.config/hypr/
        # hyprland.conf but does not signal the compositor. Reload is a
        # no-op if the new generation didn't change hyprland config.
        # Extra args (e.g. --show-trace, --refresh) are forwarded to nix build.
        hms() {
          local activator
          activator=$(nix build --no-link --print-out-paths \
            "$HWC_NIXOS_DIR#homeConfigurations.\"eric@$(hostname)\".activationPackage" \
            "$@") || return $?
          "$activator/activate" || return $?
          hash -r
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }

        # Fuzzy finding function
        ff() {
          fd -t f . ~ | fzf --query="$*" --preview 'head -20 {}'
        }

        # Quick system status check
        status() {
          echo "System Status Overview"
          echo "=========================="
          echo "Memory: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
          echo "Disk: $(df -h / | awk 'NR==2{print $5}')"
          echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
        }

        # add-app shell function
        add-app() {
          ${config.home.homeDirectory}/.nixos/workspace/nixos-dev/add-home-app.sh "$@"
        }

        # Interactive graph function for hwc-graph tool
        graph() {
          local graph_script="${config.home.homeDirectory}/.nixos/workspace/nixos-dev/graph/hwc_graph.py"

          # If arguments provided, pass directly to script
          if [ $# -gt 0 ]; then
            python3 "$graph_script" "$@"
            return
          fi

          # Interactive mode
          echo "HWC Dependency Graph Analyzer"
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
                  echo "Module name required"
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
                  echo "Module name required"
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
                  echo "Module name required"
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
                echo "Exported to $output_file"
                break
                ;;
              7)
                echo "Goodbye!"
                break
                ;;
              *)
                echo "Invalid option. Please choose 1-7."
                ;;
            esac
          done
        }
      '';
    };

    # Global fd ignore
    xdg.configFile."fd/ignore".text = ''
      .git/
      node_modules/
      __pycache__/
      .cache/
      .vscode-server/
      .nix-profile/
      .nix-defexpr/
    '';

    # Starship prompt — powerline style, Gruvbox Material Dark colors
    programs.starship = lib.mkIf cfg.zsh.starship {
      enable = true;
      settings = {
        scan_timeout = 100;
        command_timeout = 1000;
        add_newline = false;

        format = lib.concatStrings [
          "[](fg:#32302f bg:#856b43)"
          "$directory"
          "$git_branch"
          "$git_status"
          "[](fg:#576f69 bg:#32302f) "
          "$character"
        ];

        directory = {
          format = "[ $path ](bg:#856b43 fg:#d4be98)";
          truncation_length = 3;
          truncation_symbol = ".../";
          style = "bg:#856b43 fg:#d4be98";
        };

        git_branch = {
          format = "[](fg:#856b43 bg:#576f69)[ $symbol$branch ](bg:#576f69 fg:#d4be98)";
          symbol = " ";
          style = "bg:#576f69 fg:#d4be98";
        };

        git_status = {
          format = "[$all_status$ahead_behind ](bg:#576f69 fg:#d8a657)";
          style = "bg:#576f69 fg:#d8a657";
          conflicted = "!";
          ahead = "⇡\${count}";
          behind = "⇣\${count}";
          diverged = "⇕";
          untracked = "?";
          modified = "~";
          staged = "+";
          deleted = "✘";
        };

        python  = { disabled = true; };
        nodejs  = { disabled = true; };
        rust    = { disabled = true; };
        golang  = { disabled = true; };

        character = {
          success_symbol = "[❯](bold fg:#a9b665)";
          error_symbol   = "[❯](bold fg:#ea6962)";
        };
      };
    };

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
}
