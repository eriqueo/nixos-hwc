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
#   * A second `herdr-core serve` for the same session exits 0 at once. So
#     Restart is on-failure, never always: a restart loop would only race.
#   * `hc server restart` (and `hc machine update`) moves the core into a new
#     transient `hc-serve-*` unit and this unit exits 0. Terminals live in
#     separate `hc-hold-*` units and survive both, and a SIGTERM to the core.
#   * The core gives new terminals the environment it started with. Under
#     systemd that lacks the login PATH (~/.npm-global/bin, where the provider
#     CLIs live), so it starts through zsh, which reads the same zshenv an ssh
#     command does.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.herdr-core;
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
      Off where the Herdr App starts its own core'';
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.herdr-core = lib.mkIf cfg.serve.enable {
      Unit.Description = "Herdr core: terminals that stay alive";
      Service = {
        Type = "exec";
        ExecStart = "${config.programs.zsh.package}/bin/zsh -c ${lib.escapeShellArg "exec ${cfg.package}/bin/herdr-core serve"}";
        # The core starts its holders as their own units; never take them down.
        KillMode = "process";
        OOMPolicy = "continue";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # VALIDATION
    assertions = [
      {
        assertion = !cfg.serve.enable || config.programs.zsh.enable;
        message = "hwc.home.apps.herdr-core.serve starts the core through zsh for the login PATH; enable programs.zsh";
      }
    ];
  };
}
