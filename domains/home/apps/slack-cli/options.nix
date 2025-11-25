{ lib, ... }:

{
  options.hwc.home.apps.slackCli = {
    enable = lib.mkEnableOption "Terminal client for Slack (installed as 'slack-term')";
  };
}
