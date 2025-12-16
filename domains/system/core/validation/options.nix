# domains/system/core/validation/options.nix
# Toggle for permission validation service

{ lib, ... }:
{
  options.hwc.system.core.validation = {
    enable = lib.mkEnableOption "permission model validation service" // {
      default = true;
    };
  };
}
