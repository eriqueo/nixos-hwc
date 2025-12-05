{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.soularr;
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
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hwc.services.containers.slskd.enable;
        message = "soularr requires slskd to be enabled";
      }
      {
        assertion = config.hwc.services.containers.lidarr.enable;
        message = "soularr requires lidarr to be enabled";
      }
      {
        assertion = config.age.secrets ? lidarr-api-key && config.age.secrets ? slskd-api-key;
        message = "soularr requires agenix secrets: lidarr-api-key, slskd-api-key";
      }
    ];
  };
}
