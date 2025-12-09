# HWC Charter Module/domains/home/environment/shell/options.nix
#
# SHELL OPTIONS - Complete shell and CLI configuration options
# Following HWC charter namespace pattern: domains/home/environment/shell/ → hwc.home.shell.*
#
# DEPENDENCIES (Upstream):
#   - None (options only)
#
# USED BY (Downstream):
#   - domains/home/environment/shell/index.nix (implements these options)
#   - profiles/home.nix (enables via hwc.home.shell.enable)
#
# NAMESPACE: hwc.home.shell.*

{ lib, pkgs, ... }:

{
  #============================================================================
  # OPTIONS - Shell Configuration API
  #============================================================================
  options.hwc.home.shell = {
    enable = lib.mkEnableOption "Complete shell + CLI environment";

    modernUnix = lib.mkEnableOption "modern Unix replacements (eza, bat, etc.)";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        ripgrep fd fzf bat jq curl wget unzip tree micro btop fastfetch
        rsync rclone speedtest-cli nmap traceroute dig zip p7zip yq pandoc
        xclip diffutils less which lsof pstree git vim nano claude-code
      ];
      description = "Base CLI/tool packages.";
    };

    sessionVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
        EDITOR = "micro";
        VISUAL = "micro";
        HWC_NIXOS_DIR = "/home/eric/.nixos";
      };
      description = "Environment variables for the user session.";
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "ll" = "eza -l";
        "la" = "eza -lh";
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
        "nixflake" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/flake.nix\"";
        "nixlaphome" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/laptop/home.nix\"";
        "nixlapcon" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/laptop/config.nix\"";
        "nixserverhome" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/server/home.nix\"";
        "nixservercon" = "${pkgs.micro}/bin/micro \"$HWC_NIXOS_DIR/machines/server/config.nix\"";
        "nixsearch" = "nix search nixpkgs";
        "nixclean" = "nix-collect-garbage -d";
        "nixgen" = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
        "checkup" = "$HWC_NIXOS_DIR/scripts/system-checkup.sh";
        "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me";
        "reload" = "source ~/.zshrc";
        "homeserver" = "ssh eric@100.115.126.41";
        "server" = "ssh eric@100.115.126.41";
        "vpnon" = "sudo wg-quick up protonvpn";
        "vpnoff" = "sudo wg-quick down protonvpn";
        "vpnstatus" = "sudo wg show protonvpn 2>/dev/null || echo 'VPN disconnected'";
        "cdn" = "cd ~/.nixos";
        # Directory shortcuts
        "downloads" = "cd ~/00-inbox/downloads";
        "hwc" = "cd ~/01-hwc";
        "inbox" = "cd ~/00-inbox";
        "media" = "cd /mnt/media";
        "movies" = "cd /mnt/media/movies";
        "music" = "cd /mnt/media/music";
        "nixos" = "cd ~/03-tech/01-active/nixos";
        "screenshots" = "cd ~/05-media/pictures/screenshots";
        "tech" = "cd ~/03-tech";
        "tv" = "cd /mnt/media/tv";
        "vaults" = "cd ~/99-vaults";
        
        # Application shortcuts
        # ai-chat is now a proper script at /run/current-system/sw/bin/ai-chat
        "business-db" = "psql postgresql://business_user:secure_password_change_me@localhost:5432/heartwood_business";
        "business-dev" = "cd /opt/business && source /etc/business/setup-dev-env.sh";
        "cameras" = "echo 'Frigate: http://100.115.126.41:5000'";
        "context-snap" = "python3 /opt/adhd-tools/scripts/context-snapshot.py";
        "cost-dashboard" = "cd /opt/business/dashboard && streamlit run dashboard.py";
        "energy-log" = "python3 /etc/adhd-tools/energy-tracker.py";
        "focus-mode" = "systemctl --user start context-monitor";
        "focus-off" = "systemctl --user stop context-monitor";
        "frigate-logs" = "sudo podman logs -f frigate";
        "ha-logs" = "sudo podman logs -f home-assistant";
        "home-assistant" = "echo 'Home Assistant: http://100.115.126.41:8123'";
        "jobtread-sync" = "cd /opt/business/api && python3 services/jobtread_sync.py";
        "receipt-process" = "cd /opt/business/receipts && python3 ../api/services/ocr_processor.py";
        "work-stats" = "python3 /opt/adhd-tools/scripts/productivity-analysis.py";
        # Tool aliases
        "eza" = "eza --icons auto --git --group-directories-first";
        "ls" = "eza";
        "vpn" = "vpnstatus";
        "which-command" = "whence";
        "run-help" = "man";
        # Journal/log analysis aliases
        "errors" = "journal-errors";
        "errors-hour" = "journal-errors '1 hour ago'";
        "errors-today" = "journal-errors 'today'";
        "errors-tdarr" = "journal-errors '10 minutes ago' podman-tdarr";
        # Service monitoring aliases
        "services" = "list-services";
        "ss" = "list-services";
        # Development aliases
        "rebuild" = "grebuild";
        "lint" = "charter-lint";
        # Health check aliases
        "caddy" = "caddy-health";
        "health" = "caddy-health";
      };
      description = "Shell aliases for zsh";
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

    zsh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Zsh via Home-Manager";
      };
      starship = lib.mkEnableOption "Starship prompt";
      autosuggestions = lib.mkEnableOption "zsh-autosuggestions";
      syntaxHighlighting = lib.mkEnableOption "zsh-syntax-highlighting";
    };

    tmux = {
      enable = lib.mkEnableOption "tmux via Home-Manager";
      extraConfig = lib.mkOption { 
        type = lib.types.lines; 
        default = ""; 
        description = "Additional tmux configuration";
      };
    };

    # Scripts are now defined as shell functions in index.nix
    # No need for enable options - they're always available

    # MCP (Model Context Protocol) configuration
    mcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable MCP configuration file generation for Claude Desktop";
      };

      includeConfigDir = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include user config directory in filesystem MCP server (laptop only)";
      };

      includeServerTools = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include server-specific MCP tools (postgres, prometheus, puppeteer)";
      };
    };
  };
}
