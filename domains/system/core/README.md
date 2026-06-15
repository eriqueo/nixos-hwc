# System Core

## Purpose
Foundational system configuration: identity, filesystem structure, boot, and cross-cutting defaults.

## Boundaries
- Manages: User identity (PUID/PGID), tmpfiles structure, thermal management, boot config
- Does NOT manage: Networking → `networking/`, user accounts → `users/`

## Structure
```
core/
├── authentik/       # SSO/Identity Provider (hwc.system.core.authentik.*)
│   ├── index.nix
│   └── parts/
│       └── config.nix
├── identity/        # User identity options (puid, pgid, user, group) - inlined
├── coredump.nix    # systemd-coredump retention caps
├── filesystem.nix   # Filesystem structure via tmpfiles
├── index.nix        # Core aggregator
├── packages.nix     # Base system packages
├── thermal.nix      # Thermal/power management
└── validation.nix   # Cross-cutting assertions
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-03-12: Inlined options.nix into index.nix for identity, polkit, session, shell; removed separate options.nix files
- 2026-03-26: Added Authentik SSO/Identity Provider module
- 2026-05-21: `login.nix` — strip NVIDIA PRIME env exports (`__NV_PRIME_RENDER_OFFLOAD`, `__GLX_VENDOR_LIBRARY_NAME`, `__VK_LAYER_NV_optimus`, `LIBVA_DRIVER_NAME=nvidia`) from greetd's `hyprStart`. Comment claimed "ignored if not applicable" — false: they actively route libglvnd/libva to NVIDIA on every child process, poisoning Hyprland's EGL state and crashing the compositor on WebGL DMA-BUF imports. NVIDIA offload is per-process via `gpu-launch` / `blender-offload` (companion to the system/gpu.nix fix the same day)
- 2026-05-21: `login.nix` — additionally pin `__EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json` in `hyprStart`. Without this, libglvnd enumerated both Mesa (priority 50) and NVIDIA (priority 10) ICDs, loading `libEGL_nvidia.so` + `nvidia-egl-*.so` into every process — visibly broke browser WebGL even after the prior env-strip commit (page-level "WebGL supported but disabled or unavailable" error). gpu-launch / blender-offload unset this var per-process to restore enumeration when NVIDIA EGL is actually wanted
- 2026-05-21: `login.nix` — reverted the `__EGL_VENDOR_LIBRARY_FILENAMES` pin from `hyprStart`. The "WebGL disabled in LibreWolf" symptom was actually a LibreWolf-specific FPP override (`privacy.fingerprintingProtection.overrides` including `WebGLRenderCapability` via `+AllTargets`), not an EGL ICD enumeration problem — confirmed by `nix-shell -p firefox` working on the same Mesa/NVIDIA setup. The earlier NVIDIA PRIME env strip in `hyprStart` (commit 5c30ef8d) stays — that fix was correct and unrelated
- 2026-06-01: `coredump.nix` — cap `/var/lib/systemd/coredump` at `MaxUse=500M` / `KeepFree=2G`. A llama-server crash loop on 2026-05-29 dropped 29 × ~146MB cores (~4GB) into the dir with no rotation; nothing reaped them and they sat for 2+ days until manual purge. systemd-coredump's defaults do not cap disk use.
- 2026-06-11: `nixld/` — new `guiLibs` flag in system core replaces the desktop/gaming-role X11/GTK/audio library list duplication (5519f201).
- 2026-06-09: Law 9/10 — convert remaining option-declaring leaf modules to directory modules (aea7be73). Pure relocation.
- 2026-06-02: `packages` — add the `sqlite` CLI to the base system bundle (fb75c028); also the `hwc` → `hwc-server` tailnet rename sweep (22bbbb48).
- 2026-06-02: `coredump.nix` — branch the cap on `nixosApiVersion`. The original used `systemd.coredump.extraConfig`, which exists only on stable (server/xps); unstable (laptop/kids) removed it via `mkRemovedOptionModule` in favour of `systemd.coredump.settings.Coredump`, so `nix flake check` hard-failed evaluating hwc-laptop. Now emits `extraConfig` on stable and `settings.Coredump` on unstable, mirroring the `services.resolved` split in `system/networking.nix`. Same MaxUse=500M / KeepFree=2G on both.
