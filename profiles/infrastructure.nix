# profiles/infrastructure.nix
{ lib, ... }:
{
  imports = [
    ../domains/infrastructure/index.nix
  ];

  hwc.infrastructure.hardware.gpu.enable = lib.mkDefault true;
  hwc.infrastructure.hardware.peripherals.enable = lib.mkDefault true;
  hwc.infrastructure.virtualization.enable = lib.mkDefault true;
  hwc.infrastructure.winapps.enable = lib.mkDefault false;

  hwc.infrastructure.storage.hot.enable = lib.mkDefault true;
  hwc.infrastructure.storage.media.enable = lib.mkDefault true;
  hwc.infrastructure.storage.backup.enable = lib.mkDefault true;
}
