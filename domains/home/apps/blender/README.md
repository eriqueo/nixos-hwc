# blender

## Purpose
Installs Blender with GPU-rendering support matched to the host's `hwc.system.hardware.gpu` config (CUDA on NVIDIA, ROCm on AMD), plus a `blender-gpu` PRIME-offload wrapper on NVIDIA hosts. Enable via `hwc.home.apps.blender.enable`.

## Boundaries
- ✅ `pkgs.blender` overridden with `cudaSupport`/`rocmSupport` flags gated on the osConfig GPU type; `blender-gpu` wrapper (NV PRIME env vars) when CUDA applies; assertions that GPU flags match declared hardware.
- ❌ Does not manage GPU drivers or the `hwc.system.hardware.gpu` options (system domain); no Blender user preferences/config files.

## Structure
- `index.nix` — options (`enable`, `cudaSupport`, `rocmSupport`), overridden package, GPU wrapper, hardware assertions.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
