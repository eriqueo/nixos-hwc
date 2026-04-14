{ config, lib, pkgs, osConfig ? {}, ...}:
let
  mail = config.hwc.mail or {};
  vals = lib.attrValues (mail.accounts or {});
  needs = lib.any (a: a.type == "proton-bridge") vals;
  enabled = (mail.enable or false) && needs;

  br = mail.bridge or {};
  runtime = import ./parts/runtime.nix { inherit lib pkgs br; };
  files = import ./parts/files.nix { inherit lib br; };
  service = import ./parts/service.nix { inherit lib pkgs br runtime; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.mail.bridge = {
    enable = lib.mkEnableOption "Proton Mail Bridge";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.protonmail-bridge;
    };
    logLevel = lib.mkOption { type = lib.types.str; default = "warn"; };
    extraArgs = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    environment = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
    setupScript = {
      enable = lib.mkEnableOption "helper script" // { default = true; };
    };
    ensureConfigDir = lib.mkOption { type = lib.types.bool; default = true; };
    restartSec = lib.mkOption { type = lib.types.int; default = 5; };
    keychain = {
      helper = lib.mkOption {
        type = lib.types.str;
        default = "pass";
        description = "Keychain helper to use. 'pass' is more reliable than gnome-keyring for headless operation.";
      };
      disableTest = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable keychain testing to prevent hangs during startup.";
      };
    };
  };
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled (lib.mkMerge [
    { home.packages = [ (br.package or pkgs.protonmail-bridge) ]; }
    files
    service

    #==========================================================================
    # VALIDATION
    #==========================================================================
    {
      assertions = [
        {
          assertion = (br.keychain.helper == "pass") -> (builtins.elem pkgs.pass config.home.packages);
          message = "hwc.mail.bridge.keychain.helper is set to 'pass' but pass package is not available";
        }
      ];
    }
  ]);
}