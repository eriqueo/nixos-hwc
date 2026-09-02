# domains/home/apps/pi/index.nix
#
# pi coding agent wired to DataX's DX1 model (RunPod-served, exposed as the
# "mycloud" provider) and DX2 (its own proxy, exposed as the "dx2" provider).
# Declarative replacement for the imperative
# setup-pi.sh install on datax-box: pinned package (parts/package.nix) +
# ~/.pi/agent/ config rendered from Nix, with a deliberate split:
#
#   * models.json  — IMMUTABLE (home.file store symlink). Provider/endpoint/
#     model config; pi never writes it, so we keep it byte-identical and
#     deterministic across hosts. The DX1 API key never enters the store:
#     models.json references it via pi's "!cmd" indirection, resolved at
#     request time (eric ∈ `secrets` group; mount is root:secrets 0440).
#
#   * settings.json — SEEDED then MUTABLE (home.activation copy-if-absent,
#     the tuxedo/freecad pattern). pi rewrites this at runtime
#     (lastChangelogVersion, trust decisions, UI prefs); a store symlink
#     would make every launch re-nag the changelog and drop trust state.
#     Nix provides the initial defaultProvider/defaultModel; pi owns it after.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.pi;
  piPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./parts/package.nix { };

  settingsSeed = pkgs.writeText "pi-settings.json" (builtins.toJSON ({
    defaultProvider = cfg.defaultProvider;
    defaultModel = cfg.defaultModel;
  } // cfg.settings));

  # Append-only jq merge of one LIST-valued key inside the pi-owned
  # settings.json. Nix declares resource paths and the model ring; pi owns every
  # other key and rewrites the file at runtime. Seeding alone never reaches a
  # machine whose settings.json already exists, so these merge at every
  # activation instead. Entries pi or Eric added by hand survive.
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

  defaultModels = {
    providers = {
      ${cfg.defaultProvider} = {
        baseUrl = cfg.dx1.baseUrl;
        api = cfg.dx1.api;
        # pi resolves "!cmd" at request time — key stays out of the store.
        apiKey = "!cat ${cfg.dx1.apiKeyFile}";
        models = [
          {
            id = cfg.defaultModel;
            name = "DX1";
            contextWindow = cfg.dx1.contextWindow;
            maxTokens = cfg.dx1.maxTokens;
          }
        ];
      };
    }
    # DX2 is a SEPARATE provider, not a second model inside `mycloud`: it is
    # served from its own LiteLLM proxy (dx2.datax.to) and authenticated with
    # its own key, and a pi provider carries exactly one baseUrl and one
    # apiKey. Same `!cat` indirection, so the key stays out of the store.
    // lib.optionalAttrs cfg.dx2.enable {
      dx2 = {
        baseUrl = cfg.dx2.baseUrl;
        api = cfg.dx2.api;
        apiKey = "!cat ${cfg.dx2.apiKeyFile}";
        models = [
          {
            id = "dx2";
            name = "DX2";
            contextWindow = cfg.dx2.contextWindow;
            maxTokens = cfg.dx2.maxTokens;
          }
        ];
      };
    }
    # DeepSeek is a declared provider rather than a built-in login, for the
    # same reason DX1 is: the key reaches pi through `!cat` off an agenix
    # mount and never enters the Nix store. `pi --list-models` shows only
    # providers that hold credentials, so this entry is what makes DeepSeek
    # appear at all.
    // lib.optionalAttrs cfg.deepseek.enable {
      deepseek = {
        baseUrl = "https://api.deepseek.com/v1";
        api = "openai-completions";
        apiKey = "!cat ${cfg.deepseek.apiKeyFile}";
        models = [
          {
            id = "deepseek-chat";
            name = "DeepSeek V3";
            contextWindow = 131072;
            maxTokens = 8192;
          }
          {
            id = "deepseek-reasoner";
            name = "DeepSeek R1";
            contextWindow = 131072;
            maxTokens = 65536;
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
    enable = lib.mkEnableOption "pi coding agent (DX1 terminal agent)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "pi package to use. If null, the pinned parts/package.nix build.";
    };

    defaultProvider = lib.mkOption {
      type = lib.types.str;
      default = "mycloud";
      description = "Provider id pi starts on (settings.json defaultProvider + models.json key).";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "dx1";
      description = "Model id pi starts on.";
    };

    dx1 = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://dx1.datax.to/v1";
        description = ''
          OpenAI-compatible base URL of the DX1 deployment: the LiteLLM proxy,
          which is the stable client-side entry point and survives the pod being
          terminated and recreated. It previously pointed at the RunPod
          pod-proxy URL for pod `eanzbnhtt3ji8t` ("DX1 on RTX6000"), which went
          dead when that pod was stopped and DX1 migrated to an H100 pod.
        '';
      };

      api = lib.mkOption {
        type = lib.types.str;
        default = "openai-completions";
        description = "pi API dialect for the DX1 provider.";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/pi-dx1-api-key";
        description = "Runtime path of the DX1 API key (agenix mount, root:secrets 0440).";
      };

      contextWindow = lib.mkOption {
        type = lib.types.int;
        default = 262144;
        description = "DX1 context window in tokens (from lil-box models.json: 256k).";
      };

      maxTokens = lib.mkOption {
        type = lib.types.int;
        default = 65536;
        description = "DX1 max output tokens (from lil-box models.json: 64k).";
      };
    };

    dx2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Add DX2 to models.json as the `dx2` provider. ON, unlike
          `deepseek.enable`, because the key is already provisioned:
          `domains/secrets/parts/infrastructure/dx2-api-key.age` mounts at
          `apiKeyFile` on every host that evaluates the secrets domain. pi
          resolves the key with `!cat` at request time, so a host without the
          mount fails per-request rather than at activation.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://dx2.datax.to/v1";
        description = ''
          OpenAI-compatible base URL of the DX2 deployment — its own LiteLLM
          proxy, the same stable client-side entry point shape as DX1 and for
          the same reason: it survives the serving pod being replaced.
        '';
      };

      api = lib.mkOption {
        type = lib.types.str;
        default = "openai-completions";
        description = "pi API dialect for the DX2 provider.";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/dx2-api-key";
        description = ''
          Runtime path of the DX2 API key (agenix mount, root:secrets 0440).
          The name is derived from the .age path by
          domains/secrets/parts/lib.nix: `infrastructure/dx2-api-key.age` ->
          `dx2-api-key`. It carries no `pi-` prefix because the key is the
          model's, not this harness's — T3 Code reaches the same DX2 endpoint.
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

    models = lib.mkOption {
      type = lib.types.attrs;
      default = defaultModels;
      description = "Full ~/.pi/agent/models.json content (providers attrset).";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra ~/.pi/agent/settings.json keys merged over defaultProvider/defaultModel.";
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

    enabledModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "mycloud/dx1"
        "dx2/dx2"
        "anthropic/claude-opus-4-6"
        "openai/gpt-5.3-codex"
      ];
      description = ''
        Model patterns pi cycles through on Ctrl+P, written to the
        `enabledModels` array in settings.json. Same append-only merge as
        skillPaths, for the same reason: the file is pi-owned at runtime.

        The DataX models come first because they are the only routes that cost
        nothing per token. Anthropic and OpenAI are subscription logins (`pi /login`), but
        Anthropic bills a third-party harness per token as extra usage rather
        than against the Claude plan — pi prints that warning at startup. So
        Claude Code stays the cheap way to run Claude, and Claude in pi is the
        deliberate, paid choice.

        A pattern naming a provider with no credentials is inert, not an error:
        pi skips it. Add "deepseek/deepseek-chat" once deepseek.enable is on.
      '';
    };

    deepseek = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Add DeepSeek to models.json as a fourth route. OFF by default and
          deliberately so: pi resolves the key with `!cat`, and a missing agenix
          mount makes every DeepSeek request fail at request time rather than at
          activation. Provision the secret first, then set this to true.
        '';
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/pi-deepseek-api-key";
        description = "Runtime path of the DeepSeek API key (agenix mount, root:secrets 0440).";
      };
    };

    contextFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ./parts/AGENTS.md;
      description = ''
        Global instructions, installed as ~/.pi/agent/AGENTS.md. Set to null to
        install none.

        Deliberately short, and shorter than ~/.claude/CLAUDE.md. Always-loaded
        instruction volume degrades compliance across every rule, not just the
        newest one, and DX1 has less headroom for that than Claude does. So
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
    home.file.".pi/agent/models.json".text = builtins.toJSON cfg.models;

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
    # skillPaths is the exception to "pi owns it after seeding": it is a Nix-
    # declared resource path, not runtime state, and seeding cannot reach a
    # machine whose settings.json already exists. So it is merged append-only
    # on every activation — entries pi or Eric added by hand are preserved, and
    # every other key in the file is untouched.
    home.activation.piSeedSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _piAgentDir=${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent"}
      run mkdir -p "$_piAgentDir"
      if [ ! -e "$_piAgentDir/settings.json" ]; then
        run install -m 0644 ${settingsSeed} "$_piAgentDir/settings.json"
      fi
      ${lib.optionalString (cfg.skillPaths != [ ]) (mergeList "skills" cfg.skillPaths)}
      ${lib.optionalString (cfg.enabledModels != [ ]) (mergeList "enabledModels" cfg.enabledModels)}
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

    # Same trap for every DataX-served provider, so the message has one
    # producer and each provider supplies only its own option name and URL.
    warnings = lib.concatMap
      ({ opt, url, proxy }:
        lib.optional (lib.hasInfix "proxy.runpod.net" url)
          "hwc.home.apps.pi: ${opt}.baseUrl points at a RunPod pod-proxy URL — stable across Stop/Start, but it dies when that pod is terminated or replaced, and pi then 404s on every request. Prefer the LiteLLM proxy ${proxy}, which survives pod migration.")
      ([ { opt = "dx1"; url = cfg.dx1.baseUrl; proxy = "https://dx1.datax.to/v1"; } ]
        ++ lib.optional cfg.dx2.enable { opt = "dx2"; url = cfg.dx2.baseUrl; proxy = "https://dx2.datax.to/v1"; });
  };
}
