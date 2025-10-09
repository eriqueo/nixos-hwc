{ lib, pkgs, config, ... }:
with lib; {
  options.hwc.home.mail.bridge = {
    enable = mkEnableOption "Proton Mail Bridge";
    package = mkOption {
      type = types.package;
      default = pkgs.protonmail-bridge.overrideAttrs (old: {
        # Pin to version that was working 3 weeks ago
        # This removes libsecret build dependency which causes keychain hangs
        buildInputs = [];
      });
    };
    logLevel = mkOption { type = types.str; default = "warn"; };
    extraArgs = mkOption { type = types.listOf types.str; default = []; };
    environment = mkOption { type = types.attrsOf types.str; default = {}; };
    setupScript = {
      enable = mkEnableOption "helper script" // { default = true; };
    };
    ensureConfigDir = mkOption { type = types.bool; default = true; };
    restartSec = mkOption { type = types.int; default = 5; };
  };
}
