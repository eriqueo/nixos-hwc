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
| llama-gpu | `https://hwc.…ts.net:17443` | `127.0.0.1:11500` | LFM2-2.6B Q4_K_M |
| llama-cpu | `https://hwc.…ts.net:19443` | `127.0.0.1:11501` | LFM2-24B-A2B Q4_K_M |

Both expose the standard llama.cpp OpenAI-compatible server API
(`/v1/chat/completions`, `/v1/completions`, `/health`, `/props`).

## Model storage

GGUF files live under `${hwc.paths.ai.models}/llama-cpp/` (default
`/opt/ai/models/llama-cpp/`). First boot triggers an idempotent
download via `ExecStartPre`; subsequent starts are no-ops.
`TimeoutStartSec = 2h` to tolerate the 14 GB CPU-model fetch.

## Changelog

- 2026-05-29: Initial module. LFM2-2.6B on GPU + LFM2-24B-A2B on CPU.
