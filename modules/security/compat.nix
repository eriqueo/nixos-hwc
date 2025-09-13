# modules/security/compat.nix
#
# Compatibility shim for legacy secret paths
# Provides mkAliasOptionModule entries to avoid breaking existing consumers
{ lib, ... }:
{
  imports = [
    # Legacy hwc.system.secrets.* → hwc.security.materials.*
    (lib.mkAliasOptionModule 
      [ "hwc" "system" "secrets" "enable" ]
      [ "hwc" "security" "enable" ])
    
    # Note: We don't alias the old userPasswordSecret since that was a config option,
    # not a path. Consumers should use materials.userInitialPasswordFile directly.
    
    # Legacy age.secrets direct access patterns → materials facade
    # These aren't option aliases but we document the migration path:
    #   OLD: config.age.secrets."emergency-password".path
    #   NEW: config.hwc.security.materials.emergencyPasswordFile
    #   OLD: config.age.secrets."user-initial-password".path  
    #   NEW: config.hwc.security.materials.userInitialPasswordFile
    #   OLD: config.age.secrets.vpn-username.path
    #   NEW: config.hwc.security.materials.vpnUsernameFile
  ];

  # Deprecation warnings to guide migration away from legacy paths
  warnings = [
    ''
      ##################################################################
      # DEPRECATION NOTICE: Legacy secret paths detected              #
      #                                                                #
      # Please migrate from direct age.secrets access to the stable   #
      # materials facade:                                              #
      #                                                                #
      # OLD: config.age.secrets."secret-name".path                    #
      # NEW: config.hwc.security.materials.secretNameFile             #
      #                                                                #
      # This provides a stable interface isolated from agenix         #
      # implementation details.                                        #
      ##################################################################
    ''
  ];
}