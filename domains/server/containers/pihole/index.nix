# domains/server/containers/pihole/index.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.pihole;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Add helpful system packages for Pi-hole management
    environment.systemPackages = with pkgs; [
      podman-compose
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Validation logic in sys.nix per Charter pattern
}
