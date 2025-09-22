# nixos-h../domains/infrastructure/filesystem-structure/index.nix
#
# FILESYSTEM STRUCTURE - Cross-domain filesystem orchestrator
# Creates standardized directory structure for both laptop and server environments
# Provides uniform navigation and naming conventions across all domains
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/core/paths.nix)
#
# USED BY (Downstream):
#   - profiles/base.nix (core directories)
#   - profiles/server.nix (server storage)
#   - All applications expecting standard directory layout
#
# IMPORTS REQUIRED IN:
#   - modules/infrastructure/index.nix (automatic via domain aggregator)
#
# USAGE:
#   hwc.infrastructure.filesystemStructure.userDirectories.enable = true;     # PARA structure
#   hwc.infrastructure.filesystemStructure.serverStorage.enable = true;       # Hot/cold storage
#   hwc.infrastructure.filesystemStructure.businessDirectories.enable = true; # Business/AI
#   hwc.infrastructure.filesystemStructure.serviceDirectories.enable = true;  # ARR stack
#   hwc.infrastructure.filesystemStructure.securityDirectories.enable = true; # Secrets
#
# VALIDATION:
#   - Requires storage paths to be set when storage directories enabled
#   - Creates users and groups for proper permissions

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.filesystemStructure;
  paths = config.hwc.paths;
