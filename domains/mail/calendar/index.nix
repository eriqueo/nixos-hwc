{ config, lib, pkgs, inputs, osConfig ? {}, ... }:
let
  cfg = config.hwc.mail.calendar;

  # khalt supersedes plain khal: its package ships the fork's full `khal`/`ikhal`
  # CLI. Expose ONLY `khal`/`ikhal` here — NOT `bin/khalt`, which is owned by the
  # khalt HM module's `khalt-wrapped` (that module deliberately exposes only
  # khalt to avoid this very buildEnv collision; installing the whole package
  # here re-creates it). This puts the fork's `khal` on PATH for
  # waybar/todui/ics-watcher/parser; pkgs.khal is retired.
  khaltFull = inputs.khalt.packages.${pkgs.system}.default;
  khalCli = pkgs.runCommand "khalt-khal-cli" { } ''
    mkdir -p $out/bin
    ln -s ${khaltFull}/bin/khal  $out/bin/khal
    ln -s ${khaltFull}/bin/ikhal $out/bin/ikhal
  '';

  dataDir = "~/.local/share/vdirsyncer";

  # `busy` — one-liner to block time on the "hwc" calendar the booking form
  # reads (Radicale cal/migrated; khal names it by displayname "hwc"), then
  # push to Radicale immediately so availability updates now instead of on the
  # ~15-min vdirsyncer timer.
  busyScript = pkgs.writeShellScriptBin "busy" ''
    if [ $# -eq 0 ]; then
      echo "usage: busy <start> [end|duration] [summary]"
      echo "  e.g.  busy tomorrow 14:00 3h Job site — Smith"
      echo "        busy 2026-07-20 9:00 30m Call: Alden"
      exit 1
    fi
    ${khalCli}/bin/khal new -a hwc "$@" || exit 1
    if ${pkgs.vdirsyncer}/bin/vdirsyncer sync calendar_radicale >/dev/null 2>&1; then
      echo "✓ blocked + synced — availability is updated"
    else
      echo "✓ blocked — availability updates on the next sync (≤15 min)"
    fi
  '';

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

  # Same handshake for the Radicale credential (htpasswd "user:password"),
  # mirroring domains/mail/tasks/index.nix.
  hasRadicalePw = (osCfg ? age) && (osCfg.age.secrets ? radicale-htpasswd);
  radicalePwPath = if hasRadicalePw
    then osCfg.age.secrets.radicale-htpasswd.path
    else "/run/agenix/radicale-htpasswd";

  radicalePair = lib.optionalString cfg.radicale.enable
    (import ./parts/vdirsyncer-pair-radicale.nix {
      inherit dataDir;
      url = cfg.radicale.url;
      username = cfg.radicale.username;
      secretPath = radicalePwPath;
    });

  vdirsyncer = import ./parts/vdirsyncer.nix {
    inherit lib pkgs cfg applePwPath radicalePair;
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

    radicale = {
      enable = lib.mkEnableOption ''
        calendar (VEVENT) sync against the self-hosted Radicale server
        (tasks.hwc.iheartwoodcraft.com — same vhost/secret as the tasks
        backend). When on, the iCloud `accounts` no longer generate
        vdirsyncer pairs (calendar lives on Radicale, plumbed exactly like
        tasks); khal/ikhal discover the synced calendars under
        ~/.local/share/vdirsyncer/calendars-radicale/. Requires the
        radicale-htpasswd secret and the server's
        hwc.server.services.radicale to be deployed
      '';

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://tasks.hwc.iheartwoodcraft.com/";
        description = "Radicale CalDAV base URL (the Caddy vhost).";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = ''
          Radicale username for the calendar principal. Consolidated to the
          single `eric` principal (2026-07-16) so ONE iPhone CalDAV account
          carries calendar + reminders and one CardDAV account carries the
          CRM rolodex. The former split (calendar under a separate `cal`
          user to stop cross-discovery) is superseded: this pair pins
          `collections = ["migrated"]`, so the only leak is the tasks pair
          discovering the calendar collection — VTODO-filtered and empty, a
          cosmetic extra list at worst. Requires a matching
          `eric:<password>` line in the radicale-htpasswd secret.
        '';
      };

      color = lib.mkOption {
        type = lib.types.str;
        default = "dark green";
        description = "khal display color for the Radicale calendar(s).";
      };
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
      # khaltPkg provides THE `khal`/`ikhal` CLI (khalt is a source fork of
      # khal); pkgs.khal is retired. The standard ~/.config/khal/config below
      # is what khaltPkg's `khal` reads, so waybar/todui/ics-watcher/the MCP
      # all run on the fork.
      home.packages = [ pkgs.vdirsyncer khalCli parser.emailToKhalScript busyScript ];

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
        ${lib.optionalString cfg.radicale.enable
          "run mkdir -p ~/.local/share/vdirsyncer/calendars-radicale"}
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
          assertion = cfg.accounts != {} || cfg.radicale.enable;
          message = "hwc.mail.calendar requires at least one iCloud account "
            + "or hwc.mail.calendar.radicale.enable = true.";
        }
      ];
    }
  ]);
}
