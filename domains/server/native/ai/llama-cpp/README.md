# llama.cpp

Native systemd llama.cpp inference services for hwc-server. Three services
share one CUDA-built `pkgs.llama-cpp` binary, all instances of a single
`mkLlamaService` submodule type (extend by adding one entry to
`subServices` in `index.nix`):

- **llama-gpu** — small dense chat model (LFM2-2.6B Q4_K_M, ~1.5 GB) fully
  offloaded to the Quadro P1000 via `-ngl 999`. Fast turn-around for
  autocomplete / classification / structured extraction.
- **llama-cpu** — large MoE chat model (LFM2-24B-A2B Q4_K_M, ~14 GB) loaded
  in host RAM with `-ngl 0`. Memory-bandwidth bound; ~6 tok/s on the
  i7-8700K because only ~2 B parameters are active per token.
- **llama-embed** — embeddings (nomic-embed-text-v1.5 Q5, ~270 MB, 768-dim
  vectors) on the GPU. Consumed by `persona-daemon` for RAG retrieval over
  the brain vault.

Charter v11.1 native-systemd pattern; mirrors
`domains/server/native/ai/hermes/` and `…/lead-scout/`.

## Structure

```
              # - top-level: enable, user, modelsDir, cudaSupport, cudaCapabilities
              # - per-service submodule via mkLlamaService { defaults = ...; }
              # - instances: gpu, cpu, embed (each {enable,port,modelFile,
              #              modelUrl,contextSize,gpuLayers,threads,extraArgs})
index.nix     # OPTIONS / IMPLEMENTATION / VALIDATION
              # - subServices list drives systemd.services (one per enabled)
              # - shared mkService helper, mkServerArgs derives CLI flags
              # - llama-cpp-fetch-model (writeShellApplication, ExecStartPre)
              # - port-uniqueness assertion across all enabled instances
README.md     # (this file)
```

## Endpoints

| Service     | External (Caddy)            | Internal           | Model                       |
|-------------|-----------------------------|--------------------|-----------------------------|
| llama-gpu   | `https://hwc.…ts.net:26443` | `127.0.0.1:11500`  | LFM2-2.6B Q4_K_M            |
| llama-cpu   | `https://hwc.…ts.net:27443` | `127.0.0.1:11501`  | LFM2-24B-A2B Q4_K_M         |
| llama-embed | _(none yet — loopback only)_ | `127.0.0.1:11502`  | nomic-embed-text-v1.5 Q5_K_M |

All expose llama.cpp's OpenAI-compatible server API. Chat services serve
`/v1/chat/completions`; the embed service serves `/v1/embeddings` (and
`/embedding` for single-input). Health probe is `/health` on all three.

## CUDA capabilities (Pascal note)

The cache.nixos-cuda.org binary targets `sm_75;80;86;89;90;100;120` —
modern data-center cards only. Pascal (Quadro P1000, GTX 10xx; compute
6.1) is NOT in that list and llama-server aborts with "no kernel image
is available for execution on the device" on startup.

Set `hwc.server.ai.llamaCpp.cudaCapabilities = [ "6.1" ]` to force a
local rebuild that targets just sm_61. ~15-25 min compile on the i7-8700K
(first time only; subsequent rebuilds hit the local store cache).

Tradeoff: leaving the option `null` keeps the cache hit but breaks GPU
on Pascal. Setting it forces a rebuild but the binary is smaller and
boots clean. Pick `null` for Ampere+ (RTX 30xx/A100/H100) and the
explicit list for anything older.

## Model storage

GGUF files live under `${hwc.paths.ai.models}/llama-cpp/` (default
`/opt/ai/models/llama-cpp/`). First boot triggers an idempotent
download via `ExecStartPre`; subsequent starts are no-ops.
`TimeoutStartSec = 2h` to tolerate the 14 GB CPU-model fetch.

## Changelog

- 2026-06-28: Add `cudaSupport` option (nullOr bool, default `null`). `null`
  trusts the host's global `nixpkgs.config.cudaSupport` (unchanged for the
  server's stable-cuda pkgs). Set `true` on hosts without global cudaSupport
  (the unstable laptop) to force the CUDA backend via
  `pkgs.llama-cpp.override { cudaSupport = true; }` — the whisper-cpp/blender
  precedent — otherwise `-ngl` is silently ignored and inference runs on the
  CPU. Module now reused in-place by `machines/laptop` (gpu + embed only).
- 2026-05-29: Refactor — extract `mkLlamaService` submodule type from the
  duplicated gpu/cpu option trees; add `llama-embed` (nomic-embed-text-v1.5,
  port 11502) as a third instance. Adding a fourth service is now one
  entry in `subServices`. Powers Phase 2.5 RAG (persona-daemon).
- 2026-05-29: Initial module. LFM2-2.6B on GPU + LFM2-24B-A2B on CPU. Added
  `cudaCapabilities` option for Pascal/older GPU support (default `null`
  keeps cache hit, `[ "6.1" ]` rebuilds for Quadro P1000).
