# whisper

Resident whisper.cpp speech-to-text service on hwc-work. It serves the pinned
small.en model on CPU with four threads, CPUQuota400%, and MemoryMax2G.
OpenAI-compatible `POST /v1/audio/transcriptions` remains available at
`https://whisper.hwc.iheartwoodcraft.com`. The home server retains forwarding.

Consumers found by repository search and live configuration:
- Work inbox-processor for phone audio captures.
- Laptop hwc-dictation (`prefer_remote`, 30-second remote timeout, local fallback).
- The documented phone Shortcut and other Whisper API clients.

Same-model synthetic tests on work (2026-09-26):12/30/60-second recordings
completed in2.6/5.5/9.3seconds. A short request queued behind60seconds of audio
took11.7seconds. Peak RSS720MiB. This measures capacity, not microphone accuracy.

## Structure

```
index.nix   # OPTIONS / IMPLEMENTATION / VALIDATION
            # - hwc.server.ai.whisper: enable, user, port, model (enum of
            #   pinned ggml weights), gpu, cudaCapabilities, threads, extraArgs
            # - model = pkgs.fetchurl pinned to one HF revision; ExecStart
            #   references the store path directly
            # - cudaCapabilities -> CMAKE_CUDA_ARCHITECTURES override
            #   (Pascal needs "6.1"; same mechanism as llama-cpp)
            # - --convert + --tmp-dir /run/whisper-server so m4a/ogg/mp3 are
            #   transcoded by ffmpeg inside the only writable dir
README.md
```

## Usage

```sh
curl -sf http://127.0.0.1:11503/v1/audio/transcriptions \
  -F file=@clip.m4a -F response_format=json | jq -r .text
```

From the phone, same call against `https://whisper.<vhostDomain>/...`.

### iOS Shortcut (talk to the local LLM)

1. **Record Audio** (stop on tap).
2. **Get Contents of URL** — `https://whisper.<vhostDomain>/v1/audio/transcriptions`,
   method POST, request body **Form**, one field named `file` of type File
   set to the recording, plus `response_format` = `json`.
3. **Get Dictionary Value** `text`.
4. **Get Contents of URL** — `https://llama-gpu.<vhostDomain>/v1/chat/completions`,
   POST, JSON body `{"messages":[{"role":"user","content":<text>}]}`.
5. **Get Dictionary Value** `choices.1.message.content`, then **Show Result**
   or **Speak Text**.

Bind the Shortcut to the Action Button. The phone must be on the tailnet.

## Limits

- whisper-server serialises inference behind one mutex. Single-user box;
  a long capture from the inbox delays a phone request until it finishes.
- No auth on the endpoint. The tailnet-only firewall is the boundary.
- Work uses CPU; the home GPU allocation is released after cutover. Very long
  recordings can still delay dictation beyond its30-second timeout.

## Changelog
- 2026-09-26: Move same-model inference to work CPU after capacity tests; preserve the API hostname and include the live laptop dictation caller in the inventory.

- 2026-09-05: created. Root cause of the GPU failure that shaped this
  module: the cached `whisper-cpp` binary is built for `CUDA : ARCHS =
  750,...`; on the sm_61 P1000 every model above base.en aborts with
  `ggml_cuda_compute_forward: IM2COL failed` / "no kernel image is available".
  `cudaCapabilities = [ "6.1" ]` forces the same local rebuild llama-cpp
  already does. CPU was measured and rejected as the primary path: small.en
  5.0 s, medium.en 17 s, large-v3-turbo-q5_0 26 s per 11 s clip on the
  i7-8700K — the encoder is compute-bound, so the 62 GB of RAM does not help.
