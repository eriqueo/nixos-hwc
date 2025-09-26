# nixos-h../domains/home/environment/shell.nix
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
        HWC_NIXOS_DIR = "/home/eric/.nixos";
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
        "gresync" = "cd \"$HWC_NIXOS_DIR\" && git fetch origin && git pull origin master && echo '✅ Git sync complete!'";
        "gstatus" = "cd \"$HWC_NIXOS_DIR\" && git status";
        "glog" = "cd \"$HWC_NIXOS_DIR\" && git log --oneline -10";
        "nixflake" = "${EDITOR:-micro} \"$HWC_NIXOS_DIR/flake.nix\"";
        "nixlaphome" = "${EDITOR:-micro} \"$HWC_NIXOS_DIR/machines/laptop/home.nix\"";
        "nixlapcon" = "${EDITOR:-micro} \"$HWC_NIXOS_DIR/machines/laptop/config.nix\"";
        "nixserverhome" = "${EDITOR:-micro} \"$HWC_NIXOS_DIR/machines/server/home.nix\"";
        "nixservercon" = "${EDITOR:-micro} \"$HWC_NIXOS_DIR/machines/server/config.nix\"";
        "nixsearch" = "nix search nixpkgs";
        "nixclean" = "nix-collect-garbage -d";
        "nixgen" = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
        "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me";
        "reload" = "source ~/.zshrc";
        "homeserver" = "ssh eric@100.115.126.41";
        "server" = "ssh eric@100.115.126.41";
        "vpnon" = "sudo wg-quick up protonvpn";
        "vpnoff" = "sudo wg-quick down protonvpn";
        "vpnstatus" = "sudo wg show protonvpn 2>/dev/null || echo 'VPN disconnected'";
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
        default = ''
          # Enhanced grebuild function with dynamic directory detection
          grebuild() {
            if [[ -z "$1" ]]; then
              echo "Usage: grebuild <commit message>"
              echo "       grebuild --test <commit message>  (test only, no switch)"
              echo "       grebuild --sync  (sync only, no rebuild)"
              echo "Example: grebuild 'added waybar autostart'"
              return 1
            fi

            # Save current directory
            local original_dir="$PWD"

            # Use dynamic NixOS config directory
            local nixdir="$HWC_NIXOS_DIR"

            if [[ -z "$nixdir" || ! -d "$nixdir" ]]; then
              echo "❌ Could not find NixOS configuration directory at: $nixdir"
              echo "💡 HWC_NIXOS_DIR environment variable may not be set correctly"
              return 1
            fi

            # Change to NixOS config directory
            cd "$nixdir" || {
              echo "❌ Could not access $nixdir directory"
              return 1
            }

            echo "📁 Working in: $nixdir"

            # Check for test mode
            local test_mode=false
            if [[ "$1" == "--test" ]]; then
              test_mode=true
              shift
              if [[ -z "$1" ]]; then
                echo "❌ Commit message required even in test mode"
                cd "$original_dir"
                return 1
              fi
            fi

            # Handle sync-only mode
            if [[ "$1" == "--sync" ]]; then
              echo "🔄 Syncing with remote..."
              if ! sudo -E git fetch origin; then
                echo "❌ Git fetch failed"
                cd "$original_dir"
                return 1
              fi
              if ! sudo -E git pull origin master; then
                echo "❌ Git pull failed - resolve conflicts manually"
                cd "$original_dir"
                return 1
              fi
              echo "✅ Git sync complete!"
              cd "$original_dir"
              return 0
            fi

            # Check if tree is dirty
            if ! sudo git diff-index --quiet HEAD 2>/dev/null; then
              echo "📋 Detected local changes to commit"
              local has_changes=true
            else
              echo "✅ Working tree is clean"
              local has_changes=false
            fi

            # ENHANCED SYNC - Handle multi-host scenarios safely
            echo "🔄 Syncing with remote (safe multi-host sync)..."

            # Stash local changes if any exist
            local stash_created=false
            if [[ "$has_changes" == true ]]; then
              echo "💾 Stashing local changes for safe sync..."
              if sudo git stash push -m "grebuild-temp-$(date +%s)"; then
                stash_created=true
                echo "✅ Local changes stashed"
              else
                echo "❌ Failed to stash local changes"
                cd "$original_dir"
                return 1
              fi
            fi

            # Fetch and pull latest changes
            if ! sudo -E git fetch origin; then
              echo "❌ Git fetch failed"
              if [[ "$stash_created" == true ]]; then
                echo "🔄 Restoring stashed changes..."
                sudo git stash pop
              fi
              cd "$original_dir"
              return 1
            fi

            if ! sudo -E git pull origin master; then
              echo "❌ Git pull failed - resolve conflicts manually"
              if [[ "$stash_created" == true ]]; then
                echo "🔄 Restoring stashed changes..."
                sudo git stash pop
              fi
              cd "$original_dir"
              return 1
            fi

            # Restore local changes on top of pulled changes
            if [[ "$stash_created" == true ]]; then
              echo "🔄 Applying local changes on top of remote changes..."
              if ! sudo git stash pop; then
                echo "❌ Merge conflict applying local changes!"
                echo "💡 Resolve conflicts manually and run 'git stash drop' when done"
                cd "$original_dir"
                return 1
              fi
              echo "✅ Local changes applied successfully"
            fi

            # Add all changes (including any merged ones)
            echo "📝 Adding all changes..."
            if ! sudo git add .; then
              echo "❌ Git add failed"
              cd "$original_dir"
              return 1
            fi

            # IMPROVED FLOW: Test BEFORE committing
            echo "🧪 Testing configuration before committing..."
            local hostname=$(hostname)
            local test_success=false

            if [[ -f flake.nix ]]; then
              if sudo nixos-rebuild test --flake .#"$hostname"; then
                test_success=true
              fi
            else
              if sudo nixos-rebuild test; then
                test_success=true
              fi
            fi

            if [[ "$test_success" != true ]]; then
              echo "❌ NixOS test failed! No changes committed."
              echo "💡 Fix configuration issues and try again"
              cd "$original_dir"
              return 1
            fi

            echo "✅ Test passed! Configuration is valid."

            if [[ "$test_mode" == true ]]; then
              echo "✅ Test mode complete! Configuration is valid but not committed."
              cd "$original_dir"
              return 0
            fi

            # Only commit if test passed
            echo "💾 Committing tested changes: $*"
            if ! sudo git commit -m "$*"; then
              echo "❌ Git commit failed"
              cd "$original_dir"
              return 1
            fi

            echo "☁️  Pushing to remote..."
            if ! sudo -E git push; then
              echo "❌ Git push failed"
              cd "$original_dir"
              return 1
            fi

            # Switch to new configuration (already tested)
            echo "🔄 Switching to new configuration..."
            if [[ -f flake.nix ]]; then
              if ! sudo nixos-rebuild switch --flake .#"$hostname"; then
                echo "❌ NixOS switch failed (but changes are committed)"
                cd "$original_dir"
                return 1
              fi
            else
              if ! sudo nixos-rebuild switch; then
                echo "❌ NixOS switch failed (but changes are committed)"
                cd "$original_dir"
                return 1
              fi
            fi

            echo "✅ Complete! System rebuilt and switched with: $*"
            cd "$original_dir"
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
        '';
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
      initContent = ''
        # add-app shell function
        add-app() {
          /home/eric/.nixos/scripts/add-home-app.sh "$@"
        }
        
        ${cfg.zsh.initContent}
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

