# domains/home/apps/tasq/index.nix
#
# tasq — VTODO-native keyboard task TUI (Textual) over the Phase A vdir
#
# NAMESPACE: hwc.home.apps.tasq.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.tasq.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). Enabled in
# profiles/desktop/home.nix. Source lives git-tracked in workspace/home/tasq/
# and is exec'd by absolute path (scraper precedent) — editing the .py files
# takes effect immediately; only env/module changes need a rebuild.

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.tasq;

  # Handshake protocol for standalone compatibility
  nixosPath = lib.attrByPath [ "hwc" "paths" "nixos" ] "/home/eric/.nixos" osConfig;

  # Follow the enabled backends (same HM eval as hwc.mail.tasks): tasq reads
  # the matching vdirs, syncs the matching pairs, and `N` creates lists in
  # the Radicale root (where they genuinely sync server-side). iCloud died
  # 2026-06-11 (Apple Reminders "upgrade" removed CalDAV access).
  radicaleOn = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "enable" ] false config;
  icloudOn = lib.attrByPath [ "hwc" "mail" "tasks" "icloud" "enable" ] true config;
  vdirRoot = "${config.home.homeDirectory}/.local/share/vdirsyncer";

  # Radicale CalDAV endpoint + credential, mirrored from the vdirsyncer pair
  # (hwc.mail.tasks.radicale.* + the shared agenix htpasswd). tasq uses these
  # for list deletion: vdirsyncer can't delete a collection, but a CalDAV
  # DELETE straight to Radicale can. Same osConfig.age handshake as
  # domains/mail/tasks so it resolves under standalone HM eval too.
  radicaleUrl = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "url" ]
    "https://tasks.hwc.iheartwoodcraft.com/" config;
  radicaleUser = lib.attrByPath [ "hwc" "mail" "tasks" "radicale" "username" ]
    "eric" config;
  radicalePwPath =
    if (osConfig ? age) && ((osConfig.age.secrets or {}) ? radicale-htpasswd)
    then osConfig.age.secrets.radicale-htpasswd.path
    else "/run/agenix/radicale-htpasswd";

  backendGlobs =
    lib.optional icloudOn "${vdirRoot}/tasks/*"
    ++ lib.optional radicaleOn "${vdirRoot}/tasks-radicale/*";
  syncPairs =
    lib.optional icloudOn "tasks" ++ lib.optional radicaleOn "tasks_radicale";

  # toPythonModule is the trick: nixpkgs only ships todoman as a top-level
  # application (no python3Packages.todoman), but its lib (todoman.model) is
  # the VTODO read/write engine tasq is built on.
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.textual
    ps.icalendar
    (ps.toPythonModule pkgs.todoman)
  ]);

  # Active system palette (domains/home/theme), flattened to its string
  # tokens and handed to the app as JSON. tasq derives all its colors from
  # this — switching hwc.home.theme.palette restyles tasq on next rebuild.
  paletteJson = builtins.toJSON
    (lib.filterAttrs (_: v: builtins.isString v)
      (((config.hwc.home.theme or {}).colors or {})));

  runner = pkgs.writeShellScriptBin "tasq" ''
    export TASQ_PATH="''${TASQ_PATH:-${cfg.tasksGlob}}"
    export TASQ_CACHE="''${TASQ_CACHE:-${cfg.cachePath}}"
    export TASQ_PALETTE=${lib.escapeShellArg paletteJson}
    ${lib.optionalString (syncPairs != []) ''
      export TASQ_SYNC_PAIRS="${lib.concatStringsSep " " syncPairs}"
    ''}
    ${lib.optionalString radicaleOn ''
      export TASQ_NEW_LIST_ROOT="${vdirRoot}/tasks-radicale"
      export TASQ_NEW_LIST_PAIR="tasks_radicale"
      export TASQ_RADICALE_URL="${radicaleUrl}"
      export TASQ_RADICALE_USER="${radicaleUser}"
      export TASQ_RADICALE_PW_CMD="cut -d: -f2- ${radicalePwPath}"
    ''}
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/tasq/app.py "$@"
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.tasq = {
    enable = lib.mkEnableOption "tasq — VTODO-native keyboard task TUI";

    tasksGlob = lib.mkOption {
      type = lib.types.str;
      default =
        if backendGlobs == [] then "${vdirRoot}/tasks/*"
        else lib.concatStringsSep ":" backendGlobs;
      description = ''
        Glob(s) to the VTODO vdir list dirs, ":"-separated — derived from the
        enabled hwc.mail.tasks backends (icloud and/or radicale).
      '';
    };

    cachePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/tasq/cache.sqlite3";
      description = "tasq's own todoman.model sqlite cache (separate from the todoman CLI's).";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ runner ];

    home.sessionVariables = {
      TASQ_PATH = cfg.tasksGlob;
      TASQ_CACHE = cfg.cachePath;
    };

    home.activation.tasqDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg (builtins.dirOf cfg.cachePath)}
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    # Relative path so the check works under pure/restricted eval (an absolute
    # /home path here would break flake evaluation).
    assertions = [
      {
        assertion = builtins.pathExists ../../../../workspace/home/tasq/app.py;
        message = "hwc.home.apps.tasq: workspace/home/tasq/app.py is missing from the repo.";
      }
    ];
  };
}
