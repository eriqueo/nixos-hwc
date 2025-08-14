￼## nixos-hwc/modules/system/paths.nix
#
# This module establishes the single source of truth for all critical
# filesystem paths used throughout the NixOS configuration.
#
# By centralizing path definitions here, we eliminate hardcoded strings
# from service modules, making the entire configuration more robust,
# portable, and easier to manage.
#
# All other modules should reference these options via `config.hwc.paths.*`.

{ lib, ... }:

{
  options.hwc.paths = {
    # Base system paths
    root = lib.mkOption {
      type = lib.types.path;
      default = "/";
      description = "Absolute path to the system's root filesystem.";
    };

    # Persistent storage paths, typically mounted drives
    hot = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/hot";
      description = "Path to the primary (hot) storage volume, for frequently accessed data.";
    };

    media = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/media";
      description = "Path to the media storage volume, for large media files (movies, music, etc.).";
    };

    # Application state and data paths, managed by NixOS
    state = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc";
      description = "Root directory for persistent application state data. Services should create subdirectories here.";
    };

    cache = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/hwc";
      description = "Root directory for non-essential cached data. This data can be safely deleted.";
    };

    logs = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/hwc";
      description = "Root directory for application logs. Services should create subdirectories here.";
    };
  };
}