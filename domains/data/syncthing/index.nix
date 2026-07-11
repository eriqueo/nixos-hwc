# domains/data/syncthing/index.nix
#
# Bidirectional file sync between HWC machines via Syncthing over Tailscale.
#
# NAMESPACE: hwc.data.syncthing.*
#
# USED BY:
#   - machines/server/config.nix (sync with laptop)
#   - machines/laptop/config.nix (sync with server)

{ lib, config, pkgs, ... }:
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
          type = lib.mkOption {
            type = lib.types.enum [ "sendreceive" "sendonly" "receiveonly" ];
            default = "sendreceive";
            description = ''
              Syncthing folder direction. `sendonly` = this device NEVER accepts
              peer changes — use when this device is the canonical writer and its
              only Syncthing role is to feed read-only mirrors (e.g. a git-managed
              vault pushed to a receive-only phone). This is the structural guard
              that makes it impossible for a stale peer to clobber the source.
            '';
          };
          ignores = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = [ ".git" ".trash/" ".obsidian/workspace.json" ];
            description = ''
              Syncthing ignore patterns for this folder, written declaratively
              to <path>/.stignore. Syncthing never syncs .stignore between
              devices (it is per-device, local-only), so this is the ONLY way
              to guarantee a folder excludes paths like .git on every machine.
              A vault that is also a git repo MUST list .git here, or Syncthing
              will replicate .git internals and a stale peer can corrupt history.
              Empty (default) = no .stignore is managed for this folder.
            '';
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
      dataDir = config.hwc.paths.user.home;
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
          inherit (folder) path devices type;
          versioning = {
            type = folder.versioning.type;
            params.maxAge = folder.versioning.maxAge;
          };
        }) cfg.folders;
      };
    };

    #========================================================================
    # DECLARATIVE .stignore PROVISIONING
    #
    # Syncthing does NOT sync .stignore between devices, so a per-device file
    # is the only place .git (and other excludes) can be guaranteed. This
    # oneshot writes <path>/.stignore for every folder with non-empty
    # `ignores`, before syncthing starts, so the guard is in place on first
    # scan. Without this, a git-backed vault folder leaks .git into the sync
    # set and a stale peer can clobber committed history.
    #========================================================================
    systemd.services.syncthing-stignore =
      let
        owner = config.services.syncthing.user;
        foldersWithIgnores = lib.filterAttrs (_n: f: f.ignores != []) cfg.folders;
        writeOne = name: folder:
          let
            content = lib.concatStringsSep "\n" folder.ignores + "\n";
            src = pkgs.writeText "stignore-${name}" content;
            dest = "${folder.path}/.stignore";
          in ''
            if [ -d ${lib.escapeShellArg folder.path} ]; then
              install -D -m 0644 -o ${owner} -g users ${src} ${lib.escapeShellArg dest}
              echo "syncthing-stignore: wrote ${dest}"
            else
              echo "syncthing-stignore: ${folder.path} missing — skipped" >&2
            fi
          '';
      in
      lib.mkIf (foldersWithIgnores != {}) {
        description = "Provision declarative Syncthing .stignore files";
        wantedBy = [ "multi-user.target" ];
        before = [ "syncthing.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = lib.concatStringsSep "\n" (lib.mapAttrsToList writeOne foldersWithIgnores);
      };
  };
}
