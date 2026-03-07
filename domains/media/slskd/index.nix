{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.slskd;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.slskd = {
    enable = lib.mkEnableOption "slskd container";
    image = lib.mkOption { type = lib.types.str; default = "slskd/slskd:0.21.4"; description = "Container image (pinned for stability)"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
    directories = {
      downloads = lib.mkOption { type = lib.types.str; default = "/downloads/music"; description = "Completed downloads directory"; };
      incomplete = lib.mkOption { type = lib.types.str; default = "/downloads/incomplete"; description = "Incomplete downloads directory"; };
    };
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
        assertion = config.hwc.paths ? media && config.hwc.paths ? hot;
        message = "slskd requires hwc.paths.media and hwc.paths.hot to be defined";
      }
      {
        assertion = config.age.secrets ? slskd-web-username
                  && config.age.secrets ? slskd-web-password
                  && config.age.secrets ? slskd-soulseek-username
                  && config.age.secrets ? slskd-soulseek-password
                  && config.age.secrets ? slskd-api-key;
        message = "slskd requires agenix secrets: slskd-web-username, slskd-web-password, slskd-soulseek-username, slskd-soulseek-password, slskd-api-key";
      }
    ];
  };
}
