# blender

## Purpose
Installs Blender with GPU-rendering support matched to the host's `hwc.system.hardware.gpu` config (CUDA on NVIDIA, ROCm on AMD), plus a `blender-gpu` PRIME-offload wrapper on NVIDIA hosts. Enable via `hwc.home.apps.blender.enable`.

## Boundaries
- ✅ Package selection via `package` (explicit wins; else `pkgs.blender` overridden with `cudaSupport`/`rocmSupport` gated on the osConfig GPU type); `blender-gpu` wrapper (NV PRIME env vars) when CUDA applies; assertions that GPU flags match declared hardware. `parts/package.nix` is an opt-in pin of the official upstream release binary.
- ❌ Does not manage GPU drivers or the `hwc.system.hardware.gpu` options (system domain); no Blender user preferences/config files.

## Structure
- `index.nix` — options (`enable`, `package`, `cudaSupport`, `rocmSupport`), package selection, GPU wrapper, hardware assertions.
- `parts/package.nix` — optional pinned Blender 5.2.0 derivation from the official upstream tarball (autoPatchelf'd, driver libs via `/run/opengl-driver` in the wrapper).

## Changelog
- 2026-07-30: added `package` option + `parts/package.nix` (official upstream binary), wired on hwc-laptop. `pkgs.blender.override { cudaSupport = true; }` is a variant Hydra never builds, so the default path recompiled Blender and its CUDA-context deps (~30 min) on every nixpkgs bump. The upstream tarball bundles those deps (embree/OIDN/OpenEXR/OSL/USD/TBB) and ships the Cycles CUDA + OptiX kernels. Verified: enumerates the RTX 2000 Ada on both CUDA and OPTIX backends. Side effect — this removed openimagedenoise from the closure entirely, so `overlays/openimagedenoise-cuda.nix` became dead code and was deleted.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
