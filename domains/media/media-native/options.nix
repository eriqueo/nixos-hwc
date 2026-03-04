# domains/server/media/options.nix
#
# Feature toggle for server media defaults (storage scaffolding, etc.)

{ lib, ... }:
{
  options.hwc.media.media = {
    enable = lib.mkEnableOption "media services defaults (storage scaffolding)";
  };
}
