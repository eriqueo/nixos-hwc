# domains/home/apps/claude-code/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
  claimcheckPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.jsonschema ]);
  claimcheckPackage = pkgs.writeShellApplication {
    name = "claimcheck";
    text = ''
      exec ${claimcheckPython}/bin/python3 \
        "${cfg.shareConfig.repoPath}/claimcheck/bin/claimcheck" "$@"
    '';
  };

  # Every Claude config dir that receives the shared items and memory links.
  configDirs = map (dir: "${config.home.homeDirectory}/${dir}")
    ([ ".claude" ] ++ cfg.shareConfig.extraConfigDirs);

  postMergeScript = pkgs.writeShellScript "claude-config-post-merge" ''
    rc=0
    ${lib.concatMapStringsSep "\n" (cmd: "${cmd} || rc=1") cfg.shareConfig.sync.postMerge}
    exit $rc
  '';

  # Two-way sync + memory link layer. The logic is config-sync.sh, beside this
  # file, so config-sync.test.sh exercises the same bytes the unit runs.
  configSync = pkgs.writeShellApplication {
    name = "claude-config-sync";
    runtimeInputs = with pkgs; [ git coreutils util-linux gawk findutils diffutils openssh ];
    text = ''
      CC_HOST="$(uname -n)"
      export CC_HOST
      export CC_REPO=${lib.escapeShellArg cfg.shareConfig.repoPath}
      export CC_CONFIG_DIRS=${lib.escapeShellArg (lib.concatStringsSep ":" configDirs)}
      export CC_POST_MERGE=${postMergeScript}
      exec ${pkgs.bash}/bin/bash ${./config-sync.sh} "$@"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI (Nix package + Obsidian MCP cert)";

    # Shared, version-controlled skill/agent/command/CLAUDE.md/engineering-principles set. Lives in a
    # standalone git repo (NOT ~/.nixos — branch switches there would vaporize
    # the symlink targets mid-session). Symlinked live so edits are immediate
    # and identical across every host.
    #
    # Deliberately INDEPENDENT of `enable`: hwc-server runs claude from an
    # ad-hoc npm global and must NOT get the Nix package or the laptop-only
    # Obsidian cert var (the cert file does not exist there). It opts into the
    # shared config alone via shareConfig.enable.
    shareConfig = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Symlink ~/.claude/{skills,agents,commands,CLAUDE.md,engineering-principles} from the shared claude-config git repo. Defaults to the package enable, but can be turned on standalone (e.g. hwc-server).";
      };
      repoPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.claude-config";
        description = "Working-tree path of the shared claude-config git repo (mkOutOfStoreSymlink target).";
      };
      items = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "skills"
          "agents"
          "commands"
          "CLAUDE.md"
          "engineering-principles.md"
          # Individual files, not the hooks/ dir — ~/.claude/hooks also holds
          # host-local hooks (herdr-agent-state.sh) that must stay unmanaged.
          "hooks/principles-primer.sh"
          "hooks/principles-gate.sh"
          "hooks/principles-lint.sh"
          # settings.json is shared too (2026-09-16). It carried the autoMode
          # block, guard-wrapped hook commands and model prefs on the laptop
          # while the server ran a three-week-old copy — the heal below only
          # ADDS wiring, so nothing converged the rest. Claude Code writes
          # through a symlink (measured with `claude plugin enable` against a
          # symlinked CLAUDE_CONFIG_DIR: link intact, target updated), so the
          # live file on every host is the repo file. settings.local.json
          # stays host-local for per-machine permission allowlists.
          "settings.json"
        ];
        description = "Entries under repoPath to symlink into ~/.claude/ (nested paths symlink single files).";
      };
      # Extra Claude config directories that get the same `items` and memory
      # links. T3 Code runs its DX2 provider instance with CLAUDE_CONFIG_DIR set
      # to its own homePath (~/.claude_dx2_home), and Claude Code reads skills,
      # CLAUDE.md, hooks, settings and memories ONLY from that directory. Found
      # empty on hwc-server 2026-09-17. Credentials, sessions and .claude.json
      # stay per-directory.
      extraConfigDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ ".claude_dx2_home" ];
        description = "Home-relative Claude config directories (CLAUDE_CONFIG_DIR targets) that receive the same shareConfig.items symlinks and memory links as ~/.claude.";
      };
      # Two-way sync replaces the 2026-07 pull-only timer. Pull-only kept
      # hand edits safe but left every host-written fact stranded: on
      # 2026-09-16 the laptop was 8 commits ahead with 12 dirty files and the
      # server held MISTAKES.md entries and memories nobody else could see.
      # The unit commits ONLY data paths (MISTAKES.md, projects/*/memory),
      # merges without autostash so git refuses to touch a dirty hand edit,
      # and pushes. Hand edits stay the author's to commit.
      sync = {
        enable = lib.mkOption {
          type = lib.types.bool;
          # Every host that shares the repo also writes to it; a sharing host
          # without sync is the stranded-facts state this replaced.
          default = cfg.shareConfig.enable;
          description = "Run a systemd --user timer that links per-project memories into the repo, commits memories and MISTAKES.md, merges the hub, and pushes.";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "5min";
          description = "systemd OnUnitActiveSec cadence for the sync timer.";
        };
        postMerge = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands run after a merge changed the tree (e.g. regenerate derived Codex files). A failure is logged, never fatal.";
        };
      };
      wireGateHooks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Self-heal every gate-hook entry (enforce-tools, premortem-gate,
          claimcheck Artifact publication, track-evidence ×2, optional
          claim-guard, nixos-primer, path-conventions, charter-gate,
          standing-instructions ×2, ste100-guard ×2, memory-staleness) and the
          skill-description char budget into
          ~/.claude/settings.json at every activation. Append-only jq
          merge keyed on script filename: existing entries, permissions, and
          runtime-written keys (model, etc.) are never edited or removed, so
          Claude Code's own writes to the file survive. principles-lint.sh
          Check 4 independently verifies five of those wiring points at each
          session's first code edit. Inert unless shareConfig.enable.
        '';
      };

      # PER-HOOK ARMING. Before this option existed, a hook could not be
      # disarmed anywhere durable. The heal is append-only, so deleting an entry
      # from ~/.claude/settings.json only survived until the next activation put
      # it back — measured 2026-08-25: claim-guard was deliberately unwired on
      # 2026-08-23, three documents and the script's own header recorded the
      # disarm, and Home Manager had silently re-armed it (harness-live-state.md
      # D1). Correct matching alone does not fix that; it only makes the heal
      # re-append the RIGHT thing.
      #
      # Setting a flag false does NOT delete a live entry. It stops the heal
      # restoring one, so a hand-deletion finally sticks. Deleting the entry
      # stays a separate, deliberate act.
      #
      # claimGuard defaults false after Eric explicitly disarmed it on
      # 2026-08-28. Its 2026-08-23 measurement found 19 blocks in 60 transcripts
      # and zero measured true positives; Home Manager had silently re-armed it.
      # The other flags retain the live defaults measured on 2026-08-25.
      gateHooks = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = {
          enforceTools = true;
          premortemGate = true;
          claimcheckArtifact = true;
          trackEvidence = true;
          turnStamp = true;
          claimGuard = false;
          nixosPrimer = true;
          pathConventions = true;
          charterGate = true;
          standingInject = true;
          standingSync = true;
          ste100Guard = true;
          memoryStaleness = true;
        };
        description = "Per-hook arming for the settings.json heal. False stops the heal restoring that entry; it never removes a live one. claimGuard defaults false by explicit decision; claimcheckArtifact was added from the measured 2026-08-29 publication failure; other defaults match the state measured live on 2026-08-25.";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    # Package + Obsidian MCP cert — laptop-class hosts only (cfg.enable).
    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.claude-code ];

      # Trust the self-signed cert from the Obsidian Local REST API plugin
      # so Claude Code's HTTP MCP transport can connect without validation errors.
      # Cert source: https://127.0.0.1:27124/obsidian-local-rest-api.crt
      home.sessionVariables.NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.claude/certs/obsidian-local-rest-api.crt";
    })

    # Live symlinks from the shared config repo into ~/.claude/. Independent of
    # the package so headless hosts can share skills without the Nix binary.
    (lib.mkIf cfg.shareConfig.enable {
      # claimcheck's JSON schemas are executable policy, not documentation.
      # Own the validator runtime here so a host cannot appear wired while its
      # Artifact hook blocks every report on an undeclared Python dependency.
      home.packages = [ claimcheckPackage ];
      home.file = lib.listToAttrs (lib.concatMap (dir:
        map (item:
          lib.nameValuePair "${dir}/${item}" {
            source = config.lib.file.mkOutOfStoreSymlink "${cfg.shareConfig.repoPath}/${item}";
          }) cfg.shareConfig.items
      ) ([ ".claude" ] ++ cfg.shareConfig.extraConfigDirs));
    })

    # Memory links on every activation, so a host is linked before its first
    # timer run. Non-fatal: a missing clone must not fail the generation.
    (lib.mkIf cfg.shareConfig.enable {
      home.packages = [ configSync ];
      home.activation.claudeMemoryLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${configSync}/bin/claude-config-sync link \
          || echo "claude-code: memory link layer failed — see claude-config-sync link" >&2
      '';
    })

    # Two-way sync of the shared repo. A failure leaves the unit failed, which is
    # the signal: `systemctl --user status claude-config-sync`.
    (lib.mkIf (cfg.shareConfig.enable && cfg.shareConfig.sync.enable) {
      systemd.user.services.claude-config-sync = {
        Unit.Description = "Two-way sync of the shared claude-config repo (memories, mistakes ledger)";
        Service = {
          Type = "oneshot";
          ExecStart = "${configSync}/bin/claude-config-sync sync";
        };
      };
      systemd.user.timers.claude-config-sync = {
        Unit.Description = "Periodic two-way sync of the shared claude-config repo";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.shareConfig.sync.interval;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })

    # Self-heal the enforcement wiring into ~/.claude/settings.json. The gate
    # SCRIPTS sync everywhere via the repo pull timer, but settings.json is
    # host-local mutable state that Claude Code itself rewrites at runtime —
    # found scripts-present-but-unwired on hwc-server 2026-08-02. Append-only
    # and idempotent: entries are matched by script filename, added when
    # missing, never edited or removed; a pre-heal backup is kept. Claude Code
    # stays the primary writer of the file (runtime prefs); this merge only
    # converges the wiring, so a concurrent write settles at next activation.
    (lib.mkIf (cfg.shareConfig.enable && cfg.shareConfig.wireGateHooks) (
      let
        # THE `bash -n` WRAPPER IS PART OF THE COMMAND, not decoration.
        # enforce-tools.sh fails CLOSED and matches Bash|Edit|Write, so an
        # unclosed `if` in a hook blocks the very tools needed to repair it. That
        # class bricked this laptop twice inside one hour on 2026-08-23 and Eric
        # had to run the fix by hand (MISTAKES.md:361). The wrapper makes a
        # syntax error cost ENFORCEMENT instead of every tool on the machine.
        #
        # 21 of the 24 entries in settings.json already carried this wrapper. The
        # three that did not — claim-guard and the two standing-instructions
        # duplicates — are exactly the three the heal itself wrote, because
        # hookCmd emitted a bare command. Emitting the wrapper here closes that
        # gap at the producer.
        hookCmd = name:
          let p = "${cfg.shareConfig.repoPath}/hooks/${name}";
          in "bash -n '${p}' 2>/dev/null && bash '${p}'";
        # Arguments sit between the command and the `|| exit 0` tail, matching the
        # shape of the wrapped entries already in settings.json.
        hookCmdArgs = name: args: "${hookCmd name} ${args} || exit 0";
        hookCmd' = name: "${hookCmd name} || exit 0";
        wireFile = pkgs.writeText "claude-gate-hook-wiring.json" (builtins.toJSON {
          enforceTools = {
            matcher = "Bash|Edit|Write";
            hooks = [ { type = "command"; command = hookCmd' "enforce-tools.sh"; timeout = 10; statusMessage = "Tool policy"; } ];
          };
          premortemGate = {
            matcher = "ExitPlanMode";
            hooks = [ { type = "command"; command = hookCmd' "premortem-gate.sh"; timeout = 10; statusMessage = "Premortem gate"; } ];
          };
          # Textual Artifact publication is the measured decision point the
          # notification audit crossed. The hook replays two SQLite-only plans
          # and recompiles the bytes before allowing publication. Images stay
          # outside this claim-provenance control.
          claimcheckArtifact = {
            matcher = "Artifact";
            hooks = [ { type = "command"; command = hookCmd' "claimcheck-artifact-gate.sh"; timeout = 30; statusMessage = "Claim provenance"; } ];
          };
          trackEvidence = {
            matcher = "Grep|Glob|Bash";
            hooks = [ { type = "command"; command = hookCmd' "track-evidence.sh"; timeout = 10; } ];
          };
          turnStamp = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmdArgs "track-evidence.sh" "turn"; timeout = 10; } ];
          };
          claimGuard = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmd' "claim-guard.sh"; timeout = 15; statusMessage = "Claim guard"; } ];
          };
          # Charter primer. Fires on the EDIT (path-derived: the file sits in a
          # repo with CHARTER.md + flake.nix at its root), never on the agent's
          # judgement that the work is "architectural" — Charter §0.12. Injects
          # the live `ls domains/` map, so no hand-written repo map can drift.
          nixosPrimer = {
            matcher = "Write|Edit";
            hooks = [ { type = "command"; command = hookCmd' "nixos-primer.sh"; timeout = 10; statusMessage = "Charter primer"; } ];
          };
          # Conventions whose trigger is the WRITE PATH (agent-output inbox,
          # brain vault, SKILL.md). Prose in CLAUDE.md that never needed a
          # judgement call to fire — only a look at the destination.
          pathConventions = {
            matcher = "Write|Edit";
            hooks = [ { type = "command"; command = hookCmd' "path-conventions.sh"; timeout = 10; statusMessage = "Path conventions"; } ];
          };
          # Charter rules checked at the moment of action: domain README staged
          # with its domain (Law 12), and `hms` against a system-or-mixed tree.
          # Both COMPUTE the violation and stay silent when there is none.
          charterGate = {
            matcher = "Bash|mcp__git__git_commit";
            hooks = [ { type = "command"; command = hookCmd' "charter-gate.sh"; timeout = 15; statusMessage = "Charter gate"; } ];
          };
          # Standing instructions: PREVENTION. A rule that binds every response
          # has no triggering task, so the memory index's pointer is never
          # opened — measured 2026-08-22, 42 of 53 sessions since the rule was
          # written never named its file. `inject` puts the rule TEXT in the
          # turn; `sync` regenerates the block in CLAUDE.md, which is the only
          # surface a SUBAGENT loads. Both are needed: sync alone cannot reach
          # the session already running.
          standingInject = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmdArgs "standing-instructions.sh" "inject"; timeout = 10; statusMessage = "Standing instructions"; } ];
          };
          standingSync = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmdArgs "standing-instructions.sh" "sync"; timeout = 10; } ];
          };
          # Standing instructions: ENFORCEMENT. Checks the one arithmetic rule
          # in ASD-STE100 (sentence length), never vocabulary — a guard that
          # fires on judgment calls is wallpaper. Wired on BOTH Stop and
          # SubagentStop; SubagentStop is what makes this reach a subagent at
          # all. The guard asks the memory whether the rule is live, so
          # unmarking the memory silences it without touching this file.
          ste100Guard = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmd' "ste100-guard.sh"; timeout = 15; statusMessage = "Standing instruction"; } ];
          };
          # Memory decay: a memory is not wrong when it is written, it goes wrong
          # afterwards. memory-lint.sh guards the WRITE; nothing guarded the READ.
          # Measured 2026-08-25 on the DataX store: 29 of 32 cited commit SHAs had
          # reached upstream/prod, so every "merged, deploy owed" sentence had become
          # an instruction to skip owed work. This re-tests the store against the
          # FETCHED upstream ref at session start and prints only what git refutes.
          # Silent when nothing is refuted, and silent in any repo with no upstream
          # remote — a fork's idea of prod is never treated as the truth.
          memoryStaleness = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmd' "memory-staleness.sh"; timeout = 25; statusMessage = "Memory staleness"; } ];
          };
        });
        # The filter lives in its own file so `settings-heal.test.sh` runs the
        # SAME BYTES the activation runs. Embedded in this Nix string it could
        # not be exercised without a rebuild, and a copy inside the test would be
        # a second producer of the same logic — the defect class this repo calls
        # vacuous-check. Ruled out keeping it here for exactly that reason;
        # README.md is the only other file in this directory and is prose.
        healJq = pkgs.writeText "claude-settings-heal.jq" (builtins.readFile ./settings-heal.jq);
        enableFile = pkgs.writeText "claude-gate-hook-enable.json"
          (builtins.toJSON cfg.shareConfig.gateHooks);
        emptyJson = pkgs.writeText "claude-settings-empty.json" "{}";
      in {
        home.activation.claudeGateHookWiring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          _s="${config.home.homeDirectory}/.claude/settings.json"
          _src="$_s"; [ -f "$_s" ] || _src=${emptyJson}
          _tmp=$(${pkgs.coreutils}/bin/mktemp "$_s.heal.XXXXXX" 2>/dev/null) || _tmp=""
          if [ -n "$_tmp" ] && ${pkgs.jq}/bin/jq --slurpfile wire ${wireFile} --slurpfile enable ${enableFile} -f ${healJq} "$_src" > "$_tmp" 2>/dev/null; then
            if ! ${pkgs.diffutils}/bin/cmp -s "$_tmp" "$_s" 2>/dev/null; then
              [ -f "$_s" ] && run ${pkgs.coreutils}/bin/cp "$_s" "$_s.pre-heal.bak"
              # cp, not mv: settings.json is a symlink into the shared repo
              # (shareConfig.items) and mv would replace the link with a
              # host-local regular file — the drift this share exists to end.
              run ${pkgs.coreutils}/bin/cp "$_tmp" "$_s"
              echo "claude-code: gate-hook wiring healed into $_s (backup: $_s.pre-heal.bak)"
            fi
          else
            echo "claude-code: $_s is not valid JSON — wiring NOT healed, fix it by hand" >&2
          fi
          ${pkgs.coreutils}/bin/rm -f "$_s".heal.* 2>/dev/null || true
        '';
      }
    ))

    #========================================================================
    # VALIDATION
    #========================================================================
    {
      assertions = [
        {
          assertion = cfg.shareConfig.enable -> (cfg.shareConfig.items != [ ]);
          message = "hwc.home.apps.claude-code.shareConfig.items must list at least one entry when shareConfig is enabled.";
        }
        {
          assertion = cfg.shareConfig.sync.enable -> cfg.shareConfig.enable;
          message = "hwc.home.apps.claude-code.shareConfig.sync requires shareConfig.enable = true.";
        }
      ];
    }
  ];
}
