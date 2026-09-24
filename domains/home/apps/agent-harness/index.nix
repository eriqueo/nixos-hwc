{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.hwc.home.apps.agent-harness;
  home = config.home.homeDirectory;
  harness = inputs.agent-harness;
  revision = inputs.agent-harness.rev or "dirty";
  contract = import ./contract.nix { inherit revision; };
  expectedManifest = pkgs.writeText "agent-harness-manifest.json" (builtins.toJSON contract);
  configDirs = map (name: "${home}/${name}") ([ ".claude" ] ++ cfg.claudeConfigDirs);
  stateValidator = pkgs.writeShellApplication {
    name = "agent-state-validate";
    runtimeInputs = with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      gawk
    ];
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./state-validate.sh} "$@"
    '';
  };
  stateSync = pkgs.writeShellApplication {
    name = "agent-state-sync";
    runtimeInputs = [
      stateValidator
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      util-linux
      openssh
      curl
      jq
      gawk
    ]);
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      export AGENT_CONFIG_DIRS=${lib.escapeShellArg (lib.concatStringsSep ":" configDirs)}
      export AGENT_STATE_VALIDATOR=${stateValidator}/bin/agent-state-validate
      export AGENT_STATE_NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      exec ${pkgs.bash}/bin/bash ${./state-sync.sh} "$@"
    '';
  };
  policyHook = pkgs.writeShellScriptBin "pre-commit" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
        pkgs.ripgrep
        (pkgs.python3.withPackages (p: [ p.pyyaml ]))
        pkgs.uv
      ]
    }:$PATH
    root=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
    exec ${pkgs.bash}/bin/bash "$root/bin/harness-policy-check"
  '';
  cli = pkgs.writeShellApplication {
    name = "agent-harness";
    runtimeInputs = [
      stateSync
      stateValidator
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      openssh
      nix
      systemd
      gawk
    ]);
    text = ''
      export AGENT_HARNESS_EXPECTED_MANIFEST=${expectedManifest}
      export AGENT_HARNESS_SYSTEM_MANIFEST=/etc/agent-harness-manifest.json
      export AGENT_HARNESS_SOURCE=${lib.escapeShellArg cfg.editableSource}
      export AGENT_HARNESS_NIXOS=${lib.escapeShellArg cfg.nixosRepo}
      export AGENT_HARNESS_FLEET_HOSTS=${lib.escapeShellArg (lib.concatStringsSep ":" cfg.fleetHosts)}
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./control.sh} "$@"
    '';
  };
  doctor = pkgs.writeShellScriptBin "agent-harness-doctor" ''exec ${cli}/bin/agent-harness doctor "$@"'';

  # Nothing else updates the npm-global provider CLIs on a host that drives
  # them headless (T3 serve, nightly builds). Measured 2026-09-24 on hwc-server:
  # ~/.claude.json had autoUpdates=false, claude sat at 2.1.274 and codex at
  # 0.154.0. T3's model manifest gates Opus 5.5 on claude >= 2.1.280, so the
  # model never appeared. hwc-laptop, where both are used interactively, was
  # current.
  cliUpdater = pkgs.writeShellApplication {
    name = "agent-cli-update";
    # bash supplies `sh`: npm runs lifecycle scripts through the `sh` on PATH,
    # and a user unit's PATH is systemd's bin alone. Measured 2026-09-24:
    # without it, claude-code's postinstall failed with `spawn sh ENOENT`.
    runtimeInputs = with pkgs; [
      nodejs
      bash
      jq
      curl
      coreutils
    ];
    text = ''
      export NPM_CONFIG_PREFIX=${lib.escapeShellArg cfg.cliUpdates.npmPrefix}
      NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      HOST=$(uname -n)
      # One line: the failing packages of the last run, empty after a clean run.
      # Alerts fire on a change to it, so a lasting failure alerts once.
      CASE_FILE="''${XDG_STATE_HOME:-$HOME/.local/state}/agent-cli-update/failed"
      mkdir -p "$(dirname "$CASE_FILE")"

      # npm ls exits 1 for a package that is not installed; that means "none".
      installed() {
        local json
        json=$(npm ls -g --depth=0 --json "$1" 2>/dev/null || true)
        [ -n "$json" ] || json='{}'
        jq -r --arg p "$1" '.dependencies[$p].version // "none"' <<< "$json"
      }

      notify() {
        jq -n --arg title "$1" --arg body "$2" \
          '{topic:"monitoring",title:$title,body:$body,priority:2,source:"agent-cli-update"}' \
          | curl -fsS --max-time 5 -H 'content-type: application/json' -d @- "$NOTIFY_URL" >/dev/null 2>&1
      }

      failed=()
      for pkg in ${lib.escapeShellArgs cfg.cliUpdates.packages}; do
        before=$(installed "$pkg")
        # npm's stderr stays in the journal; that is where a failure is read.
        if npm install -g --no-fund --no-audit "$pkg@latest" >/dev/null; then
          after=$(installed "$pkg")
          # The previous version is the rollback target: npm install -g "$pkg@<it>".
          if [ "$before" = "$after" ]; then
            echo "$pkg $after (current)"
          else
            echo "$pkg $before -> $after"
          fi
        else
          echo "$pkg: npm install failed, still $before" >&2
          failed+=("$pkg")
        fi
      done

      current="''${failed[*]}"
      previous=$(cat "$CASE_FILE" 2>/dev/null || true)
      if [ "$current" != "$previous" ]; then
        if [ -n "$current" ]; then
          title="Agent CLI update failed"
          body="$HOST could not update $current. T3 hides models that need a newer CLI. Check: journalctl --user -u agent-cli-update"
        else
          title="Agent CLI update recovered"
          body="$HOST updated $previous again. No action needed."
        fi
        # Record the case only once its alert is out, so a missed alert retries.
        if notify "$title" "$body"; then printf '%s' "$current" > "$CASE_FILE"; fi
      fi

      [ -z "$current" ]
    '';
  };
