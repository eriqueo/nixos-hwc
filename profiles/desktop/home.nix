# profiles/desktop/home.nix — desktop role, Home Manager lane
#
# GUI workstation HM defaults (apps with a screen, mail clients, fonts).
# All set with mkDefault — machines can override any option.
#
# REPLACES: the GUI portion of profiles/home-session.nix
# USED BY: see the machines table in flake.nix

{ config, lib, pkgs, nixosApiVersion ? "unstable", ... }:

{
  imports = [
    ../../domains/mail/index.nix
    ../../domains/home/keymap/index.nix   # unified keymap source of truth (hwc.home.keymap.grammar)
  ];

  #======================================================================
  # GUI WORKSTATION DEFAULTS
  #======================================================================

  hwc.home = {
    # Fonts (GUI machines)
    theme.fonts.enable = lib.mkDefault true;

    # Development extras
    core.development.languages.javascript = lib.mkDefault true;

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
      firefox.enable = lib.mkDefault true;

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
      zellij.enable = lib.mkDefault true;   # workbench's pane host

      # Task management
      tuxedo.enable = lib.mkDefault true;
      todui.enable = lib.mkDefault true;

      # Calendar TUI (forked khal: zoom views + space-leader keys)
      khalt.enable = lib.mkDefault true;
      khalt.defaultView = lib.mkDefault "month";  # open in the month grid

      # TUI ops host that orchestrates the peer panes (todui/khalt/yazi/nvim).
      # todui + khalt are enabled above (Task management / Calendar TUI).
      workbench.enable = lib.mkDefault true; # Textual ops host (zellij-driven)

      # Trap-safe Pave (JobTread API) query builder, TUI + CLI.
      pave-query-builder.enable = lib.mkDefault true;

      # Development & Automation
      n8n.enable = lib.mkDefault false;
      # codex release-binary pin moved to domains/home/apps/codex/parts/
      # package.nix; machine one-offs apply it (headless machines use stock).

      # Utilities
      ipcalc.enable = lib.mkDefault true;
      wasistlos.enable = lib.mkDefault false;
      bottles-unwrapped.enable = lib.mkDefault true;
      tetro.enable = lib.mkDefault true;   # terminal tetromino game (TUI)
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
# HM 26.05 changed defaults for these options; pinning to legacy values
# preserves current behavior and silences eval warnings on the unstable
# lane. The options do not exist in HM stable 25.11, so the block is
# guarded on nixosApiVersion — unguarded it breaks eval for stable-lane
# machines (stable-lane eval regression from commit fce96f45).
#
# History: `configType` and `setSessionVariables` were briefly absent from
# the HM-as-module wiring path (setting them errored at module-merge —
# removed 2026-05-31). The 2026-05 nixpkgs/HM bump restored them to module
# mode, so they are pinned here once more — re-added 2026-06-10.
// lib.optionalAttrs (nixosApiVersion == "unstable") {
  gtk.gtk4.theme = config.gtk.theme;
  wayland.windowManager.hyprland.configType = "hyprlang";
  xdg.userDirs.setSessionVariables = true;
}
