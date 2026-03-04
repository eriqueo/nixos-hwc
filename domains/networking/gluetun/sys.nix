{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.networking.gluetun;
in
{
  config = lib.mkIf cfg.enable {
    # System-lane support - actual container definition is in parts/config.nix
    # to avoid conflicts with the detailed implementation
    virtualisation.oci-containers.backend = "podman";
  };
}
