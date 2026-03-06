{ config, lib, ... }:

let
  cfg = config.hwc.system.core.identity;

  # Verify the user exists in system configuration
  userExists = config.users.users ? ${cfg.user};

  # Get actual UID/GID from user configuration if user exists
  actualUser = if userExists then config.users.users.${cfg.user} else null;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
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

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {
    # Identity options are pure configuration - no services to enable
    # Values are used by other modules via config.hwc.system.core.identity.*
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = [
    # Only validate UID consistency if user exists and has UID configured
    {
      assertion = !userExists || actualUser.uid == null || actualUser.uid == cfg.puid;
      message = ''
        hwc.system.core.identity.puid (${toString cfg.puid}) does not match
        actual UID of user "${cfg.user}" (${toString actualUser.uid}).
        These must be consistent. Update either the user's UID or hwc.system.core.identity.puid.
      '';
    }
    # Enforce Charter v10.3 Law 4: PGID must be 100
    {
      assertion = cfg.pgid == 100;
      message = ''
        hwc.system.core.identity.pgid must be 100 (the `users` group GID).
        Current value: ${toString cfg.pgid}

        This is a Charter v10.3 Law 4 requirement. Services must run with PGID=100
        to ensure proper file permissions across the system.
      '';
    }
    # Enforce Charter v10.3 Law 4: group must be "users"
    {
      assertion = cfg.group == "users";
      message = ''
        hwc.system.core.identity.group must be "users" (the shared group).
        Current value: ${cfg.group}

        This is a Charter v10.3 Law 4 requirement. Services must run with group="users"
        to ensure proper file permissions across the system.
      '';
    }
  ];
}
