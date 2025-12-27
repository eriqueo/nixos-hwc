{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = lib.mkDefault "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      #==========================================================================
      # OPTIONAL FEATURES - Sensible defaults, override per machine
      #==========================================================================

      # --- Home Environment Configuration ---
      hwc.home = {
        # Theme & Fonts (BASE)
        theme.palette = lib.mkDefault "gruv";
        fonts.enable = lib.mkDefault true;

        # Shell Environment (BASE)
        shell = {
          enable = lib.mkDefault true;
          modernUnix = lib.mkDefault true;
          git.enable = lib.mkDefault true;
          zsh = {
            enable = lib.mkDefault true;
            starship = lib.mkDefault true;
            autosuggestions = lib.mkDefault true;
            syntaxHighlighting = lib.mkDefault true;
          };
        };

        # Development Environment
        development.enable = lib.mkDefault true;

        # Mail & Communication
        mail = {
          enable = lib.mkDefault false;
          # Bridge managed by Home Manager user service
          bridge.enable = false;

          # Notmuch configuration per runbook
          notmuch = {
            userName = "Eric O'Keefe";
            primaryEmail = "eric@iheartwoodcraft.com";
            newTags = [ "unread" "inbox" ];
          };
        };

        # Applications
        apps = {
          # Desktop Environment (Session-Critical)
          hyprland.enable = lib.mkDefault true;   # Wayland compositor
          waybar.enable = lib.mkDefault true;     # Status bar
          swaync.enable = lib.mkDefault true;     # Notification daemon
          kitty.enable = lib.mkDefault true;      # Terminal emulator

          # File Management
          thunar.enable = lib.mkDefault true;     # GUI file manager
          yazi.enable = lib.mkDefault true;       # TUI file manager

          # Web Browsers
          chromium.enable = lib.mkDefault true;   # Chromium browser
          librewolf.enable = lib.mkDefault true;  # Privacy-focused Firefox
          qutebrowser.enable = lib.mkDefault true;        # Keyboard-focused browser with a minimal 

          # Mail Clients
          aerc.enable = lib.mkDefault false;                # TUI mail client
          neomutt.enable = lib.mkDefault false;             # TUI mail client (alternative)
          betterbird.enable = lib.mkDefault false;          # GUI mail client (Thunderbird fork)
          protonMail.enable = lib.mkDefault true;          # Proton Mail bridge/client

          # Security
          gpg.enable = lib.mkDefault true;

          # Proton Suite
          protonAuthenticator.enable = lib.mkDefault true; # 2FA authenticator
          protonAuthenticator.autoStart = lib.mkDefault false;      # Auto-start on login
          protonPass.enable = lib.mkDefault true;         # Password manager (optional)
          protonPass.autoStart = lib.mkDefault true;      # Auto-start on login

          # Productivity & Office
          obsidian.enable = lib.mkDefault true;                   # Knowledge base
          onlyofficeDesktopeditors.enable = lib.mkDefault true;   # Office suite

          # Development & Automation
          n8n.enable = lib.mkDefault false;                # Workflow automation (resource-heavy)
          geminiCli.enable = lib.mkDefault true;           # AI CLI tool
          codex.enable = lib.mkDefault true;             # Re-enabled AI tool (temporarily disabled for build)

          # Utilities
          ipcalc.enable = lib.mkDefault true;              # IP calculator
          wasistlos.enable = lib.mkDefault false;          # System monitor (niche)
          bottlesUnwrapped.enable = lib.mkDefault true;
          thunderbird.enable = lib.mkDefault true;
          localsend.enable = lib.mkDefault true;
          opencode.enable = lib.mkDefault true;
          googleCloudSdk.enable = lib.mkDefault true;
          slack.enable = lib.mkDefault true;
          slackCli.enable = lib.mkDefault true;
        };
      };
    };
  };
}
