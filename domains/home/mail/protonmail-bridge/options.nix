{ lib, ... }:
{
  options.hwc.home.mail.protonmailBridge = {
    enable = lib.mkEnableOption "Proton Mail Bridge system service";
  };
}