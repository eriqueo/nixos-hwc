# nixos-hwc/modules/home/environment/shell.nix
#
# SHELL ENVIRONMENT - Complete shell and CLI configuration
# Consolidated module combining shell, CLI tools, and modern Unix replacements
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#   - profiles/workstation.nix (imports this module)
#   - modules/home/theme/palettes/deep-nord.nix (for theming)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.home.shell.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../modules/home/environment/shell.nix ]
#
# USAGE:
#   hwc.home.shell.enable = true;
#   hwc.home.shell.modernUnix = true;
#   hwc.home.shell.git.enable = true;
#   hwc.home.shell.zsh = {
#     enable = true;
#     starship = true;
#     plugins.autosuggestions = true;
#     plugins.syntaxHighlighting = true;
#   };

{ config, lib, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.home.shell;
in
{
  #============================================================================
  # OPTIONS - Complete shell and CLI configuration
  #============================================================================
  options.hwc.home.shell = {
    enable = lib.mkEnableOption "Complete shell + CLI environment via Home-Manager";

    modernUnix = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable modern Unix replacements (eza, bat, fd, etc.)";
    };

    packages = lib.mkOption {
      type = t.listOf t.package;
      default = with pkgs; [
        # Modern CLI replacements (base set)
        ripgrep fd fzf bat jq curl wget unzip
        # Essential utilities
        tree micro btop fastfetch
        # Network and transfer tools
        rsync rclone speedtest-cli nmap traceroute dig
        # Archive and compression
        zip p7zip
        # Text and data processing
        yq pandoc
        # System utilities
        xclip diffutils less which lsof pstree
        # Core development
        git vim nano
        # AI/Development tools
        claude-code
      ];
      description = "Base CLI/tool packages (additional tools added based on modernUnix option)";
    };

    sessionVariables = lib.mkOption {
      type = t.attrsOf t.str;
      default = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
        EDITOR = "micro";
        VISUAL = "micro";
      };
      description = "Environment variables for the user session";
    };

    aliases = lib.mkOption {
      type = t.attrsOf t.str;
      default = {
        # File management shortcuts (modern tools)
        "ll" = "eza -l";
        "la" = "eza -la"; 
        "lt" = "eza --tree --level=2";

        # Navigation shortcuts (zoxide)
        "cd" = "z";
        "cdi" = "zi";       # interactive selection
        "cz" = "z";         # short mnemonic
        "czz" = "zi";       # short mnemonic for interactive
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # System utilities (modernized)
        "df" = "df -h";
        "du" = "du -h"; 
        "free" = "free -h";
        "htop" = "btop";
        "grep" = "rg";
        "open" = "xdg-open";

        # Universal git = sudo git (consistent everywhere)
        "git" = "sudo git";

        # Git workflow shortcuts (all use sudo for consistency)
        "gs" = "sudo git status -sb";
        "ga" = "sudo git add .";
        "gc" = "sudo git commit -m";
        "gp" = "sudo git push";
        "gl" = "sudo git log --oneline --graph --decorate --all";
        "gpl" = "sudo git pull";

        # NixOS-specific git sync aliases
        "gresync" = "cd /etc/nixos && sudo git fetch origin && sudo git pull origin master && echo '✅ Git sync complete!'";
        "gstatus" = "cd /etc/nixos && sudo git status";
        "glog" = "cd /etc/nixos && sudo git log --oneline -10";

        # NixOS system management
        "nixcon" = "sudo micro /etc/nixos/configuration.nix";
        "nixflake" = "sudo micro /etc/nixos/flake.nix";
        "nixlaphome" = "sudo micro /etc/nixos/hosts/laptop/home.nix";
        "nixlapcon" = "sudo micro /etc/nixos/hosts/laptop/config.nix";
        "nixserverhome" = "sudo micro /etc/nixos/hosts/server/home.nix";
        "nixservercon" = "sudo micro /etc/nixos/hosts/server/config.nix";
        "nixsecrets" = "sudo micro /etc/nixos/shared/secrets.nix";
        "nixcameras" = "sudo micro /etc/nixos/hosts/server/modules/surveillance.nix";
        
        # NixOS utilities
        "nixsearch" = "nix search nixpkgs";
        "nixclean" = "nix-collect-garbage -d";
        "nixgen" = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";

        # Development and productivity
        "speedtest" = "speedtest-cli";
        "myip" = "curl -s ifconfig.me";
        "reload" = "source ~/.zshrc";

        # SERVER-SPECIFIC ALIASES (safe to have on laptop)
        # Media server navigation
        "media" = "cd /mnt/media";
        "tv" = "cd /mnt/media/tv";
        "movies" = "cd /mnt/media/movies";

        # AI and business intelligence
        "ai-chat" = "ollama run llama3.2:3b";
        "business-dev" = "cd /opt/business && source /etc/business/setup-dev-env.sh";
        "context-snap" = "python3 /opt/adhd-tools/scripts/context-snapshot.py";
        "energy-log" = "python3 /etc/adhd-tools/energy-tracker.py";

        # Business workflow automation
        "receipt-process" = "cd /opt/business/receipts && python3 ../api/services/ocr_processor.py";
        "cost-dashboard" = "cd /opt/business/dashboard && streamlit run dashboard.py";
        "jobtread-sync" = "cd /opt/business/api && python3 services/jobtread_sync.py";
        "business-db" = "psql postgresql://business_user:secure_password_change_me@localhost:5432/heartwood_business";

        # ADHD productivity tools
        "focus-mode" = "systemctl --user start context-monitor";
        "focus-off" = "systemctl --user stop context-monitor";
        "work-stats" = "python3 /opt/adhd-tools/scripts/productivity-analysis.py";

        # Surveillance system shortcuts
        "cameras" = "echo 'Frigate: http://100.115.126.41:5000'";
        "home-assistant" = "echo 'Home Assistant: http://100.115.126.41:8123'";
        "frigate-logs" = "sudo podman logs -f frigate";
        "ha-logs" = "sudo podman logs -f home-assistant";

        # SSH shortcuts
        "homeserver" = "ssh eric@100.115.126.41";
        "server" = "ssh eric@100.115.126.41";

        # VPN management (ProtonVPN - Simple On-Demand Toggle)
        "vpn" = "vpnstatus";
        "vpncheck" = "vpnstatus";
      };
      description = "Shell aliases for zsh";
    };

    git = {
      enable = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Git configuration";
      };
      userName = lib.mkOption {
        type = t.str;
        default = "Eric";
        description = "Git user name";
      };
      userEmail = lib.mkOption {
        type = t.str;
        default = "eric@hwc.moe";
        description = "Git user email";
      };
    };

    zsh = {
      enable = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Zsh via Home-Manager";
      };

      starship = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Starship prompt";
      };

      plugins = {
        autosuggestions = lib.mkOption {
          type = t.bool;
          default = true;
          description = "Enable zsh-autosuggestions";
        };
        syntaxHighlighting = lib.mkOption {
          type = t.bool;
          default = true;
          description = "Enable zsh-syntax-highlighting";
        };
      };

      initExtra = lib.mkOption {
        type = t.lines;
        default = ''
          # Enhanced grebuild function with improved safety and multi-host sync
          grebuild() {
            if [[ -z "$1" ]]; then
              echo "Usage: grebuild <commit message>"
              echo "       grebuild --test <commit message>  (test only, no switch)"
              echo "       grebuild --sync  (sync only, no rebuild)"
              echo "Example: grebuild 'added Jellyfin port to firewall'"
              return 1
            fi

            # Save current directory
            local original_dir="$PWD"

            # Change to NixOS config directory
            cd /etc/nixos || {
              echo "❌ Could not access /etc/nixos directory"
              return 1
            }

            echo "📁 Working in: /etc/nixos"

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

          # Test-only version
          gtest() {
            grebuild --test "$@"
          }

          # ADHD-friendly productivity functions
          mkcd() {
            mkdir -p "$1" && cd "$1"
          }

          # Fuzzy finding functions (using modern CLI tools)
          ff() {
            fd -t f . ~ | fzf --query="$*" --preview 'head -20 {}'
          }

          fn() {
            fd -t f . /etc/nixos | fzf --query="$*" --preview 'head -20 {}'
          }

          # Universal archive extraction
          extract() {
            if [[ -f "$1" ]]; then
              case "$1" in
                *.tar.gz)  tar -xzf "$1" ;;
                *.tar.xz)  tar -xJf "$1" ;;
                *.tar.bz2) tar -xjf "$1" ;;
                *.zip)     unzip "$1" ;;
                *.rar)     unrar x "$1" ;;
                *)         echo "'$1' cannot be extracted" ;;
              esac
            else
              echo "'$1' is not a valid file"
            fi
          }

          # Quick search and replace in files
          sr() {
            (( $# != 3 )) && { echo "Usage: sr <search> <replace> <file>"; return 1; }
            sed -i "s/$1/$2/g" "$3"
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
        description = "Additional Zsh init lines (programs.zsh.initExtra)";
      };
    };

    tmux = {
      enable = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable tmux via Home-Manager";
      };

      extraConfig = lib.mkOption {
        type = t.lines;
        default = "";
        description = "Extra tmux.conf content (programs.tmux.extraConfig)";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - Complete shell and CLI environment
  #============================================================================
  config = lib.mkIf cfg.enable {

    # --- Packages: Base + Modern Unix tools ---
    home.packages = cfg.packages ++ lib.optionals cfg.modernUnix (with pkgs; [
      # Modern Unix replacements
      eza          # ls replacement
      bat          # cat replacement  
      procs        # ps replacement
      dust         # du replacement
      zoxide       # cd replacement
    ]);

    # --- Session Variables ---
    home.sessionVariables = cfg.sessionVariables;

    # --- Modern CLI tool configurations with proper integration ---
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
        "--height 40%"
        "--reverse"
        "--border"
        # Gruvbox Material color scheme (matches theme)
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
        autoclose = true;
        autoindent = true;
        autosave = 10;
        cursorline = true;
        diffgutter = true;
        ftoptions = true;
        ignorecase = false;
        indentchar = " ";
        infobar = true;
        keymenu = true;
        mouse = true;
        rmtrailingws = true;
        ruler = true;
        savecursor = true;
        saveundo = true;
        scrollbar = true;
        smartpaste = true;
        softwrap = false;
        splitbottom = true;
        splitright = true;
        statusformatl = "$(filename) $(modified)($(line),$(col)) $(status.paste)| ft:$(opt:filetype) | $(opt:fileformat) | $(opt:encoding)";
        statusformatr = "$(bind:ToggleKeyMenu): bindings, $(bind:ToggleHelp): help";
        tabsize = 2;
        tabstospaces = true;
      };
    };
    
    # --- Git configuration with full user setup ---
    programs.git = lib.mkIf cfg.git.enable {
      enable = true;
      userName = cfg.git.userName;
      userEmail = cfg.git.userEmail;
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = false;
        core.editor = "micro";
        alias = {
          st = "status";
          co = "checkout";
          br = "branch";
          ci = "commit";
          ca = "commit -a";
          cm = "commit -m";
          cam = "commit -am";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          visual = "!gitk";
          tree = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        };
      };
    };

    # --- Zsh configuration ---
    programs.zsh = {
      enable = cfg.zsh.enable;
      autosuggestion.enable = cfg.zsh.plugins.autosuggestions;
      syntaxHighlighting.enable = cfg.zsh.plugins.syntaxHighlighting;
      history = {
        size = 5000;
        save = 5000;
      };
      shellAliases = cfg.aliases;
      initExtra = cfg.zsh.initExtra;
      # Guard environment variables in .zshenv (managed by programs.zsh)
      envExtra = ''
        # Guarded Home Manager session variables loader
        # Prevents shell failures when HM variables are unavailable
        HM_VARS="/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
        [ -r "$HM_VARS" ] && . "$HM_VARS"
      '';
    };

    programs.starship.enable = cfg.zsh.starship;

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # --- Tmux configuration ---
    programs.tmux = {
      enable = cfg.tmux.enable;
      clock24 = true;
      keyMode = "vi";
      mouse = true;
      extraConfig = lib.concatStringsSep "\n" [
        # Gruvbox Material theme
        ''
          set -g status-bg "#282828"
          set -g status-fg "#d4be98"
          set -g status-left-style "bg=#7daea3,fg=#282828"
          set -g status-right-style "bg=#45403d,fg=#d4be98"
          set -g window-status-current-style "bg=#7daea3,fg=#282828"
          
          # Better key bindings
          bind-key v split-window -h
          bind-key s split-window -v
          bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!"
        ''
        cfg.tmux.extraConfig
      ];
    };
  };
}