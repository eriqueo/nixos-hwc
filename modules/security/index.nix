# modules/security/index.nix
#
# Security domain aggregator - single source of truth for all secrets and security
# Imports all security components: domain secrets, materials facade, and compatibility shim
{ lib, config, ... }:
{
  imports = [
    ./secrets/index.nix      # Aggregates all domain secret files
    ./materials.nix          # Stable read-only path facade for consumers
    ./compat.nix             # Compatibility aliases for legacy paths
    ./emergency-access.nix   # Emergency access configuration (existing)
    ./hardening.nix          # Security hardening configuration
  ];

  # Security domain enable option
  options.hwc.security.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable security domain with secrets management";
  };

  # Core agenix configuration
  config = lib.mkIf config.hwc.security.enable {
    # Ensure age identity paths are configured
    age.identityPaths = lib.mkDefault [ "/etc/age/keys.txt" ];
    
    # Create age keys directory with proper permissions
    systemd.tmpfiles.rules = [
      "d /etc/age 0755 root root -"
    ];

    # Helper environment variable for easier secret directory access
    environment.sessionVariables = {
      HWC_SECRETS_DIR = "/run/agenix";
    };

    # Security domain activation warning
    warnings = [
      ''
        ##################################################################
        # SECURITY DOMAIN ACTIVE                                        #
        # All secrets managed via hwc.security.materials.*             #
        # Secrets decrypted to /run/agenix/ during system boot.        #
        # Ensure age keys are deployed to /etc/age/keys.txt             #
        ##################################################################
      ''
    ];
  };
}
