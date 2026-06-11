# profiles/desktop/home.nix — desktop role, Home Manager lane
#
# GUI workstation HM defaults (apps with a screen, mail clients, fonts).
# All set with mkDefault — machines can override any option.
#
# REPLACES: the GUI portion of profiles/home-session.nix
# USED BY: laptop, xps (role list in flake.nix machines table)

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../domains/mail/index.nix
  ];

  # HM 26.05 changed defaults for these options; pinning to legacy values
  # preserves current behavior and silences eval warnings.
  #
  # History: `configType` and `setSessionVariables` were briefly absent from
  # the HM-as-module wiring path (setting them errored at module-merge —
  # removed 2026-05-31). The 2026-05 nixpkgs/HM bump restored them to module
  # mode (their default-change warnings appear in snix output again), so
  # they are pinned here once more — re-added 2026-06-10.
  gtk.gtk4.theme = config.gtk.theme;
  wayland.windowManager.hyprland.configType = "hyprlang";
  xdg.userDirs.setSessionVariables = true;

  #======================================================================
  # GUI WORKSTATION DEFAULTS
  #======================================================================

  hwc.home = {
    # Fonts (GUI machines)
    theme.fonts.enable = lib.mkDefault true;

    # Development extras
    development.languages.javascript = lib.mkDefault true;

    # Desktop Applications
    apps = {
      # Desktop Environment (Session-Critical)
      hyprland.enable = lib.mkDefault true;
      waybar.enable = lib.mkDefault true;
      swaync.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;

      # File Management
      thunar.enable = lib.mkDefault true;
      analysis.enable = lib.mkDefault true;

      # Web Browsers
      chromium.enable = lib.mkDefault true;
      librewolf.enable = lib.mkDefault true;

      # Mail Clients
      neomutt.enable = lib.mkDefault false;
      proton-mail.enable = lib.mkDefault true;

      # Proton Suite
      proton-authenticator.enable = lib.mkDefault true;
      proton-authenticator.autoStart = lib.mkDefault true;
      proton-pass.enable = lib.mkDefault true;
      proton-pass.autoStart = lib.mkDefault true;

      # Productivity & Office
      obsidian.enable = lib.mkDefault true;
      onlyoffice-desktopeditors.enable = lib.mkDefault true;
      xournalpp.enable = lib.mkDefault true;

      # Creative & Media
      blender.enable = lib.mkDefault true;
      freecad.enable = lib.mkDefault false;

      # Terminal Multiplexer
      tmux.enable = lib.mkDefault true;

      # Task management
      tuxedo.enable = lib.mkDefault true;

      # Development & Automation
      n8n.enable = lib.mkDefault false;
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
      localsend.enable = lib.mkDefault true;
      opencode.enable = lib.mkDefault true;
      google-cloud-sdk.enable = lib.mkDefault true;
      slack.enable = lib.mkDefault true;
      slack-cli.enable = lib.mkDefault true;
    };
  };

  # Mail & Communication
  hwc.mail = {
    enable = lib.mkDefault true;
    bridge.enable = true;
    aerc.enable = lib.mkDefault true;

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
}
