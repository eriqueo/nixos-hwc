# domains/mail/tasks/index.nix
#
# tasks — VTODO/Reminders sync substrate + todoman CLI.
#
# NAMESPACE: hwc.mail.tasks.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.mail.tasks.enable = true;
#
# Auto-imported by domains/mail/index.nix (readDir). Enabled in
# profiles/mail/home.nix.
#
# This module does NOT run its own vdirsyncer config or timer. It contributes a
# [pair tasks] fragment to hwc.mail.calendar.extraVdirsyncerPairs, so the single
# calendar vdirsyncer config + 15-min user timer also sync VTODOs. Tasks
# therefore require hwc.mail.calendar to be enabled (asserted below).

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.mail.tasks;

  dataDir = "~/.local/share/vdirsyncer";

  # Handshake: safe access to agenix secrets (mirrors calendar/index.nix).
  # Use osConfig.age.secrets path when HM evaluates as a NixOS module
  # (sudo nixos-rebuild). Fall back to the canonical agenix runtime path so
  # standalone HM (`hms`) doesn't rewrite the config with /dev/null — the secret
  # file exists at this path regardless of HM eval mode.
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  hasApplePw = (osCfg ? age) && (osCfg.age.secrets ? apple-app-pw);
  applePwPath = if hasApplePw
    then osCfg.age.secrets.apple-app-pw.path
    else "/run/agenix/apple-app-pw";

  # Same handshake for the Radicale credential (htpasswd "user:password").
  hasRadicalePw = (osCfg ? age) && (osCfg.age.secrets ? radicale-htpasswd);
  radicalePwPath = if hasRadicalePw
    then osCfg.age.secrets.radicale-htpasswd.path
    else "/run/agenix/radicale-htpasswd";

  # Reuse the calendar account's email — same Apple ID, same secret.
  calAccounts = config.hwc.mail.calendar.accounts;
  hasAccount = calAccounts ? ${cfg.account};
  email = if hasAccount then calAccounts.${cfg.account}.email else "";

  tasksPair = import ./parts/vdirsyncer-pair.nix {
    inherit email applePwPath dataDir;
    collections = cfg.collections;
  };

  radicalePair = import ./parts/vdirsyncer-pair-radicale.nix {
    inherit dataDir;
    url = cfg.radicale.url;
    username = cfg.radicale.username;
    secretPath = radicalePwPath;
  };

  todomanConfig = import ./parts/todoman-config.nix {
    defaultList = cfg.defaultList;
    # "tasks*/*" also matches tasks-radicale/ when that backend is on.
    pathGlob = if cfg.radicale.enable then "tasks*/*" else "tasks/*";
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.mail.tasks = {
    enable = lib.mkEnableOption "VTODO/Reminders task sync via vdirsyncer + todoman";

    icloud.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The iCloud CalDAV tasks pair. HISTORICAL NOTE: Apple's Reminders
        "upgrade" (triggered phone-side 2026-06-11) permanently removed
        CalDAV access to iCloud reminders — upgraded lists serve only
        placeholder items ("The creator of this list has upgraded these
        reminders."). Once upgraded there is no way back; disable this and
        use the Radicale backend instead.
      '';
    };

    account = lib.mkOption {
      type = lib.types.str;
      default = "icloud";
      description = ''
        Name of the hwc.mail.calendar.accounts.<name> entry whose email/Apple ID
        is reused for the tasks CalDAV pair. The same apple-app-pw secret is used.
      '';
    };

    defaultList = lib.mkOption {
      type = lib.types.str;
      default = "Reminders";
      description = ''
        todoman default_list for `todo new` when -l is omitted. Must match a
        collection directory created by `vdirsyncer discover tasks`; correct it
        and re-run `hms` if the discovered list name differs.
      '';
    };

    collections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "from a" "from b" ];
      example = [ "36BB690C-8948-4AB5-A0CB-C0596887C4E5" ];
      description = ''
        vdirsyncer `collections` for the tasks pair. Defaults to auto-discovery
        ("from a"/"from b"), but iCloud advertises VEVENT calendars alongside
        VTODO reminder lists and vdirsyncer cannot filter discovery by component
        type — auto-discovery therefore pulls calendars in and breaks todoman on
        duplicate display names. Pin this to the VTODO collection IDs (the Apple
        Reminders lists). Find them with `vdirsyncer discover tasks` and a
        `supported-calendar-component-set` PROPFIND. This is account-specific, so
        set it in the machine one-off, not here.
      '';
    };

    radicale = {
      enable = lib.mkEnableOption ''
        second tasks pair against the self-hosted Radicale server
        (tasks.hwc.iheartwoodcraft.com). Auto-discovers collections both ways,
        so lists created locally (todui N) sync to the server and the phone
        (via its CalDAV account). Requires the radicale-htpasswd secret and
        the server's hwc.server.services.radicale to be deployed
      '';

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://tasks.hwc.iheartwoodcraft.com/";
        description = "Radicale CalDAV base URL (the Caddy vhost).";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Radicale username (first field of the htpasswd secret).";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.todoman ];

    # Contribute the tasks pair(s) to the shared (calendar) vdirsyncer config.
    hwc.mail.calendar.extraVdirsyncerPairs =
      lib.optional cfg.icloud.enable tasksPair
      ++ lib.optional cfg.radicale.enable radicalePair;

    # Read-only config.py (todoman does not rewrite it → store symlink is fine).
    xdg.configFile."todoman/config.py".text = todomanConfig;

    # Ensure the local vdir + cache dirs exist (mirrors calendar's calendarDirs).
    home.activation.tasksDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ~/.local/share/vdirsyncer/tasks ~/.cache/todoman
      ${lib.optionalString cfg.radicale.enable
        "run mkdir -p ~/.local/share/vdirsyncer/tasks-radicale"}
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.mail.calendar.enable;
        message = "hwc.mail.tasks requires hwc.mail.calendar.enable = true "
          + "(it shares the calendar vdirsyncer config and sync timer).";
      }
      {
        assertion = hasAccount && email != "";
        message = "hwc.mail.tasks.account = \"${cfg.account}\" must name an "
          + "existing hwc.mail.calendar.accounts.<name> entry with an email set.";
      }
    ];
  };
}
