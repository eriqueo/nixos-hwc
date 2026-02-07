{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.google-cloud-sdk = {
    enable = lib.mkEnableOption "Tools for the google cloud platform";
  };
}