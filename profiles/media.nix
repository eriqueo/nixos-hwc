{ lib, ... }:
{
  imports = [
    ../domains/server/native/media/index.nix
  ];

  config = {
    # Keep media defaults opt-in via profile
    hwc.server.media.enable = lib.mkDefault true;
  };
}
