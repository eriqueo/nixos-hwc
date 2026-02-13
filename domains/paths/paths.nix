# domains/paths/paths.nix
# Single-file central path definitions — laptop vs headless server (improved v2)
#
# Charter v10.1 Law 10: Primitive Module Exception
# Co-locates options and implementation for universal filesystem abstraction.
#
# MACHINE MODELS:
# - Laptop: Flat media structure under ~/500_media with PARA user folders
# - Server: Headless with tiered storage (/mnt/hot SSD, /mnt/media HDD), no PARA
#
# Detection: Uses hostname suffix matching (laptop/server)
# Overrides: Machines can override any path via hwc.paths.* = "/custom";

{ config, lib, ... }:

let
  cfg = config.hwc.paths;
  inherit (lib) types mkOption mkIf mkDefault;

  #============================================================================
  # MACHINE DETECTION & BASE PATHS
  #============================================================================

  hostname = config.networking.hostName or "unknown";
  isLaptop = lib.hasSuffix "laptop" hostname;
  isServer = lib.hasSuffix "server" hostname;

  # User home detection (universal)
  userHome =
    if config ? users.users.eric.home
    then config.users.users.eric.home
    else "/home/eric";

  #============================================================================
  # MACHINE-SPECIFIC DEFAULT VALUES (computed once, reused in options)
  #============================================================================

  # Laptop defaults
  laptopMediaRoot = "/home/eric/500_media";
  laptopPhotos = "${laptopMediaRoot}/510_pictures";
  laptopBackup = "/mnt/backup";
  laptopInbox = "/home/eric/000_inbox";
  laptopWork = "/home/eric/100_hwc";
  laptopPersonal = "/home/eric/200_personal";
  laptopTech = "/home/eric/300_tech";
  laptopMail = "/home/eric/400_mail";
  laptopMedia = "/home/eric/500_media";
  laptopVaults = "/home/eric/900_vaults";
  laptopSsh = "${userHome}/.ssh";
  laptopConfig = "${userHome}/.config";

  # Server defaults
  serverHotRoot = "/mnt/hot";
  serverMediaRoot = "/mnt/media";
  serverPhotos = "/mnt/photos";
  serverBusinessRoot = "/opt/business";
  serverAiRoot = "/opt/ai";
  serverAdhdRoot = "/opt/adhd";
  serverSurveillanceRoot = "/opt/surveillance";

  # Helper to filter out null values
  filterNulls = lib.filterAttrs (_: v: v != null);

