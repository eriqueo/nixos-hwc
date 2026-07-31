# domains/home/apps/blender/parts/package.nix
#
# Blender pinned from the OFFICIAL upstream release binary (autoPatchelf'd),
# mirroring the codex precedent (domains/home/apps/codex/parts/package.nix).
# NOT the module default — machines that want it set:
#   hwc.home.apps.blender.package = pkgs.callPackage <this file> { };
#
# WHY a prebuilt binary instead of pkgs.blender:
#   cache.nixos.org only builds the DEFAULT blender (cudaSupport = false). This
#   module builds `pkgs.blender.override { cudaSupport = true; }` on nvidia hosts,
#   which Hydra never builds — so every nixpkgs bump triggers a ~30 min from-source
#   compile of blender AND its CUDA-context deps (embree, OpenImageDenoise, OSL…).
#   Upstream's tarball is a self-contained portable build: it BUNDLES embree, OIDN,
#   OpenEXR, OSL, OpenVDB, USD, TBB, MaterialX (see lib/), so it also sidesteps the
#   openimagedenoise CUDA breakage that overlays/openimagedenoise-cuda.nix works
#   around — and it ships the Cycles GPU kernels (kernel_compute_75.ptx for CUDA,
#   kernel_optix.ptx for OptiX), so GPU rendering is real, not CPU fallback.
#
# GPU wiring (the part that makes this correct on NixOS):
#   Cycles dlopen()s libcuda.so.1 / libnvoptix.so.1 / libnvrtc.so — they are NOT in
#   DT_NEEDED, so autoPatchelfHook cannot see them and they must come from the
#   running driver at /run/opengl-driver/lib. Same for the GL/EGL/Vulkan/wayland
#   stack. The wrapper puts the driver path FIRST (repo precedent: retroarch,
#   jellyfin-native, frigate all use LD_LIBRARY_PATH=/run/opengl-driver/lib), then
#   the nixpkgs libs for the remaining dlopen'd sonames.

{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, libglvnd
, vulkan-loader
, libxkbcommon
, wayland
, libdecor
, dbus
, alsa-lib
, libpulseaudio
, fontconfig
, freetype
, zlib
, ncurses
, libuuid
, libdrm
, libx11
, libxext
, libxfixes
, libxi
, libxrender
, libice
, libsm
, libxt
, libxrandr
, libxcursor
}:

let
  version = "5.2.0";

  # dlopen'd at runtime (not DT_NEEDED) — must be on LD_LIBRARY_PATH, not just RPATH.
  runtimeLibs = [
    libglvnd        # libGL.so.1 / libEGL.so.1 / libGLX.so.1 / libOpenGL.so.0
    vulkan-loader   # libvulkan.so.1 (ICDs resolved from /run/opengl-driver/share/vulkan)
    libxkbcommon
    wayland         # libwayland-client.so.0 / libwayland-cursor.so — Hyprland session
    libdecor        # client-side decorations under wayland
    dbus
    alsa-lib        # libasound.so.2
    libpulseaudio   # libpulse.so.0
    fontconfig
    freetype
    zlib
  ];
in
stdenv.mkDerivation {
  pname = "blender";
  inherit version;

  src = fetchurl {
    # One producer: the URL is derived from `version`, never restated.
    url = "https://download.blender.org/release/Blender${lib.versions.majorMinor version}/blender-${version}-linux-x64.tar.xz";
    hash = "sha256-lvbBgaMPSVBgeDnchNQqNUslDYoCMbCYtZt7xpw1HEg=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  # DT_NEEDED entries autoPatchelfHook must resolve. Everything else the binary
  # needs is bundled in lib/ (autoPatchelf finds those inside the output itself).
  # Derived by scanning DT_NEEDED across every ELF in the tarball and subtracting
  # the sonames it bundles itself — not by fixing one autoPatchelf error at a time.
  buildInputs = [
    stdenv.cc.cc.lib   # libstdc++.so.6, libgcc_s.so.1
    libxkbcommon
    vulkan-loader
    ncurses            # libncursesw.so.6 / libpanelw.so.6 / libtinfo.so.6
    libuuid            # libuuid.so.1
    libdrm             # bundled libSDL3
    libx11
    libxext
    libxfixes
    libxi
    libxrender
    libice             # bundled USD (pxr) python modules
    libsm              # bundled USD (pxr) python modules
    libxt
    libxrandr          # bundled libSDL3
    libxcursor         # bundled libSDL3
  ] ++ runtimeLibs;

  # AMD (HIP/ROCm) and Intel (oneAPI/OpenCL) backends ship in the same tarball and
  # reference vendor libs we deliberately do not provide on an nvidia host. They are
  # dlopen'd only when that backend is selected, so unresolved is correct here.
  autoPatchelfIgnoreMissingDeps = [
    "libamdhip64.so.*"
    "libatiadlxx.so"
    "libOpenCL.so*"
    "libjack.so.0"
    # Intel oneAPI / Level Zero — the Cycles oneAPI + OIDN SYCL backends, for Intel
    # Arc GPUs. This is an NVIDIA host using the CUDA/OptiX backends, so leaving the
    # Intel loader unresolved is correct; those .so's are only opened if you pick that device.
    "libze_loader.so.1"
    # Bundled SDL3 optionals: GLES1 (legacy, superseded by the GLESv2 libglvnd ships)
    # and Steam integration, neither of which Blender uses here.
    "libGLES_CM.so.1"
    "libsteam_api.so"
    # Provided by the running NVIDIA driver via /run/opengl-driver/lib (see wrapper),
    # never by a build input — the store must not pin a driver version.
    "libcuda.so.1"
  ];

  installPhase = ''
    runHook preInstall

    # Keep upstream's layout intact — blender resolves its datafiles (5.2/…) and
    # bundled lib/ relative to the real executable, so the tree must stay together.
    install -d "$out/share/blender"
    cp -r . "$out/share/blender/"

    install -d "$out/bin"
    makeWrapper "$out/share/blender/blender" "$out/bin/blender" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}"
    makeWrapper "$out/share/blender/blender-thumbnailer" "$out/bin/blender-thumbnailer" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}"

    # Desktop integration
    install -Dm644 blender.desktop "$out/share/applications/blender.desktop"
    install -Dm644 blender.svg "$out/share/icons/hicolor/scalable/apps/blender.svg"
    substituteInPlace "$out/share/applications/blender.desktop" \
      --replace-fail "Exec=blender" "Exec=$out/bin/blender"

    runHook postInstall
  '';

  meta = {
    description = "3D creation suite — official upstream binary with CUDA/OptiX Cycles kernels";
    homepage = "https://www.blender.org/";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "blender";
  };
}
