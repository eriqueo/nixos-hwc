{ lib, ... }:

{
  options.hwc.features.business = {
    enable = lib.mkEnableOption "business services (databases, APIs)";
  };
}
