# domains/home/apps/pi/index.nix
#
# pi coding agent wired to DataX's DX2 model as a bounded local worker lane.
# Declarative replacement for the imperative
# setup-pi.sh install on datax-box: pinned package (parts/package.nix) +
# ~/.pi/agent/ config rendered from Nix, with a deliberate split:
#
#   * models.json  — IMMUTABLE (home.file store symlink). Provider/endpoint/
#     model config; pi never writes it, so we keep it byte-identical and
#     deterministic across hosts. The DataX API key never enters the store:
#     models.json references it via pi's "!cmd" indirection, resolved at
#     request time (eric ∈ `secrets` group; mount is root:secrets 0440).
#
#   * settings.json — SEEDED then MUTABLE (home.activation copy-if-absent,
#     the tuxedo/freecad pattern). pi rewrites this at runtime
#     (lastChangelogVersion, trust decisions, UI prefs); a store symlink
#     would make every launch re-nag the changelog and drop trust state.
#     Nix reconciles routing keys; pi owns unrelated runtime state.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.pi;
  piPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./parts/package.nix { };
  dx2ProviderId = "dx2";
  dx2ModelId = "llm";
  dx2QualifiedModel = "${dx2ProviderId}/${dx2ModelId}";

  managedSettings = {
    defaultProvider = dx2ProviderId;
    defaultModel = dx2ModelId;
    enabledModels = [ dx2QualifiedModel ];
    subagents = {
      defaultProvider = dx2ProviderId;
      defaultModel = dx2QualifiedModel;
      defaultThinking = "low";
      modelScope = {
        enforce = true;
        strict = true;
        allow = [ dx2QualifiedModel ];
      };
      agentOverrides = builtins.listToAttrs (map
        (name: { inherit name; value.disabled = true; })
        [
          "claude-code"
          "claude-code-writer"
          "codex-exec"
          "codex-exec-writer"
          "cursor-agent"
          "cursor-agent-writer"
        ]);
    };
  };

  settingsSeed = pkgs.writeText "pi-settings.json" (builtins.toJSON (managedSettings // {
    skills = cfg.skillPaths;
  }));

  # Append-only jq merge of one LIST-valued key inside the pi-owned
  # settings.json. Skills are shared resources, so manual paths survive.
  mergeList = key: values: ''
    _piS="$_piAgentDir/settings.json"
    _piTmp=$(${pkgs.coreutils}/bin/mktemp "$_piS.${key}.XXXXXX" 2>/dev/null) || _piTmp=""
    if [ -n "$_piTmp" ] && ${pkgs.jq}/bin/jq \
        --arg key ${lib.escapeShellArg key} \
        --argjson want ${lib.escapeShellArg (builtins.toJSON values)} \
        '.[$key] = (((.[$key] // []) + $want) | unique)' "$_piS" > "$_piTmp" 2>/dev/null; then
      if ! ${pkgs.diffutils}/bin/cmp -s "$_piTmp" "$_piS" 2>/dev/null; then
        run ${pkgs.coreutils}/bin/mv "$_piTmp" "$_piS"
        echo "pi: ${key} merged into $_piS"
      fi
    else
      echo "pi: $_piS is not valid JSON — ${key} NOT wired, fix it by hand" >&2
    fi
    ${pkgs.coreutils}/bin/rm -f "$_piS".${key}.* 2>/dev/null || true
  '';

  # Replace only Nix-owned routing keys. The shallow merge preserves Pi-owned
  # package, trust, changelog, and UI state.
  reconcileRouting = ''
    _piS="$_piAgentDir/settings.json"
    _piTmp=$(${pkgs.coreutils}/bin/mktemp "$_piS.routing.XXXXXX" 2>/dev/null) || _piTmp=""
    if [ -n "$_piTmp" ] && ${pkgs.jq}/bin/jq \
        --argjson managed ${lib.escapeShellArg (builtins.toJSON managedSettings)} \
        '. + $managed' "$_piS" > "$_piTmp" 2>/dev/null; then
      if ! ${pkgs.diffutils}/bin/cmp -s "$_piTmp" "$_piS" 2>/dev/null; then
        run ${pkgs.coreutils}/bin/mv "$_piTmp" "$_piS"
        echo "pi: DX2 routing reconciled in $_piS"
      fi
    else
      echo "pi: $_piS is not valid JSON — DX2 routing NOT wired, fix it by hand" >&2
    fi
    ${pkgs.coreutils}/bin/rm -f "$_piS".routing.* 2>/dev/null || true
  '';

  defaultModels = {
    providers = {
      ${dx2ProviderId} = {
        baseUrl = cfg.dx2.baseUrl;
        api = cfg.dx2.api;
        apiKey = "!cat ${cfg.dx2.apiKeyFile}";
        models = [
          {
            id = dx2ModelId;
            name = "DX2";
            contextWindow = cfg.dx2.contextWindow;
            maxTokens = cfg.dx2.maxTokens;
            reasoning = true;
            thinkingLevelMap = {
              off = null;
              minimal = null;
              low = "low";
              medium = "medium";
              high = null;
              xhigh = "xhigh";
              max = null;
            };
            compat.supportsReasoningEffort = true;
          }
        ];
      };
    };
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.pi = {
    enable = lib.mkEnableOption "pi coding agent (DX2 worker lane)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "pi package to use. If null, the pinned parts/package.nix build.";
    };

    dx2 = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://dx2.datax.to/v1";
        description = ''
          OpenAI-compatible base URL of the DX2 deployment. This endpoint
          selects the DX2 deployment directly; it is not the DX1 LiteLLM
          proxy.
        '';
      };

      api = lib.mkOption {
        type = lib.types.str;
        default = "openai-completions";
        description = "pi API dialect for the DX2 provider.";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/pi-dx1-api-key";
        description = ''
          Runtime path of the shared DataX API key (agenix mount,
          root:secrets 0440). DX2's endpoint accepts the existing DataX
          credential, so the provider consumes the pi-dx1-api-key mount.
        '';
      };

      contextWindow = lib.mkOption {
        type = lib.types.int;
        default = 262144;
        description = "DX2 context window in tokens.";
      };

      maxTokens = lib.mkOption {
        type = lib.types.int;
        default = 65536;
        description = "DX2 max output tokens.";
      };
    };

    skillPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "~/.claude/skills" ];
      description = ''
        Directories pi loads Agent Skills from, written to the `skills` array
        in settings.json. pi implements the Agent Skills standard, so the
        Claude Code skill tree is consumed as-is — one tree, two harnesses, no
        second copy to drift.

        settings.json is pi-owned at runtime, so these are merged in
        append-only at every activation rather than seeded once (seeding alone
        would never reach a machine whose settings.json already exists). Same
        jq-merge shape the claude-code module uses for its gate-hook wiring.
      '';
    };

    contextFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ./parts/AGENTS.md;
      description = ''
        Global instructions, installed as ~/.pi/agent/AGENTS.md. Set to null to
        install none.

        Deliberately short, and shorter than ~/.claude/CLAUDE.md. Always-loaded
        instruction volume degrades compliance across every rule, not just the
        newest one, and DX2 has less headroom for that than Claude does. So
        this file carries only what cannot be enforced mechanically
        (parts/guards.ts) or loaded on demand (skills, per-repo CLAUDE.md,
        which pi discovers from cwd and its ancestors).
      '';
    };

    guards.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install parts/guards.ts as a pi extension (~/.pi/agent/extensions/,
        auto-discovered — no settings entry). Blocks grep/sed, confirms
        destructive git and nixos-rebuild, and refuses unbounded reads of
        large files. Port of the Claude Code enforce-tools PreToolUse hook:
        rules the model cannot decline, which is the half of the contract that
        survives being run against a smaller model.

        Also carries the port of the write-guard PreToolUse hook: a write to an
        existing file, a delete, and a `git checkout`/`git restore` over
        uncommitted changes are all blocked until the session has looked at the
        target.
      '';
    };

    stopGuards.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install parts/stop-guards.ts as a pi extension. Port of two Claude Code
        Stop hooks: the ASD-STE100 sentence-length ceiling, and the self-caught
        channel of the mistake ledger.

        A SEPARATE FILE FROM guards.ts, and separate on purpose. guards.ts runs
        on `tool_call` and BLOCKS — the model gets no vote. This one runs on
        `agent_end`, which carries no result type in pi 0.80.7 and therefore
        cannot reject a turn; it queues a correcting follow-up turn instead,
        with pi.sendMessage(..., triggerTurn). Blocking and nagging are
        different contracts with different failure modes, so each gets its own
        switch. One file could not carry two switches.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ piPkg ];

    # pi reads ~/.pi/agent/*, not XDG.
    # models.json: deterministic, pi never writes it → immutable store symlink.
    home.file.".pi/agent/models.json".text = builtins.toJSON defaultModels;

    # AUTO-MANAGED: bounded orchestration policy, rebuilt from Nix.
    home.file.".pi/agent/extensions/subagent/config.json".text = builtins.toJSON {
      globalConcurrencyLimit = 2;
      maxSubagentSpawnsPerRun = 4;
      maxSubagentSpawnsPerSession = 8;
      maxActiveAsyncRunsPerSession = 2;
      toolDescriptionMode = "compact";
    };

    # AGENTS.md: deterministic, pi never writes it → immutable store symlink.
    home.file.".pi/agent/AGENTS.md" = lib.mkIf (cfg.contextFile != null) {
      source = cfg.contextFile;
    };

    # guards.ts: deterministic, pi never writes it → immutable store symlink.
    # Extensions in ~/.pi/agent/extensions/ are auto-discovered, so this needs
    # no settings.json entry at all.
    home.file.".pi/agent/extensions/hwc-guards.ts" = lib.mkIf cfg.guards.enable {
      source = ./parts/guards.ts;
    };

    home.file.".pi/agent/extensions/hwc-stop-guards.ts" = lib.mkIf cfg.stopGuards.enable {
      source = ./parts/stop-guards.ts;
    };

    # settings.json: pi rewrites it at runtime → seed once, writable, then pi
    # owns it. Mirrors the tuxedo seed-if-absent pattern; works under both
    # HM-as-module and HM-as-flake.
    #
    # Nix reconciles routing keys on every activation because seeding cannot
    # update an existing settings file. Skill paths remain append-only.
    home.activation.piSeedSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _piAgentDir=${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent"}
      run mkdir -p "$_piAgentDir"
      if [ ! -e "$_piAgentDir/settings.json" ]; then
        run install -m 0644 ${settingsSeed} "$_piAgentDir/settings.json"
      fi
      ${reconcileRouting}
      ${lib.optionalString (cfg.skillPaths != [ ]) (mergeList "skills" cfg.skillPaths)}
    '';

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = piPkg != null;
        message = "hwc.home.apps.pi: pi package must be available";
      }
    ];

    warnings = lib.optional (lib.hasInfix "proxy.runpod.net" cfg.dx2.baseUrl)
      "hwc.home.apps.pi: dx2.baseUrl points at a RunPod pod-proxy URL — stable across Stop/Start, but it dies when that pod is terminated or replaced. Prefer https://dx2.datax.to/v1, which survives pod migration.";
  };
}
