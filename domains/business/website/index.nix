# domains/business/website/index.nix
#
# Heartwood CMS Dashboard — content management for heartwoodcraft.me
# Node.js REST API + vanilla JS frontend, manages 11ty site content
#
# NAMESPACE: hwc.business.website.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - agenix secrets: cms-api-key, hostinger-sftp
#   - heartwood-site repo at /home/eric/.nixos/domains/business/website/heartwood-site/

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.website;
  paths = config.hwc.paths;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.business.website = {
    enable = lib.mkEnableOption "Heartwood CMS Dashboard (content management for heartwoodcraft.me)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8095;
      description = "Port for Heartwood CMS API (binds to 127.0.0.1)";
    };

    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/heartwood-cms";
      description = "Path to the Heartwood CMS application directory";
    };

    siteDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/.nixos/domains/business/website/heartwood-site";
      description = "Path to the heartwood-site 11ty repo (content source)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    #--------------------------------------------------------------------------
    # HEARTWOOD CMS SERVICE
    #--------------------------------------------------------------------------
    systemd.services.heartwood-cms = {
      description = "Heartwood CMS Dashboard";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/server.js";
        WorkingDirectory = cfg.srcDir;
        Restart = "on-failure";
        RestartSec = "5s";
        User = lib.mkForce cfg.user;
        Group = "users";
        SupplementaryGroups = [ "secrets" ]; # Read agenix secrets directly

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false; # Needs access to srcDir + siteDir
        ReadWritePaths = [
          cfg.srcDir       # .last-deploy.json
          cfg.siteDir      # Content files, build output
          "/tmp"           # Multer uploads
        ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "100%"; # Build needs CPU headroom
      };

      # Ensure ImageMagick and npx are available for build + image processing
      path = [ pkgs.imagemagick pkgs.nodejs_22 ];
    };

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    assertions = [
      {
        assertion = config.age.secrets ? cms-api-key;
        message = ''
          hwc.business.website requires the cms-api-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
      {
        assertion = config.age.secrets ? hostinger-sftp;
        message = ''
          hwc.business.website requires the hostinger-sftp agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
