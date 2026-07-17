# domains/home/apps/pi/index.nix
#
# pi coding agent wired to DataX's DX1 model (RunPod-served, exposed as the
# "mycloud" provider). Declarative replacement for the imperative
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

  defaultModels = {
    providers.${cfg.defaultProvider} = {
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
        default = "https://eanzbnhtt3ji8t-8000.proxy.runpod.net/v1";
        description = ''
          OpenAI-compatible base URL of the DX1 deployment. This is the RunPod
          pod-proxy URL for pod `eanzbnhtt3ji8t` ("DX1 on RTX6000"). The pod ID
          — and thus this URL — is STABLE across Stop/Start; it changes only if
          the pod is terminated and recreated. If that happens, update this one
          line and rebuild.
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
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ piPkg ];

    # pi reads ~/.pi/agent/*, not XDG.
    # models.json: deterministic, pi never writes it → immutable store symlink.
    home.file.".pi/agent/models.json".text = builtins.toJSON cfg.models;

    # settings.json: pi rewrites it at runtime → seed once, writable, then pi
    # owns it. Mirrors the tuxedo seed-if-absent pattern; works under both
    # HM-as-module and HM-as-flake.
    home.activation.piSeedSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _piAgentDir=${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent"}
      run mkdir -p "$_piAgentDir"
      if [ ! -e "$_piAgentDir/settings.json" ]; then
        run install -m 0644 ${settingsSeed} "$_piAgentDir/settings.json"
      fi
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

    warnings = lib.optional (lib.hasInfix "proxy.runpod.net" cfg.dx1.baseUrl)
      "hwc.home.apps.pi: dx1.baseUrl points at a RunPod pod-proxy URL — stable across Stop/Start, but if pod eanzbnhtt3ji8t is terminated & recreated the URL changes and DX1 will 404 until you update dx1.baseUrl.";
  };
}
