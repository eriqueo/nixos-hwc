{ lib, ... }:
{
  imports = [
    ../domains/server/native/business/index.nix
  ];

  config = {
    # Placeholder: enable business feature flag when this profile is used
    hwc.server.native.business.enable = lib.mkDefault true;
    hwc.server.containers.paperless.enable = lib.mkDefault true;
    hwc.server.databases.redis.enable = lib.mkDefault true;
  };
}
