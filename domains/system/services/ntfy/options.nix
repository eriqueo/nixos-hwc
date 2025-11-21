# domains/system/services/ntfy/options.nix
# Centralized ntfy notification system for cross-machine and cross-service notifications
{ lib, ... }:

{
  options.hwc.system.services.ntfy = {
    enable = lib.mkEnableOption "Enable ntfy notification system";

    #==========================================================================
    # SERVER CONFIGURATION
    #==========================================================================
    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = "ntfy server URL (public or self-hosted)";
    };

    defaultTopic = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "hwc-alerts";
      description = "Default topic to send notifications to when not explicitly specified";
    };

    #==========================================================================
    # NOTIFICATION FORMATTING
    #==========================================================================
    defaultTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "hwc" "nixos" ];
      description = "Default tags to apply to all notifications";
    };

    defaultPriority = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.int lib.types.str);
      default = null;
      example = 3;
      description = "Default priority level (1=min, 3=default, 5=max)";
    };

    hostTag = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically include hostname as a tag in all notifications";
    };

    #==========================================================================
    # AUTHENTICATION
    #==========================================================================
    auth = {
      enable = lib.mkEnableOption "Enable authentication for ntfy";

      method = lib.mkOption {
        type = lib.types.enum [ "basic" "token" ];
        default = "token";
        description = "Authentication method: basic (username/password) or token (Bearer token)";
      };

      userFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/ntfy-user";
        description = "Path to file containing username (for basic auth)";
      };

      passFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/ntfy-pass";
        description = "Path to file containing password (for basic auth)";
      };

      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/ntfy-token";
        description = "Path to file containing authentication token (for token auth)";
      };
    };
  };
}
