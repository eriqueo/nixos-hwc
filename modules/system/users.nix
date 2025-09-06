{lib, ...}:
{
  options.hwc.system.users = {
    enable = lib.mkEnableOption "Enable HWC users module";
    emergencyEnable = lib.mkEnableOption "Enable emergency root access during migration";
  };

  imports = [
    ./users/eric.nix
    ];
  config = {};
}
