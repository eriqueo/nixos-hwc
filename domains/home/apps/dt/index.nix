# domains/home/apps/dt/index.nix
#
# dt — DataX time tracker (CLI + TUI + waybar widget)
# Config: ~/.config/dt/config.toml
# Database: ~/.local/share/dt/dt.sqlite
# Invoices: ~/Documents/datax-time/
# Calendar: ~/.local/share/dt/calendar/dt-<id>.ics (per completed session)
{ config, lib, options, pkgs, ... }:
let
  cfg = config.hwc.home.apps.dt;

  dtPkg = pkgs.callPackage ./parts/package.nix { };

  # Stale-session notifier: prompts the user with action buttons
  # (Clock out / Snooze 15 / Dismiss). Runs detached so the stale-check
  # systemd service exits promptly; this script blocks on user input.
  staleNotifier = pkgs.writeShellScriptBin "dt-stale-notifier" ''
    set -u
    body="''${1:-Session running too long}"
    action=$(${pkgs.libnotify}/bin/notify-send \
      -u critical -a dt \
      --action="clock-out=Clock out" \
      --action="snooze=Snooze 15 min" \
      --action="dismiss=Dismiss" \
      "dt — stale session" "$body" 2>/dev/null || true)
    case "$action" in
      clock-out) ${dtPkg}/bin/dt out -n "auto: stale" >/dev/null 2>&1 || true ;;
      snooze)    ${dtPkg}/bin/dt snooze --minutes 15 >/dev/null 2>&1 || true ;;
      *)         : ;;
    esac
  '';

  configToml = ''
    name = "${cfg.settings.name}"
    rate = ${toString cfg.settings.rate}
    max_session_hours = ${toString cfg.settings.maxSessionHours}
    waybar_poll_seconds = ${toString cfg.settings.waybarPollSeconds}
    pomodoro_minutes = ${toString cfg.pomodoro.intervalMinutes}
  '' + lib.optionalString (cfg.settings.defaultCategory != null) ''
    default_category = "${cfg.settings.defaultCategory}"
  '';

  # PATH that helper scripts and the notifier need for notify-send + dt
  helperPath = lib.makeBinPath [ pkgs.libnotify pkgs.coreutils staleNotifier dtPkg ];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.dt = {
    enable = lib.mkEnableOption "dt — DataX time tracker (CLI + TUI)";

    settings = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Eric O'Keefe";
        description = "Name to print on invoices.";
      };
      rate = lib.mkOption {
        type = lib.types.number;
        default = 40;
        description = "Hourly rate in dollars.";
      };
      maxSessionHours = lib.mkOption {
        type = lib.types.number;
        default = 10;
        description = "Hours before an open clock-in is considered stale.";
      };
      waybarPollSeconds = lib.mkOption {
        type = lib.types.number;
        default = 30;
        description = "How often waybar polls `dt status --waybar`.";
      };
      defaultCategory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Skip the clock-in category prompt by defaulting to this.";
      };
    };

    waybar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add the custom/dt widget to waybar (requires hwc.home.apps.waybar.enable).";
      };
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Bind SUPER+T to open the dt TUI (requires hwc.home.apps.hyprland.enable).";
      };
      toggleBind = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "SUPER SHIFT,T";
        example = "SUPER SHIFT,T";
        description = ''
          Hyprland modifier+key spec for `dt toggle` (click-free clock in/out).
          Set to null to disable. Format: "<MODS>,<KEY>" — see hyprland bind syntax.
        '';
      };
    };

    pomodoro = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Send a notification at each pomodoro interval while clocked in.";
      };
      intervalMinutes = lib.mkOption {
        type = lib.types.int;
        default = 25;
        description = "Notify every N minutes of continuous active session.";
      };
    };

    calendar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Write each completed session as an .ics event under ~/.local/share/dt/calendar/.";
      };
      integrateKhal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Inject a `dt-sessions` calendar into khal so sessions appear in ikhal/calcure
          alongside iCloud events. Requires hwc.mail.calendar.enable.
        '';
      };
      khalColor = lib.mkOption {
        type = lib.types.str;
        default = "dark cyan";
        description = "khal display color for the dt calendar.";
      };
    };

    staleCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run `dt stale-check` on a systemd user timer for desktop notifications.";
      };
      intervalMinutes = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "How often the stale-check timer fires.";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ dtPkg pkgs.libnotify staleNotifier ];

      xdg.configFile."dt/config.toml".text = configToml;

      # Stale-session check (uses dt-stale-notifier for actionable prompts)
      systemd.user.services.dt-stale-check = lib.mkIf cfg.staleCheck.enable {
        Unit = {
          Description = "dt — stale session check";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${dtPkg}/bin/dt stale-check";
          Environment = [ "PATH=${helperPath}" ];
        };
      };

      systemd.user.timers.dt-stale-check = lib.mkIf cfg.staleCheck.enable {
        Unit = {
          Description = "Periodic stale-session check for dt";
        };
        Timer = {
          OnCalendar = "*:0/${toString cfg.staleCheck.intervalMinutes}";
          Persistent = true;
        };
        Install = { WantedBy = [ "timers.target" ]; };
      };

      # Pomodoro boundary check (fires every minute; cheap DB read + notify if
      # the session crossed another N-minute boundary since last notification)
      systemd.user.services.dt-pomodoro = lib.mkIf cfg.pomodoro.enable {
        Unit = {
          Description = "dt — pomodoro boundary check";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${dtPkg}/bin/dt pomodoro-check";
          Environment = [ "PATH=${helperPath}" ];
        };
      };

      systemd.user.timers.dt-pomodoro = lib.mkIf cfg.pomodoro.enable {
        Unit = {
          Description = "Periodic pomodoro boundary check for dt";
        };
        Timer = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
        };
        Install = { WantedBy = [ "timers.target" ]; };
      };

      # Ensure calendar dir exists on activation so first clock-out doesn't race.
      home.activation.dtCalendarDir = lib.mkIf cfg.calendar.enable
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p $HOME/.local/share/dt/calendar
        '');
    }

    # khal integration — add the dt sessions dir as a calendar so it shows up
    # alongside iCloud events in ikhal/calcure. Gated on both enables AND on
    # the hwc.mail.calendar option being declared in scope — on hosts that
    # don't import the mail domain (e.g. kids) the option isn't declared,
    # and `lib.mkIf` alone isn't enough (the SET would still register against
    # an undeclared option). `lib.optionalAttrs` returns {} when the option
    # is out of scope, which mkMerge happily absorbs.
    (lib.mkIf (cfg.calendar.enable
               && cfg.calendar.integrateKhal
               && (config.hwc.mail.calendar.enable or false))
      (lib.optionalAttrs (lib.hasAttrByPath [ "hwc" "mail" "calendar" ] options) {
        hwc.mail.calendar.localCalendars."dt-sessions" = {
          path = "${config.home.homeDirectory}/.local/share/dt/calendar";
          color = cfg.calendar.khalColor;
        };
      }))


    #========================================================================
    # VALIDATION
    #========================================================================
    {
      assertions = [
        {
          assertion = !cfg.waybar.enable || config.hwc.home.apps.waybar.enable;
          message = ''
            hwc.home.apps.dt.waybar.enable is true but hwc.home.apps.waybar.enable is false.
            Either enable waybar or set hwc.home.apps.dt.waybar.enable = false.
          '';
        }
        {
          assertion = !cfg.hyprland.enable || config.hwc.home.apps.hyprland.enable;
          message = ''
            hwc.home.apps.dt.hyprland.enable is true but hwc.home.apps.hyprland.enable is false.
            Either enable hyprland or set hwc.home.apps.dt.hyprland.enable = false.
          '';
        }
        {
          assertion = !cfg.hyprland.enable || config.hwc.home.apps.kitty.enable;
          message = ''
            dt hyprland keybind opens the TUI in kitty, but hwc.home.apps.kitty.enable is false.
          '';
        }
      ];
    }
  ]);
}
