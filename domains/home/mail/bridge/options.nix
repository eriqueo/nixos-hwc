{ lib, ... }:
with lib;
{
  options.hwc.home.mail.bridge = {
    enable = mkEnableOption "Headless Proton Mail Bridge service";
    logLevel = mkOption { type = types.enum [ "error" "warn" "info" "debug" ]; default = "warn"; };
    extraArgs = mkOption { type = types.listOf types.str; default = []; };
    environment = mkOption { type = types.attrsOf types.str; default = { }; };
  };
}
