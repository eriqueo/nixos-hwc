{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.gluetun;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # VPN secrets are declared in domains/secrets/declarations/infrastructure.nix
    # Accessible via config.age.secrets.vpn-username.path and config.age.secrets.vpn-password.path

    # Validation assertions
    assertions = [
      {
        assertion = config.hwc.secrets.enable;
        message = "Gluetun requires hwc.secrets.enable = true for VPN credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Gluetun requires Podman as OCI container backend";
      }
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Validation logic above within config block
}
