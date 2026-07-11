# domains/home/core/shell/index.nix
#
# Complete shell and CLI configuration
#
# NAMESPACE: hwc.home.core.shell.*
# USED BY: profiles/base/home.nix
# USAGE: hwc.home.core.shell.enable = true;

{ config, lib, pkgs, osConfig ? {}, nixosApiVersion ? "unstable", ... }:

let
  cfg = config.hwc.home.core.shell;
  ws = "$HWC_WORKSPACE_ROOT";
  # Law 3 + Law 1: derive from system paths when hosted on NixOS, with a
  # home-derived fallback so the module evaluates with osConfig = {}.
  nixosPath =
    let p = lib.attrByPath [ "hwc" "paths" "nixos" ] null osConfig;
    in if p != null then p else "${config.home.homeDirectory}/.nixos";

  # Theme tokens (guarded read — Law 1). Fallbacks are the palette's own
  # values so the module renders identically without the theme module.
  themeColors = (config.hwc.home.theme or {}).colors or {};
  col = name: fallback: themeColors.${name} or fallback;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.core.shell = {
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
      default = { };
      description = "Extra shell aliases, merged over the base set from parts/aliases.nix (same-name entries win).";
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
      brain = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include the brain MCP server (vault CRUD + semantic search) as a native HTTP entry — tailnet-gated, no token (brain-mcp dropped Bearer auth 2026-05-22)";
        };
        url = lib.mkOption {
          type = lib.types.str;
          default = "https://hwc-server.ocelot-wahoo.ts.net:23443/mcp";
          description = "brain-mcp streamable-HTTP endpoint (Caddy tailnet route)";
        };
      };
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

    programs.fzf = import ./parts/fzf.nix { inherit col; };

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

    # SSH configuration (per-API translation) — see parts/ssh.nix
    programs.ssh = lib.mkIf cfg.ssh.enable (import ./parts/ssh.nix { inherit lib cfg nixosApiVersion; });

    # Zsh configuration
    programs.zsh = lib.mkIf cfg.zsh.enable {
      enable = true;
      autosuggestion.enable = cfg.zsh.autosuggestions;
      syntaxHighlighting.enable = cfg.zsh.syntaxHighlighting;
      history = {
        size = 5000;
        save = 5000;
      };
      shellAliases = (import ./parts/aliases.nix { inherit ws nixosPath; }) // cfg.aliases;
      initContent = import ./parts/zsh-init.nix { inherit config; };
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

    # Starship prompt — powerline style, palette colors (parts/prompt.nix)
    programs.starship = lib.mkIf cfg.zsh.starship {
      enable = true;
      settings = import ./parts/prompt.nix { inherit lib col; };
    };

    # Direnv for development environments
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # tmux is owned by domains/home/apps/tmux (hwc.home.apps.tmux) —
    # the duplicate hwc.home.shell.tmux surface was removed 2026-06-11.

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
          # git/time/fetch are Python reference servers published on PyPI, not npm.
          # They run via uvx (uv); the old npx @modelcontextprotocol/server-* paths 404.
          git = {
            command = "uvx";
            args = [ "mcp-server-git" ];
            cwd = "${config.home.homeDirectory}/.nixos";
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
            command = "uvx";
            args = [ "mcp-server-time" ];
          };
          fetch = {
            command = "uvx";
            args = [ "mcp-server-fetch" ];
          };
          memory = {
            command = "npx";
            args = [ "-y" "@modelcontextprotocol/server-memory" ];
          };
        } // lib.optionalAttrs cfg.mcp.brain.enable {
          # Native streamable-HTTP entry (Claude Code supports type=http).
          # No auth header: brain-mcp is tailnet-gated (Bearer removed 2026-05-22).
          brain = {
            type = "http";
            url = cfg.mcp.brain.url;
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
