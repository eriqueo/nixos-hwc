# whisper-cpp

## Purpose
Installs whisper.cpp speech-to-text (CUDA build by default) with declarative
model management: hash-pinned GGML weights are fetched via fetchurl and
symlinked into a models directory, so `whisper-cli -m` resolves without
imperative downloads.

## Boundaries
- ✅ `hwc.home.apps.whisper-cpp.enable`; `cuda` (default true), `models` (from the known set: large-v3, medium.en; default medium.en), `modelsDir` (default `~/models/whisper`)
- ✅ `dictate.enable` — installs `whisper-dictate` + `wtype`; Hyprland binds SUPER+SHIFT+SPACE (`apps/hyprland/parts/behavior.nix`). `dictate.model` (default medium.en) must be in `models`.
- ✅ Model files placed via `home.file` as `ggml-<name>.bin` symlinks
- ❌ No transcription services/pipelines — this only provides the binary and weights
- ❌ New models require adding a hash to `knownModels` in index.nix

## Structure
- `index.nix` — options, CUDA package override, model fetch + home.file symlinks

## Changelog
- 2026-09-05: `dictate` push-to-talk toggle. Recorder runs as transient user unit `whisper-dictate-rec` (pw-record 16 kHz mono); stop transcribes with whisper-cli on the local GPU, copies to clipboard, types with wtype only if focus is unchanged since the recording started. One flock around every transition; presses during transcription are refused; takes under 0.5 s are dropped. Model URLs pinned to a Hugging Face revision.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
