{ lib, pkgs, ... }:

let
  # IMPORTANT: Same hybrid-GPU constraint as chromium-hwc — on this laptop
  # Hyprland renders on the Intel iGPU, so Firefox must too. Cross-GPU
  # DMA-BUF imports fail with EGL_BAD_MATCH inside Mesa and can take down
  # the compositor (see parts/launcher.nix in domains/home/apps/chromium
  # for the full history). We therefore strip any inherited NVIDIA PRIME
  # env vars and pin VA-API to the Intel iHD driver when present.
  #
  # Firefox hardware accel is driven primarily by about:config prefs
  # (see parts/appearance.nix: gfx.webrender.all, media.ffmpeg.vaapi,
  # widget.dmabuf, etc.). This wrapper just ensures the *environment* the
  # browser inherits doesn't route it onto the wrong render node.

  launcher = pkgs.writeShellScriptBin "firefox-hwc" ''
    set -u

    # Strip NVIDIA PRIME / GLX vendor overrides so libglvnd doesn't try
    # the NVIDIA EGL vendor on a Wayland session driven by Intel Mesa.
    unset __NV_PRIME_RENDER_OFFLOAD
    unset __GLX_VENDOR_LIBRARY_NAME
    unset __VK_LAYER_NV_optimus
    unset __EGL_VENDOR_LIBRARY_FILENAMES

    # Wayland + dbus remote (helps portal integration and single-instance).
    export MOZ_ENABLE_WAYLAND=1
    export MOZ_DBUS_REMOTE=1

    # Force libva onto Intel iHD when an Intel iGPU is present AND the
    # driver is installed. Without this, a system-wide LIBVA_DRIVER_NAME=
    # nvidia (typical on hybrid laptops where the dGPU is the nominal type)
    # makes Firefox's HW video decode fail because we render on Intel.
    # NO-OP on machines without an Intel iGPU or without the iHD driver.
    intel_present=0
    for n in /dev/dri/renderD*; do
      v=$(cat "/sys/class/drm/$(basename "$n")/device/vendor" 2>/dev/null || true)
      if [ "$v" = "0x8086" ]; then
        intel_present=1
        break
      fi
    done
    if [ "$intel_present" = "1" ] && \
       [ -r /run/opengl-driver/lib/dri/iHD_drv_video.so ]; then
      export LIBVA_DRIVER_NAME=iHD
    fi

    exec ${pkgs.firefox}/bin/firefox "$@"
  '';
in
{
  packages = [ launcher ];
}
