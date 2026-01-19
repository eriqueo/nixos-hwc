

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.samba;
in {
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
          path = "${config.hwc.paths.state}/sketchup/vm/shared";
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
      "d ${config.hwc.paths.state}/sketchup/vm/shared 0777 nobody nogroup -"
    ];
    
    # Include samba client tools
    environment.systemPackages = with pkgs; [
      samba  # SMB client tools
    ];
  };
}
