# profiles/infrastructure.nix
{
  imports = [
    ../domains/infrastructure/index.nix
  ];

  hwc.infrastructure.hardware.gpu.enable = false;
  hwc.infrastructure.hardware.peripherals.enable = false;
  hwc.infrastructure.virtualization.enable = false;

  hwc.infrastructure.storage.hot.enable = false;
  hwc.infrastructure.storage.media.enable = false;
  hwc.infrastructure.storage.backup.enable = false;
}
