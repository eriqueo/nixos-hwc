{ lib, ... }:

{
  options.hwc.home.apps.slack-cli = {
    enable = lib.mkEnableOption "Terminal client for Slack (installed as 'slack-term')";
  };
}
