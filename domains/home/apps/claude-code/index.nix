# domains/home/apps/claude-code/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
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
        ];
        description = "Entries under repoPath to symlink into ~/.claude/ (nested paths symlink single files).";
      };
      autoPull = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Run a systemd --user timer that fast-forward-pulls the config repo so other hosts' commits arrive zero-touch.";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "15min";
          description = "systemd OnUnitActiveSec cadence for the auto-pull timer.";
        };
      };
      wireGateHooks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Self-heal every gate-hook entry (enforce-tools, premortem-gate,
          track-evidence ×2, claim-guard, nixos-primer, path-conventions,
          charter-gate, standing-instructions ×2, ste100-guard ×2,
          memory-staleness) and the skill-description char budget into
          ~/.claude/settings.json at every activation. Append-only jq
          merge keyed on script filename: existing entries, permissions, and
          runtime-written keys (model, etc.) are never edited or removed, so
          Claude Code's own writes to the file survive. principles-lint.sh
          Check 4 independently verifies five of those wiring points at each
          session's first code edit. Inert unless shareConfig.enable.
        '';
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
      home.file = lib.listToAttrs (map (item:
        lib.nameValuePair ".claude/${item}" {
          source = config.lib.file.mkOutOfStoreSymlink "${cfg.shareConfig.repoPath}/${item}";
        }) cfg.shareConfig.items);
    })

    # Optional zero-touch receive: fast-forward-pull the config repo on a timer.
    # Pull-only (never auto-commits/pushes) so a dirty working tree of in-progress
    # skill edits is never clobbered — a non-ff state just makes the unit no-op.
    (lib.mkIf (cfg.shareConfig.enable && cfg.shareConfig.autoPull.enable) {
      systemd.user.services.claude-config-pull = {
        Unit.Description = "Fast-forward-pull the shared claude-config repo";
        Service = {
          Type = "oneshot";
          # Fetch, then fast-forward ONLY when strictly behind. A diverged/ahead
          # or dirty tree is a clean no-op (exit 0) — matching the receive-only
          # intent — instead of `pull --ff-only`'s loud exit-128 every interval.
          ExecStart = pkgs.writeShellScript "claude-config-pull" ''
            set -eu
            ${pkgs.git}/bin/git -C ${cfg.shareConfig.repoPath} fetch --quiet
            ${pkgs.git}/bin/git -C ${cfg.shareConfig.repoPath} merge --ff-only '@{u}' \
              || echo "claude-config: non-ff (diverged/ahead/dirty) — skipping pull"
          '';
        };
      };
      systemd.user.timers.claude-config-pull = {
        Unit.Description = "Periodic pull of the shared claude-config repo";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.shareConfig.autoPull.interval;
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
        hookCmd = name: "bash ${cfg.shareConfig.repoPath}/hooks/${name}";
        wireFile = pkgs.writeText "claude-gate-hook-wiring.json" (builtins.toJSON {
          enforceTools = {
            matcher = "Bash|Edit|Write";
            hooks = [ { type = "command"; command = hookCmd "enforce-tools.sh"; timeout = 10; statusMessage = "Tool policy"; } ];
          };
          premortemGate = {
            matcher = "ExitPlanMode";
            hooks = [ { type = "command"; command = hookCmd "premortem-gate.sh"; timeout = 10; statusMessage = "Premortem gate"; } ];
          };
          trackEvidence = {
            matcher = "Grep|Glob|Bash";
            hooks = [ { type = "command"; command = hookCmd "track-evidence.sh"; timeout = 10; } ];
          };
          turnStamp = {
            matcher = "*";
            hooks = [ { type = "command"; command = "${hookCmd "track-evidence.sh"} turn"; timeout = 10; } ];
          };
          claimGuard = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmd "claim-guard.sh"; timeout = 15; statusMessage = "Claim guard"; } ];
          };
          # Charter primer. Fires on the EDIT (path-derived: the file sits in a
          # repo with CHARTER.md + flake.nix at its root), never on the agent's
          # judgement that the work is "architectural" — Charter §0.12. Injects
          # the live `ls domains/` map, so no hand-written repo map can drift.
          nixosPrimer = {
            matcher = "Write|Edit";
            hooks = [ { type = "command"; command = hookCmd "nixos-primer.sh"; timeout = 10; statusMessage = "Charter primer"; } ];
          };
          # Conventions whose trigger is the WRITE PATH (agent-output inbox,
          # brain vault, SKILL.md). Prose in CLAUDE.md that never needed a
          # judgement call to fire — only a look at the destination.
          pathConventions = {
            matcher = "Write|Edit";
            hooks = [ { type = "command"; command = hookCmd "path-conventions.sh"; timeout = 10; statusMessage = "Path conventions"; } ];
          };
          # Charter rules checked at the moment of action: domain README staged
          # with its domain (Law 12), and `hms` against a system-or-mixed tree.
          # Both COMPUTE the violation and stay silent when there is none.
          charterGate = {
            matcher = "Bash|mcp__git__git_commit";
            hooks = [ { type = "command"; command = hookCmd "charter-gate.sh"; timeout = 15; statusMessage = "Charter gate"; } ];
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
            hooks = [ { type = "command"; command = "${hookCmd "standing-instructions.sh"} inject"; timeout = 10; statusMessage = "Standing instructions"; } ];
          };
          standingSync = {
            matcher = "*";
            hooks = [ { type = "command"; command = "${hookCmd "standing-instructions.sh"} sync"; timeout = 10; } ];
          };
          # Standing instructions: ENFORCEMENT. Checks the one arithmetic rule
          # in ASD-STE100 (sentence length), never vocabulary — a guard that
          # fires on judgment calls is wallpaper. Wired on BOTH Stop and
          # SubagentStop; SubagentStop is what makes this reach a subagent at
          # all. The guard asks the memory whether the rule is live, so
          # unmarking the memory silences it without touching this file.
          ste100Guard = {
            matcher = "*";
            hooks = [ { type = "command"; command = hookCmd "ste100-guard.sh"; timeout = 15; statusMessage = "Standing instruction"; } ];
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
            hooks = [ { type = "command"; command = hookCmd "memory-staleness.sh"; timeout = 25; statusMessage = "Memory staleness"; } ];
          };
        });
        healJq = pkgs.writeText "claude-settings-heal.jq" ''
          def has_cmd($ev; $frag):
            [.hooks[$ev][]?.hooks[]?.command // empty] | map(contains($frag)) | any;
          def ensure($ev; $frag; $entry):
            if has_cmd($ev; $frag) then . else .hooks[$ev] = ((.hooks[$ev] // []) + [$entry]) end;
          $wire[0] as $w
          | ensure("PreToolUse"; "enforce-tools.sh"; $w.enforceTools)
          | ensure("PreToolUse"; "premortem-gate.sh"; $w.premortemGate)
          | ensure("PostToolUse"; "track-evidence.sh"; $w.trackEvidence)
          | ensure("UserPromptSubmit"; "track-evidence.sh"; $w.turnStamp)
          | ensure("Stop"; "claim-guard.sh"; $w.claimGuard)
          | ensure("PreToolUse"; "nixos-primer.sh"; $w.nixosPrimer)
          | ensure("PreToolUse"; "path-conventions.sh"; $w.pathConventions)
          | ensure("PreToolUse"; "charter-gate.sh"; $w.charterGate)
          | ensure("UserPromptSubmit"; "standing-instructions.sh inject"; $w.standingInject)
          | ensure("UserPromptSubmit"; "standing-instructions.sh sync"; $w.standingSync)
          | ensure("Stop"; "ste100-guard.sh"; $w.ste100Guard)
          | ensure("SubagentStop"; "ste100-guard.sh"; $w.ste100Guard)
          | ensure("SessionStart"; "memory-staleness.sh"; $w.memoryStaleness)
          | .env.SLASH_COMMAND_TOOL_CHAR_BUDGET = (.env.SLASH_COMMAND_TOOL_CHAR_BUDGET // "30000")
        '';
        emptyJson = pkgs.writeText "claude-settings-empty.json" "{}";
      in {
        home.activation.claudeGateHookWiring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          _s="${config.home.homeDirectory}/.claude/settings.json"
          _src="$_s"; [ -f "$_s" ] || _src=${emptyJson}
          _tmp=$(${pkgs.coreutils}/bin/mktemp "$_s.heal.XXXXXX" 2>/dev/null) || _tmp=""
          if [ -n "$_tmp" ] && ${pkgs.jq}/bin/jq --slurpfile wire ${wireFile} -f ${healJq} "$_src" > "$_tmp" 2>/dev/null; then
            if ! ${pkgs.diffutils}/bin/cmp -s "$_tmp" "$_s" 2>/dev/null; then
              [ -f "$_s" ] && run ${pkgs.coreutils}/bin/cp "$_s" "$_s.pre-heal.bak"
              run ${pkgs.coreutils}/bin/mv "$_tmp" "$_s"
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
          assertion = cfg.shareConfig.autoPull.enable -> cfg.shareConfig.enable;
          message = "hwc.home.apps.claude-code.shareConfig.autoPull requires shareConfig.enable = true.";
        }
      ];
    }
  ];
}
