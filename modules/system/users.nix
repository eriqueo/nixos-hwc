{lib, ...}:
{
  options.hwc.system.users.enable = lib.mkEnableOption "Enable HWC users module";

  imports = [
    ./users/eric.nix
    ];
  config = {};
}
