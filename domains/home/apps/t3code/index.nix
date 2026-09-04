# domains/home/apps/t3code/index.nix
#
# T3 Code — an agent-harness control plane. It drives the provider CLIs already
# on this machine (claude, codex, pi) from one window, and from the T3 Code
# phone app over the same server.
#
# TWO SHAPES, ONE FORK. `desktop.*` is the Electron app hwc-laptop runs.
# `serve.*` is the headless `t3 serve` process hwc-server runs, reached over
# HTTPS through the Caddy vhost. They are mutually exclusive on one machine —
# see the assertion below.
#
# THIS MODULE PACKAGES NO SOURCE. T3 Code is a pnpm monorepo, built from Eric's
# fork at ~/600_apps/t3code and run from that working tree. Nix supplies only
# what a working tree cannot supply for itself:
#
#   * Electron, for the desktop shape. NixOS cannot run the Electron binary npm
#     downloads — that binary expects an FHS dynamic linker. The `electron` npm
#     package honours ELECTRON_OVERRIDE_DIST_PATH, so the launcher below points
#     it at a shim directory holding one symlink to nixpkgs' Electron.
#
#   * A garbage-collection root. Putting pkgs.electron in home.packages is what
#     stops the next `nix-collect-garbage` from deleting the store path the
#     launcher resolves. A hand-made symlink into /nix/store is not a GC root;
#     the launcher therefore rebuilds the shim from PATH at every start rather
#     than trusting a path baked in at build time.
#
#   * A desktop entry and an icon, so the app appears in the launcher like any
#     other application instead of living in a terminal.
#
#   * For the headless shape: a deterministic PATH. A systemd user service
#     inherits none of an interactive shell's PATH, and T3 resolves its provider
#     binaries out of its own process environment.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.t3code;

  # Resolve Electron from PATH at RUN time, never at build time. A store path
  # written into this script would survive until the next garbage collection
  # and then break with a file-not-found the user cannot read.
  launcher = pkgs.writeShellApplication {
    name = "t3code";
    runtimeInputs = [ cfg.desktop.electronPackage pkgs.coreutils pkgs.nodejs ];
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

      ${lib.optionalString (cfg.desktop.port != null) ''
        export T3CODE_PORT=${toString cfg.desktop.port}
      ''}

      cd "$REPO"
      exec node "$START" "$@"
    '';
  };

  # Headless server. `serve` is upstream's own headless entry point
  # (apps/server/src/cli/server.ts): it starts the backend, skips the browser,
  # and prints pairing details. It does NOT need Electron.
  #
  # Both artifacts are checked, not just the binary: `vp run --filter t3 build`
  # bundles the web client into apps/server/dist/client (apps/server/vite.config.ts
  # declares `dependsOn: ["@t3tools/web#build"]`), and a half-built tree that has
  # bin.mjs but no client serves a blank page instead of failing.
  serveLauncher = pkgs.writeShellApplication {
    name = "t3-serve";
    runtimeInputs = [ pkgs.nodejs pkgs.coreutils ];
    text = ''
      REPO=${lib.escapeShellArg cfg.repo}
      BIN="$REPO/apps/server/dist/bin.mjs"
      CLIENT="$REPO/apps/server/dist/client/index.html"

      for artifact in "$BIN" "$CLIENT"; do
        if [ ! -f "$artifact" ]; then
          echo "t3-serve: $artifact is missing — the fork is not built." >&2
          echo "  run t3-update" >&2
          exit 1
        fi
      done

      cd "$REPO"
      exec node "$BIN" serve \
        --host ${lib.escapeShellArg cfg.serve.host} \
        --port ${toString cfg.serve.port} "$@"
    '';
  };

  # One command for the whole update, because the three steps are not
  # independent: the server bundle embeds the web client, so pulling without
  # rebuilding leaves source, bundle and client assets on different revisions.
  updater = pkgs.writeShellApplication {
    name = "t3-update";
    runtimeInputs = [ pkgs.nodejs pkgs.git pkgs.coreutils pkgs.curl pkgs.systemd ];
    text = ''
      REPO=${lib.escapeShellArg cfg.repo}
      cd "$REPO"

      git pull --ff-only
      # Electron is a desktop-only dependency and its npm binary cannot run on
      # NixOS anyway; skipping the download saves ~200MB per install.
      export ELECTRON_SKIP_BINARY_DOWNLOAD=1
      npx --yes pnpm@${cfg.pnpmVersion} install --frozen-lockfile
      ${
        if cfg.serve.enable
        then "npx --yes pnpm@${cfg.pnpmVersion} exec vp run --filter t3 build"
        else "npx --yes pnpm@${cfg.pnpmVersion} build"
      }

      echo "built $(git rev-parse --short HEAD)"

      ${lib.optionalString cfg.serve.enable ''
        systemctl --user restart t3-serve.service
        systemctl --user --no-pager --lines=0 status t3-serve.service
      ''}
    '';
  };

  # The service's PATH, spelled out. `claude` is an ad-hoc npm global on
  # hwc-server rather than a Nix package, and codex/pi/herdr live in the
  # per-user Nix profile — none of which a user unit inherits on its own.
  servePath = lib.concatStringsSep ":" (
    [ (lib.makeBinPath cfg.serve.packages) ]
    ++ cfg.serve.extraPath
  );
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.t3code = {
    enable = lib.mkEnableOption "T3 Code, built from the local fork";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/600_apps/t3code";
      description = ''
        Working tree of the T3 Code fork (eriqueo/t3code). The launchers run the
        build in this directory; they do not build it. `t3-update` does.
      '';
    };

    pnpmVersion = lib.mkOption {
      type = lib.types.str;
      default = "11.10.0";
      description = ''
        pnpm version the fork pins in package.json `packageManager`. Used by
        `t3-update`, and in the error message a launcher prints when the build
        is missing, so the fix it names is the fix that works.
      '';
    };

    #------------------------------------------------------------------
    # Desktop shape (hwc-laptop)
    #------------------------------------------------------------------
    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the Electron app, its launcher and its desktop entry. Off on a
          headless machine, where Electron is dead weight and cannot start.
        '';
      };

      electronPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.electron_43;
        description = ''
          Electron used at run time. Keep the MAJOR version matched to
          apps/desktop/package.json — main.cjs is compiled against that ABI.
          Pinned to the MAJOR explicitly, not to `pkgs.electron`, so a nixpkgs
          bump cannot silently move the ABI out from under a built fork.

          Measured 2026-09-03: the fork asks for 43.4.1 and nixpkgs' 43.1.0 runs
          it. Was 41.5.0/41.9.1 until the upstream rebase that brought in
          claude-fable-5-1; the desktop Electron pin moved 41 -> 43 with it.
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

    #------------------------------------------------------------------
    # Headless shape (hwc-server)
    #------------------------------------------------------------------
    serve = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `t3 serve` as a systemd user service, with no Electron and no
          desktop entry. Reached through a reverse proxy, not directly: the
          service binds `serve.host` only.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Interface the headless server binds. Loopback is correct behind Caddy —
          the vhost terminates TLS with the *.hwc.iheartwoodcraft.com wildcard and
          the server firewall is tailscale-only, so binding wider adds exposure
          without adding reach.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3773;
        description = ''
          Port the headless server binds. Fixed, not scanned: the reverse-proxy
          upstream and the phone's pairing both hold this number.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          nodejs
          git
          openssh
          coreutils
          gnugrep
          gnused
          findutils
          ripgrep
          fd
          curl
          jq
          less
          bashInteractive
        ];
        description = ''
          Nix packages placed on the service's PATH. T3 resolves provider
          binaries and the tools its agents shell out to from its own process
          environment, and a systemd user service inherits nothing.
        '';
      };

      extraPath = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "${config.home.homeDirectory}/.npm-global/bin"
          "/etc/profiles/per-user/${config.home.username}/bin"
          "/run/current-system/sw/bin"
        ];
        description = ''
          Non-store directories appended to the service PATH. These carry the
          provider CLIs the harness drives: `claude` is an ad-hoc npm global on
          hwc-server, while `codex`, `pi` and `herdr` come from the per-user Nix
          profile. `pi` matters as much as the others — the delegate skill runs
          `pi --model mycloud/dx1` as a child process, not through Herdr.
        '';
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # electronPackage is listed as well as referenced, so it is a GC root even
    # if the launcher script is never run.
    home.packages =
      [ updater ]
      ++ lib.optionals cfg.desktop.enable [ launcher cfg.desktop.electronPackage ]
      ++ lib.optional cfg.serve.enable serveLauncher;

    systemd.user.services.t3code = lib.mkIf (cfg.desktop.enable && cfg.desktop.autoStart) {
      Unit = {
        Description = "T3 Code (autostart)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        # THE BACKEND ESCAPES THIS UNIT'S CGROUP, so systemd's own KillMode
        # cannot reach it. Measured 2026-08-26: after `systemctl --user stop
        # t3code`, the backend was still alive holding port 3773, and
        # /proc/<pid>/cgroup read
        # `…/app.slice/app-electron-1473967.scope` — a sibling scope, not
        # t3code.service. Electron moves its child there. The orphan then made
        # the next app launch start a SECOND backend against the same
        # ~/.t3 SQLite store, and the app failed with
        # "Primary environment request failed during fetch-session-state
        # (HTTP 500)".
        #
        # So the unit sweeps by command line instead of by cgroup. The pattern
        # names this repo's own bin.mjs, so a second checkout is untouched.
        # `-` prefixes are required: pkill exits 1 when nothing matches, which
        # is the normal case and must not fail the unit.
        #
        # THIS SWEEP IS ELECTRON-SPECIFIC. The headless unit below does not
        # carry it: `t3 serve` is the process systemd starts, so it stays in the
        # unit's own cgroup and ordinary KillMode reaches it.
        ExecStartPre = "-${pkgs.procps}/bin/pkill -f ${lib.escapeShellArg "${cfg.repo}/apps/server/dist/bin.mjs"}";
        ExecStart = lib.getExe launcher;
        ExecStopPost = "-${pkgs.procps}/bin/pkill -f ${lib.escapeShellArg "${cfg.repo}/apps/server/dist/bin.mjs"}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.t3-serve = lib.mkIf cfg.serve.enable {
      Unit = {
        Description = "T3 Code headless server (${cfg.repo})";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        WorkingDirectory = cfg.repo;
        Environment = [ "PATH=${servePath}" ];
        ExecStart = lib.getExe serveLauncher;
        Restart = "on-failure";
        RestartSec = 5;
        # The server closes WebSocket scopes on SIGTERM
        # (apps/server/src/server.ts) — give it room, then take the cgroup.
        KillMode = "control-group";
        TimeoutStopSec = 30;
        # Stop a crash-looping build from restarting forever.
        StartLimitBurst = 5;
        StartLimitIntervalSec = 120;
      };
      # default.target, not graphical-session.target: hwc-server has no session
      # to hang this off, and lingering is already on for eric.
      Install.WantedBy = [ "default.target" ];
    };

    xdg.desktopEntries.t3code = lib.mkIf (cfg.desktop.enable && cfg.desktop.desktopEntry.enable) {
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
      lib.mkIf (cfg.desktop.enable && cfg.desktop.desktopEntry.enable) {
        source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/assets/prod/logo.svg";
      };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = !(cfg.desktop.enable && cfg.serve.enable);
        message = ''
          hwc.home.apps.t3code: desktop.enable and serve.enable are mutually
          exclusive on one machine. The desktop app always starts its OWN backend
          (apps/desktop/src/app/DesktopApp.ts) and never attaches to a running
          one, so both together put two writers on one event-sourced ~/.t3
          SQLite store. That is the failure that produced "Primary environment
          request failed during fetch-session-state (HTTP 500)" on 2026-08-26.
        '';
      }
    ];

    warnings =
      lib.optional (!builtins.pathExists "${cfg.repo}/apps/desktop/package.json")
        "hwc.home.apps.t3code: ${cfg.repo} does not look like the T3 Code fork. Clone eriqueo/t3code there, or set hwc.home.apps.t3code.repo.";
  };
}
