# HWC dictation

## Purpose
Deploys the owned dictation app as a Home Manager user service. Hyprland and
Waybar call the same client; the daemon owns recording and transcription.

## Boundaries
- Manages the app package, local model reference, remote endpoint and user service.
- The app repository owns control, recovery, delivery and overlay behavior.
- `whisper-cpp` owns declared model downloads. No server changes belong here.

## Structure
- `index.nix` — options, generated app configuration with CPU fallback settings, launcher and user service.

## Changelog
- 2026-09-08: pinned the package runtime-dependency repair after live clipboard delivery failed without `cat`; desktop acceptance now uses a restricted daemon PATH.
- 2026-09-08: native browser paste, focus guard, cancellation and overlay smoke passed; selected tested base.en CPU fallback on the laptop. Reduced context stays disabled after a short-speech accuracy regression. Service stop allows the bounded engine and overlay drains. Documented app-owned recovery cleanup: admission enforces capacity; acknowledged successes become eligible after 24h and are pruned on startup or the next reservation. Activation remains pending.
- 2026-09-07: prepared bounded desktop dictation deployment; activation pending app verification.
