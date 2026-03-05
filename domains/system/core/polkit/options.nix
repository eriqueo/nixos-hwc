# domains/system/core/polkit/options.nix
{ lib, ... }:
{
  options.hwc.system.services.polkit = {
    enable = lib.mkEnableOption "polkit directory management";
    createMissingDirectories = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create missing polkit rule directories to silence warnings";
    };
  };
}
