{ lib, ... }:

{
  options.hwc.home.apps.n8n = {
    enable = lib.mkEnableOption "Free and source-available fair-code licensed workflow automation tool";
  };
}
