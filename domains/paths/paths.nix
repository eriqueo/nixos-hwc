{ config, lib, pkgs, osConfig ? {}, ... }:

# domains/paths/paths.nix
#
# Primitive Module Exception:
# This file is the authoritative hwc.paths.* module. It intentionally co-locates
# option declarations and implementation as a single foundational primitive for
# universal filesystem abstraction for the HWC repo.
#
# Charter reference: Law 10 Primitive Module Exception (v10.1)
#
# Responsibilities:
# - Declare hwc.paths.* options (storage tiers, PARA, application roots)
# - Provide recursive per-machine overrides (hwc.paths.overrides)
# - Export environment/session variables (HWC_* variables)
# - Validate absoluteness and invariants
#
# Prohibition:
# - No dotfiles/templates/payloads. If payload is required, split into
#   options.nix/index.nix/parts/ and revoke this exception.

let
  isNixOS = osConfig ? hwc;
  cfg = config.hwc.paths;

  envHome =
    let
      rawHome = builtins.getEnv "HOME";
    in
    if rawHome != "" then rawHome else "/home/eric";

  merged = lib.recursiveUpdate cfg (cfg.overrides or {});

  getOr = path: default: lib.attrByPath path default merged;

  hotRoot = getOr [ "hot" "root" ] "${envHome}/storage/hot";
  mediaRoot = getOr [ "media" "root" ] "${envHome}/storage/media";
  userHome = getOr [ "user" "home" ] "/home/eric";

  hwcVars = {
    HOME = userHome;

    HWC_HOT_STORAGE = hotRoot;
    HWC_HOT_DOWNLOADS = getOr [ "hot" "downloads" ] "${hotRoot}/downloads";
    HWC_HOT_SURVEILLANCE = getOr [ "hot" "surveillance" ] "${hotRoot}/surveillance";

    HWC_MEDIA_STORAGE = mediaRoot;
    HWC_MEDIA_MUSIC = getOr [ "media" "music" ] "${mediaRoot}/music";

    HWC_COLD_STORAGE = getOr [ "cold" ] "${envHome}/storage/archive";
    HWC_BACKUP_STORAGE = getOr [ "backup" ] "${envHome}/storage/backup";
    HWC_PHOTOS_STORAGE = getOr [ "photos" ] "${envHome}/storage/photos";

    HWC_USER_HOME = userHome;
    HWC_INBOX_DIR = getOr [ "user" "inbox" ] "${userHome}/000_inbox";
    HWC_WORK_DIR = getOr [ "user" "work" ] "${userHome}/100_hwc";
    HWC_PERSONAL_DIR = getOr [ "user" "personal" ] "${userHome}/200_personal";
    HWC_TECH_DIR = getOr [ "user" "tech" ] "${userHome}/300_tech";
    HWC_MAIL_DIR = getOr [ "user" "mail" ] "${userHome}/400_mail";
    HWC_MEDIA_DIR = getOr [ "user" "media" ] "${userHome}/500_media";
    HWC_VAULTS_DIR = getOr [ "user" "vaults" ] "${userHome}/900_vaults";

    HWC_BUSINESS_ROOT = getOr [ "business" "root" ] "/opt/business";
    HWC_AI_ROOT = getOr [ "ai" "root" ] "/opt/ai";
    HWC_ADHD_ROOT = getOr [ "adhd" "root" ] "/opt/adhd";
    HWC_SURVEILLANCE_ROOT = getOr [ "surveillance" "root" ] "/opt/surveillance";

    HWC_NIXOS_DIR = getOr [ "nixos" ] (toString ../../..);

    # legacy compatibility
    HEARTWOOD_USER_HOME = userHome;
    HEARTWOOD_HOT_STORAGE = hotRoot;
  };
