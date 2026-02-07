{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.mail.abook = {
    enable = lib.mkEnableOption "address book functionality";
  };
}