# domains/home/apps/todui/index.nix
#
# todui — standalone VTODO task TUI (its own repo at ~/600_apps/todui, consumed as
# the `todui` flake input). This module is a THIN TRANSLATOR: it imports
# todui's reusable Home Manager module and feeds it HWC-specific values —
# the system theme palette, the Radicale CalDAV endpoint + agenix secret, and
# the vdir paths. todui itself knows nothing about HWC (hexagonal: this is the
# inbound adapter that wires our config into its generic option surface).
#
# NAMESPACE: hwc.home.apps.todui.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.todui.enable = true;   (set in profiles/desktop)
#
# Replaces the former in-tree `tasq` module + workspace/home/tasq sources.

{ config, lib, pkgs, inputs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.todui;

  # Follow the enabled tasks backend (same HM eval as hwc.mail.tasks). iCloud
  # CalDAV died 2026-06-11; Radicale is the backend. Falls back to the generic
  # tasks vdir when radicale is off so the app still opens.
  radicaleOn = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "enable" ] false config;
  vdirRoot = "${config.home.homeDirectory}/.local/share/vdirsyncer";

  radicaleUrl = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "url" ]
    "https://tasks.hwc.iheartwoodcraft.com/" config;
  radicaleUser = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "username" ]
    "eric" config;
  # Same osConfig.age handshake as domains/mail/tasks so it resolves under
  # standalone HM eval too (osConfig may be {}). Law-1 pattern: attrByPath.
  radicalePwPath = lib.attrByPath [ "age" "secrets" "radicale-htpasswd" "path" ]
    "/run/agenix/radicale-htpasswd" osConfig;

  # System theme palette → todui (it derives its UI roles from these tokens).
  paletteColors = lib.filterAttrs (_: v: builtins.isString v)
    (((config.hwc.home.theme or {}).colors or {}));

  # Unified keymap grammar → staged as ~/.config/todui/keymap.json. todui does
  # not read it YET (app-side reader is the staged prerequisite — see
  # domains/home/keymap/README.md); writing the file is harmless and ready, and
  # the app must LOG when it finds-but-ignores it so the drift can't hide.
  km      = (config.hwc.home.keymap or {}).grammar or {};
  kmTodui = lib.optionalString (km ? listVerbs)
    (import ../../keymap/parts/to-todui.nix { inherit lib; grammar = km; }).json;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ inputs.todui.homeManagerModules.todui ];

  options.hwc.home.apps.todui = {
    enable = lib.mkEnableOption "todui — VTODO-native keyboard task TUI";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.todui = {
      enable = true;

      tasksGlob =
        if radicaleOn then "${vdirRoot}/tasks-radicale/*"
        else "${vdirRoot}/tasks/*";
      syncPairs = lib.optional radicaleOn "tasks_radicale";
      newListRoot = lib.optionalString radicaleOn "${vdirRoot}/tasks-radicale";
      newListPair = lib.optionalString radicaleOn "tasks_radicale";

      radicale.url = lib.optionalString radicaleOn radicaleUrl;
      radicale.username = lib.optionalString radicaleOn radicaleUser;
      radicale.passwordCommand =
        lib.optionalString radicaleOn "cut -d: -f2- ${radicalePwPath}";

      palette = paletteColors;
      extraRuntimePackages = [ pkgs.khal pkgs.vdirsyncer ];
    };

    # Staged unified-keymap data (see let-block note). Harmless until the
    # app-side reader lands; written only when the keymap module is imported.
    xdg.configFile = lib.optionalAttrs (kmTodui != "") {
      "todui/keymap.json".text = kmTodui;
    };

    # Launcher entry — todui is a TUI, so host it in kitty (the session
    # terminal). Makes it appear in wofi/rofi `drun` (terminal = false because
    # `kitty -e` already supplies the window). Hyprland keybind SUPER+T is wired
    # in domains/home/apps/hyprland/parts/behavior.nix (gated on this enable).
    xdg.desktopEntries.todui = {
      name = "todui";
      genericName = "Task Manager";
      comment = "VTODO task TUI (CalDAV-synced reminders)";
      exec = "kitty -e todui";
      terminal = false;
      categories = [ "Utility" "Office" ];
      settings.Keywords = "tasks;todo;vtodo;reminders;caldav;";
    };
  };
}
