{ lib, ... }:

{
  options.hwc.system.core.identity = {
    puid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = ''
        Primary user ID for services and containers.
        This is the UID that all hwc-managed services run as.
      '';
    };

    pgid = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = ''
        Primary group ID for services and containers.
        This should be the `users` group GID (100), NOT the user's private group.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = ''
        Primary username for services and containers.
        This is the username that all hwc-managed services run as.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = ''
        Primary group name for services and containers.
        This should be the shared `users` group, NOT the user's private group.
      '';
    };
  };
}
