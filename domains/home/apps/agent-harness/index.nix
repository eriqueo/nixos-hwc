{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:
let
  cfg = config.hwc.home.apps.agent-harness;
  home = config.home.homeDirectory;
  harness = inputs.agent-harness;
  revision = inputs.agent-harness.rev or "dirty";
  # The Workbench area registry lives in the system config (hwc.business.workbench);
  # null when the host has no workbench, so the tracker shows no switcher there.
  workbenchSite =
    if lib.attrByPath [ "hwc" "business" "workbench" "enable" ] false osConfig
    then lib.attrByPath [ "hwc" "business" "workbench" "site" ] null osConfig
    else null;
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
  # claimcheck validates against JSON schemas, so its interpreter carries
  # jsonschema. The commit gate runs claimcheck's suite, so it uses the same one.
  harnessPython = pkgs.python3.withPackages (p: [
    p.jsonschema
    p.pyyaml
  ]);
  # The verifier claimcheck-artifact-gate.sh calls, from the pinned revision.
  # Until 2026-10-11 the only wrapper sat behind claude-code's shareConfig,
  # which no host enables, so the gate fell back to a bare python3 without
  # jsonschema and blocked every textual Artifact with DEPENDENCY-MISSING.
  claimcheck = pkgs.writeShellScriptBin "claimcheck" ''
    exec ${harnessPython}/bin/python3 ${harness}/claimcheck/bin/claimcheck "$@"
  '';
  policyHook = pkgs.writeShellScriptBin "pre-commit" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
        pkgs.ripgrep
        harnessPython
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
      # publish runs the live hook tier, which includes claimcheck's suite.
      harnessPython
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
      curl
    ]);
    text = ''
      export AGENT_HARNESS_SKILL_SET=${agentSkills}
      export AGENT_HARNESS_SKILL_ROOTS=${lib.escapeShellArg (lib.concatMapStringsSep ":" (r: "${home}/${r}") skillRoots)}
      export AGENT_HARNESS_NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
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

  # The one skill set every runtime loads: Claude (~/.claude/skills and each
  # claudeConfigDirs root), Codex (~/.agents/skills) and Pi (skillPaths). Before
  # this, Codex got two hand allowlists plus hand copies that went stale, and
  # third-party skills sat in one runtime on two hosts.
  #
  # Only top-level directories with a SKILL.md are skills. skills/synced/ is
  # Claude Code's claude.ai sync, committed by mistake; Codex and Pi recursed into
  # it and loaded a second, older copy of 25 skills.
  #
  # Copied, not linked per entry: one real tree reads the same to every runtime's
  # discovery. A name taken by both sources fails the build.
  agentSkills = pkgs.runCommand "agent-skills" { nativeBuildInputs = [ harnessPython ]; } ''
    mkdir "$out"
    for dir in ${harness}/skills/*/; do
      name=$(basename "$dir")
      [ -f "$dir/SKILL.md" ] || continue
      cp -R --no-preserve=mode "$dir" "$out/$name"
    done
    for name in ${lib.escapeShellArgs cfg.adoptedSkills}; do
      src=${inputs.cloudflare-skills}/skills/$name
      if [ ! -f "$src/SKILL.md" ]; then
        echo "agent-skills: adopted skill '$name' has no SKILL.md in cloudflare/skills" >&2
        exit 1
      fi
      if [ -e "$out/$name" ]; then
        echo "agent-skills: adopted skill '$name' collides with a harness skill; drop it from adoptedSkills" >&2
        exit 1
      fi
      cp -R --no-preserve=mode "$src" "$out/$name"
    done
    ${lib.concatStrings (
      lib.mapAttrsToList (name: src: ''
        if [ ! -f ${src}/SKILL.md ]; then
          echo "agent-skills: extra skill '${name}' has no SKILL.md at ${src}" >&2
          exit 1
        fi
        if [ -e "$out/${name}" ]; then
          echo "agent-skills: extra skill '${name}' collides with a harness or adopted skill" >&2
          exit 1
        fi
        cp -R --no-preserve=mode ${src} "$out/${name}"
      '') cfg.extraSkills
    )}
    python3 ${harness}/bin/skill-curation-check --root ${harness} --packaged "$out" \
      ${lib.optionalString (!(cfg.extraSkills ? reverse-engineer-anything)) "--without-skill reverse-engineer-anything"}
  '';
  skillRoots = map (dir: "${dir}/skills") ([ ".claude" ] ++ cfg.claudeConfigDirs) ++ [ ".agents/skills" ];

  # How tracker/t3.py reaches T3 Code: its CLI issues short bearer sessions
  # from T3's own state dir, so no token is stored. Used on each host by
  # tracker-link and tracker-relay, never by the hub.
  t3Env = {
    T3CODE_NODE = "${pkgs.nodejs}/bin/node";
    T3CODE_BIN = "${lib.attrByPath [ "hwc" "home" "apps" "t3code" "repo" ] "${home}/600_apps/t3code" config}/apps/server/dist/bin.mjs";
  };

  # The agent-workspace allocator. Its code is static policy (claude-config
  # bin/ws); the dependencies are declared here so it also runs from the
  # state-sync unit, whose PATH is systemd's alone.
  # Only inspection is elevated. Existing sudo authority is required; no new
  # sudoers grant is installed. -I excludes caller-controlled Python imports.
  wsPreservation = pkgs.writeShellScript "ws-preservation" ''
    exec /run/wrappers/bin/sudo -n -- ${pkgs.python3}/bin/python3 -I ${harness}/tracker/preservation.py --sudo "$@"
  '';
  ws = pkgs.writeShellApplication {
    name = "ws";
    runtimeInputs = with pkgs; [
      git
      jq
      ripgrep
      coreutils
      findutils
      gawk
      util-linux
      python3
      bash
      systemd
    ];
    text = ''
      export WS_ROOT=${lib.escapeShellArg cfg.workspaceRoot}
      export WS_PRESERVATION_HELPER=${wsPreservation}
      exec ${pkgs.bash}/bin/bash ${harness}/bin/ws "$@"
    '';
  };

  # Keep ws's own store path outside this JSON to avoid a derivation cycle.
  # The relay binds the two immutable ports at its composition root.
  closeRuntime = pkgs.writeText "tracker-close-runtime.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit revision;
    workspaceRoot = cfg.workspaceRoot;
    brainRoot = cfg.tracker.lifecycle.close.brainRoot;
    profile = cfg.tracker.lifecycle.close.profile;
  });

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
      default = "${cfg.workspaceRoot}/state";
      defaultText = lib.literalExpression ''"''${workspaceRoot}/state"'';
      description = "The agent-state git clone: memories, MISTAKES.md, ledger/ and guard/.";
    };
    stateHub = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/eric/git/agent-state.git";
      description = ''
        The bare agent-state hub, set only on the host that holds it. Its
        pre-receive hook (pinned through hwc.home.core.repoHooks) refuses any
        push whose tip fails agent-state-validate, so a hand push cannot land
        state that would block every host. Emergency bypass on that host:
        git -C <hub> config --unset core.hooksPath (the next activation re-pins).
      '';
    };
    workspaceRoot = lib.mkOption {
      type = lib.types.str;
      default = osConfig.hwc.paths.user.agents or "${home}/800_agents";
      defaultText = lib.literalExpression ''osConfig.hwc.paths.user.agents or "''${home}/800_agents"'';
      description = ''
        Agent workspace root: projects/, closed/, state/ (the agent-state
        clone), log/ and LEDGER.md. Local to each host and never a Syncthing
        folder; the system module asserts that.
      '';
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
        "hwc-home"
        "hwc-laptop"
        "hwc-work"
      ];
    };
    notifyUrl = lib.mkOption {
      type = lib.types.str;
      # Derived from the system's hwc.notifications.notify.url (the one
      # producer); the literal is only the standalone-HM fallback.
      default = "${
        lib.attrByPath [ "hwc" "notifications" "notify" "url" ] "https://hwc-work.ocelot-wahoo.ts.net:29443" osConfig
      }/notify";
      description = "hwc-notify endpoint used for state-sync failure and recovery transitions";
    };
    tracker = {
      enable = lib.mkEnableOption ''
        the project tracker hub (claude-config tracker/server.py): every agent
        project's roadmap, plan and Eric's decision cards, on one tailnet page.
        Run it on ONE host; project data syncs through the deliverables folder'';
      lifecycle = {
        intakeEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Accept explicit Review requests after backup, native isolation and result/stop acceptance.";
        };
        dispatchEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow new lifecycle worker/helper starts and prepared effects; existing requests remain inspectable when disabled.";
        };
        close = {
          enable = lib.mkEnableOption "canonical Close after ordinary native, owning cleanup and shutdown acceptance";
          brainRoot = lib.mkOption {
            type = lib.types.str;
            default = toString (lib.findFirst (p: p != null) "${home}/900_vaults/brain" [
              (lib.attrByPath [ "hwc" "paths" "brain" "vault" ] null osConfig)
              (lib.attrByPath [ "hwc" "paths" "brain" "server-replica" ] null osConfig)
            ]);
            description = "Existing brain vault used for the verified Close outcome note.";
          };
          profile = {
            instanceId = lib.mkOption {
              type = lib.types.str;
              default = "codex";
              description = "Explicit ordinary T3 provider instance; never the reserved reviewer.";
            };
            model = lib.mkOption {
              type = lib.types.str;
              default = "gpt-6.1-sol";
              description = "Ordinary model used for the bounded Close assessment.";
            };
          };
        };
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8765;
        description = "Listening port (tailnet-only: the host firewall trusts tailscale0).";
      };
      root = lib.mkOption {
        type = lib.types.str;
        default = "${home}/000_inbox/downloads/agent";
        description = "Deliverables root scanned for <project>/tracker.json.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://hwc-work:8765";
        description = "The hub as every host's tracker-relay reaches it (tailnet).";
      };
      refineryUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString (lib.attrByPath [ "hwc" "automation" "refinery" "port" ] 8060 osConfig)}";
        defaultText = lib.literalExpression ''"http://127.0.0.1:''${osConfig.hwc.automation.refinery.port or 8060}"'';
        description = ''
          The Refinery board as the hub reaches it. The Refinery is the one store of
          work items; the hub's Backlog tab proxies GET /api/items?project=<id> from
          here with a short timeout, so a slow board never holds the single-threaded hub.'';
      };
      refineryPublicUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://refinery.hwc.iheartwoodcraft.com";
        description = "The Refinery board as Eric's browser reaches it: item links and the add-to-backlog form.";
      };
    };
    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".claude_dx2_home" ];
    };
    adoptedSkills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # C5 removed the old global adoption set. Retained domain workflows live
      # in the pinned harness's explicit project packs; they are not discovery roots.
      default = [ ];
      description = ''
        Skills from the cloudflare-skills flake input added to the shared skill
        set. The curated inventory check rejects unapproved discovery entries.
      '';
    };
    extraSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Skills other home modules add to the one skill set: name → directory
        holding SKILL.md (a store path, so the set stays one fingerprint across
        hosts). A name already taken fails the build. `rg extraSkills domains`
        lists the producers (rea).
      '';
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
    hwc.home.core.repoHooks.repos = lib.mkIf (cfg.stateHub != null) [ {
      path = cfg.stateHub;
      dispatched = [ ];
      pinned.pre-receive = pkgs.writeShellScript "agent-state-hub-pre-receive" ''
        exec ${stateValidator}/bin/agent-state-validate pre-receive
      '';
    } ];

    home.packages = [
      cli
      doctor
      ws
      stateSync
      stateValidator
      (pkgs.writeShellScriptBin "log-mistake" ''exec ${pkgs.python3}/bin/python3 ${harness}/bin/log-mistake "$@"'')
      claimcheck
      # Fire counts per blocking guard from hooks/lib/fire-log.sh; names the
      # guards with no fire in the window (the removal budget).
      (pkgs.writeShellApplication {
        name = "guard-audit";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          jq
          openssh
        ];
        text = ''exec ${pkgs.bash}/bin/bash ${harness}/bin/guard-audit "$@"'';
      })
      # Blocks until Eric presses "Done deciding" on the tracker hub, then prints
      # the next prompt; the fallback for agents outside T3 Code.
      (pkgs.writeShellScriptBin "tracker-wait" ''exec ${pkgs.python3}/bin/python3 ${harness}/tracker/wait.py "$@"'')
      # Binds the calling T3 thread to a tracker project, so "Done deciding"
      # posts the next prompt into that thread.
      (pkgs.writeShellScriptBin "tracker-link" ''
        export ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") t3Env)}
        exec ${pkgs.python3}/bin/python3 ${harness}/tracker/t3.py "$@"
      '')
      # Stamps a project's live handoff (agent/<project>/handoff.md) with the
      # writer and each checkout's HEAD, which the hub checks against the ledgers.
      (pkgs.writeShellScriptBin "tracker-handoff" ''
        export TRACKER_ROOT=${lib.escapeShellArg cfg.tracker.root} WS_ROOT=${lib.escapeShellArg cfg.workspaceRoot} TRACKER_WS_BIN=${ws}/bin/ws
        exec ${pkgs.python3}/bin/python3 ${harness}/tracker/handoff_doc.py "$@"
      '')
    ]
    ++ lib.optional cfg.cliUpdates.enable cliUpdater;

    home.file = lib.mkMerge (
      [ (lib.genAttrs skillRoots (_: { source = agentSkills; })) ]
      ++ map (dir: {
        "${dir}/agents".source = harness + "/agents";
        "${dir}/commands".source = harness + "/commands";
        "${dir}/CLAUDE.md".source = harness + "/CLAUDE.md";
        "${dir}/standing-instructions.md".source = harness + "/standing-instructions.md";
        "${dir}/engineering-principles.md".source = harness + "/engineering-principles.md";
      }) ([ ".claude" ] ++ cfg.claudeConfigDirs)
    );

    # The S2 one-time move of the state clone into the workspace root ran on all
    # three hosts and was deleted in S8 (2026-10-01).
    # Home Manager will not replace a directory it does not own with the
    # skill-set link, and Codex keeps loading whatever sits in ~/.codex/skills.
    # So hand-made skill dirs move to a timestamped backup first; nothing is
    # deleted. Dot entries stay: ~/.codex/skills/.system is Codex's own,
    # rewritten at its startup. A second run finds nothing to move.
    home.activation.agentSkillsMigrate = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      _skBak="${home}/.local/state/agent-harness/pre-skillset-$(date +%Y%m%dT%H%M%S)"
      _skMove() {
        run mkdir -p "$_skBak/$2"
        run mv "$1" "$_skBak/$2/"
        echo "agent-harness: moved $1 to $_skBak/$2/"
      }
      if [ -d "${home}/.agents/skills" ] && [ ! -L "${home}/.agents/skills" ]; then
        _skMove "${home}/.agents/skills" agents
      fi
      if [ -d "${home}/.codex/skills" ] && [ ! -L "${home}/.codex/skills" ]; then
        for _sk in "${home}/.codex/skills"/*; do
          [ -e "$_sk" ] || [ -L "$_sk" ] || continue
          _skMove "$_sk" codex-skills
        done
      fi
    '';

    home.activation.agentWorkspace = lib.hm.dag.entryBefore [ "agentHarnessMemoryLinks" ] ''
      root=${lib.escapeShellArg cfg.workspaceRoot}
      run mkdir -p "$root/projects" "$root/closed" "$root/log"
    '';

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
        # Re-render ~/800_agents/LEDGER.md from the ledgers just pulled, so each
        # host shows the others' projects within one sync interval. A render
        # failure never fails the sync.
        ExecStartPost = "-${ws}/bin/ws ledger --write";
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

    # Hourly per-host audit (agent-workspace S8): writes this host's ledger,
    # renders LEDGER.md, expires closed/ folders past 30 days and logs findings
    # to the journal. About 3-4 s per run, measured on all three hosts.
    systemd.user.services.ws-audit = {
      Unit.Description = "Agent workspace audit (ledger, closed/ expiry, findings)";
      Service = {
        Type = "oneshot";
        ExecStart = "${ws}/bin/ws audit";
      };
    };
    systemd.user.timers.ws-audit = {
      Unit.Description = "Hourly agent workspace audit";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # Hourly skill and harness drift check; alerts once per change of the
    # doctor's FAIL lines. Exits non-zero while drift lasts, so it shows in
    # `systemctl --user --failed` too.
    systemd.user.services.agent-harness-drift = {
      Unit.Description = "Agent harness drift check (skill roots, hand installs, hooks)";
      Service = {
        Type = "oneshot";
        ExecStart = "${cli}/bin/agent-harness drift";
      };
    };
    systemd.user.timers.agent-harness-drift = {
      Unit.Description = "Hourly agent harness drift check";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # Tracker data is not state of this unit: tracker.json (agents) and
    # decisions.json / next-prompt.md (this server) live in each project's
    # synced deliverables folder, so no StateDirectory or retention timer.
    systemd.user.services.hwc-tracker = lib.mkIf cfg.tracker.enable {
      Unit = {
        Description = "HWC project tracker hub (roadmaps, plans, decision cards)";
        After = [ "network-online.target" ];
        # The server and page are pinned harness files; a new revision restarts it.
        X-Restart-Triggers = map (f: "${harness}/tracker/${f}") [ "server.py" "index.html" "handoff_doc.py" "lifecycle.py" "close-contract.json" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${harness}/tracker/server.py ${toString cfg.tracker.port}";
        # No T3 environment: the hub only queues pings; each host's
        # tracker-relay posts them into its own T3.
        # TRACKER_LEDGERS: every host's ws ledger, for the handoff coverage check.
        Environment = [
          "TRACKER_ROOT=${cfg.tracker.root}"
          "TRACKER_LEDGERS=${cfg.stateDir}/ledger"
          "TRACKER_LIFECYCLE_INTAKE=${if cfg.tracker.lifecycle.intakeEnabled then "1" else "0"}"
          "TRACKER_LIFECYCLE_DISPATCH=${if cfg.tracker.lifecycle.dispatchEnabled then "1" else "0"}"
          "TRACKER_CLOSE_ENABLED=${if cfg.tracker.lifecycle.close.enable then "1" else "0"}"
          # The Backlog tab's read model lives on the Refinery board (one store of work items).
          "TRACKER_REFINERY_URL=${cfg.tracker.refineryUrl}"
          "TRACKER_REFINERY_PUBLIC_URL=${cfg.tracker.refineryPublicUrl}"
        ] ++ lib.optional (workbenchSite != null)
          # Workbench area switcher: the page renders the Nix-produced registry
          # (hwc.business.workbench, the one producer of the area list) from the
          # hub's own areas.json. Absent → the switcher is not shown.
          "TRACKER_WORKBENCH_AREAS_FILE=${workbenchSite}/areas.json";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Every host: posts the hub's pings for this host's T3 threads into the
    # local T3 and reports back (tracker/relay.py). Polls every 5 s; while the
    # host sleeps, the page shows the ping as "not answering" and it is
    # delivered on wake. A T3 that is not running is reported as a failure.
    systemd.user.services.tracker-relay = {
      Unit = {
        Description = "Deliver tracker pings into this host's T3 threads";
        After = [ "network-online.target" ];
        # relay.py imports handoff_doc; a change there must restart the relay too.
        X-Restart-Triggers = map (f: "${harness}/tracker/${f}") [ "relay.py" "t3.py" "handoff_doc.py" "lifecycle.py" "closeout.py" "close-contract.json" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${harness}/tracker/relay.py";
        Environment = [
          "TRACKER_URL=${cfg.tracker.url}"
          "TRACKER_WS_BIN=${ws}/bin/ws"
          "TRACKER_LOCAL_LEDGER=${cfg.stateDir}/ledger/%H.json"
          "PATH=${lib.makeBinPath [ pkgs.systemd pkgs.git pkgs.coreutils ]}:/run/current-system/sw/bin"
        ] ++ lib.mapAttrsToList (k: v: "${k}=${v}") t3Env
          ++ lib.optional cfg.tracker.lifecycle.close.enable "TRACKER_CLOSE_RUNTIME=${closeRuntime}";
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
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
