# profiles/system.nix
#
# SYSTEM DOMAIN - Feature menu for system-level capabilities
# Provides base system requirements and optional system features
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality  
  #==========================================================================
  
  imports = [
    ../domains/system/users
    ../domains/system/core/paths
    ../domains/system/security/secrets
    ../domains/system/services/networking
    ../domains/system/services/vpn
  ];
  
  # Essential system functionality - every machine needs these
  hwc.system.users.enable = true;
  hwc.system.users.user.enable = true;
  hwc.paths.enable = true;
  hwc.system.security.secrets.enable = true;
  hwc.networking.enable = true;
  
  #==========================================================================
  # OPTIONAL SYSTEM FEATURES - Sensible defaults, override per machine
  #==========================================================================
  
  # Development tools
  hwc.system.packages.development.enable = false;
  hwc.system.packages.media.enable = false;
  
  # System services
  hwc.system.services.behavior.enable = false;
  hwc.system.services.session.enable = false;
  hwc.system.services.vpn.enable = true;
  hwc.system.services.vpn.protonvpn.enable = true;
  
  # Security levels
  hwc.system.security.level = "standard";  # Can be: minimal, standard, hardened
  
  # Networking levels  
  hwc.networking.level = "basic";          # Can be: basic, advanced, server
}