{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.slack = {
    enable = lib.mkEnableOption "Desktop client for Slack";
  };
}