{ lib, ... }:
{
  options.hwc.filesystem.enable = lib.mkEnableOption "Enable centralized filesystem wiring";

  options.hwc.filesystem.paths = {
    hot = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    cold = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };

    user = {
      home = lib.mkOption { type = lib.types.str; default = "/home/eric"; };
      inbox = lib.mkOption { type = lib.types.str; default = "/home/eric/Inbox"; };
      work  = lib.mkOption { type = lib.types.str; default = "/home/eric/Work"; };
    };

    business.root = lib.mkOption { type = lib.types.str; default = "/opt/business"; };
    ai.root       = lib.mkOption { type = lib.types.str; default = "/opt/ai"; };

    state = lib.mkOption { type = lib.types.str; default = "/var/lib/hwc"; };
    cache = lib.mkOption { type = lib.types.str; default = "/var/cache/hwc"; };
    logs  = lib.mkOption { type = lib.types.str; default = "/var/log/hwc"; };
    temp  = lib.mkOption { type = lib.types.str; default = "/var/tmp/hwc"; };

    security = {
      secrets    = lib.mkOption { type = lib.types.str; default = "/var/lib/hwc/secrets"; };
      sopsAgeKey = lib.mkOption { type = lib.types.str; default = "/var/lib/sops/age/keys.txt"; };
    };
  };
}
