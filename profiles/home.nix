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
        theme.fonts.enable = lib.mkDefault true;

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
          enable = lib.mkDefault true;
          # Bridge managed by Home Manager user service (already configured)
          bridge.enable = true;

          # Notmuch configuration for unified inbox view
          notmuch = {
            maildirRoot = lib.mkDefault "/home/eric/400_mail/Maildir";
            userName = "Eric O'Keefe";
            primaryEmail = "eric@iheartwoodcraft.com";
            otherEmails = [ "eriqueo@proton.me" "heartwoodcraftmt@gmail.com" "eriqueokeefe@gmail.com" ];
            newTags = [ "unread" "inbox" ];
            excludeFolders = [ "trash" "spam" "[Gmail]/All Mail" ];
            savedSearches = {
              inbox = "tag:inbox and not tag:archived";
              unread = "tag:unread";
              work = "from:*@iheartwoodcraft.com or from:*heartwoodcraftmt@gmail.com";
              personal = "from:*@proton.me or from:*eriqueokeefe@gmail.com";
              urgent = "tag:urgent or tag:important";
            };
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
          analysis.enable = lib.mkDefault true;
          # Web Browsers
          chromium.enable = lib.mkDefault true;   # Chromium browser
          librewolf.enable = lib.mkDefault true;  # Privacy-focused Firefox

          # Mail Clients (aerc with notmuch backend for unified inbox)
          aerc.enable = lib.mkDefault true;                 # TUI mail client with notmuch
          neomutt.enable = lib.mkDefault false;             # TUI mail client (alternative)
          betterbird.enable = lib.mkDefault false;          # GUI mail client (Thunderbird fork)
          proton-mail.enable = lib.mkDefault true;           # Proton Mail desktop client

          # Security
          gpg.enable = lib.mkDefault true;

          # Proton Suite
          proton-authenticator.enable = lib.mkDefault true; # 2FA authenticator
          proton-authenticator.autoStart = lib.mkDefault true; # Auto-start on login
          proton-pass.enable = lib.mkDefault true;         # Password manager (optional)
          proton-pass.autoStart = lib.mkDefault true;      # Auto-start on login

          # Productivity & Office
          obsidian.enable = lib.mkDefault true;                   # Knowledge base
          onlyoffice-desktopeditors.enable = lib.mkDefault true;   # Office suite

          # Creative & Media
          blender.enable = lib.mkDefault false;            # 3D creation suite (disabled - CUDA forces source compile)
          freecad.enable = lib.mkDefault false;            # Parametric 3D CAD (disabled - heavy compile)

          # Development & Automation
          n8n.enable = lib.mkDefault false;                # Workflow automation (resource-heavy)
          gemini-cli.enable = lib.mkDefault true;           # AI CLI tool
          codex.enable = lib.mkDefault true;             # Re-enabled AI tool (temporarily disabled for build)
          codex.package = lib.mkDefault (pkgs.stdenv.mkDerivation {
            pname = "codex";
            version = "0.101.0";
            src = pkgs.fetchurl {
              url = "https://github.com/openai/codex/releases/download/rust-v0.101.0/codex-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "sha256-6XMt47hw32o5zkukRplhDvWBhDlneTRX+O8R86WlgjY=";
            };
            dontUnpack = true;
            installPhase = ''
              install -d "$out/bin"
              ${pkgs.gzip}/bin/gunzip -c "$src" > "$out/bin/codex"
              chmod 755 "$out/bin/codex"
            '';
          });

          # Utilities
          ipcalc.enable = lib.mkDefault true;              # IP calculator
          wasistlos.enable = lib.mkDefault false;          # System monitor (niche)
          bottles-unwrapped.enable = lib.mkDefault true;
          thunderbird.enable = lib.mkDefault true;
          localsend.enable = lib.mkDefault true;
          opencode.enable = lib.mkDefault true;
          google-cloud-sdk.enable = lib.mkDefault true;
          slack.enable = lib.mkDefault true;
          slack-cli.enable = lib.mkDefault true;
        };
      };
    };
  };
}