in
{
  options.hwc.paths = {
    overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Recursive per-machine overrides for hwc.paths.*. Prefer this to copying defaults.";
    };

    hot = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "${envHome}/storage/hot";
        description = "Hot storage base path (SSD) - fast tier for active processing";
      };
      downloads = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.hot.root}/downloads";
        description = "Downloads staging area (hot tier)";
      };
      surveillance = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.hot.root}/surveillance";
        description = "Surveillance buffer (hot tier)";
      };
    };

    media = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "${envHome}/storage/media";
        description = "Media storage base path (HDD) - bulk tier for media libraries";
      };
      music = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.media.root}/music";
        description = "Music library (media tier)";
      };
    };

    cold = lib.mkOption {
      type = lib.types.path;
      default = "${envHome}/storage/archive";
      description = "Archive storage - long-term backup tier";
    };

    backup = lib.mkOption {
      type = lib.types.path;
      default = "${envHome}/storage/backup";
      description = "Backup destination - snapshot storage";
    };

    photos = lib.mkOption {
      type = lib.types.path;
      default = "${envHome}/storage/photos";
      description = "Photo storage tier (separate from media for Immich)";
    };

    user = {
      home = lib.mkOption {
        type = lib.types.path;
        default = if isNixOS && osConfig.users ? users && osConfig.users.users ? eric
          then osConfig.users.users.eric.home
          else "/home/eric";
        description = "User home directory (auto-detected where possible)";
      };

      inbox = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/000_inbox";
        description = "Global inbox for unsorted items";
      };

      work = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/100_hwc";
        description = "Work/business project area";
      };

      personal = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/200_personal";
        description = "Personal project area";
      };

      tech = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/300_tech";
        description = "Technology development area";
      };

      media = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/500_media";
        description = "Cross-domain media collection";
      };

      mail = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/400_mail";
        description = "Mail storage (Maildir, mbox, mail configs)";
      };

      vaults = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/900_vaults";
        description = "Knowledge management and cloud storage (Obsidian, etc.)";
      };

      ssh = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/.ssh";
        description = "SSH configuration directory";
      };

      config = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/.config";
        description = "User configuration directory";
      };
    };

    business = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "/opt/business";
        description = "Business intelligence applications root";
      };
      api = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.business.root}/api";
        description = "Business API application directory";
      };
      uploads = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.business.root}/uploads";
        description = "Business document uploads";
      };
      backups = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.business.root}/backups";
        description = "Business data backups";
      };
    };

    ai = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "/opt/ai";
        description = "AI/ML applications root directory";
      };
      models = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.ai.root}/models";
        description = "AI model storage directory";
      };
      context = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.ai.root}/context-snapshots";
        description = "AI context state backups";
      };
    };

    adhd = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "/opt/adhd";
        description = "ADHD tools root directory";
      };
    };

    surveillance = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "/opt/surveillance";
        description = "Surveillance applications root";
      };
      frigate = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.surveillance.root}/frigate";
        description = "Frigate AI surveillance system";
      };
    };

    security = {
      secrets = lib.mkOption {
        type = lib.types.path;
        default = "/etc/secrets";
        description = "System secrets directory";
      };
      age = lib.mkOption {
        type = lib.types.path;
        default = "/etc/secrets/age";
        description = "Age encryption keys";
      };
      sops = lib.mkOption {
        type = lib.types.path;
        default = "/etc/secrets/sops";
        description = "SOPS encrypted files";
      };
      sopsAgeKey = lib.mkOption {
        type = lib.types.path;
        default = "/etc/sops/age/keys.txt";
        description = "SOPS age private key file";
      };
    };

    nixos = lib.mkOption {
      type = lib.types.path;
      default = toString ../../..;
      description = "NixOS configuration directory (repo root)";
    };
  };

  config = lib.mkIf isNixOS {
    environment.sessionVariables = hwcVars;
    assertions = [
      {
        assertion = lib.hasPrefix "/" userHome;
        message = "hwc.paths.user.home must be absolute";
      }
      {
        assertion = lib.hasPrefix "/" hotRoot;
        message = "hwc.paths.hot.root must be absolute";
      }
      {
        assertion = lib.hasPrefix "/" mediaRoot;
        message = "hwc.paths.media.root must be absolute";
      }
      {
        assertion = hotRoot != mediaRoot;
        message = "hwc.paths.hot.root and hwc.paths.media.root must not be the same path";
      }
    ];
  };
}
