# HWC Charter Module/domains/system/paths.nix
#
# PATHS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.paths.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/system/paths.nix
#
# USAGE:
#   hwc.system.paths.enable = true;
#   # TODO: Add specific usage examples

# HWC Charter Module/domains/system/paths.nix
#
# HWC Centralized Path Configuration System
# Comprehensive path management for all system components
#
# DEPENDENCIES:
#   Upstream: None (foundational module)
#
# USED BY:
#   Downstream: All service and infrastructure modules
#   Downstream: modules/system/filesystem.nix (directory creation)
#   Downstream: Shell scripts via environment variables
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../domains/system/paths.nix
#
# USAGE:
#   config.hwc.paths.hot           # "/mnt/hot"
#   config.hwc.paths.user.home     # "/home/eric"
#   config.hwc.paths.business.root # "/opt/business"
#
# VALIDATION:
#   - All paths are absolute
#   - Storage paths are machine-configurable (nullable)

{ config, lib, ... }:

let
  cfg = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - Comprehensive Path Structure
  #============================================================================

  options.hwc.paths = {

    #=========================================================================
    # STORAGE TIERS - Hot/Cold Architecture (Nullable - Machine Specific)
    #=========================================================================

    hot = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Hot storage (SSD) - fast tier for active processing";
      example = "/mnt/hot";
    };

    media = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Cold storage (HDD) - bulk tier for media libraries";
      example = "/mnt/media";
    };

    cold = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Archive storage - long-term backup tier";
      example = "/mnt/archive";
    };

    backup = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Backup destination - snapshot storage";
      example = "/mnt/backup";
    };

    #=========================================================================
    # SYSTEM PATHS - Always Available
    #=========================================================================

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

    temp = lib.mkOption {
      type = lib.types.path;
      default = "/tmp/hwc";
      description = "System temporary processing directory";
    };

    #=========================================================================
    # USER PATHS - PARA Structure
    #=========================================================================

    user = {
      home = lib.mkOption {
        type = lib.types.path;
        default = "/home/eric";
        description = "User home directory";
      };

      # PARA Structure
      inbox = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/00-inbox";
        description = "Global inbox for unsorted items";
      };

      work = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/01-hwc";
        description = "Work/business project area";
      };

      personal = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/02-personal";
        description = "Personal project area";
      };

      tech = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/03-tech";
        description = "Technology development area";
      };

      reference = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/04-ref";
        description = "Reference materials";
      };

      media = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/05-media";
        description = "Personal media collection";
      };

      vaults = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.user.home}/99-vaults";
        description = "Knowledge management and cloud storage";
      };

      # User configuration
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

    #=========================================================================
    # APPLICATION ROOTS - Service Directories
    #=========================================================================

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
        default = "/opt/adhd-tools";
        description = "ADHD productivity tools root";
      };

      context = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.adhd.root}/context-snapshots";
        description = "Work context snapshots";
      };

      logs = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.adhd.root}/focus-logs";
        description = "Focus session tracking";
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

    #=========================================================================
    # ARR STACK PATHS - Media Management Pipeline
    #=========================================================================

    arr = {
      # Service configuration directories
      lidarr = lib.mkOption {
        type = lib.types.path;
        default = "/opt/lidarr";
        description = "Lidarr music management configuration";
      };

      radarr = lib.mkOption {
        type = lib.types.path;
        default = "/opt/radarr";
        description = "Radarr movie management configuration";
      };

      sonarr = lib.mkOption {
        type = lib.types.path;
        default = "/opt/sonarr";
        description = "Sonarr TV series management configuration";
      };

      prowlarr = lib.mkOption {
        type = lib.types.path;
        default = "/opt/prowlarr";
        description = "Prowlarr indexer management configuration";
      };

      # Download client directories
      downloads = lib.mkOption {
        type = lib.types.path;
        default = "/opt/downloads";
        description = "Download client configurations";
      };
    };

    #=========================================================================
    # SECURITY PATHS - Secrets and Certificates
    #=========================================================================

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

      tailscale = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/tailscale";
        description = "Tailscale state directory";
      };

      certificates = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/tailscale/certs";
        description = "Tailscale certificates";
      };
    };
      userDirs = {
        desktop = lib.mkOption { type = lib.types.path; default = "${cfg.user.inbox}"; };
        download = lib.mkOption { type = lib.types.path; default = "${cfg.user.inbox}/downloads"; };
        documents = lib.mkOption { type = lib.types.path; default = "${cfg.user.reference}/documents"; };
        templates = lib.mkOption { type = lib.types.path; default = "${cfg.user.reference}/templates"; };
        publicShare = lib.mkOption { type = lib.types.path; default = "${cfg.user.inbox}"; };
        pictures = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/pictures"; };
        music = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/music"; };
        videos = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/videos"; };
      };

      mediaPaths = {
        pictures = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/pictures"; };
        music = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/music"; };
        videos = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/videos"; };
        screenshots = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/pictures/01-screenshots"; };
        picturesInbox = lib.mkOption { type = lib.types.path; default = "${cfg.user.media}/pictures/99-inbox"; };
      };

    #=========================================================================
    # NIXOS CONFIGURATION
    #=========================================================================

    nixos = lib.mkOption {
      type = lib.types.path;
      default = toString ./../..; # Dynamic path to repo root (two levels up from this file)
      description = "NixOS configuration directory";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Environment Variables and Validation
  #============================================================================

  config = {
    # Validation assertions
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.user.home;
        message = "hwc.paths.user.home must be an absolute path";
      }
      {
        assertion = cfg.hot == null || lib.hasPrefix "/" cfg.hot;
        message = "hwc.paths.hot must be an absolute path if set";
      }
      {
        assertion = cfg.media == null || lib.hasPrefix "/" cfg.media;
        message = "hwc.paths.media must be an absolute path if set";
      }
      {
        assertion = cfg.hot != cfg.media || cfg.hot == null;
        message = "hwc.paths.hot and hwc.paths.media cannot be the same path";
      }
    ];

    # Export paths as environment variables for script integration
    environment.sessionVariables = {
      # Storage tiers
      HWC_HOT_STORAGE = if cfg.hot != null then cfg.hot else "";
      HWC_MEDIA_STORAGE = if cfg.media != null then cfg.media else "";
      HWC_COLD_STORAGE = if cfg.cold != null then cfg.cold else "";
      HWC_BACKUP_STORAGE = if cfg.backup != null then cfg.backup else "";

      # System paths
      HWC_STATE_DIR = cfg.state;
      HWC_CACHE_DIR = cfg.cache;
      HWC_LOGS_DIR = cfg.logs;
      HWC_TEMP_DIR = cfg.temp;

      # User PARA structure
      HWC_USER_HOME = cfg.user.home;
      HWC_INBOX_DIR = cfg.user.inbox;
      HWC_WORK_DIR = cfg.user.work;
      HWC_PERSONAL_DIR = cfg.user.personal;
      HWC_TECH_DIR = cfg.user.tech;
      HWC_REFERENCE_DIR = cfg.user.reference;
      HWC_MEDIA_DIR = cfg.user.media;
      HWC_VAULTS_DIR = cfg.user.vaults;

      # Application roots
      HWC_BUSINESS_ROOT = cfg.business.root;
      HWC_AI_ROOT = cfg.ai.root;
      HWC_ADHD_ROOT = cfg.adhd.root;
      HWC_SURVEILLANCE_ROOT = cfg.surveillance.root;

      # ARR stack
      HWC_LIDARR_CONFIG = cfg.arr.lidarr;
      HWC_RADARR_CONFIG = cfg.arr.radarr;
      HWC_SONARR_CONFIG = cfg.arr.sonarr;
      HWC_PROWLARR_CONFIG = cfg.arr.prowlarr;
      HWC_DOWNLOADS_CONFIG = cfg.arr.downloads;

      # Security
      HWC_SECRETS_SRC_DIR = cfg.security.secrets;
      HWC_SOPS_AGE_KEY = cfg.security.sopsAgeKey;

      # NixOS configuration
      HWC_NIXOS_DIR = cfg.nixos;

      HWC_XDG_DESKTOP = cfg.userDirs.desktop;
      HWC_XDG_DOWNLOAD = cfg.userDirs.download;
      HWC_XDG_DOCUMENTS = cfg.userDirs.documents;
      HWC_XDG_TEMPLATES = cfg.userDirs.templates;
      HWC_XDG_PUBLIC = cfg.userDirs.publicShare;
      HWC_XDG_PICTURES = cfg.userDirs.pictures;
      HWC_XDG_MUSIC = cfg.userDirs.music;
      HWC_XDG_VIDEOS = cfg.userDirs.videos;
      HWC_PICTURES_DIR = cfg.mediaPaths.pictures;
      HWC_SCREENSHOTS_DIR = cfg.mediaPaths.screenshots;
      

      # Legacy compatibility (for existing scripts)
      HEARTWOOD_USER_HOME = cfg.user.home;
      HEARTWOOD_HOT_STORAGE = if cfg.hot != null then cfg.hot else "";
      HEARTWOOD_COLD_STORAGE = if cfg.media != null then cfg.media else "";
      HEARTWOOD_BUSINESS_ROOT = cfg.business.root;
      HEARTWOOD_AI_ROOT = cfg.ai.root;
      HEARTWOOD_SECRETS_DIR = cfg.security.secrets;
      HEARTWOOD_SOPS_AGE_KEY = cfg.security.sopsAgeKey;
    };

    # Configure XDG user directories globally
    environment.etc."xdg/user-dirs.defaults".text = ''
      DESKTOP=${cfg.userDirs.desktop}
      DOWNLOAD=${cfg.userDirs.download}
      TEMPLATES=${cfg.userDirs.templates}
      PUBLICSHARE=${cfg.userDirs.publicShare}
      DOCUMENTS=${cfg.userDirs.documents}
      MUSIC=${cfg.userDirs.music}
      PICTURES=${cfg.userDirs.pictures}
      VIDEOS=${cfg.userDirs.videos}
    '';

    # Create system path directories (always available)
    systemd.tmpfiles.rules = [
      "d ${cfg.state} 0755 root root -"
      "d ${cfg.cache} 0755 root root -"
      "d ${cfg.logs} 0755 root root -"
      "d ${cfg.temp} 0755 root root -"
    ];
  };
}
