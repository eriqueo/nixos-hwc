# whisper-cpp

## Purpose
Installs whisper.cpp speech-to-text (CUDA build by default) with declarative
model management: hash-pinned GGML weights are fetched via fetchurl and
symlinked into a models directory, so `whisper-cli -m` resolves without
imperative downloads.

## Boundaries
- ✅ `hwc.home.apps.whisper-cpp.enable`; `cuda` (default true), `models` (from the known set: base.en, large-v3, medium.en; default medium.en), `modelsDir` (default `~/models/whisper`)
- ✅ Model files placed via `home.file` as `ggml-<name>.bin` symlinks
- ❌ Desktop dictation service → `../hwc-dictation/`; this module provides the binary and weights
- ❌ New models require adding a hash to `knownModels` in index.nix

## Structure
- `index.nix` — options, CUDA package override, hash-pinned base/medium/large model fetch + home.file symlinks

## Changelog
- 2026-09-08: added base.en for the laptop CPU fallback; retained existing larger models.
- 2026-09-07: removed the shell dictation implementation; the owned app now supplies that workflow. Model management remains here.
- 2026-09-05: `dictate` push-to-talk toggle. Recorder runs as transient user unit `whisper-dictate-rec` (pw-record 16 kHz mono); stop transcribes with whisper-cli on the local GPU, copies to clipboard, types with wtype only if focus is unchanged since the recording started. One flock around every transition; presses during transcription are refused; takes under 0.5 s are dropped. Model URLs pinned to a Hugging Face revision.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
