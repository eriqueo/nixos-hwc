# domains/system/packages/options.nix
# Consolidated options for all system package collections
# Charter-compliant: all hwc.system.packages.* options in one place

{ lib, ... }:

{
  options.hwc.system.packages = {

    # Base system packages - essential tools for all machines
    base = {
      enable = lib.mkEnableOption "Essential system packages";
    };

    # Server-specific packages - tools for server operations
    server = {
      enable = lib.mkEnableOption "Server-specific system packages";
    };

    # ISO/CD image tools - xorriso, genisoimage, etc.
    isoTools = {
      enable = lib.mkEnableOption "ISO and CD image manipulation tools";
    };

    # Security/backup packages - backup tools and utilities
    security = {
      enable = lib.mkEnableOption "backup system packages and utilities";

      # Cloud storage configuration
      protonDrive = {
        enable = lib.mkEnableOption "Proton Drive integration";

        email = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proton Mail email address (leave empty to use interactive setup)";
        };

        encodedPassword = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Rclone-encoded password (leave empty to use interactive setup)";
        };

        useSecret = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Use agenix secret for rclone configuration";
        };

        secretName = lib.mkOption {
          type = lib.types.str;
          default = "rclone-proton-config";
          description = "Name of agenix secret containing rclone config";
        };
      };

      # Additional backup tools
      extraTools = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Additional backup-related packages to install";
      };

      # Maintenance and monitoring
      monitoring = {
        enable = lib.mkEnableOption "backup monitoring and maintenance tools";
      };
    };
  };
}
