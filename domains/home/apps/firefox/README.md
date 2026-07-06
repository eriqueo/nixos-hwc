# domains/home/apps/firefox

## Purpose
Firefox browser (Home Manager) with HWC theming, curated privacy hardening,
and a hybrid-GPU-safe launcher wrapper. Successor to the LibreWolf module —
LibreWolf was flagged insecure in nixpkgs (2026-06, no active committer).

## Boundaries
- Namespace: `hwc.home.apps.firefox.*` (Law: namespace = folder).
- HM lane only — no system-level config. GPU env stripping lives in the
  `firefox-hwc` wrapper, not in `domains/system/gpu/`.
- Theme tokens come from `hwc.home.theme` (materialized palette) with a
  deep-nord fallback; no hardcoded colors outside `parts/theme.nix`.

## Structure
```
index.nix            # Options + programs.firefox profiles.hwc + desktop entry
parts/behavior.nix   # Privacy/hardening prefs, web-platform pins, session persistence
parts/appearance.nix # GPU/render/VA-API prefs
parts/theme.nix      # userChrome/userContent CSS from the HWC palette
parts/launcher.nix   # firefox-hwc wrapper (Intel iGPU pin, NVIDIA env strip)
```

## Changelog
- 2026-07-06: Module created — migration from librewolf (unmaintained in nixpkgs, insecure-flagged 2026-06). Same theme/launcher architecture; hardening prefs ported minus FPP +AllTargets (site-breakage history).
