{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.mail.calendar;

  # Handshake: safe access to agenix secrets
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  # Use osConfig.age.secrets path when HM evaluates as a NixOS module
  # (sudo nixos-rebuild). Fall back to the canonical agenix runtime path
  # so standalone HM (`hms`) doesn't rewrite the config with /dev/null
  # — the secret file exists at this path regardless of HM eval mode.
  hasApplePw = (osCfg ? age) && (osCfg.age.secrets ? apple-app-pw);
  applePwPath = if hasApplePw
    then osCfg.age.secrets.apple-app-pw.path
    else "/run/agenix/apple-app-pw";

  vdirsyncer = import ./parts/vdirsyncer.nix {
    inherit lib pkgs cfg applePwPath;
  };
  # khal.nix is now palette-aware: it derives its urwid [palette] hi-color
  # fields from the active system theme (fail-soft to gruvbox literals).
  khal = import ./parts/khal.nix {
    inherit lib pkgs cfg;
    colors = (config.hwc.home.theme or {}).colors or {};
  };
  service = import ./parts/service.nix { inherit lib pkgs; };
  parser = import ./parts/parser.nix { inherit lib pkgs cfg; };
  icsWatcher = import ./parts/ics-watcher.nix { inherit lib pkgs; };

in
{
  # OPTIONS
  options.hwc.mail.calendar = {
    enable = lib.mkEnableOption "calendar sync via khal + vdirsyncer";

    icsWatch = {
      enable = lib.mkEnableOption "auto-import .ics files dropped in ~/000_inbox/downloads into khal";
    };

    extraVdirsyncerPairs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      description = ''
        Extra [pair …]/[storage …] blocks contributed by sibling modules
        (e.g. domains/mail/tasks for VTODO/Reminders sync), appended verbatim
        to the single generated vdirsyncer config so there is one config file
        and one sync timer. Each entry is a complete config fragment.
      '';
    };

    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          email = lib.mkOption {
            type = lib.types.str;
            description = "Apple ID email address";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "light magenta";
            description = "khal display color for this calendar";
          };
        };
      });
      default = {};
      description = "Apple Calendar accounts to sync via CalDAV";
    };

    localCalendars = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Filesystem path to a directory of .ics files (one event per file).";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "dark cyan";
            description = "khal display color for this calendar.";
          };
        };
      });
      default = {};
      description = ''
        Extra read-only calendars to expose to khal/ikhal/calcure beyond the
        CalDAV-synced accounts. Other modules (e.g. dt) set this to surface
        their .ics output in the user's calendar tools.
      '';
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ pkgs.vdirsyncer pkgs.khal parser.emailToKhalScript ];

      xdg.configFile = {
          "vdirsyncer/config".text = vdirsyncer.config;
          "khal/config".text = khal.config;
      } // parser.aercConfig;

      # Ensure storage directories exist
      home.activation.calendarDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ~/.local/share/vdirsyncer/{status,tokens,calendars}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _:
          "mkdir -p ~/.local/share/vdirsyncer/calendars/${name}"
        ) cfg.accounts)}
      '';
    }

    # systemd timer for periodic sync
    service
    parser.homeFiles

    # .ics file watcher (optional)
    (lib.mkIf cfg.icsWatch.enable icsWatcher)

    # VALIDATION
    {
      assertions = [
        {
          assertion = cfg.accounts != {};
          message = "hwc.mail.calendar requires at least one account";
        }
      ];
    }
  ]);
}