in
{
  options.hwc.home.apps.agent-harness = {
    enable = lib.mkEnableOption "shared agent harness control plane";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.agent-state";
    };
    editableSource = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.claude-config";
    };
    nixosRepo = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.nixos";
    };
    fleetHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "hwc-server"
        "hwc-laptop"
      ];
    };
    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hwc-notify.hwc.iheartwoodcraft.com:29443/notify";
      description = "hwc-notify endpoint used for state-sync failure and recovery transitions";
    };
    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".claude_dx2_home" ];
    };
    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "1min";
    };
    cliUpdates = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Update the npm-global provider CLIs on a timer, for headless hosts.
          Off by default: hwc-laptop's claude is the native install, which
          updates itself, and its npm codex was current when this was added.
        '';
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "@anthropic-ai/claude-code"
          "@openai/codex"
        ];
        description = "npm packages installed globally at @latest on each run.";
      };
      npmPrefix = lib.mkOption {
        type = lib.types.str;
        default = "${home}/.npm-global";
        description = "npm global prefix; the T3 serve PATH reads its bin/ first.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 04:30:00";
        description = ''
          When to update. Clear of nightly-builds (01:30 launch) and its
          07:30 review, so no headless run sees the binary swapped under it.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cli
      doctor
      stateSync
      stateValidator
      (pkgs.writeShellScriptBin "log-mistake" ''exec ${pkgs.python3}/bin/python3 ${harness}/bin/log-mistake "$@"'')
    ]
    ++ lib.optional cfg.cliUpdates.enable cliUpdater;

    home.file = lib.mkMerge (
      map (dir: {
        "${dir}/skills".source = harness + "/skills";
        "${dir}/agents".source = harness + "/agents";
        "${dir}/commands".source = harness + "/commands";
        "${dir}/CLAUDE.md".source = harness + "/CLAUDE.md";
        "${dir}/standing-instructions.md".source = harness + "/standing-instructions.md";
        "${dir}/engineering-principles.md".source = harness + "/engineering-principles.md";
      }) ([ ".claude" ] ++ cfg.claudeConfigDirs)
    );

    home.activation.agentHarnessMemoryLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${stateSync}/bin/agent-state-sync link || echo "agent-harness: state clone missing; run agent-harness doctor" >&2
      if [ -d ${lib.escapeShellArg cfg.editableSource}/.git ]; then
        run ${pkgs.git}/bin/git -C ${lib.escapeShellArg cfg.editableSource} config core.hooksPath ${policyHook}/bin
      fi
    '';

    systemd.user.services.agent-state-sync = {
      Unit.Description = "Synchronize mutable agent memories and mistakes ledger";
      Service = {
        Type = "oneshot";
        ExecStart = "${stateSync}/bin/agent-state-sync sync";
        SuccessExitStatus = [ 75 ];
      };
    };
    systemd.user.timers.agent-state-sync = {
      Unit.Description = "Periodic agent state synchronization";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.syncInterval;
        Unit = "agent-state-sync.service";
      };
    };

    systemd.user.services.agent-cli-update = lib.mkIf cfg.cliUpdates.enable {
      Unit = {
        Description = "Update npm-global agent CLIs (${lib.concatStringsSep ", " cfg.cliUpdates.packages})";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe cliUpdater;
        TimeoutStartSec = "10min";
      };
    };
    systemd.user.timers.agent-cli-update = lib.mkIf cfg.cliUpdates.enable {
      Unit.Description = "Daily npm-global agent CLI update";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = cfg.cliUpdates.onCalendar;
        # A run missed while the host was down happens at the next boot.
        Persistent = true;
        Unit = "agent-cli-update.service";
      };
    };
  };
}
