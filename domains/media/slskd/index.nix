{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.slskd;
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
