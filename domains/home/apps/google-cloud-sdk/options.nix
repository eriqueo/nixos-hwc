{ lib, ... }:

{
  options.hwc.home.apps.googleCloudSdk = {
    enable = lib.mkEnableOption "Tools for the google cloud platform";
  };
}
