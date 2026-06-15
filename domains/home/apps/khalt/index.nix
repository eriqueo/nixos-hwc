# domains/home/apps/khalt/index.nix
#
# khalt — forked khal/ikhal calendar TUI (its own repo at ~/600_apps/khalt,
# consumed as the `khalt` flake input). Thin translator (same role as
# domains/home/apps/todui): imports khalt's reusable Home Manager module and
# feeds it an HWC-specific khal config.
#
# HEXAGONAL / DATA-DRIVEN (mirrors todui):
#   * which calendars to show     -> read from the shared hwc.mail.calendar
#     data (single source of truth), rendered into khalt's [calendars].
#   * how the UI is coloured       -> the system theme's flat tokens
#     (hwc.home.theme.colors) are injected as [palette_tokens]; khalt derives
#     every ikhal/leader/grid role from them (khal/ui/khalt_theme.py). NO
#     hardcoded [palette] block, so the theme genuinely drives the colours —
#     change the system palette and khalt follows, exactly like todui.
#   * keybindings (space leader, z to cycle views, hjkl) ship as khalt defaults;
#     `extraConfig` can append a [keybindings] override block.
#
# NAMESPACE: hwc.home.apps.khalt.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.khalt.enable = true;   (set in a profile)

{ config, lib, pkgs, inputs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.khalt;
  calCfg = config.hwc.mail.calendar;
  themeColors = (config.hwc.home.theme or {}).colors or {};

  # Unified keymap: list-app bare verbs (a=add, e=edit, d=delete, Enter=open),
  # shared with todui. Generated [keybindings] block, appended below. Guarded so
  # khalt still evaluates when the keymap module is not imported.
  km        = (config.hwc.home.keymap or {}).grammar or {};
  kmKhalt   = lib.optionalString (km ? listVerbs)
    (import ../../keymap/parts/to-khalt.nix { inherit lib; grammar = km; }).keybindingsBlock;

  dataDir = "~/.local/share/vdirsyncer";

  # --- calendars: same data + rendering as domains/mail/calendar's khal.nix ---
  mkCalendar = name: acc: ''
    [[${name}]]
    path = ${dataDir}/calendars/${name}/*
    color = ${acc.color}
    type = discover
  '';
  mkLocalCalendar = name: local: ''
    [[${name}]]
    path = ${local.path}
    color = ${local.color}
    type = discover
  '';
  # Radicale-synced calendars (VEVENT), discovered under calendars-radicale/.
  # When hwc.mail.calendar.radicale is on, the iCloud accounts no longer sync,
  # so this is the live calendar source (same data the MCP's khal reads).
  radicaleEnabled = (calCfg.radicale or {}).enable or false;
  radicaleCalendar = lib.optionalString radicaleEnabled ''
    [[radicale]]
    path = ${dataDir}/calendars-radicale/*
    color = ${(calCfg.radicale or {}).color or "dark green"}
    type = discover
  '';

  # When Radicale is the backend, iCloud account pairs are not synced, so their
  # stale calendars/<account>/ dirs are not surfaced (mirrors khal.nix).
  accountCalendars = lib.optionals (!radicaleEnabled)
    (lib.mapAttrsToList mkCalendar (calCfg.accounts or {}));

  calendars = lib.concatStringsSep "\n" (
    accountCalendars
    ++ (lib.mapAttrsToList mkLocalCalendar (calCfg.localCalendars or {}))
    ++ lib.optional (radicaleCalendar != "") radicaleCalendar
  );

  # --- palette tokens: flat system-theme colours -> khalt's token vocabulary ---
  tokenNames = [ "bg0" "bg1" "bg2" "bg3" "fg0" "fg1" "fg2" "fg3"
                 "accent" "info" "success" "warning" "error" "purple" "aqua" ];
  passthrough = lib.filterAttrs (n: v: (lib.elem n tokenNames) && builtins.isString v) themeColors;
  # khalt also wants purple/aqua; map from the nearest theme tokens when absent.
  extraTokens = lib.filterAttrs (_: v: v != null) {
    aqua   = themeColors.aqua   or themeColors.successDim or null;
    purple = themeColors.purple or themeColors.markedAlt  or themeColors.accentAlt or null;
  };
  paletteTokens = passthrough // extraTokens;
  tokensBlock = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: "${k} = ${v}") paletteTokens);

  generatedConfig = ''
    [calendars]
    ${calendars}

    [locale]
    timeformat = %H:%M
    dateformat = %Y-%m-%d
    longdateformat = %Y-%m-%d %A
    datetimeformat = %Y-%m-%d %H:%M
    longdatetimeformat = %Y-%m-%d %H:%M %A

    [default]
    highlight_event_days = true

    [view]
    theme = dark
    default_view = ${cfg.defaultView}
    agenda_event_format = {calendar-color}{cancelled}{start-end-time-style} {title}{repeat-symbol}{alarm-symbol}{reset}
    blank_line_before_day = true
    event_view_weighting = 2
    frame = top

    [palette_tokens]
    ${tokensBlock}
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ inputs.khalt.homeManagerModules.khalt ];

  options.hwc.home.apps.khalt = {
    enable = lib.mkEnableOption "khalt — forked khal/ikhal TUI (zoom views + leader keys)";

    defaultView = lib.mkOption {
      type = lib.types.enum [ "agenda" "month" "quarter" ];
      default = "agenda";
      description = "Zoom level khalt opens in (z cycles, space→v switches).";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra khal-config text appended to the generated config — e.g. a
        [keybindings] block remapping leader/zoom keys, or explicit [palette]
        overrides that should win over the theme-derived tokens.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    programs.khalt = {
      enable = true;
      configText = generatedConfig
        + lib.optionalString (kmKhalt != "") ("\n" + kmKhalt)
        + lib.optionalString (cfg.extraConfig != "") ("\n" + cfg.extraConfig);
      extraRuntimePackages = [ pkgs.vdirsyncer ];
    };
  };
}