in {
  #============================================================================
  # IMPORTS - Options definition
  #============================================================================
  
  imports = [
    ./options.nix
  ];

  #============================================================================
  # IMPLEMENTATION - Directory Creation Based on Toggles
  #============================================================================

  config = lib.mkIf cfg.enable (lib.mkMerge [

    #=========================================================================
    # BASE SYSTEM - Users, Groups, System Directories
    #=========================================================================
    {
      # Create system users and groups
      users.groups = {
        ${cfg.permissions.mediaGroup} = {
          gid = 2000;
        };
        hwc = {
          gid = 2001;
        };
      };

      # Install filesystem utilities
      environment.systemPackages = with pkgs; [
        ncdu        # Disk usage analyzer
        tree        # Directory structure viewer
        lsof        # List open files
        psmisc      # Find processes using files
      ];
    }

    #=========================================================================
    # USER DIRECTORIES - PARA Structure (Laptop/Workstation)
    #=========================================================================
    (lib.mkIf cfg.userDirectories.enable {
      systemd.tmpfiles.rules = [
        # NixOS configuration access permissions
        "Z /etc/nixos - eric users - -"

        # Main user directory
        "d ${paths.user.home} 0755 eric users -"

        #====================================================================
        # GLOBAL INBOX - Central sorting area
        #====================================================================
        "d ${paths.user.inbox} 0755 eric users -"
        "d ${paths.user.inbox}/downloads 0755 eric users -"
        "d ${paths.user.inbox}/general 0755 eric users -"

        #====================================================================
        # WORK AREA - Recursive PARA structure
        #====================================================================
        "d ${paths.user.work} 0755 eric users -"
        "d ${paths.user.work}/00-inbox 0755 eric users -"
        "d ${paths.user.work}/01-active 0755 eric users -"
        "d ${paths.user.work}/02-reference 0755 eric users -"
        "d ${paths.user.work}/03-archive 0755 eric users -"

        # Active work project structure
        "d ${paths.user.work}/01-active/clients 0755 eric users -"
        "d ${paths.user.work}/01-active/internal 0755 eric users -"
        "d ${paths.user.work}/01-active/proposals 0755 eric users -"

        # Work reference materials
        "d ${paths.user.work}/02-reference/processes 0755 eric users -"
        "d ${paths.user.work}/02-reference/templates 0755 eric users -"
        "d ${paths.user.work}/02-reference/resources 0755 eric users -"

        #====================================================================
        # PERSONAL AREA - Recursive PARA structure
        #====================================================================
        "d ${paths.user.personal} 0755 eric users -"
        "d ${paths.user.personal}/00-inbox 0755 eric users -"
        "d ${paths.user.personal}/01-active 0755 eric users -"
        "d ${paths.user.personal}/02-reference 0755 eric users -"
        "d ${paths.user.personal}/03-archive 0755 eric users -"

        # Active personal project areas
        "d ${paths.user.personal}/01-active/health 0755 eric users -"
        "d ${paths.user.personal}/01-active/finance 0755 eric users -"
        "d ${paths.user.personal}/01-active/home 0755 eric users -"
        "d ${paths.user.personal}/01-active/learning 0755 eric users -"

        # Personal reference materials
        "d ${paths.user.personal}/02-reference/documents 0755 eric users -"
        "d ${paths.user.personal}/02-reference/manuals 0755 eric users -"
        "d ${paths.user.personal}/02-reference/contacts 0755 eric users -"

        #====================================================================
        # TECHNOLOGY AREA - Recursive PARA structure
        #====================================================================
        "d ${paths.user.tech} 0755 eric users -"
        "d ${paths.user.tech}/00-inbox 0755 eric users -"
        "d ${paths.user.tech}/01-active 0755 eric users -"
        "d ${paths.user.tech}/02-reference 0755 eric users -"
        "d ${paths.user.tech}/03-archive 0755 eric users -"

        # Active tech project areas
        "d ${paths.user.tech}/01-active/nixos 0755 eric users -"
        "d ${paths.user.tech}/01-active/development 0755 eric users -"
        "d ${paths.user.tech}/01-active/experiments 0755 eric users -"
        "d ${paths.user.tech}/01-active/learning 0755 eric users -"

        # Tech reference materials
        "d ${paths.user.tech}/02-reference/manuals 0755 eric users -"
        "d ${paths.user.tech}/02-reference/configs 0755 eric users -"
        "d ${paths.user.tech}/02-reference/tools 0755 eric users -"

        #====================================================================
        # REFERENCE AREA - Simple structure
        #====================================================================
        "d ${paths.user.reference} 0755 eric users -"
        "d ${paths.user.reference}/templates 0755 eric users -"
        "d ${paths.user.reference}/manuals 0755 eric users -"
        "d ${paths.user.reference}/research 0755 eric users -"
        "d ${paths.user.reference}/forms 0755 eric users -"

        #====================================================================
        # MEDIA AREA - Simple structure
        #====================================================================
        "d ${paths.user.media} 0755 eric users -"
        "d ${paths.user.media}/pictures 0755 eric users -"
        "d ${paths.user.media}/music 0755 eric users -"
        "d ${paths.user.media}/videos 0755 eric users -"
        "d ${paths.user.media}/documents 0755 eric users -"

        # Media subdirectories
        "d ${paths.user.media}/pictures/screenshots 0755 eric users -"
        "d ${paths.user.media}/pictures/camera 0755 eric users -"
        "d ${paths.user.media}/pictures/projects 0755 eric users -"
        "d ${paths.user.media}/pictures/wallpapers 0755 eric users -"

        #====================================================================
        # VAULTS AREA - Knowledge management and cloud storage
        #====================================================================
        "d ${paths.user.vaults} 0755 eric users -"

        # Cloud storage drives
        "d ${paths.user.vaults}/drives 0755 eric users -"
        "d ${paths.user.vaults}/drives/proton 0755 eric users -"
        "d ${paths.user.vaults}/drives/google 0755 eric users -"

        #====================================================================
        # STANDARD USER CONFIGURATION DIRECTORIES
        #====================================================================
        "d ${paths.user.config} 0755 eric users -"
        "d ${paths.user.home}/.local 0755 eric users -"
        "d ${paths.user.home}/.local/bin 0755 eric users -"
        "d ${paths.user.ssh} 0700 eric users -"

        #====================================================================
        # TRADITIONAL DIRECTORY SYMLINKS - Application Compatibility
        #====================================================================
        "L ${paths.user.home}/Desktop - - - - ${paths.user.inbox}/general"
        "L ${paths.user.home}/Downloads - - - - ${paths.user.inbox}/downloads"
        "L ${paths.user.home}/Documents - - - - ${paths.user.reference}"
        "L ${paths.user.home}/Pictures - - - - ${paths.user.media}/pictures"
        "L ${paths.user.home}/Music - - - - ${paths.user.media}/music"
        "L ${paths.user.home}/Videos - - - - ${paths.user.media}/videos"
        "L ${paths.user.home}/Templates - - - - ${paths.user.reference}/templates"
        "L ${paths.user.home}/Public - - - - ${paths.user.inbox}/general"

        # Cloud service integration
        "L ${paths.user.home}/Proton Drive - - - - ${paths.user.vaults}/drives/proton"
        "L ${paths.user.home}/Google Drive - - - - ${paths.user.vaults}/drives/google"

        # Development directory expectations
        "L ${paths.user.home}/Code - - - - ${paths.user.tech}/01-active/development"
        "L ${paths.user.home}/Development - - - - ${paths.user.tech}/01-active"
        "L ${paths.user.home}/Projects - - - - ${paths.user.tech}/01-active"
        "L ${paths.user.home}/Workspace - - - - ${paths.user.tech}/01-active"

        # Media application shortcuts
        "L ${paths.user.home}/Screenshots - - - - ${paths.user.media}/pictures/screenshots"
        "L ${paths.user.home}/Camera - - - - ${paths.user.media}/pictures/camera"

        # Create marker files
        "f ${paths.user.home}/.para-managed 0644 eric users - Clean numbered PARA structure managed by NixOS"
        "f ${paths.user.inbox}/.para-managed 0644 eric users - Global inbox managed by PARA system"
      ];

      # XDG User Directories Configuration
      environment.etc."skel/.config/user-dirs.dirs".text = ''
        # XDG User Directories - Clean PARA Method Integration
        XDG_DESKTOP_DIR="${paths.user.inbox}/general"
        XDG_DOWNLOAD_DIR="${paths.user.inbox}/downloads"
        XDG_TEMPLATES_DIR="${paths.user.reference}/templates"
        XDG_PUBLICSHARE_DIR="${paths.user.inbox}/general"
        XDG_DOCUMENTS_DIR="${paths.user.reference}"
        XDG_MUSIC_DIR="${paths.user.media}/music"
        XDG_PICTURES_DIR="${paths.user.media}/pictures"
        XDG_VIDEOS_DIR="${paths.user.media}/videos"
      '';
    })

    #=========================================================================
    # SERVER STORAGE - Hot/Cold Architecture (Server)
    #=========================================================================
    (lib.mkIf cfg.serverStorage.enable {
      assertions = [
        {
          assertion = paths.hot != null && paths.media != null;
          message = "Server storage requires hwc.paths.hot and hwc.paths.media to be configured";
        }
      ];

      systemd.tmpfiles.rules = [
        # COLD STORAGE - HDD for long-term media library storage
        "d ${paths.media} 0755 eric users -"
        "d ${paths.media}/tv 0755 eric users -"
        "d ${paths.media}/movies 0755 eric users -"
        "d ${paths.media}/music 0755 eric users -"
        "d ${paths.media}/pictures 0755 eric users -"
        "d ${paths.media}/downloads 0755 eric users -"
        "d ${paths.media}/surveillance 0755 eric users -"
        "d ${paths.media}/surveillance/frigate 0755 eric users -"
        "d ${paths.media}/surveillance/frigate/media 0755 eric users -"

        # HOT STORAGE - SSD for active processing and caching
        "d ${paths.hot} 0755 eric users -"
      ] ++ lib.optionals cfg.serverStorage.createDownloadZones [
        # Download staging area (active downloads before processing)
        "d ${paths.hot}/downloads 0755 eric users -"
        "d ${paths.hot}/downloads/torrents 0755 eric users -"
        "d ${paths.hot}/downloads/torrents/music 0755 eric users -"
        "d ${paths.hot}/downloads/torrents/movies 0755 eric users -"
        "d ${paths.hot}/downloads/torrents/tv 0755 eric users -"
        "d ${paths.hot}/downloads/usenet 0755 eric users -"
        "d ${paths.hot}/downloads/usenet/music 0755 eric users -"
        "d ${paths.hot}/downloads/usenet/movies 0755 eric users -"
        "d ${paths.hot}/downloads/usenet/tv 0755 eric users -"
        "d ${paths.hot}/downloads/usenet/software 0755 eric users -"
        "d ${paths.hot}/downloads/soulseek 0755 eric users -"

        # Processing zones for quality control and manual intervention
        "d ${paths.hot}/manual 0755 eric users -"
        "d ${paths.hot}/manual/music 0755 eric users -"
        "d ${paths.hot}/manual/movies 0755 eric users -"
        "d ${paths.hot}/manual/tv 0755 eric users -"
        "d ${paths.hot}/quarantine 0755 eric users -"
        "d ${paths.hot}/quarantine/music 0755 eric users -"
        "d ${paths.hot}/quarantine/movies 0755 eric users -"
        "d ${paths.hot}/quarantine/tv 0755 eric users -"

        # *ARR application working directories
        "d ${paths.hot}/processing 0755 eric users -"
        "d ${paths.hot}/processing/lidarr-temp 0755 eric users -"
        "d ${paths.hot}/processing/sonarr-temp 0755 eric users -"
        "d ${paths.hot}/processing/radarr-temp 0755 eric users -"
      ] ++ lib.optionals cfg.serverStorage.createCacheDirectories [
        # Media cache directories for fast access
        "d ${paths.hot}/cache 0755 eric users -"
        "d ${paths.hot}/cache/frigate 0755 eric users -"
        "d ${paths.hot}/cache/jellyfin 0755 eric users -"
        "d ${paths.hot}/cache/immich 0755 eric users -"

        # Surveillance buffer for immediate recordings
        "d ${paths.hot}/surveillance 0755 eric users -"
        "d ${paths.hot}/surveillance/buffer 0755 eric users -"

        # Database storage on hot SSD
        "d ${paths.hot}/databases 0755 eric users -"
        "d ${paths.hot}/databases/postgresql 0755 eric users -"
        "d ${paths.hot}/databases/redis 0755 eric users -"

        # AI model storage
        "d ${paths.hot}/ai 0755 eric users -"
        "d ${paths.hot}/ai/ollama 0755 eric users -"

        # GPU cache directories
        "d ${paths.hot}/cache/gpu 0755 eric users -"
        "d ${paths.hot}/cache/tensorrt 0755 eric users -"
      ];
    })

    #=========================================================================
    # BUSINESS & AI DIRECTORIES (Server)
    #=========================================================================
    (lib.mkIf cfg.businessDirectories.enable {
      systemd.tmpfiles.rules = [
        # Main business application directory
        "d ${paths.business.root} 0755 eric users -"
        "d ${paths.business.api} 0755 eric users -"
        "d ${paths.business.api}/app 0755 eric users -"
        "d ${paths.business.api}/models 0755 eric users -"
        "d ${paths.business.api}/routes 0755 eric users -"
        "d ${paths.business.api}/services 0755 eric users -"
        "d ${paths.business.root}/dashboard 0755 eric users -"
        "d ${paths.business.root}/config 0755 eric users -"
        "d ${paths.business.uploads} 0755 eric users -"
        "d ${paths.business.root}/receipts 0755 eric users -"
        "d ${paths.business.root}/processed 0755 eric users -"
        "d ${paths.business.backups} 0755 eric users -"
        "d ${paths.business.backups}/secrets 0755 eric users -"

        # AI/ML business intelligence directories
        "d ${paths.ai.root} 0755 eric users -"
        "d ${paths.ai.models} 0755 eric users -"
        "d ${paths.ai.context} 0755 eric users -"
        "d ${paths.ai.root}/document-embeddings 0755 eric users -"
        "d ${paths.ai.root}/business-rag 0755 eric users -"
      ] ++ lib.optionals cfg.businessDirectories.createAdhd [
        # ADHD productivity tools directories
        "d ${paths.adhd.root} 0755 eric users -"
        "d ${paths.adhd.context} 0755 eric users -"
        "d ${paths.adhd.logs} 0755 eric users -"
        "d ${paths.adhd.root}/energy-tracking 0755 eric users -"
        "d ${paths.adhd.root}/scripts 0755 eric users -"
      ];
    })

    #=========================================================================
    # SERVICE CONFIGURATION DIRECTORIES - *ARR Apps (Server)
    #=========================================================================
    (lib.mkIf cfg.serviceDirectories.enable {
      systemd.tmpfiles.rules = [
        # *ARR applications (media management)
        "d ${paths.arr.lidarr} 0755 eric users -"
        "d ${paths.arr.lidarr}/config 0755 eric users -"
        "d ${paths.arr.lidarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.lidarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.radarr} 0755 eric users -"
        "d ${paths.arr.radarr}/config 0755 eric users -"
        "d ${paths.arr.radarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.radarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.sonarr} 0755 eric users -"
        "d ${paths.arr.sonarr}/config 0755 eric users -"
        "d ${paths.arr.sonarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.sonarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.prowlarr} 0755 eric users -"
        "d ${paths.arr.prowlarr}/config 0755 eric users -"

        # Surveillance services
        "d ${paths.surveillance.root} 0755 eric users -"
        "d ${paths.surveillance.frigate} 0755 eric users -"
        "d ${paths.surveillance.frigate}/config 0755 eric users -"
        "d ${paths.surveillance.frigate}/media 0755 eric users -"
        "d ${paths.surveillance.root}/home-assistant 0755 eric users -"
        "d ${paths.surveillance.root}/home-assistant/config 0755 eric users -"
      ] ++ lib.optionals cfg.serviceDirectories.createLegacyPaths [
        # Legacy download application directories (compatibility)
        "d ${paths.arr.downloads} 0755 eric users -"
        "d ${paths.arr.downloads}/qbittorrent 0755 eric users -"
        "d ${paths.arr.downloads}/sonarr 0755 eric users -"
        "d ${paths.arr.downloads}/radarr 0755 eric users -"
        "d ${paths.arr.downloads}/lidarr 0755 eric users -"
        "d ${paths.arr.downloads}/prowlarr 0755 eric users -"
        "d ${paths.arr.downloads}/navidrome 0755 eric users -"
        "d ${paths.arr.downloads}/immich 0755 eric users -"
        "d ${paths.arr.downloads}/sabnzbd 0755 eric users -"
        "d ${paths.arr.downloads}/slskd 0755 eric users -"
        "d ${paths.arr.downloads}/soularr 0755 eric users -"
        "d ${paths.arr.downloads}/gluetun 0755 root root -"
      ];
    })

    #=========================================================================
    # SECURITY DIRECTORIES - Secrets and Certificates (Always Available)
    #=========================================================================
    (lib.mkIf cfg.securityDirectories.enable {
      systemd.tmpfiles.rules = [
        # Main secrets directory (SOPS integration)
        "d ${paths.security.secrets} 0750 root root -"
        "d ${paths.security.age} 0750 root root -"
        "d ${paths.security.sops} 0750 root root -"

        # Tailscale certificate management
        "d ${paths.security.tailscale} 0750 root root -"
        "d ${paths.security.certificates} 0750 caddy caddy -"
      ];
    })

  ]);
}
