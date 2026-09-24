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
# [pair tasks_radicale] fragment to hwc.mail.calendar.extraVdirsyncerPairs, so
# the single calendar vdirsyncer config + 15-min user timer also sync VTODOs.
# Tasks therefore require hwc.mail.calendar to be enabled (asserted below).
#
# Radicale is the only backend. The iCloud pair was deleted 2026-09-24: Apple's
# Reminders "upgrade" (2026-06-11) removed CalDAV access to iCloud reminders, and
# the pair still defaulted on, so the server synced a dead store for months.

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.mail.tasks;

  dataDir = "~/.local/share/vdirsyncer";

  # Handshake: safe access to the Radicale credential (htpasswd "user:password").
  # Use osConfig.age.secrets path when HM evaluates as a NixOS module
  # (sudo nixos-rebuild). Fall back to the canonical agenix runtime path so
  # standalone HM (`hms`) doesn't rewrite the config with /dev/null — the secret
  # file exists at this path regardless of HM eval mode.
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  hasRadicalePw = (osCfg ? age) && (osCfg.age.secrets ? radicale-htpasswd);
  radicalePwPath = if hasRadicalePw
    then osCfg.age.secrets.radicale-htpasswd.path
    else "/run/agenix/radicale-htpasswd";

  radicalePair = import ./parts/vdirsyncer-pair-radicale.nix {
    inherit lib dataDir;
    url = cfg.radicale.url;
    username = cfg.radicale.username;
    secretPath = radicalePwPath;
  };

  todomanConfig = import ./parts/todoman-config.nix {
    defaultList = cfg.defaultList;
  };

  emailToTask = pkgs.writeShellScriptBin "email-to-task" ''
    exec ${pkgs.python3}/bin/python3 ${./parts/email-to-task.py} "$@"
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.mail.tasks = {
    enable = lib.mkEnableOption ''
      VTODO task sync against the self-hosted Radicale server
      (tasks.hwc.iheartwoodcraft.com) via vdirsyncer + todoman. Auto-discovers
      collections both ways, so lists created locally (todui N) sync to the
      server and the phone (via its CalDAV account). Requires the
      radicale-htpasswd secret and the server's hwc.server.services.radicale
    '';

    defaultList = lib.mkOption {
      type = lib.types.str;
      default = config.hwc.mail.calendar.primaryCalendar;
      defaultText = lib.literalExpression "config.hwc.mail.calendar.primaryCalendar";
      description = ''
        todoman default_list for `todo new` when -l is omitted. todoman matches
        the collection's displayname, and the Work collection (eric/work) is
        shared with the calendar, so this follows the calendar's name for it.
      '';
    };

    radicale = {
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
    home.packages = [ pkgs.todoman emailToTask ];

    # Contribute the tasks pair to the shared (calendar) vdirsyncer config.
    hwc.mail.calendar.extraVdirsyncerPairs = [ radicalePair ];

    # Read-only config.py (todoman does not rewrite it → store symlink is fine).
    xdg.configFile."todoman/config.py".text = todomanConfig;

    # Ensure the local vdir + cache dirs exist (mirrors calendar's calendarDirs).
    home.activation.tasksDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ~/.local/share/vdirsyncer/tasks-radicale ~/.cache/todoman
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
    ];
  };
}
