{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.home.apps.agent-harness;
  home = config.home.homeDirectory;
  harness = inputs.agent-harness;
  configDirs = map (name: "${home}/${name}") ([ ".claude" ] ++ cfg.claudeConfigDirs);
  stateSync = pkgs.writeShellApplication {
    name = "agent-state-sync";
    runtimeInputs = with pkgs; [ git coreutils findutils util-linux openssh curl jq ];
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      export AGENT_CONFIG_DIRS=${lib.escapeShellArg (lib.concatStringsSep ":" configDirs)}
      exec ${pkgs.bash}/bin/bash ${./state-sync.sh} "$@"
    '';
  };
  doctor = pkgs.writeShellApplication {
    name = "agent-harness-doctor";
    runtimeInputs = with pkgs; [ git coreutils findutils jq ];
    text = ''
      set -u
      failures=0
      check() { if "$@"; then printf 'ok   %s\n' "$*"; else printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); fi; }
      check test -r /etc/agent-harness/CLAUDE.md
      check test -r "$HOME/.claude/CLAUDE.md"
      check test -r "$HOME/.codex/AGENTS.md"
      check test -r "$HOME/.pi/agent/AGENTS.md"
      check test -d ${lib.escapeShellArg cfg.stateDir}/.git
      check test -r ${lib.escapeShellArg cfg.stateDir}/MISTAKES.md
      check systemctl --user --quiet is-active agent-state-sync.timer
      check command -v claude
      check command -v codex
      check command -v pi
      check command -v herdr
      printf '%s\n' "static revision: ${inputs.agent-harness.rev or "dirty"}"
      exit "$failures"
    '';
  };
  cli = pkgs.writeShellApplication {
    name = "agent-harness";
    runtimeInputs = [ stateSync doctor pkgs.git pkgs.systemd ];
    text = ''
      command="''${1:-}"
      if [ -z "$command" ] && [ -t 0 ]; then
        printf '1 status\n2 doctor\n3 sync\n4 static diff\n> '
        read -r choice
        case "$choice" in 1) command=status;; 2) command=doctor;; 3) command=sync;; 4) command=diff;; *) exit 2;; esac
      fi
      case "$command" in
        status) systemctl --user status agent-state-sync.timer --no-pager; git -C ${lib.escapeShellArg cfg.stateDir} status --short --branch ;;
        doctor) exec agent-harness-doctor ;;
        sync) exec agent-state-sync sync ;;
        diff) git --no-pager diff --no-index /etc/agent-harness ${lib.escapeShellArg cfg.editableSource} || [ "$?" = 1 ] ;;
        *) echo 'usage: agent-harness [status|doctor|sync|diff]' >&2; exit 2 ;;
      esac
    '';
  };
in
{
  options.hwc.home.apps.agent-harness = {
    enable = lib.mkEnableOption "shared agent harness control plane";
    stateDir = lib.mkOption { type = lib.types.str; default = "${home}/.agent-state"; };
    editableSource = lib.mkOption { type = lib.types.str; default = "${home}/.claude-config"; };
    claudeConfigDirs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ".claude_dx2_home" ]; };
    syncInterval = lib.mkOption { type = lib.types.str; default = "1min"; };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cli doctor stateSync (pkgs.writeShellScriptBin "log-mistake" ''exec ${pkgs.python3}/bin/python3 ${harness}/bin/log-mistake "$@"'') ];

    home.file = lib.mkMerge (map (dir: {
      "${dir}/skills".source = harness + "/skills";
      "${dir}/agents".source = harness + "/agents";
      "${dir}/commands".source = harness + "/commands";
      "${dir}/CLAUDE.md".source = harness + "/CLAUDE.md";
      "${dir}/standing-instructions.md".source = harness + "/standing-instructions.md";
      "${dir}/engineering-principles.md".source = harness + "/engineering-principles.md";
    }) ([ ".claude" ] ++ cfg.claudeConfigDirs));

    home.activation.agentHarnessMemoryLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${stateSync}/bin/agent-state-sync link || echo "agent-harness: state clone missing; run agent-harness doctor" >&2
    '';

    systemd.user.services.agent-state-sync = {
      Unit.Description = "Synchronize mutable agent memories and mistakes ledger";
      Service = { Type = "oneshot"; ExecStart = "${stateSync}/bin/agent-state-sync sync"; };
    };
    systemd.user.timers.agent-state-sync = {
      Unit.Description = "Periodic agent state synchronization";
      Install.WantedBy = [ "timers.target" ];
      Timer = { OnBootSec = "1min"; OnUnitActiveSec = cfg.syncInterval; Unit = "agent-state-sync.service"; };
    };
  };
}
