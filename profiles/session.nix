# profiles/session.nix — Human-facing workstation profile
#
# Cross-domain bundle: home (GUI) + audio + display + theme
# For machines with a screen and human interaction.
#
# REPLACES: home.nix
# USED BY: laptop, xps (full workstations)
# NOT USED BY: server (headless), firestick/gaming (custom HM in machine config)

{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # HOME MANAGER — Full GUI workstation setup
  #==========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = lib.mkDefault "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      #======================================================================
      # GUI WORKSTATION DEFAULTS
      # All set with mkDefault — machines can override any option.
      #======================================================================

      hwc.home = {
        # Theme & Fonts
        theme.palette = lib.mkDefault "gruv";
        theme.fonts.enable = lib.mkDefault true;

        # Shell Environment
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
          bridge.enable = true;

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

        # Desktop Applications
        apps = {
          # Desktop Environment (Session-Critical)
          hyprland.enable = lib.mkDefault true;
          waybar.enable = lib.mkDefault true;
          swaync.enable = lib.mkDefault true;
          kitty.enable = lib.mkDefault true;

          # File Management
          thunar.enable = lib.mkDefault true;
          yazi.enable = lib.mkDefault true;
          analysis.enable = lib.mkDefault true;

          # Web Browsers
          chromium.enable = lib.mkDefault true;
          librewolf.enable = lib.mkDefault true;

          # Mail Clients
          aerc.enable = lib.mkDefault true;
          neomutt.enable = lib.mkDefault false;
          betterbird.enable = lib.mkDefault false;
          proton-mail.enable = lib.mkDefault true;

          # Security
          gpg.enable = lib.mkDefault true;

          # Proton Suite
          proton-authenticator.enable = lib.mkDefault true;
          proton-authenticator.autoStart = lib.mkDefault true;
          proton-pass.enable = lib.mkDefault true;
          proton-pass.autoStart = lib.mkDefault true;

          # Productivity & Office
          obsidian.enable = lib.mkDefault true;
          onlyoffice-desktopeditors.enable = lib.mkDefault true;

          # Creative & Media
          blender.enable = lib.mkDefault true;
          freecad.enable = lib.mkDefault false;

          # Development & Automation
          n8n.enable = lib.mkDefault false;
          gemini-cli.enable = lib.mkDefault true;
          codex.enable = lib.mkDefault true;
          aider.enable = lib.mkDefault true;
          codex.package = lib.mkDefault (pkgs.stdenv.mkDerivation {
            pname = "codex";
            version = "0.101.0";
            nativeBuildInputs = [ pkgs.autoPatchelfHook ];
            buildInputs = [
              pkgs.libcap
              pkgs.openssl
              pkgs.zlib
              pkgs.stdenv.cc.cc.lib
              pkgs.glibc
            ];
            src = pkgs.fetchurl {
              url = "https://github.com/openai/codex/releases/download/rust-v0.101.0/codex-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "sha256-6XMt47hw32o5zkukRplhDvWBhDlneTRX+O8R86WlgjY=";
            };
            dontUnpack = true;
            installPhase = ''
              install -d "$out/bin"
              ${pkgs.gnutar}/bin/tar -xf "$src" -C "$out/bin"
              mv "$out/bin/codex-x86_64-unknown-linux-gnu" "$out/bin/codex"
              chmod 755 "$out/bin/codex"
            '';
          });

          # Utilities
          ipcalc.enable = lib.mkDefault true;
          wasistlos.enable = lib.mkDefault false;
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

  #==========================================================================
  # SYSTEM-LEVEL GUI SUPPORT — Audio, Display, Session
  #==========================================================================

  # Hardware services — audio, keyboard, bluetooth for interactive use
  hwc.system.hardware.enable = true;

  # Session — display manager, sudo, lingering
  hwc.system.core.session = {
    enable = true;
    loginManager.autoLoginUser = lib.mkDefault "eric";
    sudo.enable = true;
    sudo.wheelNeedsPassword = false;
    linger.users = [ "eric" ];
  };

  # dconf required for GTK applications
  programs.dconf.enable = true;
}
