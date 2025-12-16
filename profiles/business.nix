{ lib, ... }:
{
  imports = [
    ../domains/server/native/business/index.nix
  ];

  config = {
    # Placeholder: enable business feature flag when this profile is used
    hwc.server.business.enable = lib.mkDefault true;
  };
}