in
{
  #============================================================================
  # OPTIONS - All paths with machine-appropriate defaults
  #============================================================================

  options.hwc.paths = {

    # -------------------------------------------------------------------------
    # UNIVERSAL PATHS
    # -------------------------------------------------------------------------

    user.home = mkOption {
      type = types.path;
      default = userHome;
      description = "User home directory";
    };

    state = mkOption {
      type = types.path;
      default = "/var/lib/hwc";
      description = "Service persistent state directory";
    };

    cache = mkOption {
      type = types.path;
      default = "/var/cache/hwc";
      description = "Temporary cache directory";
    };

    logs = mkOption {
      type = types.path;
      default = "/var/log/hwc";
      description = "Service logs directory";
    };

    nixos = mkOption {
      type = types.path;
      default = "${userHome}/.nixos";
      description = "NixOS configuration directory";
    };

    # -------------------------------------------------------------------------
    # STORAGE TIERS (Server: hot SSD, cold/media HDD; Laptop: flat)
    # -------------------------------------------------------------------------

    hot = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then serverHotRoot else null;
        description = "Hot storage tier (SSD) - server only";
      };

      downloads = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Downloads staging area (auto-derived from hot.root)";
      };

      surveillance = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Surveillance buffer (auto-derived from hot.root)";
      };
    };

    media = {
      root = mkOption {
        type = types.nullOr types.path;
        default =
          if isServer then serverMediaRoot
          else if isLaptop then laptopMediaRoot
          else null;
        description = "Media storage (HDD on server, flat dir on laptop)";
      };

      music = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Music library (auto-derived from media.root)";
      };
    };

    cold = mkOption {
      type = types.nullOr types.path;
      default = if isServer then serverMediaRoot else null;
      description = "Archive/cold storage tier - server only";
    };

    backup = mkOption {
      type = types.nullOr types.path;
      default = if isLaptop then laptopBackup else null;
      description = "Backup destination";
    };

    photos = mkOption {
      type = types.nullOr types.path;
      default =
        if isServer then serverPhotos
        else if isLaptop then laptopPhotos
        else null;
      description = "Photo storage";
    };

    screenshots = mkOption {
      type = types.nullOr types.path;
      default = if isLaptop then "${laptopPhotos}/screenshots" else null;
      description = "Screenshot save location - laptop only";
    };

    # -------------------------------------------------------------------------
    # PARA STRUCTURE (Laptop only)
    # -------------------------------------------------------------------------

    user = {
      inbox = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopInbox else null;
        description = "Global inbox - laptop only";
      };

      work = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopWork else null;
        description = "Work/business area - laptop only";
      };

      personal = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopPersonal else null;
        description = "Personal projects - laptop only";
      };

      tech = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopTech else null;
        description = "Technology development - laptop only";
      };

      mail = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopMail else null;
        description = "Mail storage - laptop only";
      };

      media = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopMedia else null;
        description = "Media collection - laptop only";
      };

      vaults = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopVaults else null;
        description = "Knowledge vaults - laptop only";
      };

      ssh = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopSsh else null;
        description = "SSH directory - laptop only";
      };

      config = mkOption {
        type = types.nullOr types.path;
        default = if isLaptop then laptopConfig else null;
        description = "User config directory - laptop only";
      };
    };

    # -------------------------------------------------------------------------
    # APPLICATION ROOTS (Server only)
    # -------------------------------------------------------------------------

    apps = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then "/opt" else null;
        description = "Application config root (server only)";
      };
    };

    business = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then serverBusinessRoot else null;
        description = "Business applications - server only";
      };

      api = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Business API directory";
      };

      uploads = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Business uploads";
      };

      backups = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Business backups";
      };
    };

    ai = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then serverAiRoot else null;
        description = "AI/ML applications - server only";
      };

      models = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "AI model storage";
      };

      context = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "AI context snapshots";
      };
    };

    adhd = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then serverAdhdRoot else null;
        description = "ADHD tools - server only";
      };
    };

    surveillance = {
      root = mkOption {
        type = types.nullOr types.path;
        default = if isServer then serverSurveillanceRoot else null;
        description = "Surveillance apps - server only";
      };

      frigate = mkOption {
        type = types.nullOr types.path;
        default = null; # Auto-derived in config section
        description = "Frigate surveillance";
      };
    };

    # -------------------------------------------------------------------------
    # SECURITY (Universal)
    # -------------------------------------------------------------------------

    security = {
      secrets = mkOption {
        type = types.path;
        default = "/etc/secrets";
        description = "System secrets directory";
      };

      age = mkOption {
        type = types.path;
        default = "/etc/secrets/age";
        description = "Age encryption keys";
      };

      sops = mkOption {
        type = types.path;
        default = "/etc/secrets/sops";
        description = "SOPS encrypted files";
      };

      sopsAgeKey = mkOption {
        type = types.path;
        default = "/etc/sops/age/keys.txt";
        description = "SOPS age private key";
      };
    };
  };

  #============================================================================
  # AUTO-DERIVED PATHS (Set in config based on parent paths)
  #============================================================================

  config.hwc.paths = {
    # Hot storage sub-paths
    hot.downloads = mkIf (cfg.hot.root != null) (mkDefault "${cfg.hot.root}/downloads");
    hot.surveillance = mkIf (cfg.hot.root != null) (mkDefault "${cfg.hot.root}/surveillance");

    # Media sub-paths
    media.music = mkIf (cfg.media.root != null) (mkDefault "${cfg.media.root}/music");

    # Business sub-paths
    business.api = mkIf (cfg.business.root != null) (mkDefault "${cfg.business.root}/api");
    business.uploads = mkIf (cfg.business.root != null) (mkDefault "${cfg.business.root}/uploads");
    business.backups = mkIf (cfg.business.root != null) (mkDefault "${cfg.business.root}/backups");

    # AI sub-paths
    ai.models = mkIf (cfg.ai.root != null) (mkDefault "${cfg.ai.root}/models");
    ai.context = mkIf (cfg.ai.root != null) (mkDefault "${cfg.ai.root}/context-snapshots");

    # Surveillance sub-paths
    surveillance.frigate = mkIf (cfg.surveillance.root != null) (mkDefault "${cfg.surveillance.root}/frigate");
  };

  #============================================================================
  # ENVIRONMENT VARIABLES (Export only defined paths)
  #============================================================================

  config.environment.sessionVariables = filterNulls {
    # Universal
    HOME = cfg.user.home;
    HWC_USER_HOME = cfg.user.home;
    HWC_STATE_DIR = cfg.state;
    HWC_CACHE_DIR = cfg.cache;
    HWC_LOGS_DIR = cfg.logs;
    HWC_NIXOS_DIR = cfg.nixos;

    # Storage tiers
    HWC_HOT_STORAGE = cfg.hot.root;
    HWC_HOT_DOWNLOADS = cfg.hot.downloads;
    HWC_HOT_SURVEILLANCE = cfg.hot.surveillance;
    HWC_MEDIA_STORAGE = cfg.media.root;
    HWC_MEDIA_MUSIC = cfg.media.music;
    HWC_COLD_STORAGE = cfg.cold;
    HWC_BACKUP_STORAGE = cfg.backup;
    HWC_PHOTOS_STORAGE = cfg.photos;
    HWC_SCREENSHOTS_DIR = cfg.screenshots;

    # PARA structure
    HWC_INBOX_DIR = cfg.user.inbox;
    HWC_WORK_DIR = cfg.user.work;
    HWC_PERSONAL_DIR = cfg.user.personal;
    HWC_TECH_DIR = cfg.user.tech;
    HWC_MAIL_DIR = cfg.user.mail;
    HWC_MEDIA_DIR = cfg.user.media;
    HWC_VAULTS_DIR = cfg.user.vaults;

    # Application roots
    HWC_APPS_ROOT = cfg.apps.root;
    HWC_BUSINESS_ROOT = cfg.business.root;
    HWC_AI_ROOT = cfg.ai.root;
    HWC_ADHD_ROOT = cfg.adhd.root;
    HWC_SURVEILLANCE_ROOT = cfg.surveillance.root;

    # Security (HWC_SECRETS_DIR exported by secrets domain, not here)
    HWC_SOPS_AGE_KEY = cfg.security.sopsAgeKey;
  };

  #============================================================================
  # VALIDATION ASSERTIONS
  #============================================================================

  config.assertions = [
    # Server: hot and media must be different paths
    {
      assertion = !(isServer && cfg.hot.root != null && cfg.media.root != null && cfg.hot.root == cfg.media.root);
      message = ''
        Server storage tiers must use different paths:
          hot.root  = ${toString cfg.hot.root}
          media.root = ${toString cfg.media.root}

        Hot (SSD) is for active processing; Media (HDD) is for bulk storage.
      '';
    }

    # Laptop: media.root must be defined (core dependency)
    {
      assertion = !isLaptop || cfg.media.root != null;
      message = "Laptop requires hwc.paths.media.root to be defined (core media structure)";
    }

    # All defined paths must be absolute
    {
      assertion = lib.hasPrefix "/" cfg.user.home;
      message = "hwc.paths.user.home must be an absolute path";
    }

    {
      assertion = cfg.hot.root == null || lib.hasPrefix "/" cfg.hot.root;
      message = "hwc.paths.hot.root must be null or absolute";
    }

    {
      assertion = cfg.media.root == null || lib.hasPrefix "/" cfg.media.root;
      message = "hwc.paths.media.root must be null or absolute";
    }

    {
      assertion = cfg.cold == null || lib.hasPrefix "/" cfg.cold;
      message = "hwc.paths.cold must be null or absolute";
    }

    {
      assertion = cfg.photos == null || lib.hasPrefix "/" cfg.photos;
      message = "hwc.paths.photos must be null or absolute";
    }

    {
      assertion = cfg.business.root == null || lib.hasPrefix "/" cfg.business.root;
      message = "hwc.paths.business.root must be null or absolute";
    }

    {
      assertion = cfg.ai.root == null || lib.hasPrefix "/" cfg.ai.root;
      message = "hwc.paths.ai.root must be null or absolute";
    }

    {
      assertion = cfg.surveillance.root == null || lib.hasPrefix "/" cfg.surveillance.root;
      message = "hwc.paths.surveillance.root must be null or absolute";
    }

    {
      assertion = cfg.apps.root == null || lib.hasPrefix "/" cfg.apps.root;
      message = "hwc.paths.apps.root must be null or absolute";
    }
  ];
}
