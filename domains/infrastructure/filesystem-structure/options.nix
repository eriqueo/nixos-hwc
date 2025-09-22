# nixos-h../domains/infrastructure/filesystem-structure/options.nix
#
# FILESYSTEM STRUCTURE - Cross-domain filesystem orchestrator options
# Provides standardized directory structure for both laptop and server environments
#
# PURPOSE:
#   Creates uniform navigation and naming conventions across all domains
#   Provides compatibility symlinks so applications work without retraining
#   Establishes foundational directory infrastructure for system and home manager
#
{ lib, config, ... }:

{
  #============================================================================
  # OPTIONS - Filesystem Structure Configuration
  #============================================================================

  options.hwc.infrastructure.filesystemStructure = {
    enable = lib.mkEnableOption "HWC cross-domain filesystem structure management";

    #=========================================================================
    # USER DIRECTORIES - PARA Structure
    #=========================================================================

    userDirectories = {
      enable = lib.mkEnableOption "PARA user directories, XDG config, and compatibility symlinks";

      createHomeManager = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create Home Manager integration for PARA structure";
      };
    };

    #=========================================================================
    # SERVER STORAGE - Hot/Cold Architecture
    #=========================================================================

    serverStorage = {
      enable = lib.mkEnableOption "hot/cold storage directories for media server";

      createDownloadZones = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create download staging and processing zones";
      };

      createCacheDirectories = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create media cache directories for transcoding";
      };
    };

    #=========================================================================
    # BUSINESS & AI DIRECTORIES
    #=========================================================================

    businessDirectories = {
      enable = lib.mkEnableOption "business intelligence and AI application directories";

      createAdhd = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create ADHD productivity tools directories";
      };
    };

    #=========================================================================
    # SERVICE CONFIGURATION DIRECTORIES
    #=========================================================================

    serviceDirectories = {
      enable = lib.mkEnableOption "*ARR service configuration directories";

      createLegacyPaths = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create legacy /opt/downloads compatibility paths";
      };
    };

    #=========================================================================
    # SECURITY DIRECTORIES
    #=========================================================================

    securityDirectories = {
      enable = lib.mkEnableOption "security and secrets directories";
    };

    #=========================================================================
    # USER & GROUP MANAGEMENT
    #=========================================================================

    permissions = {
      mediaGroup = lib.mkOption {
        type = lib.types.str;
        default = "media";
        description = "Group for media file access";
      };

      serviceUser = lib.mkOption {
        type = lib.types.str;
        default = "hwc";
        description = "User for HWC service data";
      };
    };
  };
}