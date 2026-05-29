# llama.cpp

Native systemd llama.cpp inference services for hwc-server. Two services
share one CUDA-built `pkgs.llama-cpp` binary:

- **llama-gpu** — small dense model (LFM2-2.6B Q4_K_M, ~1.5 GB) fully
  offloaded to the Quadro P1000 via `-ngl 999`. Fast turn-around for
  autocomplete / classification / structured extraction.
- **llama-cpu** — large MoE model (LFM2-24B-A2B Q4_K_M, ~14 GB) loaded
  in host RAM with `-ngl 0`. Memory-bandwidth bound; ~15-25 tok/s on the
  i7-8700K because only ~2 B parameters are active per token.

Charter v11.1 native-systemd pattern; mirrors
`domains/server/native/ai/hermes/` and `…/lead-scout/`.

## Structure

```
options.nix   # hwc.server.ai.llamaCpp.* schema (gpu + cpu sub-services)
index.nix     # OPTIONS / IMPLEMENTATION / VALIDATION
              # - llama-gpu.service (long-lived, GPU)
              # - llama-cpu.service (long-lived, CPU only)
              # - llama-cpp-fetch-model (writeShellApplication, ExecStartPre)
              # - tmpfiles rule for modelsDir
README.md     # (this file)
```

## Endpoints

| Service | External (Caddy) | Internal | Model |
|---------|------------------|----------|-------|
| llama-gpu | `https://hwc.…ts.net:26443` | `127.0.0.1:11500` | LFM2-2.6B Q4_K_M |
| llama-cpu | `https://hwc.…ts.net:27443` | `127.0.0.1:11501` | LFM2-24B-A2B Q4_K_M |

Both expose the standard llama.cpp OpenAI-compatible server API
(`/v1/chat/completions`, `/v1/completions`, `/health`, `/props`).

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

- 2026-05-29: Initial module. LFM2-2.6B on GPU + LFM2-24B-A2B on CPU. Added
  `cudaCapabilities` option for Pascal/older GPU support (default `null`
  keeps cache hit, `[ "6.1" ]` rebuilds for Quadro P1000).
