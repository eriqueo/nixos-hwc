# whisper-cpp

## Purpose
Installs whisper.cpp speech-to-text (CUDA build by default) with declarative
model management: hash-pinned GGML weights are fetched via fetchurl and
symlinked into a models directory, so `whisper-cli -m` resolves without
imperative downloads.

## Boundaries
- ✅ `hwc.home.apps.whisper-cpp.enable`; `cuda` (default true), `models` (from the known set: large-v3, medium.en; default medium.en), `modelsDir` (default `~/models/whisper`)
- ✅ Model files placed via `home.file` as `ggml-<name>.bin` symlinks
- ❌ No transcription services/pipelines — this only provides the binary and weights
- ❌ New models require adding a hash to `knownModels` in index.nix

## Structure
- `index.nix` — options, CUDA package override, model fetch + home.file symlinks

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
