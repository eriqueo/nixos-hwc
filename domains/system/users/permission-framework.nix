# domains/system/users/permission-framework.nix
#
# HWC Permission Management Framework
# Provides systematic user/group management and secret access patterns
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.permissions;
in
{
  options.hwc.system.permissions = {
    enable = lib.mkEnableOption "HWC permission management framework";

    # Service user management
    serviceUsers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Description of the service user";
          };

          groups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional groups for the service user";
          };

          homeDirectory = lib.mkOption {
            type = lib.types.str;
            description = "Home directory for the service user";
          };

          createHome = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to create the home directory";
          };

          secretAccess = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "List of secrets this service user should access";
          };
        };
      });
      default = {};
      description = "Service users to create with permission management";
    };

    # Shared groups for resource coordination
    sharedGroups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Description of the shared group";
          };

          members = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Users that should be members of this group";
          };
        };
      });
      default = {};
      description = "Shared groups for cross-service coordination";
    };

    # Directory management with proper permissions
    managedDirectories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          owner = lib.mkOption {
            type = lib.types.str;
            description = "Directory owner";
          };

          group = lib.mkOption {
            type = lib.types.str;
            description = "Directory group";
          };

          mode = lib.mkOption {
            type = lib.types.str;
            default = "0755";
            description = "Directory permissions";
          };

          recursive = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Apply permissions recursively";
          };
        };
      });
      default = {};
      description = "Directories to manage with proper ownership/permissions";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create shared groups
    users.groups = lib.mapAttrs (name: groupCfg: {
      members = groupCfg.members;
    }) cfg.sharedGroups;

    # Create service users
    users.users = lib.mapAttrs (name: userCfg: {
      isSystemUser = true;
      description = userCfg.description;
      home = userCfg.homeDirectory;
      createHome = userCfg.createHome;
      group = name;  # Each service user gets its own primary group
      extraGroups = userCfg.groups;
    }) cfg.serviceUsers;

    # Create primary groups for service users
    users.groups = users.groups // (lib.mapAttrs (name: userCfg: {}) cfg.serviceUsers);

    # Manage directory permissions
    systemd.tmpfiles.rules = lib.mapAttrsToList (path: dirCfg:
      "d ${path} ${dirCfg.mode} ${dirCfg.owner} ${dirCfg.group} -"
    ) cfg.managedDirectories;

    # Runtime permission validation service
    systemd.services.hwc-permission-validator = {
      description = "HWC Permission Framework Validator";
      wantedBy = [ "multi-user.target" ];
      after = [ "agenix.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "validate-permissions" ''
          set -eu

          # Validate secret access for service users
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (userName: userCfg:
            lib.concatStringsSep "\n" (map (secretName: ''
              if [[ -f "/run/agenix/${secretName}" ]]; then
                if ! sudo -u ${userName} test -r "/run/agenix/${secretName}" 2>/dev/null; then
                  echo "WARNING: User ${userName} cannot read secret ${secretName}"
                fi
              fi
            '') userCfg.secretAccess)
          ) cfg.serviceUsers)}

          # Validate managed directory permissions
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: dirCfg: ''
            if [[ -d "${path}" ]]; then
              OWNER=$(stat -c '%U' "${path}")
              GROUP=$(stat -c '%G' "${path}")
              if [[ "$OWNER" != "${dirCfg.owner}" ]] || [[ "$GROUP" != "${dirCfg.group}" ]]; then
                echo "WARNING: Directory ${path} has incorrect ownership: $OWNER:$GROUP (expected ${dirCfg.owner}:${dirCfg.group})"
              fi
            fi
          '') cfg.managedDirectories)}

          echo "HWC permission validation complete"
        '';
      };
    };

    # Assertions for permission framework
    assertions = [
      {
        assertion = cfg.enable -> config.hwc.secrets.enable;
        message = "HWC permission framework requires secrets to be enabled";
      }
    ] ++ (lib.mapAttrsToList (userName: userCfg:
      {
        assertion = lib.all (secretName:
          config.hwc.secrets.api ? ${secretName} &&
          config.hwc.secrets.api.${secretName} != null
        ) userCfg.secretAccess;
        message = "Service user ${userName} references undefined secrets: ${lib.concatStringsSep ", " userCfg.secretAccess}";
      }
    ) cfg.serviceUsers);
  };
}