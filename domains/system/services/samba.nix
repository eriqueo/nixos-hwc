# nixos-h../domains/infrastructure/samba.nix
#
# SAMBA - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.samba.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/samba.nix
#
# USAGE:
#   hwc.infrastructure.samba.enable = true;
#   # TODO: Add specific usage examples

# nixos-h../domains/infrastructure/samba.nix
#
# Samba File Sharing Infrastructure
# Provides SMB/CIFS file sharing with modern Windows compatibility
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.* (for share paths) [optional]
#
# USED BY:
#   Downstream: profiles/workstation.nix (enables for development VMs)
#   Downstream: machines/laptop/config.nix (may override shares)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../domains/infrastructure/samba.nix
#
# USAGE:
#   hwc.infrastructure.samba.enable = true;
#   hwc.infrastructure.samba.workgroup = "DOMAIN";  # Override default
#   hwc.infrastructure.samba.shares.myshare = { path = "/path"; };
#
# VALIDATION:
#   - Share paths must exist
#   - Firewall ports will be opened automatically

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.samba;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.infrastructure.samba = {
    enable = lib.mkEnableOption "Samba file sharing with modern Windows compatibility";
    
    # Global settings
    workgroup = lib.mkOption {
      type = lib.types.str;
      default = "WORKGROUP";
      description = "SMB workgroup name";
    };
    
    serverString = lib.mkOption {
      type = lib.types.str;
      default = "Samba on ${config.networking.hostName}";
      description = "Server description string";
    };
    
    # Security settings
    security = lib.mkOption {
      type = lib.types.enum [ "user" "ads" "domain" ];
      default = "user";
      description = "Samba security model";
    };
    
    # Share definitions
    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.path;
            description = "Path to shared directory";
          };
          
          browseable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether share appears in browse lists";
          };
          
          readOnly = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether share is read-only";
          };
          
          guestAccess = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Allow guest access to share";
          };
          
          extraSettings = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional share-specific settings";
          };
        };
      });
      default = {};
      description = "Samba share configurations";
    };
    
    # Predefined shares
    enableSketchupShare = lib.mkEnableOption "SketchUp VM share at /opt/sketchup/vm/shared";
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check share paths exist
    assertions = lib.mapAttrsToList (name: share: {
      assertion = builtins.pathExists (builtins.toString share.path);
      message = "Samba share '${name}' path '${share.path}' does not exist";
    }) cfg.shares;
    
    # Samba service configuration
    services.samba = {
      enable = true;
      openFirewall = true;
      
      settings = {
        # Global configuration
        global = {
          "workgroup" = cfg.workgroup;
          "server string" = cfg.serverString;
          "security" = cfg.security;
          "map to guest" = "Bad User";
          "guest account" = "nobody";
          
          # Modern SMB compatibility settings
          "server min protocol" = "SMB2_10";
          "client min protocol" = "SMB2_10";
          "server max protocol" = "SMB3";
          
          # SMB Signing and Encryption (CRITICAL for modern Windows)
          "server signing" = "auto";
          "server schannel" = "auto";
          "encrypt passwords" = "yes";
          
          # Disable problematic features for guest access
          "ntlm auth" = "yes";
          "lanman auth" = "no";
          "client lanman auth" = "no";
          "client ntlmv2 auth" = "yes";
          
          # Other potentially helpful settings
          "dns proxy" = "no";
          "strict allocate" = "yes";
          "oplocks" = "yes";
          "level2 oplocks" = "yes";
          "wide links" = "yes";
          "unix extensions" = "no"; # Often helps with Windows compatibility
        };
        
        # User-defined shares
      } // lib.mapAttrs (name: share: {
        path = share.path;
        browseable = if share.browseable then "yes" else "no";
        "read only" = if share.readOnly then "yes" else "no";
        "guest ok" = if share.guestAccess then "yes" else "no";
      } // share.extraSettings) cfg.shares
      
      # Predefined SketchUp share
      // lib.optionalAttrs cfg.enableSketchupShare {
        "skpshare" = {
          path = "/opt/sketchup/vm/shared";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "yes";
          "create mask" = "0777";
          "directory mask" = "0777";
          "force user" = "nobody";
          "force group" = "nogroup";
          "guest only" = "yes";
        };
      };
    };
    
    # Ensure SketchUp share directory exists
    systemd.tmpfiles.rules = lib.optionals cfg.enableSketchupShare [
      "d /opt/sketchup/vm/shared 0777 nobody nogroup -"
    ];
    
    # Include samba client tools
    environment.systemPackages = with pkgs; [
      samba  # SMB client tools
    ];
  };
}