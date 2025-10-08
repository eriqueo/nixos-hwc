# domains/secrets/index.nix
#
# Secrets domain aggregator - single source of truth for all secrets
# Imports all secret declarations, API facade, emergency access, and hardening
{ lib, config, ... }:
{
  imports = [
    ./options.nix            # Consolidated options (charter-compliant)
    ./declarations/index.nix # Age secret declarations organized by domain
    ./secrets-api.nix        # Stable read-only path facade for consumers
    ./emergency.nix          # Emergency root access for recovery
    ./hardening.nix          # Security hardening configuration
  ];

  # Core agenix configuration
  config = lib.mkIf config.hwc.secrets.enable {
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

  };
}
