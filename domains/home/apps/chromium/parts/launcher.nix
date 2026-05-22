{ lib, pkgs, ... }:

let
  # Flags shared by both GPU paths. --enable-features is intentionally
  # NOT here — Chromium misbehaves when it's passed twice, so we compose
  # one final --enable-features arg below.
  commonFlags = [
    "--ozone-platform=wayland"
    "--disable-features=UseChromeOSDirectVideoDecoder"
    "--enable-gpu-rasterization"
    "--enable-zero-copy"
  ];

  commonFeatures = [
    "VaapiVideoDecoder"
    "VaapiVideoEncoder"
    "VaapiIgnoreDriverChecks"
    "WaylandWindowDecorations"
  ];

  joinFeatures = fs: "--enable-features=" + lib.concatStringsSep "," fs;

  # IMPORTANT: On hybrid-GPU Wayland systems, Chromium MUST render on the
  # same GPU as the compositor. Cross-GPU DMA-BUF imports fail with
  # EGL_BAD_MATCH inside Mesa and abort the compositor (observed:
  # Hyprland/Aquamarine crash via dri_create_fence_fd when chromium was
  # forced onto the NVIDIA render node while Hyprland ran on Intel).
  #
  # Hyprland here runs on Intel Mesa, so chromium also stays on Intel.
  # ANGLE-on-OpenGL gives us reliable WebGL/Canvas/Video accel via the
  # Intel iGPU and avoids the EGL_BAD_MATCH spam the previous
  # ANGLE-on-Vulkan config produced. We do NOT use --use-angle=vulkan
  # (incompatible with --ozone-platform=wayland) and we do NOT pass
  # --render-node-override or override __EGL_VENDOR_LIBRARY_FILENAMES,
  # because both can route chromium to the dGPU and crash the compositor.
  baseFlags = commonFlags ++ [
    (joinFeatures commonFeatures)
    "--use-gl=angle"
    "--use-angle=gl"
  ];

  # gpu-launch may export PRIME GLX env vars in performance mode. Those
  # only affect GLX clients (e.g. games) and are inert for chromium's EGL
  # pipeline, but we strip them explicitly here so a stray inherited
  # __NV_PRIME_RENDER_OFFLOAD=1 cannot cause libglvnd to attempt the
  # NVIDIA EGL vendor and trigger the cross-GPU crash described above.
  launcher = pkgs.writeShellScriptBin "chromium-hwc" ''
    set -u

    unset __NV_PRIME_RENDER_OFFLOAD
    unset __GLX_VENDOR_LIBRARY_NAME
    unset __VK_LAYER_NV_optimus
    unset __EGL_VENDOR_LIBRARY_FILENAMES

    # If an Intel iGPU is present AND the iHD VA-API driver is installed,
    # force chromium's libva to use it. Without this, a system-wide
    # LIBVA_DRIVER_NAME=nvidia (set on hybrid laptops where the dGPU is the
    # nominal type) makes chromium's HW video decode fail because chromium
    # renders on the Intel render node — causing CPU-bound fallback decode.
    # This block is a NO-OP on machines without an Intel iGPU or without the
    # iHD driver installed, so the same wrapper is safe on other hosts.
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

    exec chromium ${lib.escapeShellArgs baseFlags} "$@"
  '';
in
{
  packages = [ launcher ];
}
