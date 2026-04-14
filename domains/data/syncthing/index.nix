# domains/data/syncthing/index.nix
#
# Bidirectional file sync between HWC machines via Syncthing over Tailscale.
#
# NAMESPACE: hwc.data.syncthing.*
#
# USED BY:
#   - machines/server/config.nix (sync with laptop)
#   - machines/laptop/config.nix (sync with server)

{ lib, config, ... }:
let
  cfg = config.hwc.data.syncthing;
in
{
  # OPTIONS
  options.hwc.data.syncthing = {
    enable = lib.mkEnableOption "Syncthing bidirectional file sync";

    devices = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Syncthing device ID";
          };
          addresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Device addresses (e.g., tcp://100.x.x.x:22000). Empty = auto-discovery.";
          };
        };
      });
      default = {};
      description = "Peer devices to sync with";
    };

    folders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Local path for this folder";
          };
          devices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Device names to sync this folder with";
          };
          versioning = {
            type = lib.mkOption {
              type = lib.types.str;
              default = "staggered";
              description = "Versioning strategy";
            };
            maxAge = lib.mkOption {
              type = lib.types.str;
              default = "2592000";
              description = "Max age for versioned files (seconds). Default 30 days.";
            };
          };
        };
      });
      default = {};
      description = "Folders to sync";
    };

    globalAnnounce = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Syncthing global announce servers (false = Tailscale only, no cloud relay)";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "eric";
      dataDir = "/home/eric";
      openDefaultPorts = true;
      overrideDevices = true;
      overrideFolders = true;

      settings = {
        options.globalAnnounceEnabled = cfg.globalAnnounce;

        devices = lib.mapAttrs (_name: dev:
          { inherit (dev) id; }
          // lib.optionalAttrs (dev.addresses != []) { inherit (dev) addresses; }
        ) cfg.devices;

        folders = lib.mapAttrs (_name: folder: {
          inherit (folder) path devices;
          versioning = {
            type = folder.versioning.type;
            params.maxAge = folder.versioning.maxAge;
          };
        }) cfg.folders;
      };
    };
  };
}
