{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.soularr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.soularr = {
    enable = lib.mkEnableOption "soularr container";
    image = lib.mkOption { type = lib.types.str; default = "docker.io/mrusse08/soularr:latest"; description = "Container image"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hwc.media.slskd.enable;
        message = "soularr requires slskd to be enabled";
      }
      {
        assertion = config.hwc.media.lidarr.enable;
        message = "soularr requires lidarr to be enabled";
      }
      {
        assertion = config.age.secrets ? lidarr-api-key && config.age.secrets ? slskd-api-key;
        message = "soularr requires agenix secrets: lidarr-api-key, slskd-api-key";
      }
    ];
  };
}
