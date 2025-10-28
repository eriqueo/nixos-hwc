{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.soularr;
in
{
  config = lib.mkIf cfg.enable {
    # System-lane support - actual container definition is in parts/config.nix
    # to avoid conflicts with the detailed implementation
    virtualisation.oci-containers.backend = "podman";
  };
}
