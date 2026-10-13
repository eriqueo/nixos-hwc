# domains/home/apps/vectorcraft/index.nix
# VectorCraft — open-source vector editor in the Illustrator mould, from our fork
# (github:eriqueo/vectorcraft, branch hwc/main), being tailored for GIS map
# finishing. The fork owns the build (its flake.nix); this module only installs
# it. Ship a change: push to hwc/main → `nix flake update vectorcraft` → rebuild.

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.home.apps.vectorcraft;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.vectorcraft = {
    enable = lib.mkEnableOption "VectorCraft vector editor (HWC fork)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Brings vectorcraft, vectorcraft-cli, the launcher entry, icons and the
    # SVG/PDF MIME registration.
    home.packages = [ inputs.vectorcraft.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  };
}
