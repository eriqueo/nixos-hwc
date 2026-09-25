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
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  # Tailnet addresses from hwc.networking.hosts (Law 1 fallback lives in hmLib,
  # the single HM-lane copy). Never retype a tailnet IP here.
  fleet = hmLib.fleet osConfig;
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
            proxyCommand = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional ProxyCommand (e.g. cloudflared Access ssh for hosts behind a Cloudflare tunnel).";
            };
          };
        });
        default = {
          server = { hostname = fleet.ips.main; user = "eric"; forwardAgent = true; };
          # Home-LAN fallback for when Tailscale can't connect (internet down).
          server-lan = { hostname = fleet.lanIps.main; user = "eric"; forwardAgent = true; };
          # Elliott's lil-box (DataX), reachable only via Cloudflare Access.
          # Agent forwarding OFF: never forward your ssh-agent into a third party's box.
          lil-box = {
            hostname = "lil-box.icebanditbox.com";
            user = "eric";
            forwardAgent = false;
            proxyCommand = "cloudflared access ssh --hostname %h";
          };
        };
        description = "SSH host configurations";
      };
    };

    # MCP client config (~/.mcp.json) moved to the system lane on 2026-09-25:
    # hwc.system.apps.agent-harness.userMcp (domains/home/apps/agent-harness/sys.nix).
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

    programs.fzf = import ./parts/fzf.nix { inherit col nixosApiVersion; };

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
      shellAliases = (import ./parts/aliases.nix { inherit ws nixosPath fleet; }) // cfg.aliases;
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
      # HM's integration runs `starship init zsh` with the ambient PATH, which
      # bakes ~/.nix-profile/bin/starship after an `hms` and breaks every shell
      # on the next nixos-rebuild. parts/zsh-init.nix owns the init instead.
      enableZshIntegration = false;
      settings = import ./parts/prompt.nix { inherit lib col; };
    };

    # Direnv for development environments
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # tmux is owned by domains/home/apps/tmux (hwc.home.apps.tmux) —
    # the duplicate hwc.home.shell.tmux surface was removed 2026-06-11.
  };
}
