# Herdr core (`herdr-core`, also `hc`): the terminal runtime behind the Herdr
# App. Not the older TUI multiplexer, which apps/herdr owns.
#
# `serve` keeps one core running on a headless host across reboots, so the
# laptop's Herdr machine entry (`hc machine add hwc-work`) reaches terminals
# that outlive every login. Facts this relies on, measured on 0.1.20:
#   * The laptop reaches a machine with
#     `ssh M sh -c 'p=$(command -v herdr-core) || p=~/.local/bin/herdr-core; exec "$p" connect'`.
#     `connect` starts a core only when none answers on the session socket, so
#     the managed core is the one it finds.
#   * A second `herdr-core serve` for the same session exits 0 at once
#     (re-measured 2026-11-13). Restart=always is safe only because the
#     reclaim step first stops the default core's transient unit, and the
#     start limit ends a loop against any other default core.
#   * `hc server restart` (and `hc machine update`) moves the core into a new
#     transient `hc-serve-*` unit and this unit exits 0. Terminals live in
#     separate `hc-hold-*` units and survive both, and a SIGTERM to the core.
#   * The core gives new terminals the environment it started with. Under
#     systemd that lacks the login PATH (~/.npm-global/bin, where the provider
#     CLIs live), so it starts through zsh, which reads the same zshenv an ssh
#     command does.
#   * The Herdr App attaches to a core that already answers: `hc server start`
#     against a running core returns that core (same pid, measured 2026-11-13).
#
# serve.binary (the laptop): the app installs and updates its own core in
# ~/.local, so the unit runs that binary, installs no package, starts with the
# graphical session (the core hands its environment to every terminal it
# starts, including the shells a reboot gives back) and never takes a core back
# from the app, whose updates restart it in a transient unit by design.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.herdr-core;
  managed = cfg.serve.binary == null;
  binary = if managed then "${cfg.package}/bin/herdr-core" else cfg.serve.binary;

  # HELPERS
  # After `hc server restart` the default session's core runs in a transient
  # hc-serve-* unit and this unit has exited. Stop that core so this unit owns
  # it again; terminals live in hc-hold-* units and survive. Cores of other
  # sessions (HC_SESSION, e.g. isolated test cores) are left alone.
  reclaim = pkgs.writeShellApplication {
    name = "herdr-core-reclaim";
    runtimeInputs = [ pkgs.systemd pkgs.gawk pkgs.coreutils ];
    text = ''
      for unit in $(systemctl --user list-units 'hc-serve-*.service' --state=active --plain --no-legend | awk '{ print $1 }'); do
        pid=$(systemctl --user show -p MainPID --value "$unit")
        [ "''${pid:-0}" -gt 0 ] || continue
        session=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | awk -F= '$1 == "HC_SESSION" { print substr($0, 12) }') || true
        [ "''${session:-default}" = default ] || continue
        echo "herdr-core: taking the default core back from $unit (pid $pid)"
        systemctl --user stop "$unit"
      done
    '';
  };
in
{
  # OPTIONS
  options.hwc.home.apps.herdr-core = {
    enable = lib.mkEnableOption "Herdr core (herdr-core / hc), pinned from its upstream release";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./parts/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./parts/package.nix { }";
      description = "The herdr-core package. A Nix store binary refuses `hc update`; bump it here.";
    };

    serve.enable = lib.mkEnableOption ''
      a persistent core for the default session (systemd user unit
      herdr-core.service), for a headless host other machines reach over ssh.
      Off where nothing should start a core at login'';

    serve.binary = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression ''"''${config.home.homeDirectory}/.local/bin/herdr-core"'';
      description = ''
        Run this herdr-core binary instead of `package`, for a host whose Herdr
        App installs and updates its own core. The module then installs no
        package, starts the core with the graphical session, and never takes a
        core back from the app. With the default (null) the unit runs `package`
        at login and takes the default core back after `hc server restart`.'';
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    home.packages = lib.mkIf managed [ cfg.package ];

    systemd.user.services.herdr-core = lib.mkIf cfg.serve.enable {
      Unit = {
        Description = "Herdr core: terminals that stay alive";
        # A core that keeps exiting at once (another default core outside an
        # hc-serve-* unit answers) fails visibly instead of looping.
        StartLimitIntervalSec = 120;
        StartLimitBurst = 5;
      } // lib.optionalAttrs (!managed) {
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "exec";
        ExecStart = "${config.programs.zsh.package}/bin/zsh -c ${lib.escapeShellArg "exec ${lib.escapeShellArg binary} serve"}";
        # The core starts its holders as their own units; never take them down.
        KillMode = "process";
        OOMPolicy = "continue";
        # A second core for the session exits 0 at once, so the app-owned
        # laptop core restarts only on failure. The managed core restarts
        # always: after `hc server restart` hands it to a transient unit (exit
        # 0), the next start takes it back (reclaim). Also after `hc server
        # stop`; stop this unit to keep it down.
        Restart = if managed then "always" else "on-failure";
        RestartSec = 5;
      } // lib.optionalAttrs managed {
        ExecStartPre = "${reclaim}/bin/herdr-core-reclaim";
      };
      Install.WantedBy = [ (if managed then "default.target" else "graphical-session.target") ];
    };

    # VALIDATION
    assertions = [
      {
        assertion = !cfg.serve.enable || config.programs.zsh.enable;
        message = "hwc.home.apps.herdr-core.serve starts the core through zsh for the login PATH; enable programs.zsh";
      }
      {
        assertion = managed || lib.hasPrefix "/" cfg.serve.binary;
        message = "hwc.home.apps.herdr-core.serve.binary must be an absolute path";
      }
    ];
  };
}
