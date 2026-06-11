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

  # Reuse the calendar account's email — same Apple ID, same secret.
  calAccounts = config.hwc.mail.calendar.accounts;
  hasAccount = calAccounts ? ${cfg.account};
  email = if hasAccount then calAccounts.${cfg.account}.email else "";

  tasksPair = import ./parts/vdirsyncer-pair.nix {
    inherit email applePwPath dataDir;
  };

  todomanConfig = import ./parts/todoman-config.nix {
    defaultList = cfg.defaultList;
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.mail.tasks = {
    enable = lib.mkEnableOption "VTODO/Reminders task sync via vdirsyncer + todoman";

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
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.todoman ];

    # Contribute the tasks pair to the shared (calendar) vdirsyncer config.
    hwc.mail.calendar.extraVdirsyncerPairs = [ tasksPair ];

    # Read-only config.py (todoman does not rewrite it → store symlink is fine).
    xdg.configFile."todoman/config.py".text = todomanConfig;

    # Ensure the local vdir + cache dirs exist (mirrors calendar's calendarDirs).
    home.activation.tasksDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ~/.local/share/vdirsyncer/tasks ~/.cache/todoman
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
