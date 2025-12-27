{ lib, ... }:
{
  imports = [
    ../domains/server/native/media/index.nix
  ];

  config = {
    # Keep media defaults opt-in via profile
    hwc.server.native.media.enable = lib.mkDefault true;
  };
}
