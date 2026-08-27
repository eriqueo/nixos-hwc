# domains/home/apps/t3code/index.nix
#
# T3 Code — an agent-harness control plane. It drives the provider CLIs already
# on this machine (claude, codex, opencode) from one desktop window, and from
# the T3 Code phone app over the same server.
#
# THIS MODULE PACKAGES NO SOURCE. T3 Code is a pnpm monorepo, built from Eric's
# fork at ~/600_apps/t3code and run from that working tree. Nix supplies only
# what a working tree cannot supply for itself:
#
#   * Electron. NixOS cannot run the Electron binary npm downloads — that
#     binary expects an FHS dynamic linker. The `electron` npm package honours
#     ELECTRON_OVERRIDE_DIST_PATH, so the launcher below points it at a shim
#     directory holding one symlink to nixpkgs' Electron.
#
#   * A garbage-collection root. Putting pkgs.electron in home.packages is what
#     stops the next `nix-collect-garbage` from deleting the store path the
#     launcher resolves. A hand-made symlink into /nix/store is not a GC root;
#     the launcher therefore rebuilds the shim from PATH at every start rather
#     than trusting a path baked in at build time.
#
#   * A desktop entry and an icon, so the app appears in the launcher like any
#     other application instead of living in a terminal.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.t3code;

  # Resolve Electron from PATH at RUN time, never at build time. A store path
  # written into this script would survive until the next garbage collection
  # and then break with a file-not-found the user cannot read.
  launcher = pkgs.writeShellApplication {
    name = "t3code";
    runtimeInputs = [ cfg.electronPackage pkgs.coreutils pkgs.nodejs ];
    text = ''
      REPO=${lib.escapeShellArg cfg.repo}
      MAIN="$REPO/apps/desktop/dist-electron/main.cjs"
      START="$REPO/apps/desktop/scripts/start-electron.mjs"

      if [ ! -f "$MAIN" ]; then
        echo "t3code: $MAIN is missing — the fork is not built." >&2
        echo "  cd $REPO" >&2
        echo "  npx --yes pnpm@${cfg.pnpmVersion} install" >&2
        echo "  npx --yes pnpm@${cfg.pnpmVersion} build" >&2
        exit 1
      fi

      # The shim directory the electron npm package reads. Rebuilt every start,
      # so a garbage-collected or upgraded Electron heals itself instead of
      # leaving a dangling symlink.
      SHIM="''${XDG_DATA_HOME:-$HOME/.local/share}/t3code-electron"
      mkdir -p "$SHIM"
      ln -sfn "$(command -v electron)" "$SHIM/electron"
      export ELECTRON_OVERRIDE_DIST_PATH="$SHIM"

      ${lib.optionalString (cfg.port != null) ''
        export T3CODE_PORT=${toString cfg.port}
      ''}

      cd "$REPO"
      exec node "$START" "$@"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.t3code = {
    enable = lib.mkEnableOption "T3 Code desktop app (built from the local fork)";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/600_apps/t3code";
      description = ''
        Working tree of the T3 Code fork (eriqueo/t3code). The launcher runs the
        build in this directory; it does not build it. Rebuild after a pull.
      '';
    };

    electronPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.electron;
      description = ''
        Electron used at run time. Keep the MAJOR version matched to
        apps/desktop/package.json — main.cjs is compiled against that ABI.
        Measured 2026-08-26: the fork asks for 41.5.0 and nixpkgs' 41.9.1 runs
        it correctly ("backend ready", "main window created").
      '';
    };

    pnpmVersion = lib.mkOption {
      type = lib.types.str;
      default = "11.10.0";
      description = ''
        pnpm version the fork pins in package.json `packageManager`. Used only
        in the error message the launcher prints when the build is missing, so
        the fix it names is the fix that works.
      '';
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Fixed port for the app's own backend (`T3CODE_PORT`). Leave null and the
        app scans upward from its default for a free port, which means the phone
        app must be re-paired whenever the number moves. Set a port to keep the
        pairing stable.
      '';
    };

    # NO tailscaleServe OPTION, and the reason is a deliberate upstream choice
    # rather than an oversight. `rg -c T3CODE_TAILSCALE_SERVE apps packages
    # scripts` returns exactly two files. One reads it: the headless `t3 serve`
    # CLI (apps/server/src/cli/config.ts:134). The other DELETES it:
    # DESKTOP_BACKEND_ENV_NAMES (apps/desktop/src/backend/DesktopBackendConfiguration.ts:77)
    # feeds `backendChildEnvPatch`, which maps every name in the list to
    # `undefined` and so strips it from the backend child's environment before
    # the desktop app spawns that child.
    #
    # The desktop app therefore supplies its own exposure settings, persisted in
    # the UI and driven over the IPC channels `desktop:set-server-exposure-mode`
    # and `desktop:set-tailscale-serve-enabled` (apps/desktop/src/ipc/channels.ts:38).
    # Measured 2026-08-26: the launcher exported the variable, the app started,
    # and `tailscale serve status` still reported "No serve config".
    #
    # `port` survives the same strip because the desktop reads T3CODE_PORT in
    # its OWN process and passes the value down, which is why 3891 was honoured
    # in the test and the tailscale flag was not.
    #
    # Turn Tailscale Serve on in Settings -> Connections.

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the app with the graphical session, as a systemd user service.

        THE SERVICE STARTS THE APP, NOT A SECOND SERVER, and that distinction is
        the whole design. `apps/desktop/src/app/DesktopApp.ts` always starts its
        own backend — it probes for a free port and never attaches to a running
        one. A separate `t3 serve` unit against the same `~/.t3` would therefore
        put two writers on one event-sourced SQLite store. Starting the app
        itself keeps one backend, one database and one thread history, and still
        gives the always-running behaviour a service is wanted for.
      '';
    };

    desktopEntry.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a .desktop entry and icon, so launchers list T3 Code.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # electronPackage is listed as well as referenced, so it is a GC root even
    # if the launcher script is never run.
    home.packages = [ launcher cfg.electronPackage ];

    systemd.user.services.t3code = lib.mkIf cfg.autoStart {
      Unit = {
        Description = "T3 Code (autostart)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe launcher;
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    xdg.desktopEntries.t3code = lib.mkIf cfg.desktopEntry.enable {
      name = "T3 Code";
      genericName = "Agent harness control plane";
      comment = "Drive Claude Code, Codex and OpenCode from one window";
      exec = "t3code";
      icon = "t3code";
      terminal = false;
      categories = [ "Development" ];
      startupNotify = true;
    };

    # OUT-OF-STORE SYMLINK, not a copy. The icon lives in the fork's working
    # tree, which is outside this flake — a plain `source` would try to import
    # a path the pure evaluator cannot see, and fail at build time.
    xdg.dataFile."icons/hicolor/scalable/apps/t3code.svg" =
      lib.mkIf cfg.desktopEntry.enable {
        source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/assets/prod/logo.svg";
      };

    #========================================================================
    # VALIDATION
    #========================================================================
    warnings =
      lib.optional (!builtins.pathExists "${cfg.repo}/apps/desktop/package.json")
        "hwc.home.apps.t3code: ${cfg.repo} does not look like the T3 Code fork. Clone eriqueo/t3code there, or set hwc.home.apps.t3code.repo.";
  };
}
