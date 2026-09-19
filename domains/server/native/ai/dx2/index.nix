# domains/server/native/ai/dx2/index.nix
#
# DX2 — DataX's hosted OpenAI-compatible model (Qwen3.8-27B on vLLM, 262K
# context). This module runs nothing. It is the one system-lane producer of
# the endpoint facts (URL, model id, key path), so each consumer stops
# repeating them. DX1 was retired on 2026-09-11 and research-scout kept its
# own copy of the old URL: it failed with HTTP 404 for five days before anyone
# saw it. One producer means the next endpoint move is one edit.
#
# Consumers: research-scout (item scoring), inbox-processor (voice-note cleanup).
#
# What DX2 is good for, measured 2026-09-19 by replaying stored work through
# it: paper scoring and voice-note summaries. What it is NOT a drop-in for:
# lead-scout classification (about half of Claude's leads came back as
# something else) and mail triage (10 of 12 urgent threads went to noise).
# Test on stored data before moving a classifier here.
#
# The Home Manager lane keeps its own copy in hwc.home.apps.pi.dx2: Pi also
# runs on hosts that do not import this server module.
#
# Sibling ruled out: research-scout/index.nix was the first consumer, but a
# second consumer cannot depend on that module being imported, and
# llama-cpp/whisper configure local inference binaries, not a remote endpoint.
#
# NAMESPACE: hwc.server.ai.dx2

{ lib, ... }:

{
  # OPTIONS
  options.hwc.server.ai.dx2 = {
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://dx2.datax.to/v1";
      description = "OpenAI-compatible base URL of DX2. Survives RunPod pod migration; a pod-proxy URL does not.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "llm";
      description = "Model id sent in requests. `llm` is canonical; the endpoint also answers to `dx1` and `dx2`.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/pi-dx1-api-key";
      description = ''
        File holding the bearer key (agenix mount, root:secrets 0440). The
        secret is still named for DX1: the same key authenticates DX2.
      '';
    };
  };

  # IMPLEMENTATION — none: this module only declares facts for its consumers.

  # VALIDATION — none: the option types are the contract.
}
