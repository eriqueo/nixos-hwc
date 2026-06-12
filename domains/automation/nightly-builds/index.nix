# domains/automation/nightly-builds/index.nix
#
# Nightly Builds — unattended overnight execution of gauntlet cards.
#
# Picks up cards marked `status: queued` from the brain vault's
# _inbox/nightly_builds/ goal folders, runs each in a disposable git
# worktree of the nixos repo via headless Claude Code, writes a
# self-verifying REPORT.md into the vault's runs/ tree, pushes the
# result branch to origin, and flips the card status. A card-smith
# pre-pass drafts new cards from _ideas.md (drafts only — a human
# flips draft -> queued; that flip IS the Phase-4 gate).
#
# Containment model (gauntlet gate 7): output goes to branches and the
# vault only. The agent never runs nixos-rebuild and never touches live
# services; morning review is the only thing that promotes anything.
#
# NAMESPACE: hwc.automation.nightlyBuilds.*
#
# DEPENDENCIES:
#   - hwc.paths.nixos (repo working copy)
#   - hwc.paths.brain.server-replica / .vault (Syncthing'd brain vault)
#   - Claude Code CLI authenticated for the eric user

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.nightlyBuilds;
  paths = config.hwc.paths;
  agentDir = "${paths.nixos}/domains/automation/nightly-builds";
in
{
  # OPTIONS
  options.hwc.automation.nightlyBuilds = {
    enable = lib.mkEnableOption "Nightly gauntlet-card runner (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 01:30:00";
      description = "systemd calendar expression for the nightly launch";
    };

    maxCards = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum number of queued cards to run per night";
    };

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if paths.brain.server-replica != null
        then paths.brain.server-replica
        else paths.brain.vault;
      description = "Brain vault root (contains _inbox/nightly_builds/ and runs/)";
    };

    repoDir = lib.mkOption {
      type = lib.types.path;
      default = paths.nixos;
      description = "nixos repo working copy that worktrees are created from";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vaultDir != null;
        message = "hwc.automation.nightlyBuilds: vaultDir is null — brain vault path not defined on this host";
      }
    ];

    systemd.services.nightly-builds = {
      description = "Nightly Builds — gauntlet card runner (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME = paths.user.home;
        NB_VAULT_DIR = toString cfg.vaultDir;
        NB_REPO_DIR = toString cfg.repoDir;
        NB_MAX_CARDS = toString cfg.maxCards;
      };
      path = [
        pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
        pkgs.nodejs_22 pkgs.python3 pkgs.jq pkgs.ripgrep
      ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # One card budget tops out at 150 min; card-smith + overhead on top.
        TimeoutSec = 4 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.nightly-builds = {
      description = "Nightly Builds launch timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Not Persistent: a missed night must not fire mid-day while the
        # repo/vault are being actively worked on.
        Persistent = false;
        RandomizedDelaySec = "60s";
      };
    };
  };
}
