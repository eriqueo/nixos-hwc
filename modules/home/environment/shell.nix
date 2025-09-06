# nixos-hwc/modules/home/environment/shell.nix
#
# SHELL ENVIRONMENT - Complete shell and CLI configuration
# Consolidated module combining shell, CLI tools, and modern Unix replacements
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#
# USED BY (Downstream):
#   - Imported via Home Manager user configuration (e.g., in machines/laptop/home.nix)
#
# USAGE:
#   hwc.home.shell.enable = true;

{ config, lib, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.home.shell;
in
{
  #============================================================================
  # OPTIONS - Refactored for modern Home Manager API
  #============================================================================
  options.hwc.home.shell = {
    enable = lib.mkEnableOption "Complete shell + CLI environment";

    modernUnix = lib.mkEnableOption "modern Unix replacements (eza, bat, etc.)";

    packages = lib.mkOption {
      type = t.listOf t.package;
      default = with pkgs; [
        ripgrep fd fzf bat jq curl wget unzip tree micro btop fastfetch
        rsync rclone speedtest-cli nmap traceroute dig zip p7zip yq pandoc
        xclip diffutils less which lsof pstree git vim nano claude-code
      ];
      description = "Base CLI/tool packages.";
    };

    sessionVariables = lib.mkOption {
      type = t.attrsOf t.str;
      default = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
        EDITOR = "micro";
        VISUAL = "micro";
      };
      description = "Environment variables for the user session.";
    };

    aliases = lib.mkOption {
      type = t.attrsOf t.str;
      default = {
        "ll" = "eza -l";
        "la" = "eza -la";
        "lt" = "eza --tree --level=2";
        "cd" = "z";
        "cdi" = "zi";
        "cz" = "z";
        "czz" = "zi";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        "df" = "df -h";
        "du" = "du -h";
        "free" = "free -h";
        "htop" = "btop";
        "grep" = "rg";
        "open" = "xdg-open";
        "gs" = "git status -sb";
        "ga" = "git add .";
        "gc" = "git commit -m";
        "gp" = "git push";
        "gpl" = "git pull";
        "gl" = "git log --oneline --graph --decorate --all";
        "gll" = "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        "gresync" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && cd \"$nixdir\" && git fetch origin && git pull origin master && echo '✅ Git sync complete!'";
        "gstatus" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && cd \"$nixdir\" && git status";
        "glog" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && cd \"$nixdir\" && git log --oneline -10";
        "nixflake" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && ${EDITOR:-micro} \"$nixdir/flake.nix\"";
        "nixlaphome" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && ${EDITOR:-micro} \"$nixdir/machines/laptop/home.nix\"";
        "nixlapcon" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && ${EDITOR:-micro} \"$nixdir/machines/laptop/config.nix\"";
        "nixserverhome" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && ${EDITOR:-micro} \"$nixdir/machines/server/home.nix\"";
        "nixservercon" = "nixdir=$(find /etc/nixos ~/.nixos ~/.config/nixos -maxdepth 1 -type d 2>/dev/null | head -1) && ${EDITOR:-micro} \"$nixdir/machines/server/config.nix\"";
        "nixsearch" = "nix search nixpkgs";
        "nixclean" = "nix-collect-garbage -d";
        "nixgen" = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
        "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me";
        "reload" = "source ~/.zshrc";
        "homeserver" = "ssh eric@100.115.126.41";
        "server" = "ssh eric@100.115.126.41";
      };
      description = "Shell aliases for zsh";
    };

    git = {
      enable = lib.mkEnableOption "Git configuration";
      userName = lib.mkOption { type = t.str; default = "Eric"; };
      userEmail = lib.mkOption { type = t.str; default = "eric@hwc.moe"; };
    };

    zsh = {
      enable = lib.mkEnableOption "Zsh via Home-Manager";
      starship = lib.mkEnableOption "Starship prompt";
      autosuggestions = lib.mkEnableOption "zsh-autosuggestions";
      syntaxHighlighting = lib.mkEnableOption "zsh-syntax-highlighting";
      initContent = lib.mkOption {
        type = t.lines;
        default = "";
        description = "Additional Zsh init lines";
      };
    };

    tmux = {
      enable = lib.mkEnableOption "tmux via Home-Manager";
      extraConfig = lib.mkOption { type = t.lines; default = ""; };
    };
  };

  #============================================================================
  # IMPLEMENTATION - Complete shell and CLI environment
  #============================================================================
  config = lib.mkIf cfg.enable {

    home.packages = cfg.packages ++ lib.optionals cfg.modernUnix (with pkgs; [
      eza bat procs dust zoxide
    ]);

    home.sessionVariables = cfg.sessionVariables;

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
        # ... other settings
      };
    };

    programs.git = lib.mkIf cfg.git.enable {
      enable = true;
      userName = cfg.git.userName;
      userEmail = cfg.git.userEmail;
      extraConfig = {
        init.defaultBranch = "main";
        core.editor = "micro";
      };
    };

    programs.zsh = {
      enable = cfg.zsh.enable;
      autosuggestion.enable = cfg.zsh.autosuggestions;
      syntaxHighlighting.enable = cfg.zsh.syntaxHighlighting;
      history = {
        size = 5000;
        save = 5000;
      };
      shellAliases = cfg.aliases;
      initContent = cfg.zsh.initContent;
      envExtra = ''
        # Guarded Home Manager session variables loader
        if [ -f "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
          . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
        fi
      '';
    };

    programs.starship.enable = cfg.zsh.starship;

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.tmux = {
      enable = cfg.tmux.enable;
      clock24 = true;
      keyMode = "vi";
      mouse = true;
      extraConfig = cfg.tmux.extraConfig;
    };
  };
}

