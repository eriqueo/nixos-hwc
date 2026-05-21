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
