# profiles/infrastructure.nix
#
# INFRASTRUCTURE DOMAIN - Feature menu for infrastructure capabilities
# Provides cross-domain orchestration and hardware management
{
  #==========================================================================
  # BASE INFRASTRUCTURE - Critical for machine functionality  
  #==========================================================================
  
  imports = [
    ../domains/infrastructure/filesystem-structure
  ];
  
  # Essential infrastructure - every machine needs these
  hwc.infrastructure.filesystemStructure.enable = true;
  hwc.infrastructure.filesystemStructure.userDirectories.enable = true;
  hwc.infrastructure.filesystemStructure.securityDirectories.enable = true;
  
  #==========================================================================
  # OPTIONAL INFRASTRUCTURE FEATURES - Sensible defaults, override per machine
  #==========================================================================
  
  # Hardware capabilities
  hwc.infrastructure.hardware.gpu.enable = false;
  hwc.infrastructure.hardware.peripherals.enable = false;
  hwc.infrastructure.hardware.virtualization.enable = false;
  
  # Storage tiers
  hwc.infrastructure.hardware.storage.hot.enable = false;
  hwc.infrastructure.hardware.storage.media.enable = false;
  hwc.infrastructure.hardware.storage.backup.enable = false;
  
  # Cross-domain orchestration
  hwc.infrastructure.session.services.enable = false;
}