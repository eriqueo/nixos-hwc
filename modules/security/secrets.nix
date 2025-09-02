# nixos-hwc/modules/security/secrets.nix
#
# SECRETS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.security.secrets.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/security/secrets.nix
#
# USAGE:
#   hwc.security.secrets.enable = true;
#   # TODO: Add specific usage examples

# modules/security/secrets.nix
#
# HWC Agenix Secrets Management (Charter v3)
# Simplified secrets management using agenix instead of SOPS
#
# DEPENDENCIES:
#   Upstream: agenix.nixosModules.default (flake.nix)
#
# USED BY:
#   Downstream: All modules requiring secrets
#   Downstream: profiles/base.nix (basic secrets)
#   Downstream: profiles/server.nix (server secrets)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/security/secrets.nix
#   - flake.nix: ./secrets.nix (CRITICAL - missing this caused the lockout)
#
# USAGE:
#   config.age.secrets.vpn-username.path       # Path to decrypted secret
#   config.age.secrets.database-password.path  # Database password file
#
# VALIDATION:
#   - Requires age keys to be present on target machines
#   - Secrets are decrypted to /run/agenix/ with proper permissions
#
# EMERGENCY RECOVERY PROCEDURES:
# ================================
# If you get locked out due to agenix failure:
#
# METHOD 1: GRUB Generation Rollback
#   1. Reboot system
#   2. At GRUB menu, select "Previous generations"
#   3. Boot older generation (before the switch that caused lockout)
#   4. Run: sudo nixos-rebuild switch --flake /etc/nixos#hwc-laptop
#
# METHOD 2: Emergency Root Access (if secrets are enabled)
#   - Username: root
#   - Password: emergency123
#   - SSH with your regular SSH key should also work for root
#
# METHOD 3: Single User Mode Boot
#   1. At GRUB, press 'e' to edit boot entry
#   2. Add 'init=/bin/sh' to kernel line
#   3. Boot, then: mount -o remount,rw / && passwd eric
#
# METHOD 4: Check Agenix Status
#   - systemctl status agenix
#   - ls -la /run/agenix/
#   - ls -la /etc/age/keys.txt
#   - journalctl -u agenix

{ config, lib, ... }:

let
  cfg = config.hwc.security;
in {
  #============================================================================
  # OPTIONS - Security Configuration Toggles
  #============================================================================
  
  options.hwc.security = {
    enable = lib.mkEnableOption "HWC security and secrets management";
    
    secrets = {
      vpn = lib.mkEnableOption "VPN credentials for media services";
      database = lib.mkEnableOption "Database credentials for business services";
      couchdb = lib.mkEnableOption "CouchDB credentials for Obsidian sync";
      services = lib.mkEnableOption "Service API keys and admin credentials";
      user = lib.mkEnableOption "User account secrets";
      surveillance = lib.mkEnableOption "Surveillance system credentials";
      arr = lib.mkEnableOption "ARR stack API keys";
      ntfy = lib.mkEnableOption "NTFY notification tokens";
    };

    # Age key configuration
    ageKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/age/keys.txt";
      description = "Path to age private key file";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Agenix Secret Definitions
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Configure agenix key file location
    age.identityPaths = [ cfg.ageKeyFile ];


    # VPN secrets for media services
    age.secrets = lib.mkMerge [
      (lib.mkIf cfg.secrets.vpn {
        vpn-username = {
          file = ../../secrets/vpn-username.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        vpn-password = {
          file = ../../secrets/vpn-password.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.database {
        database-password = {
          file = ../../secrets/database-password.age;
          mode = "0400";
          owner = "postgres";
          group = "postgres";
        };
        database-user = {
          file = ../../secrets/database-user.age;
          mode = "0400";
          owner = "postgres";
          group = "postgres";
        };
        database-name = {
          file = ../../secrets/database-name.age;
          mode = "0400";
          owner = "postgres";
          group = "postgres";
        };
      })

      (lib.mkIf cfg.secrets.couchdb {
        couchdb-admin-username = {
          file = ../../secrets/couchdb-admin-username.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        couchdb-admin-password = {
          file = ../../secrets/couchdb-admin-password.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.user {
        user-initial-password = {
          file = ../../secrets/user-initial-password.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        user-ssh-public-key = {
          file = ../../secrets/user-ssh-public-key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.services {
        jellyfin-admin = {
          file = ../../secrets/jellyfin-admin.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        homeassistant-admin = {
          file = ../../secrets/homeassistant-admin.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        caddy-admin = {
          file = ../../secrets/caddy-admin.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.arr {
        sonarr-api-key = {
          file = ../../secrets/sonarr-api-key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        radarr-api-key = {
          file = ../../secrets/radarr-api-key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        lidarr-api-key = {
          file = ../../secrets/lidarr-api-key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
        prowlarr-api-key = {
          file = ../../secrets/prowlarr-api-key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.ntfy {
        ntfy-token = {
          file = ../../secrets/ntfy-user.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })

      (lib.mkIf cfg.secrets.surveillance {
        surveillance-admin = {
          file = ../../secrets/surveillance-admin.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      })
    ];

    # Ensure age key directory exists with proper permissions
    systemd.tmpfiles.rules = [
      "d /etc/age 0755 root root -"
    ];

    # Helper environment variables for easier secret access in scripts
    environment.sessionVariables = {
      HWC_SECRETS_DIR = "/run/agenix";
    };
  };
}
