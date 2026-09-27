# domains/server/native/ai/brainvec/index.nix
#
# brainvec ingest — semantic index of the brain vault (one note = one
# embedding) at ~/.cache/brainvec/index.jsonl, consumed by brain-mcp's
# search_semantic / related_notes tools.
#
# The pipeline code lives in its OWN repo (github.com/eriqueo/brainvec,
# pinned as a flake input). Nix owns source deployment, schedule and environment.
# Update with `nix flake update brainvec`, commit, build and switch. The timer
# runs that immutable source without updating a checkout or needing GitHub.
#
# Embeddings come from the local llama-embed service (nomic-embed-text-v1.5,
# 768-dim, 127.0.0.1:11502) — fully self-hosted, no external API. nomic's
# asymmetric task prefixes are set here (doc side) and in brain-mcp (query
# side); the prefix is part of the index's embedId so drift is loud.
#
# Timer: *:5/15 — five minutes behind brain-vault-sync's *:0/15, so notes
# folded on the laptop are pulled by the sync tick and indexed on the next
# ingest tick. Deliberately a dumb offset timer, not OnSuccess= coupling:
# vault-sync also exists on the laptop (no embed backend there), and a
# no-change ingest run costs zero embedding calls.
#
# brainvec is the only vault index: persona-daemon, which kept a second
# chunked copy, was retired 2026-09-19.
#
# NAMESPACE: hwc.server.ai.brainvec
#
# DEPENDENCIES:
#   - brainvec flake input (source revision in flake.lock)
#   - hwc.server.ai.llamaCpp embed sub-service (127.0.0.1:11502)
#   - the vault clone at the brain-mcp vaultPath

{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.server.ai.brainvec;
  paths = config.hwc.paths;

  ingestScript = pkgs.writeShellApplication {
    name = "brainvec-ingest";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      set -uo pipefail
      echo "brainvec source=${inputs.brainvec.rev}"
      exec node ${inputs.brainvec}/ingest.mjs "$@"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.server.ai.brainvec = {
    enable = lib.mkEnableOption "brainvec semantic index ingest (brain vault embeddings)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the ingest as (must own the vault clone + cache)";
    };

    vaultDir = lib.mkOption {
      type = lib.types.path;
      default = if paths.brain.vault != null then paths.brain.vault
                else "${paths.user.home}/900_vaults/brain";
      description = "Brain vault clone to index";
    };

    # REPLACEABLE: one current index + metadata, rebuilt from the vault.
    # Each successful ingest drops vanished notes and atomically replaces it.
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "${paths.user.home}/.cache/brainvec";
      description = "Index location (index.jsonl + meta.json); disposable, rebuildable";
    };

    embedBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11502/v1";
      description = "OpenAI-compatible embeddings endpoint (llama-embed)";
    };

    embedModel = lib.mkOption {
      type = lib.types.str;
      default = "nomic-embed-text-v1.5";
      description = "Model label recorded in the index's embedId (llama-server ignores the request field)";
    };

    embedInputMax = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "Per-note embed input cap in chars (~500 tokens — llama-embed ctx is 2048 across 4 unified KV slots; do NOT raise the model contextSize, GGML_ASSERT crash)";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:5/15";
      description = "OnCalendar — offset behind brain-vault-sync's *:0/15";
    };
  };

  config = lib.mkIf cfg.enable {

    warnings = lib.optional (!(config.hwc.server.ai.llamaCpp.enable or false))
      "hwc.server.ai.brainvec: llama-cpp (embed backend on :11502) is not enabled — ingest and query-time embedding will fail until it is.";

    #==========================================================================
    # SYSTEMD SERVICE + TIMER
    #==========================================================================
    systemd.services.brainvec-ingest = {
      description = "brainvec — incremental semantic index of the brain vault";
      # Ordering only (no wants): degrade gracefully if either is absent.
      after = [ "llama-embed.service" "brain-vault-sync.service" ];

      environment = {
        HOME = "/home/${cfg.user}";
        BRAINVEC_VAULT = toString cfg.vaultDir;
        BRAINVEC_CACHE = cfg.cacheDir;
        BRAINVEC_EMBED_BASE_URL = cfg.embedBaseUrl;
        BRAINVEC_EMBED_MODEL = cfg.embedModel;
        BRAINVEC_EMBED_INPUT_MAX = toString cfg.embedInputMax;
        BRAINVEC_BATCH = "4";
        BRAINVEC_EMBED_PREFIX_DOC = "search_document: ";
        BRAINVEC_EMBED_PREFIX_QUERY = "search_query: ";
      };

      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = "${ingestScript}/bin/brainvec-ingest";
        # Background batch work; yields to interactive load like llama-embed does.
        Nice = 10;
        CPUWeight = 20;
        # Ingest is read-only over the vault; writes only its own cache.
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.brainvec-ingest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
