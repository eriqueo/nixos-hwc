# overlays/openimagedenoise-cuda.nix
#
# TEMPORARY (tracked) — upstream nixpkgs breakage on the 2026-07-25 unstable rev
# (624af665), same batch as overlays/pandas-stubs.nix.
#
# blender is built as `pkgs.blender.override { cudaSupport = true; }` on nvidia
# machines (domains/home/apps/blender), which propagates config.cudaSupport = true
# into its dependency closure. That flips openimagedenoise's OIDN_DEVICE_CUDA
# device ON — and on this rev the CUDA device fails to *configure* (a find_package
# / CUDA-toolkit mismatch at CMakeLists.txt:23), which fails openimagedenoise,
# then blender-gpu, then the whole system toplevel. The CPU device builds fine.
#
# Fix: force OIDN_DEVICE_CUDA=FALSE regardless of config.cudaSupport, so
# openimagedenoise builds CPU-only. Blender keeps CUDA *rendering* (Cycles); it
# just denoises on the CPU device instead of the GPU one. We drop any existing
# OIDN_DEVICE_CUDA flag and append FALSE last so it wins over the config-driven
# TRUE that the cuda context injects. Verified: builds under config.cudaSupport=true.
#
# REMOVE WHEN: openimagedenoise's CUDA device configures again on the pinned
# nixpkgs. Check by building blender with cudaSupport and this overlay removed.
final: prev: {
  openimagedenoise = prev.openimagedenoise.overrideAttrs (o: {
    cmakeFlags =
      (builtins.filter (x: !(final.lib.hasInfix "OIDN_DEVICE_CUDA" x)) (o.cmakeFlags or [ ]))
      ++ [ "-DOIDN_DEVICE_CUDA:BOOL=FALSE" ];
  });
}
