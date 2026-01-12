{ config, lib, pkgs, ... }:

# domains/paths/paths.nix
#
# Primitive Module Exception (Charter v10.1 Law 10):
# This file co-locates option declarations and implementation as the authoritative
# hwc.paths.* primitive module for universal filesystem abstraction.
#
# Responsibilities:
# - Declare hwc.paths.* options (storage tiers, PARA structure, app roots)
# - Provide recursive per-machine overrides (hwc.paths.overrides)
# - Export environment/session variables (HWC_* variables)
# - Validate absoluteness and invariants
#
# Restrictions:
# - No dotfiles/templates/payloads
# - Must remain narrow in scope
# - Revocable if complexity grows

let
  # Correct isNixOS detection - check if we're in system context (not Home Manager)
  # In NixOS: config has system.build.toplevel
  # In Home Manager: config has home.* options
  isNixOS = config ? system;

  # Reference to original config (before overrides)
  cfgRef = config.hwc.paths;

  # Merged config with overrides applied - THIS is authoritative
  cfg = lib.recursiveUpdate cfgRef (cfgRef.overrides or {});

  # Safe attribute getter with fallback
  getOr = path: default:
    lib.attrByPath path default cfg;

  # Detect user home from system config when available
  userHomeDefault =
    if isNixOS && config ? users && config.users ? users && config.users.users ? eric
    then config.users.users.eric.home
    else "/home/eric";

  # Environment variables exported from merged/authoritative config
  hwcVars = {
    HOME                     = cfg.user.home;
    HWC_HOT_STORAGE          = cfg.hot.root;
    HWC_HOT_DOWNLOADS        = cfg.hot.downloads;
    HWC_HOT_SURVEILLANCE     = cfg.hot.surveillance;
    HWC_MEDIA_STORAGE        = cfg.media.root;
    HWC_MEDIA_MUSIC          = cfg.media.music;
    HWC_COLD_STORAGE         = cfg.cold;
    HWC_BACKUP_STORAGE       = cfg.backup;
    HWC_PHOTOS_STORAGE       = cfg.photos;
    HWC_USER_HOME            = cfg.user.home;
    HWC_INBOX_DIR            = cfg.user.inbox;
    HWC_WORK_DIR             = cfg.user.work;
    HWC_PERSONAL_DIR         = cfg.user.personal;
    HWC_TECH_DIR             = cfg.user.tech;
    HWC_MAIL_DIR             = cfg.user.mail;
    HWC_MEDIA_DIR            = cfg.user.media;
    HWC_VAULTS_DIR           = cfg.user.vaults;
    HWC_BUSINESS_ROOT        = cfg.business.root;
    HWC_AI_ROOT              = cfg.ai.root;
    HWC_ADHD_ROOT            = cfg.adhd.root;
    HWC_SURVEILLANCE_ROOT    = cfg.surveillance.root;
    HWC_NIXOS_DIR            = cfg.nixos;

    # Legacy compatibility
    HEARTWOOD_USER_HOME      = cfg.user.home;
    HEARTWOOD_HOT_STORAGE    = cfg.hot.root;
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================

  options.hwc.paths = {
    overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Recursive per-machine overrides for hwc.paths.* (preferred method for customization)";
    };

    hot = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "${userHomeDefault}/storage/hot";
        description = "Hot storage base path (SSD) - fast tier for active processing";
      };
      downloads = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.hot.root}/downloads";
        description = "Downloads staging area (hot tier)";
      };
      surveillance = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.hot.root}/surveillance";
        description = "Surveillance buffer (hot tier)";
      };
    };

    media = {
      root = lib.mkOption {
        type = lib.types.path;
        default = "${userHomeDefault}/storage/media";
        description = "Media storage base path (HDD) - bulk tier for media libraries";
      };
      music = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.media.root}/music";
        description = "Music library (media tier)";
      };
    };

    cold = lib.mkOption {
      type = lib.types.path;
      default = "${userHomeDefault}/storage/archive";
      description = "Archive storage - long-term backup tier";
    };

    backup = lib.mkOption {
      type = lib.types.path;
      default = "${userHomeDefault}/storage/backup";
      description = "Backup destination - snapshot storage";
    };

    photos = lib.mkOption {
      type = lib.types.path;
      default = "${userHomeDefault}/storage/photos";
      description = "Photo storage tier (separate from media for Immich)";
    };

    user = {
      home = lib.mkOption {
        type = lib.types.path;
        default = userHomeDefault;
        description = "User home directory (auto-detected when possible)";
      };

      inbox = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/000_inbox";
        description = "Global inbox for unsorted items";
      };

      work = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/100_hwc";
        description = "Work/business project area";
      };

      personal = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/200_personal";
        description = "Personal project area";
      };

      tech = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/300_tech";
        description = "Technology development area";
      };

      media = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/500_media";
        description = "Cross-domain media collection";
      };

      mail = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/400_mail";
        description = "Mail storage (Maildir, mbox, mail configs)";
      };

      vaults = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/900_vaults";
        description = "Knowledge management and cloud storage (Obsidian, etc.)";
      };

      ssh = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/.ssh";
        description = "SSH configuration directory";
      };

      config = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.user.home}/.config";
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
        default = "${cfgRef.business.root}/api";
        description = "Business API application directory";
      };
      uploads = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.business.root}/uploads";
        description = "Business document uploads";
      };
      backups = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.business.root}/backups";
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
        default = "${cfgRef.ai.root}/models";
        description = "AI model storage directory";
      };
      context = lib.mkOption {
        type = lib.types.path;
        default = "${cfgRef.ai.root}/context-snapshots";
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
        default = "${cfgRef.surveillance.root}/frigate";
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

    # System directories (created by filesystem materializer)
    state = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc";
      description = "Service persistent data directory";
    };

    cache = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/hwc";
      description = "Temporary/regeneratable cache directory";
    };

    logs = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/hwc";
      description = "Service logs and monitoring data";
    };

    nixos = lib.mkOption {
      type = lib.types.path;
      default = "${userHomeDefault}/.nixos";
      description = "NixOS configuration directory (user-writeable, not store path)";
    };
  };

  #============================================================================
  # IMPLEMENTATION & VALIDATION
  #============================================================================

  # Only set environment variables and assertions when evaluated in NixOS system context
  config = lib.mkIf isNixOS {
    environment.sessionVariables = hwcVars;

    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.user.home;
        message = "hwc.paths.user.home must be absolute";
      }
      {
        assertion = lib.hasPrefix "/" cfg.hot.root;
        message = "hwc.paths.hot.root must be absolute";
      }
      {
        assertion = lib.hasPrefix "/" cfg.media.root;
        message = "hwc.paths.media.root must be absolute";
      }
      {
        assertion = cfg.hot.root != cfg.media.root;
        message = "hwc.paths.hot.root and hwc.paths.media.root must not be the same path";
      }
    ];
  };
}
